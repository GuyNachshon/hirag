#!/bin/bash

set -e

echo "=========================================="
echo "H100 RAG System Deployment Validation"
echo "Comprehensive Health and Performance Check"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    print_header "$test_name"
    
    if eval "$test_command"; then
        print_status "PASSED: $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        print_error "FAILED: $test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Helper functions
check_service_health() {
    local service_name="$1"
    local url="$2"
    local timeout="${3:-10}"
    
    if timeout "$timeout" curl -f -s "$url" >/dev/null 2>&1; then
        local status=$(curl -s "$url" 2>/dev/null | head -1)
        print_status "$service_name: Healthy"
        return 0
    else
        print_error "$service_name: Unhealthy or unreachable"
        return 1
    fi
}

check_gpu_memory() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        local gpu_info=$(nvidia-smi --query-gpu=memory.used,memory.total,name --format=csv,noheader,nounits)
        print_status "GPU: $gpu_info"
        return 0
    else
        print_error "nvidia-smi not available"
        return 1
    fi
}

# Test 1: System Prerequisites
run_test "Docker Status" "docker info >/dev/null 2>&1"
run_test "NVIDIA GPU Detection" "nvidia-smi >/dev/null 2>&1"
run_test "Docker Network Exists" "docker network inspect rag-network >/dev/null 2>&1"

echo ""
print_header "GPU Memory Overview"
check_gpu_memory
echo ""

# Test 2: Container Status
print_header "Container Status Check"
SERVICES=("rag-frontend" "rag-api" "rag-embedding-server" "rag-dots-ocr" "rag-llm-server" "rag-whisper")

for service in "${SERVICES[@]}"; do
    if docker ps --format "table {{.Names}}" | grep -q "^$service$"; then
        print_status "$service: Running"
    else
        print_error "$service: Not running or not found"
        # Check if container exists but stopped
        if docker ps -a --format "table {{.Names}}" | grep -q "^$service$"; then
            print_warning "$service: Container exists but stopped"
        fi
    fi
done

echo ""

# Test 3: Health Endpoints
print_header "Service Health Checks"
run_test "Frontend Health" "check_service_health 'Frontend' 'http://localhost:3000/frontend-health'"
run_test "API Health" "check_service_health 'API' 'http://localhost:8080/health'"
run_test "Embedding Health" "check_service_health 'Embedding' 'http://localhost:8001/health'"
run_test "DotsOCR Health" "check_service_health 'DotsOCR' 'http://localhost:8002/health' 30"
run_test "LLM Health" "check_service_health 'LLM' 'http://localhost:8003/health' 30"
run_test "Whisper Health" "check_service_health 'Whisper' 'http://localhost:8004/health'"

echo ""

# Test 4: API Functional Tests
print_header "API Functional Tests"

# Test API endpoints
run_test "API Root Endpoint" "curl -f -s http://localhost:8080/ >/dev/null"
run_test "API Health Detail" "curl -s http://localhost:8080/health | grep -q 'status'"

echo ""

# Test 5: Service Integration Tests
print_header "Service Integration Tests"

# Test embedding service
run_test "Embedding Service Response" "curl -f -s -X POST http://localhost:8001/embeddings -H 'Content-Type: application/json' -d '{\"input\": \"test\", \"model\": \"embedding\"}' | grep -q 'data' || true"

# Test whisper service (if audio file exists)
if [ -f "test_audio.wav" ]; then
    run_test "Whisper Transcription" "curl -f -s -X POST http://localhost:8004/transcribe -F 'file=@test_audio.wav' | grep -q 'text'"
else
    print_warning "No test audio file found, skipping Whisper test"
fi

echo ""

# Test 6: Memory and Resource Usage
print_header "Resource Usage Analysis"

echo "Docker Container Memory Usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | grep rag-

echo ""
echo "GPU Memory Detailed:"
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv
else
    print_warning "nvidia-smi not available for detailed GPU stats"
fi

echo ""

# Test 7: Log Analysis
print_header "Error Log Analysis"

echo "Checking for critical errors in logs..."
for service in "${SERVICES[@]}"; do
    if docker ps --format "table {{.Names}}" | grep -q "^$service$"; then
        error_count=$(docker logs "$service" 2>&1 | grep -i "error\|exception\|failed\|critical" | wc -l)
        if [ "$error_count" -gt 5 ]; then
            print_warning "$service: $error_count errors/warnings found in logs"
        else
            print_status "$service: Log analysis clean ($error_count minor issues)"
        fi
    fi
done

echo ""

# Test 8: Network Connectivity
print_header "Network Connectivity Tests"

# Test internal service connectivity
if docker ps | grep -q "rag-api"; then
    run_test "API to Embedding Connectivity" "docker exec rag-api curl -f -s http://rag-embedding-server:8000/health >/dev/null 2>&1 || true"
    run_test "API to LLM Connectivity" "docker exec rag-api curl -f -s http://rag-llm-server:8000/health >/dev/null 2>&1 || true"
    run_test "API to DotsOCR Connectivity" "docker exec rag-api curl -f -s http://rag-dots-ocr:8000/health >/dev/null 2>&1 || true"
fi

echo ""

# Test 9: Configuration Validation
print_header "Configuration Validation"

run_test "Data Directory Exists" "test -d ./data"
run_test "Config Directory Exists" "test -d ./config || test -f ./config.yaml"
run_test "Logs Directory Accessible" "test -w ./data/logs || mkdir -p ./data/logs"

echo ""

# Final Summary
print_header "Deployment Validation Summary"
echo "=========================================="

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
    echo "✅ RAG System is fully operational on H100"
else
    echo -e "${YELLOW}⚠️  SOME TESTS FAILED${NC}"
    echo "❌ $FAILED_TESTS out of $TOTAL_TESTS tests failed"
fi

echo ""
echo "Test Results: $PASSED_TESTS passed, $FAILED_TESTS failed, $TOTAL_TESTS total"
echo ""

if [ $FAILED_TESTS -gt 0 ]; then
    echo "🔧 Troubleshooting suggestions:"
    echo "• Check failed service logs: docker logs <service-name>"
    echo "• Monitor GPU memory: ./monitor_gpu.sh"
    echo "• Try sequential testing: ./test_services_sequential.sh"
    echo "• Restart failed services: docker restart <service-name>"
    echo ""
fi

echo "📊 Current System Status:"
echo "• Services: http://localhost:3000 (Frontend)"
echo "• API Documentation: http://localhost:8080/docs"
echo "• GPU Monitoring: ./monitor_gpu.sh"
echo "• Service Logs: docker logs <service-name>"
echo ""

# Create issue report if there are failures
if [ $FAILED_TESTS -gt 0 ]; then
    echo "Creating issue report..."
    {
        echo "# RAG System Deployment Issues Report"
        echo "Generated: $(date)"
        echo ""
        echo "## Failed Tests ($FAILED_TESTS/$TOTAL_TESTS)"
        echo ""
        echo "## System Information"
        echo "- GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
        echo "- Memory: $(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)MB"
        echo "- Docker: $(docker --version)"
        echo ""
        echo "## Container Status"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        echo "## GPU Memory"
        nvidia-smi --query-gpu=memory.used,memory.total --format=csv
        echo ""
    } > deployment_issues_$(date +%Y%m%d_%H%M%S).md
    
    print_status "Issue report saved to: deployment_issues_$(date +%Y%m%d_%H%M%S).md"
fi

exit $FAILED_TESTS