#!/bin/bash

echo "=========================================="
echo "RAG System Integration Tests"
echo "=========================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
PASSED=0
FAILED=0

# Base URLs
API_URL="http://localhost:8080"
FRONTEND_URL="http://localhost:3000"

print_test() {
    echo -e "\n${YELLOW}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}✓ PASS${NC} $1"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}✗ FAIL${NC} $1"
    ((FAILED++))
}

# Wait for services to be ready
wait_for_service() {
    local url=$1
    local name=$2
    local max_attempts=30
    local attempt=0
    
    echo "Waiting for $name to be ready..."
    while [ $attempt -lt $max_attempts ]; do
        if curl -s -f "$url" > /dev/null 2>&1; then
            echo "$name is ready!"
            return 0
        fi
        sleep 2
        ((attempt++))
    done
    echo "Timeout waiting for $name"
    return 1
}

# Test 1: Health Checks
print_test "1. Service Health Checks"

# API Health
if curl -s -f "$API_URL/health" > /dev/null 2>&1; then
    response=$(curl -s "$API_URL/health")
    if echo "$response" | grep -q "healthy"; then
        print_pass "API health check"
    else
        print_fail "API health check - unexpected response"
    fi
else
    print_fail "API health check - service not responding"
fi

# Frontend Health
if curl -s -f "$FRONTEND_URL/" > /dev/null 2>&1; then
    print_pass "Frontend is accessible"
else
    print_fail "Frontend is not accessible"
fi

# Test 2: API Endpoints
print_test "2. API Endpoint Tests"

# Test root endpoint
if response=$(curl -s -w "\n%{http_code}" "$API_URL/"); then
    http_code=$(echo "$response" | tail -1)
    if [ "$http_code" = "200" ]; then
        print_pass "API root endpoint"
    else
        print_fail "API root endpoint - HTTP $http_code"
    fi
else
    print_fail "API root endpoint - request failed"
fi

# Test 3: File Search
print_test "3. File Search Functionality"

search_response=$(curl -s -X POST "$API_URL/api/search" \
    -H "Content-Type: application/json" \
    -d '{
        "query": "test query",
        "max_results": 5
    }' 2>/dev/null)

if [ $? -eq 0 ]; then
    if echo "$search_response" | grep -q "results"; then
        print_pass "File search endpoint responds correctly"
    else
        print_fail "File search endpoint - unexpected response format"
        echo "Response: $search_response"
    fi
else
    print_fail "File search endpoint - request failed"
fi

# Test 4: Chat Session Management
print_test "4. Chat Session Management"

# Create session
session_response=$(curl -s -X POST "$API_URL/api/chat/sessions" \
    -H "Content-Type: application/json" \
    -d '{
        "user_id": "test_user",
        "title": "Test Session"
    }' 2>/dev/null)

if [ $? -eq 0 ]; then
    session_id=$(echo "$session_response" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$session_id" ]; then
        print_pass "Chat session creation"
        
        # Test 5: Send Message
        print_test "5. Send Chat Message"
        
        message_response=$(curl -s -X POST "$API_URL/api/chat/sessions/$session_id/messages" \
            -H "Content-Type: application/json" \
            -d '{
                "content": "Hello, this is a test",
                "use_rag": false
            }' 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            if echo "$message_response" | grep -q "content"; then
                print_pass "Chat message sent successfully"
            else
                print_fail "Chat message - unexpected response"
                echo "Response: $message_response"
            fi
        else
            print_fail "Chat message - request failed"
        fi
        
        # Test 6: Get Session History
        print_test "6. Get Session History"
        
        history_response=$(curl -s "$API_URL/api/chat/sessions/$session_id/messages" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            if echo "$history_response" | grep -q "messages"; then
                print_pass "Session history retrieval"
            else
                print_fail "Session history - unexpected response"
            fi
        else
            print_fail "Session history - request failed"
        fi
    else
        print_fail "Chat session creation - no session ID returned"
    fi
else
    print_fail "Chat session creation - request failed"
fi

# Test 7: File Upload
print_test "7. File Upload"

# Create a test file
echo "Test content for upload" > test_upload.txt

upload_response=$(curl -s -X POST "$API_URL/api/upload" \
    -F "files=@test_upload.txt" 2>/dev/null)

if [ $? -eq 0 ]; then
    if echo "$upload_response" | grep -q "success\|filename\|id"; then
        print_pass "File upload"
    else
        print_fail "File upload - unexpected response"
        echo "Response: $upload_response"
    fi
else
    print_fail "File upload - request failed"
fi

# Clean up test file
rm -f test_upload.txt

# Test 8: Frontend API Proxy
print_test "8. Frontend API Proxy"

# Test if frontend can reach API through proxy
proxy_response=$(curl -s "$FRONTEND_URL/health" 2>/dev/null)

if [ $? -eq 0 ]; then
    if echo "$proxy_response" | grep -q "healthy"; then
        print_pass "Frontend proxy to API working"
    else
        print_fail "Frontend proxy - unexpected response"
    fi
else
    print_fail "Frontend proxy - request failed"
fi

# Test 9: Mock Service Integration
print_test "9. Mock Service Integration"

# Test if API can reach mock LLM
llm_test=$(curl -s -X POST "$API_URL/api/chat/sessions/$session_id/messages" \
    -H "Content-Type: application/json" \
    -d '{
        "content": "Test RAG integration",
        "use_rag": true
    }' 2>/dev/null)

if [ $? -eq 0 ]; then
    if echo "$llm_test" | grep -q "content\|mock\|response"; then
        print_pass "Mock LLM integration"
    else
        print_fail "Mock LLM integration - unexpected response"
    fi
else
    print_fail "Mock LLM integration - request failed"
fi

# Test 10: Error Handling
print_test "10. Error Handling"

# Test invalid endpoint
invalid_response=$(curl -s -w "\n%{http_code}" "$API_URL/api/invalid_endpoint" 2>/dev/null)
http_code=$(echo "$invalid_response" | tail -1)

if [ "$http_code" = "404" ] || [ "$http_code" = "405" ]; then
    print_pass "Proper error handling for invalid endpoints"
else
    print_fail "Error handling - unexpected HTTP code: $http_code"
fi

# Summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}Passed:${NC} $PASSED"
echo -e "${RED}Failed:${NC} $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo ""
    echo "Troubleshooting tips:"
    echo "1. Check service logs: docker logs rag-test-api"
    echo "2. Verify all services are running: docker ps"
    echo "3. Check network connectivity: docker network inspect rag-test-network"
    exit 1
fi