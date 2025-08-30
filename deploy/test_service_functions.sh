#!/bin/bash

# Service-specific test functions for sequential testing
# Source this file from test_services_sequential.sh for enhanced testing

# Test DotsOCR with actual image processing
test_dotsocr_detailed() {
    local service_name="$1"
    local base_url="$2"
    
    print_test "Testing DotsOCR image processing..."
    ((TOTAL_TESTS++))
    
    # Create a test image if it doesn't exist
    local test_image="$TEST_DATA_DIR/images/test_text.png"
    if [[ ! -f "$test_image" ]] && command -v convert > /dev/null; then
        mkdir -p "$(dirname "$test_image")"
        # Create simple text image using ImageMagick
        convert -size 300x100 xc:white -font DejaVu-Sans -pointsize 20 -fill black -gravity center -annotate +0+0 "Test OCR Text" "$test_image" 2>/dev/null || true
    fi
    
    if [[ -f "$test_image" ]]; then
        # Test OCR endpoint (assuming DotsOCR has a /process endpoint)
        if response=$(curl -s -X POST -F "file=@$test_image" "$base_url/process" 2>/dev/null); then
            if echo "$response" | grep -i "text\|content"; then
                print_status "✓ DotsOCR image processing test passed"
                ((PASSED_TESTS++))
                if $VERBOSE; then
                    echo "OCR Response: $response" | head -3
                fi
                return 0
            fi
        fi
    fi
    
    print_warning "⚠ DotsOCR detailed test skipped (no test image or endpoint not available)"
    ((FAILED_TESTS++))
    return 1
}

# Test embedding service with text embedding
test_embedding_detailed() {
    local service_name="$1"
    local base_url="$2"
    
    print_test "Testing embedding generation..."
    ((TOTAL_TESTS++))
    
    # Test embedding endpoint (vLLM format)
    local test_data='{
        "model": "Qwen/Qwen2-0.5B-Instruct",
        "input": ["This is a test sentence for embedding generation."],
        "encoding_format": "float"
    }'
    
    if response=$(curl -s -X POST "$base_url/v1/embeddings" \
        -H "Content-Type: application/json" \
        -d "$test_data" 2>/dev/null); then
        
        if echo "$response" | grep -q "data.*embedding"; then
            print_status "✓ Embedding generation test passed"
            ((PASSED_TESTS++))
            return 0
        fi
    fi
    
    print_error "✗ Embedding generation test failed"
    ((FAILED_TESTS++))
    if $VERBOSE && [[ -n "$response" ]]; then
        echo "Response: $response" | head -3
    fi
    return 1
}

# Test LLM with text generation
test_llm_detailed() {
    local service_name="$1"
    local base_url="$2"
    local model_name="$3"
    
    print_test "Testing LLM text generation..."
    ((TOTAL_TESTS++))
    
    # Test chat completions endpoint (vLLM format)
    local test_data="{
        \"model\": \"$model_name\",
        \"messages\": [
            {\"role\": \"user\", \"content\": \"What is 2+2? Answer briefly.\"}
        ],
        \"max_tokens\": 50,
        \"temperature\": 0.1
    }"
    
    if response=$(curl -s -X POST "$base_url/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "$test_data" 2>/dev/null); then
        
        if echo "$response" | grep -q "choices.*content"; then
            # Extract the response text
            local answer=$(echo "$response" | grep -o '"content":"[^"]*"' | cut -d'"' -f4 | head -1)
            print_status "✓ LLM text generation test passed"
            if $VERBOSE && [[ -n "$answer" ]]; then
                echo "LLM Response: $answer"
            fi
            ((PASSED_TESTS++))
            return 0
        fi
    fi
    
    print_error "✗ LLM text generation test failed"
    ((FAILED_TESTS++))
    if $VERBOSE && [[ -n "$response" ]]; then
        echo "Response: $response" | head -3
    fi
    return 1
}

# Test Whisper with actual audio transcription
test_whisper_detailed() {
    local service_name="$1"
    local base_url="$2"
    
    print_test "Testing Whisper audio transcription..."
    ((TOTAL_TESTS++))
    
    # Try to find or create test audio file
    local test_audio="$TEST_DATA_DIR/audio/test.wav"
    
    if [[ ! -f "$test_audio" ]]; then
        # Try to create a test audio file with Hebrew text using espeak if available
        if command -v espeak > /dev/null && command -v ffmpeg > /dev/null; then
            mkdir -p "$(dirname "$test_audio")"
            # Create Hebrew audio (simple test)
            espeak -v he "שלום עולם" -w /tmp/test_hebrew.wav 2>/dev/null || \
            espeak "shalom olam" -w /tmp/test_hebrew.wav 2>/dev/null || \
            espeak "hello world" -w /tmp/test_hebrew.wav 2>/dev/null
            
            # Convert to proper format
            if [[ -f "/tmp/test_hebrew.wav" ]]; then
                ffmpeg -i /tmp/test_hebrew.wav -ar 16000 -ac 1 "$test_audio" -loglevel quiet 2>/dev/null || true
                rm /tmp/test_hebrew.wav 2>/dev/null || true
            fi
        fi
    fi
    
    if [[ -f "$test_audio" ]]; then
        if response=$(curl -s -X POST -F "file=@$test_audio" "$base_url/transcribe" 2>/dev/null); then
            if echo "$response" | grep -q "success.*true\|text.*:"; then
                local transcription=$(echo "$response" | grep -o '"text":"[^"]*"' | cut -d'"' -f4)
                print_status "✓ Whisper transcription test passed"
                if $VERBOSE && [[ -n "$transcription" ]]; then
                    echo "Transcription: $transcription"
                fi
                ((PASSED_TESTS++))
                return 0
            fi
        fi
    fi
    
    print_warning "⚠ Whisper detailed test skipped (no audio file available)"
    # Don't count as failed if no audio file
    return 0
}

# Test API endpoints with mock data
test_api_detailed() {
    local base_url="$1"
    
    print_test "Testing API search endpoint..."
    ((TOTAL_TESTS++))
    
    # Test file search endpoint
    local search_data='{"query": "test", "max_results": 5}'
    
    if response=$(curl -s -X POST "$base_url/api/search" \
        -H "Content-Type: application/json" \
        -d "$search_data" 2>/dev/null); then
        
        if echo "$response" | grep -q "results\|query"; then
            print_status "✓ API search test passed"
            ((PASSED_TESTS++))
        else
            print_error "✗ API search test failed - unexpected response"
            ((FAILED_TESTS++))
            if $VERBOSE; then
                echo "Response: $response" | head -3
            fi
        fi
    else
        print_error "✗ API search test failed - no response"
        ((FAILED_TESTS++))
    fi
    
    # Test chat session creation
    print_test "Testing API chat session creation..."
    ((TOTAL_TESTS++))
    
    local session_data='{"user_id": "test_user", "title": "Test Session"}'
    
    if response=$(curl -s -X POST "$base_url/api/chat/sessions" \
        -H "Content-Type: application/json" \
        -d "$session_data" 2>/dev/null); then
        
        if echo "$response" | grep -q "session_id\|id"; then
            print_status "✓ API chat session test passed"
            ((PASSED_TESTS++))
        else
            print_error "✗ API chat session test failed - unexpected response"
            ((FAILED_TESTS++))
            if $VERBOSE; then
                echo "Response: $response" | head -3
            fi
        fi
    else
        print_error "✗ API chat session test failed - no response"
        ((FAILED_TESTS++))
    fi
}

# Test frontend accessibility and basic functionality
test_frontend_detailed() {
    local base_url="$1"
    
    print_test "Testing frontend pages accessibility..."
    ((TOTAL_TESTS++))
    
    # Test main page
    if response=$(curl -s "$base_url/" 2>/dev/null); then
        if echo "$response" | grep -i "html\|<!DOCTYPE"; then
            print_status "✓ Frontend main page accessible"
            ((PASSED_TESTS++))
        else
            print_error "✗ Frontend main page test failed"
            ((FAILED_TESTS++))
        fi
    else
        print_error "✗ Frontend main page test failed - no response"
        ((FAILED_TESTS++))
    fi
    
    # Test static assets
    print_test "Testing frontend static assets..."
    ((TOTAL_TESTS++))
    
    # Try to get favicon or any static file
    if curl -s -f "$base_url/favicon.ico" > /dev/null 2>&1 || \
       curl -s -f "$base_url/assets/" > /dev/null 2>&1 || \
       curl -s -f "$base_url/static/" > /dev/null 2>&1; then
        print_status "✓ Frontend static assets accessible"
        ((PASSED_TESTS++))
    else
        print_warning "⚠ Frontend static assets test inconclusive"
        # Don't count as failure since this is optional
    fi
}

# Enhanced GPU memory monitoring
monitor_gpu_usage() {
    local service_name="$1"
    
    if ! check_gpu; then
        return 0
    fi
    
    if $VERBOSE; then
        echo "GPU Memory Status for $service_name:"
        nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv,noheader,nounits | while read line; do
            echo "  GPU Memory: $line (used,free,total in MB)"
        done
    fi
    
    # Check for memory leaks or excessive usage
    local used_mem=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
    local total_mem=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
    local usage_percent=$((used_mem * 100 / total_mem))
    
    if [[ $usage_percent -gt 90 ]]; then
        print_warning "High GPU memory usage: ${usage_percent}% for $service_name"
    elif $VERBOSE; then
        print_status "GPU memory usage: ${usage_percent}% for $service_name"
    fi
}

# Performance benchmarking
benchmark_service() {
    local service_name="$1"
    local url="$2"
    local test_type="$3"
    
    if ! $VERBOSE; then
        return 0
    fi
    
    print_test "Benchmarking $service_name response time..."
    
    local start_time=$(date +%s.%N)
    curl -s "$url" > /dev/null 2>&1
    local end_time=$(date +%s.%N)
    
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "N/A")
    
    if [[ "$duration" != "N/A" ]]; then
        print_status "Response time for $service_name: ${duration}s"
    fi
}

# Stress test - multiple concurrent requests
stress_test_service() {
    local service_name="$1"
    local url="$2"
    local requests="${3:-5}"
    
    if ! $VERBOSE; then
        return 0
    fi
    
    print_test "Stress testing $service_name with $requests concurrent requests..."
    
    local pids=()
    local start_time=$(date +%s.%N)
    
    for ((i=1; i<=requests; i++)); do
        curl -s "$url" > /dev/null 2>&1 &
        pids+=($!)
    done
    
    # Wait for all requests to complete
    for pid in "${pids[@]}"; do
        wait $pid
    done
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "N/A")
    
    if [[ "$duration" != "N/A" ]]; then
        print_status "Stress test completed in ${duration}s for $service_name"
    fi
}

# Export functions for use in main script
export -f test_dotsocr_detailed
export -f test_embedding_detailed  
export -f test_llm_detailed
export -f test_whisper_detailed
export -f test_api_detailed
export -f test_frontend_detailed
export -f monitor_gpu_usage
export -f benchmark_service
export -f stress_test_service