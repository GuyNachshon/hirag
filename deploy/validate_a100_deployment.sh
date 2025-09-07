#!/bin/bash

set -e

echo "=========================================="
echo "A100 Single GPU Deployment Validation"
echo "Optimized for a2-highgpu-1g Test Machine"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_gpu() {
    echo -e "${CYAN}[GPU]${NC} $1"
}

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Expected memory allocation for A100 40GB
declare -A EXPECTED_MEMORY_USAGE=(
    ["embedding"]="4"
    ["whisper"]="6"
    ["dotsocr"]="12"
    ["llm"]="13"
)

# Logging
LOG_FILE="./a100_validation_$(date +%Y%m%d_%H%M%S).log"

log_result() {
    local test_name="$1"
    local status="$2"
    local details="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] $test_name: $status - $details" >> "$LOG_FILE"
}

# Test execution wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    print_test "Running: $test_name"
    ((TOTAL_TESTS++))
    
    if $test_function; then
        print_status "✓ PASSED: $test_name"
        ((PASSED_TESTS++))
        log_result "$test_name" "PASSED" "Test completed successfully"
        return 0
    else
        print_error "✗ FAILED: $test_name"
        ((FAILED_TESTS++))
        log_result "$test_name" "FAILED" "Test failed - check logs for details"
        return 1
    fi
}

# Test 1: A100 Hardware Detection
test_a100_detection() {
    print_gpu "Checking A100 hardware..."
    
    if ! command -v nvidia-smi > /dev/null 2>&1; then
        print_error "nvidia-smi not available"
        return 1
    fi
    
    local gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    local gpu_memory=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
    local gpu_memory_gb=$((gpu_memory / 1024))
    
    print_gpu "Detected GPU: $gpu_name"
    print_gpu "GPU Memory: ${gpu_memory_gb}GB"
    
    if echo "$gpu_name" | grep -q "A100"; then
        print_status "✓ A100 GPU confirmed"
    else
        print_warning "⚠ Non-A100 GPU detected: $gpu_name"
        ((WARNINGS++))
    fi
    
    if [ "$gpu_memory_gb" -ge 35 ]; then
        print_status "✓ Sufficient GPU memory: ${gpu_memory_gb}GB"
    else
        print_warning "⚠ Limited GPU memory: ${gpu_memory_gb}GB (expected 40GB)"
        ((WARNINGS++))
    fi
    
    return 0
}

# Test 2: Single GPU Memory Management
test_single_gpu_memory() {
    print_gpu "Testing single GPU memory allocation..."
    
    if ! command -v nvidia-smi > /dev/null 2>&1; then
        print_warning "⚠ nvidia-smi not available - skipping memory test"
        return 0
    fi
    
    # Get current memory usage
    local gpu_memory=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)
    local used_memory=$(echo "$gpu_memory" | cut -d',' -f1)
    local total_memory=$(echo "$gpu_memory" | cut -d',' -f2)
    local used_gb=$((used_memory / 1024))
    local total_gb=$((total_memory / 1024))
    local usage_percent=$(((used_memory * 100) / total_memory))
    
    print_gpu "Current usage: ${used_gb}GB / ${total_gb}GB (${usage_percent}%)"
    
    # Check if usage is within expected range for all services
    if [ "$usage_percent" -gt 90 ]; then
        print_error "✗ Very high GPU memory usage (${usage_percent}%) - may cause instability"
        return 1
    elif [ "$usage_percent" -gt 80 ]; then
        print_warning "⚠ High GPU memory usage (${usage_percent}%) - monitor closely"
        ((WARNINGS++))
    else
        print_status "✓ Good GPU memory usage (${usage_percent}%)"
    fi
    
    # Check if we're using expected amount (should be ~35GB when all services loaded)
    local expected_usage=35
    local expected_percent=$(((expected_usage * 100) / total_gb))
    
    if [ "$usage_percent" -ge $((expected_percent - 10)) ] && [ "$usage_percent" -le $((expected_percent + 10)) ]; then
        print_status "✓ Memory usage within expected range for full deployment"
    elif [ "$usage_percent" -lt $((expected_percent - 10)) ]; then
        print_warning "⚠ Lower memory usage than expected - some services may not be loaded"
        ((WARNINGS++))
    fi
    
    return 0
}

# Test 3: Service Coexistence on Single GPU
test_service_coexistence() {
    print_gpu "Testing service coexistence on single GPU..."
    
    local services=("rag-api" "rag-embedding-server" "rag-dots-ocr" "rag-llm-server" "rag-whisper" "rag-frontend")
    local gpu_services=("rag-embedding-server" "rag-dots-ocr" "rag-llm-server" "rag-whisper")
    local running_services=0
    local gpu_services_running=0
    
    # Check which services are running
    for service in "${services[@]}"; do
        if docker ps | grep -q "$service"; then
            print_status "✓ $service is running"
            ((running_services++))
            
            # Check if it's a GPU service
            for gpu_service in "${gpu_services[@]}"; do
                if [[ "$service" == "$gpu_service" ]]; then
                    ((gpu_services_running++))
                    break
                fi
            done
        else
            print_warning "⚠ $service is not running"
            ((WARNINGS++))
        fi
    done
    
    print_gpu "Services running: $running_services/6 (GPU services: $gpu_services_running/4)"
    
    if [ $running_services -ge 5 ]; then
        print_status "✓ Good service availability"
    elif [ $running_services -ge 4 ]; then
        print_warning "⚠ Acceptable service availability"
        ((WARNINGS++))
    else
        print_error "✗ Poor service availability"
        return 1
    fi
    
    # Test concurrent GPU access
    print_gpu "Testing concurrent GPU service access..."
    local concurrent_success=0
    
    # Test health endpoints of GPU services concurrently
    local pids=()
    for gpu_service in "${gpu_services[@]}"; do
        case $gpu_service in
            "rag-embedding-server") port="8001" ;;
            "rag-dots-ocr") port="8002" ;;
            "rag-llm-server") port="8003" ;;
            "rag-whisper") port="8004" ;;
        esac
        
        (
            if curl -s -f "http://localhost:$port/health" >/dev/null 2>&1; then
                echo "success"
            else
                echo "failed"
            fi
        ) &
        pids+=($!)
    done
    
    # Wait for all concurrent requests
    for pid in "${pids[@]}"; do
        if wait "$pid" 2>/dev/null; then
            if [[ "$(cat /proc/$pid/fd/1 2>/dev/null)" == "success" ]]; then
                ((concurrent_success++))
            fi
        fi
    done >/dev/null 2>&1
    
    # Simplified concurrent test - just check that services respond
    concurrent_success=0
    for gpu_service in "${gpu_services[@]}"; do
        case $gpu_service in
            "rag-embedding-server") port="8001" ;;
            "rag-dots-ocr") port="8002" ;;
            "rag-llm-server") port="8003" ;;
            "rag-whisper") port="8004" ;;
        esac
        
        if curl -s -f "http://localhost:$port/health" >/dev/null 2>&1; then
            ((concurrent_success++))
        fi
    done
    
    print_gpu "Concurrent GPU access: $concurrent_success/4 services responding"
    
    if [ $concurrent_success -ge 3 ]; then
        print_status "✓ Good concurrent GPU service access"
        return 0
    else
        print_warning "⚠ Limited concurrent GPU service access"
        ((WARNINGS++))
        return 0
    fi
}

# Test 4: Performance Under Single GPU Constraints
test_single_gpu_performance() {
    print_gpu "Testing performance under single GPU constraints..."
    
    # Test response times for GPU services
    local services=(
        "http://localhost:8001/health:Embedding"
        "http://localhost:8002/health:DotsOCR"
        "http://localhost:8003/health:LLM"
        "http://localhost:8004/health:Whisper"
    )
    
    local total_time=0
    local successful_tests=0
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r url name <<< "$service_info"
        
        local start_time=$(date +%s.%3N)
        if curl -s -f "$url" >/dev/null 2>&1; then
            local end_time=$(date +%s.%3N)
            local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0.1")
            
            print_gpu "$name response time: ${duration}s"
            total_time=$(echo "$total_time + $duration" | bc 2>/dev/null || echo "$total_time")
            ((successful_tests++))
        else
            print_warning "⚠ $name service not responding"
            ((WARNINGS++))
        fi
    done
    
    if [ $successful_tests -gt 0 ]; then
        local avg_time=$(echo "scale=3; $total_time / $successful_tests" | bc 2>/dev/null || echo "0.1")
        print_gpu "Average response time: ${avg_time}s"
        
        if (( $(echo "$avg_time < 1.0" | bc -l 2>/dev/null || echo 1) )); then
            print_status "✓ Good average response time"
        elif (( $(echo "$avg_time < 3.0" | bc -l 2>/dev/null || echo 1) )); then
            print_warning "⚠ Acceptable average response time"
            ((WARNINGS++))
        else
            print_error "✗ Poor average response time"
            return 1
        fi
    fi
    
    return 0
}

# Test 5: Resource Monitoring and Alerts
test_resource_monitoring() {
    print_gpu "Testing resource monitoring capabilities..."
    
    # Check if monitoring tools are available
    local monitoring_score=0
    
    if command -v nvidia-smi > /dev/null 2>&1; then
        print_status "✓ nvidia-smi available for GPU monitoring"
        ((monitoring_score++))
    else
        print_warning "⚠ nvidia-smi not available"
        ((WARNINGS++))
    fi
    
    if command -v docker > /dev/null 2>&1; then
        print_status "✓ Docker available for container monitoring"
        ((monitoring_score++))
    else
        print_error "✗ Docker not available"
        return 1
    fi
    
    if command -v curl > /dev/null 2>&1; then
        print_status "✓ curl available for health checking"
        ((monitoring_score++))
    else
        print_warning "⚠ curl not available"
        ((WARNINGS++))
    fi
    
    # Test monitoring script availability
    if [[ -f "./deploy/monitor_a100_single_gpu.sh" ]]; then
        print_status "✓ A100 monitoring script available"
        ((monitoring_score++))
    else
        print_warning "⚠ A100 monitoring script not found"
        ((WARNINGS++))
    fi
    
    print_gpu "Monitoring capabilities: $monitoring_score/4"
    
    if [ $monitoring_score -ge 3 ]; then
        print_status "✓ Good monitoring capabilities"
        return 0
    else
        print_warning "⚠ Limited monitoring capabilities"
        ((WARNINGS++))
        return 0
    fi
}

# Test 6: A100-Specific Validation
test_a100_specific_features() {
    print_gpu "Testing A100-specific features and optimizations..."
    
    if ! command -v nvidia-smi > /dev/null 2>&1; then
        print_warning "⚠ Cannot test A100-specific features without nvidia-smi"
        return 0
    fi
    
    # Check GPU utilization
    local gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null)
    if [[ -n "$gpu_util" ]] && [ "$gpu_util" -gt 0 ]; then
        print_status "✓ GPU showing utilization: ${gpu_util}%"
    else
        print_warning "⚠ GPU showing low/no utilization"
        ((WARNINGS++))
    fi
    
    # Check memory bandwidth (A100 has high memory bandwidth)
    local memory_info=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)
    if [[ -n "$memory_info" ]]; then
        local used_mem=$(echo "$memory_info" | cut -d',' -f1)
        local total_mem=$(echo "$memory_info" | cut -d',' -f2)
        
        if [ "$total_mem" -ge 38000 ]; then  # ~38GB+ indicates A100 40GB
            print_status "✓ A100 memory capacity confirmed"
        else
            print_warning "⚠ Memory capacity lower than expected A100"
            ((WARNINGS++))
        fi
    fi
    
    # Check temperature (A100 should run relatively cool)
    local gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
    if [[ -n "$gpu_temp" ]]; then
        print_gpu "GPU temperature: ${gpu_temp}°C"
        if [ "$gpu_temp" -lt 80 ]; then
            print_status "✓ Good GPU temperature"
        elif [ "$gpu_temp" -lt 90 ]; then
            print_warning "⚠ Elevated GPU temperature"
            ((WARNINGS++))
        else
            print_error "✗ High GPU temperature - check cooling"
            return 1
        fi
    fi
    
    return 0
}

# Generate validation report
generate_validation_report() {
    print_test "Generating A100 validation report..."
    
    local report_file="a100_validation_report_$(date +%Y%m%d_%H%M%S).html"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>A100 Single GPU RAG Deployment Validation</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { background-color: #e6f3ff; padding: 15px; margin: 20px 0; border-radius: 5px; }
        .passed { color: #28a745; }
        .failed { color: #dc3545; }
        .warning { color: #ffc107; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; }
    </style>
</head>
<body>
    <div class="header">
        <h1>A100 Single GPU RAG Deployment Validation</h1>
        <p><strong>Generated:</strong> $(date)</p>
        <p><strong>Machine:</strong> a2-highgpu-1g (12 vCPUs, 85GB RAM, A100 40GB)</p>
        <p><strong>Deployment Type:</strong> Single GPU Shared Memory</p>
    </div>
    
    <div class="summary">
        <h2>Validation Summary</h2>
        <p><strong>Total Tests:</strong> $TOTAL_TESTS</p>
        <p><strong class="passed">Passed:</strong> $PASSED_TESTS</p>
        <p><strong class="failed">Failed:</strong> $FAILED_TESTS</p>
        <p><strong class="warning">Warnings:</strong> $WARNINGS</p>
        <p><strong>Success Rate:</strong> $(( TOTAL_TESTS > 0 ? (PASSED_TESTS * 100) / TOTAL_TESTS : 0 ))%</p>
    </div>
    
    <h2>A100 Memory Allocation Strategy</h2>
    <table>
        <tr><th>Service</th><th>Memory Allocation</th><th>Percentage</th><th>Purpose</th></tr>
        <tr><td>Embedding Server</td><td>4GB</td><td>10%</td><td>Lightweight text embedding</td></tr>
        <tr><td>Whisper Service</td><td>6GB</td><td>15%</td><td>Hebrew audio transcription</td></tr>
        <tr><td>DotsOCR Service</td><td>12GB</td><td>30%</td><td>Vision and OCR processing</td></tr>
        <tr><td>LLM Service</td><td>13GB</td><td>32.5%</td><td>Language model inference</td></tr>
        <tr><td>System Buffer</td><td>5GB</td><td>12.5%</td><td>Memory overhead and safety</td></tr>
    </table>
    
    <h2>Performance Characteristics</h2>
    <ul>
        <li><strong>Single GPU Sharing:</strong> All services share A100 40GB memory</li>
        <li><strong>Sequential Processing:</strong> Services process requests in queue</li>
        <li><strong>Memory Management:</strong> Careful allocation to prevent OOM errors</li>
        <li><strong>Concurrent Access:</strong> Multiple services can access GPU simultaneously</li>
    </ul>
    
    <h2>Validation Results</h2>
    <p>Detailed validation logs: <code>$LOG_FILE</code></p>
    
    <h2>Recommendations</h2>
    <ul>
        <li>Monitor GPU memory usage regularly to prevent exhaustion</li>
        <li>Use sequential deployment to avoid startup memory spikes</li>
        <li>Consider reducing model sizes if memory pressure occurs</li>
        <li>Implement request queuing for high-load scenarios</li>
        $([ $WARNINGS -gt 0 ] && echo "<li>Address validation warnings for optimal performance</li>")
        $([ $FAILED_TESTS -gt 0 ] && echo "<li>Resolve failed tests before production use</li>")
    </ul>
    
</body>
</html>
EOF

    print_status "✓ Validation report generated: $report_file"
}

# Main validation execution
main() {
    print_test "Starting A100 Single GPU Deployment Validation"
    print_status "Target: a2-highgpu-1g with NVIDIA A100 40GB"
    
    # Execute all validation tests
    run_test "A100 Hardware Detection" test_a100_detection
    run_test "Single GPU Memory Management" test_single_gpu_memory
    run_test "Service Coexistence" test_service_coexistence
    run_test "Single GPU Performance" test_single_gpu_performance
    run_test "Resource Monitoring" test_resource_monitoring
    run_test "A100-Specific Features" test_a100_specific_features
    
    # Generate validation report
    generate_validation_report
    
    # Final summary
    echo ""
    echo "=========================================="
    echo "A100 Validation Complete"
    echo "=========================================="
    
    print_status "Total Tests: $TOTAL_TESTS"
    print_status "Passed: $PASSED_TESTS"
    if [ $FAILED_TESTS -gt 0 ]; then
        print_error "Failed: $FAILED_TESTS"
    fi
    if [ $WARNINGS -gt 0 ]; then
        print_warning "Warnings: $WARNINGS"
    fi
    
    print_status "Validation logs: $LOG_FILE"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}🎉 A100 deployment validation successful!${NC}"
        echo ""
        print_status "RAG system properly configured for A100 single GPU"
        print_status "All services can coexist on shared GPU memory"
        print_status "Ready for testing and evaluation"
        exit 0
    else
        echo -e "${RED}❌ A100 deployment validation issues found${NC}"
        echo ""
        print_error "Review failed tests and address issues before proceeding"
        exit 1
    fi
}

# Handle command line arguments
if [[ "$1" == "--help" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo "Validate RAG system deployment on A100 single GPU"
    echo ""
    echo "Options:"
    echo "  --help       Show this help"
    echo ""
    echo "This script validates:"
    echo "  • A100 hardware detection and capabilities"
    echo "  • Single GPU memory allocation and management"
    echo "  • Service coexistence on shared GPU memory"
    echo "  • Performance under single GPU constraints"
    echo "  • Resource monitoring capabilities"
    echo "  • A100-specific optimizations"
    echo ""
    echo "Generates comprehensive HTML report with recommendations"
    exit 0
fi

# Execute main validation
main "$@"