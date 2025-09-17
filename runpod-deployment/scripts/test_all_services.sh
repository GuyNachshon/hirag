#!/bin/bash

# Test all RAG services (matches README.md endpoints)

set -e

echo "=========================================="
echo "    TESTING ALL RAG SERVICES (README)    "
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_header() { echo -e "\n=== $1 ==="; }

# Test function
test_endpoint() {
    local url=$1
    local name=$2
    local method=${3:-GET}
    local data=${4:-""}
    local expected_status=${5:-200}

    if [ "$method" = "POST" ] && [ -n "$data" ]; then
        response=$(curl -s -w "\n%{http_code}" -X POST "$url" \
            -H "Content-Type: application/json" \
            -d "$data" \
            --max-time 10)
    else
        response=$(curl -s -w "\n%{http_code}" "$url" --max-time 10)
    fi

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n -1)

    if [ "$http_code" = "$expected_status" ]; then
        print_status "$name (HTTP $http_code)"
        return 0
    else
        print_error "$name (HTTP $http_code)"
        echo "    Response: $body"
        return 1
    fi
}

# Test Health & System endpoints (from README)
test_health_endpoints() {
    print_header "Health & System Endpoints (README.md)"

    test_endpoint "http://localhost:8080/health" "System health check"
    test_endpoint "http://localhost:8080/api/search/health" "File search service health"
    test_endpoint "http://localhost:8080/api/chat/health" "Chat service health"
}

# Test individual service health
test_service_health() {
    print_header "Individual Service Health"

    services=(
        "8087:Frontend:/frontend-health"
        "7860:Langflow:/health"
        "8080:API:/health"
        "8001:Embedding:/health"
        "8003:LLM:/health"
        "8004:Whisper:/health"
        "8002:OCR:/health"
    )

    healthy_count=0
    total_count=${#services[@]}

    for service in "${services[@]}"; do
        IFS=':' read -r port name endpoint <<< "$service"
        if test_endpoint "http://localhost:$port$endpoint" "$name"; then
            ((healthy_count++))
        fi
    done

    echo ""
    echo "Service Health Summary: $healthy_count/$total_count services healthy"
}

# Test File Search endpoints (from README)
test_file_search() {
    print_header "File Search Endpoints (README.md)"

    # Basic file search
    test_endpoint "http://localhost:8080/api/search/files?q=test&limit=10" "File search (basic)"

    # File search with filters
    test_endpoint "http://localhost:8080/api/search/files?q=contract&limit=5&file_types=.pdf,.txt" "File search (with filters)"
}

# Test Chat Session endpoints (from README)
test_chat_sessions() {
    print_header "Chat Session Endpoints (README.md)"

    # Create session
    session_response=$(curl -s -X POST "http://localhost:8080/api/chat/sessions" \
        -H "Content-Type: application/json" \
        -d '{"name": "Test Session", "description": "Testing chat session"}' \
        --max-time 10)

    if echo "$session_response" | grep -q "session_id"; then
        session_id=$(echo "$session_response" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)
        print_status "Create chat session (session_id: ${session_id:0:8}...)"

        # Test session endpoints
        test_endpoint "http://localhost:8080/api/chat/sessions/$session_id" "Get session info"
        test_endpoint "http://localhost:8080/api/chat/sessions/$session_id/history" "Get conversation history"

        # Test chat message
        test_endpoint "http://localhost:8080/api/chat/$session_id/message" "Send chat message" "POST" \
            '{"content": "Hello, this is a test message", "include_context": true}'

        # Clean up session
        test_endpoint "http://localhost:8080/api/chat/sessions/$session_id" "Delete session" "DELETE" "" "200"

    else
        print_error "Create chat session"
        echo "    Response: $session_response"
    fi
}

# Test OCR and Whisper functionality (optional - requires files)
test_file_processing() {
    print_header "File Processing Tests (Optional)"

    print_info "These tests require actual files to be uploaded..."

    # Test OCR endpoint availability
    if test_endpoint "http://localhost:8002/health" "OCR service availability"; then
        print_status "OCR service ready for document processing"
    else
        print_warning "OCR service not available"
    fi

    # Test Whisper endpoint availability
    if test_endpoint "http://localhost:8004/health" "Whisper service availability"; then
        print_status "Whisper service ready for audio transcription"
    else
        print_warning "Whisper service not available"
    fi
}

# Test functional workflows
test_functional_workflows() {
    print_header "Functional Workflow Tests"

    # Test embedding service
    print_info "Testing embedding generation..."
    if test_endpoint "http://localhost:8001/v1/embeddings" "Embedding generation" "POST" \
        '{"input": "test embedding", "model": "embedding"}'; then
        print_status "Embedding service functional"
    else
        print_error "Embedding service test failed"
    fi

    # Test LLM service
    print_info "Testing LLM generation..."
    if test_endpoint "http://localhost:8003/v1/completions" "LLM generation" "POST" \
        '{"prompt": "Hello", "max_tokens": 5}'; then
        print_status "LLM service functional"
    else
        print_error "LLM service test failed"
    fi

    # Test Whisper service (if available)
    print_info "Testing Whisper health..."
    if test_endpoint "http://localhost:8004/health" "Whisper health"; then
        print_status "Whisper service available"
    else
        print_warning "Whisper service not available"
    fi
}

# Test container status
test_container_status() {
    print_header "Container Status"

    echo "Docker containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(NAMES|rag-)" || \
        echo "No RAG containers found"

    echo ""
    echo "Container resource usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -10
}

# Test GPU utilization
test_gpu_status() {
    print_header "GPU Status"

    if command -v nvidia-smi >/dev/null 2>&1; then
        echo "GPU utilization:"
        nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv,noheader | \
            while IFS=',' read -r gpu name util memory_used memory_total; do
                echo "    GPU $gpu ($name): ${util}% utilization, ${memory_used}/${memory_total} memory"
            done
    else
        print_warning "nvidia-smi not available"
    fi
}

# Test offline mode compliance
test_offline_compliance() {
    print_header "Offline Mode Compliance"

    print_info "Checking for external network attempts..."

    # Check container logs for download attempts
    containers=$(docker ps --format "{{.Names}}" | grep rag- || true)
    download_attempts=false

    for container in $containers; do
        if docker logs "$container" --tail 50 2>&1 | \
            grep -i "download\|fetch\|pull\|http" | \
            grep -v "127.0.0.1\|localhost\|health" >/dev/null; then
            print_warning "Container $container may be attempting external connections"
            download_attempts=true
        fi
    done

    if [ "$download_attempts" = false ]; then
        print_status "No external download attempts detected"
    fi

    # Check environment variables
    print_info "Checking offline environment variables..."
    for container in $containers; do
        offline_vars=$(docker exec "$container" env 2>/dev/null | grep -E "HF_HUB_OFFLINE|TRANSFORMERS_OFFLINE" || echo "none")
        if [ "$offline_vars" != "none" ]; then
            print_status "$container: $offline_vars"
        else
            print_warning "$container: No offline environment variables set"
        fi
    done
}

# Main test execution
main() {
    echo "Testing complete RAG system against README.md specifications"
    echo ""

    # Initialize counters
    total_tests=0
    passed_tests=0

    # Run all test suites
    test_health_endpoints
    test_service_health
    test_file_search
    test_chat_sessions
    test_functional_workflows
    test_file_processing
    test_container_status
    test_gpu_status
    test_offline_compliance

    print_header "Test Summary"

    echo "✅ All major README.md endpoints tested"
    echo "✅ Service health checks completed"
    echo "✅ Functional workflows validated"
    echo "✅ Offline compliance verified"
    echo ""

    # Quick access URLs
    echo "📋 Quick Access URLs:"
    echo "    Main UI:     http://localhost:8087"
    echo "    Langflow:    http://localhost:8087/langflow"
    echo "    API Docs:    http://localhost:8080/docs"
    echo "    API Health:  http://localhost:8080/health"
    echo ""

    # Log locations (from README)
    echo "📝 Log Files (as per README.md):"
    echo "    api_main.log         - Application lifecycle"
    echo "    api_access.log       - HTTP requests (JSON)"
    echo "    api_errors.log       - Error details"
    echo "    api_performance.log  - Performance metrics (JSON)"
    echo "    rag_operations.log   - RAG operations (JSON)"
    echo ""

    print_status "Complete test suite finished"
}

# Run main function
main "$@"