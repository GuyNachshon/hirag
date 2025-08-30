#!/bin/bash

echo "=========================================="
echo "Validating RAG System Offline Deployment"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Track validation results
PASSED=0
FAILED=0

validate_service() {
    local service_name="$1"
    local url="$2"
    local expected_status="$3"
    
    print_test "Testing $service_name at $url"
    
    if response=$(curl -s -w "%{http_code}" -o /dev/null --max-time 10 "$url" 2>/dev/null); then
        if [[ "$response" == "$expected_status" ]]; then
            print_status "✓ $service_name is responding (HTTP $response)"
            ((PASSED++))
            return 0
        else
            print_error "✗ $service_name returned HTTP $response (expected $expected_status)"
            ((FAILED++))
            return 1
        fi
    else
        print_error "✗ $service_name is not responding at $url"
        ((FAILED++))
        return 1
    fi
}

# Check Docker containers are running
print_test "Checking container status..."
CONTAINERS=("rag-dots-ocr" "rag-embedding-server" "rag-llm-server" "rag-api")

for container in "${CONTAINERS[@]}"; do
    if docker ps | grep -q "$container"; then
        status=$(docker inspect --format='{{.State.Status}}' "$container")
        print_status "✓ $container is $status"
        ((PASSED++))
    else
        print_error "✗ $container is not running"
        ((FAILED++))
    fi
done

echo ""

# Test service endpoints
print_test "Testing service health endpoints..."

# Test API health
validate_service "API Service" "http://localhost:8080/health" "200"

# Test DotsOCR health  
validate_service "DotsOCR Service" "http://localhost:8002/health" "200"

# Test Embedding service
validate_service "Embedding Service" "http://localhost:8001/health" "200"

# Test LLM service
validate_service "LLM Service" "http://localhost:8003/health" "200"

echo ""

# Test API endpoints
print_test "Testing API functionality..."

# Test root endpoint
if validate_service "API Root" "http://localhost:8080/" "200"; then
    # Try to get a simple response
    if response=$(curl -s "http://localhost:8080/" 2>/dev/null); then
        if echo "$response" | grep -q "Offline RAG API"; then
            print_status "✓ API root endpoint returns correct response"
            ((PASSED++))
        else
            print_warning "⚠ API root endpoint responds but content unexpected"
        fi
    fi
fi

echo ""

# Check data directories
print_test "Checking data directories..."
DATA_DIRS=("./data/input" "./data/working" "./data/logs" "./data/cache")

for dir in "${DATA_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        print_status "✓ $dir exists"
        ((PASSED++))
    else
        print_error "✗ $dir missing"
        ((FAILED++))
    fi
done

echo ""

# Check configuration
print_test "Checking configuration..."
if [[ -f "./config/config.yaml" ]]; then
    print_status "✓ Configuration file exists"
    ((PASSED++))
    
    # Basic validation of config content
    if grep -q "rag-llm-server" "./config/config.yaml"; then
        print_status "✓ Configuration uses Docker service names"
        ((PASSED++))
    else
        print_warning "⚠ Configuration might not be using Docker service names"
    fi
else
    print_error "✗ Configuration file missing"
    ((FAILED++))
fi

echo ""

# Network connectivity test
print_test "Testing inter-service communication..."
if docker exec rag-api ping -c 1 rag-llm-server > /dev/null 2>&1; then
    print_status "✓ API can reach LLM service"
    ((PASSED++))
else
    print_error "✗ API cannot reach LLM service"
    ((FAILED++))
fi

if docker exec rag-api ping -c 1 rag-embedding-server > /dev/null 2>&1; then
    print_status "✓ API can reach Embedding service"
    ((PASSED++))
else
    print_error "✗ API cannot reach Embedding service"
    ((FAILED++))
fi

echo ""

# Summary
print_test "Validation Summary"
echo "=========================================="
if [[ $FAILED -eq 0 ]]; then
    print_status "🎉 ALL TESTS PASSED! ($PASSED/$((PASSED + FAILED)))"
    print_status "Your RAG system is ready for use!"
    echo ""
    print_status "Try these commands:"
    print_status "  curl http://localhost:8080/health"
    print_status "  curl http://localhost:8080/"
    echo ""
    print_status "Add documents to ./data/input/ and start using the system!"
    exit 0
else
    print_error "❌ SOME TESTS FAILED ($FAILED failed, $PASSED passed)"
    print_error "Please check the failed services and try again"
    echo ""
    print_status "Troubleshooting tips:"
    print_status "1. Check container logs: docker logs <container-name>"
    print_status "2. Restart failed services: ./deploy_complete.sh"
    print_status "3. Check network: docker network ls"
    exit 1
fi