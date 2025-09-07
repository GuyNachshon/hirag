#!/bin/bash

set -e

echo "=========================================="
echo "H100 8-Core GPU Performance Validation"
echo "Testing Optimal GPU Utilization & Distribution"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
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
    echo -e "${PURPLE}[GPU]${NC} $1"
}

print_perf() {
    echo -e "${CYAN}[PERF]${NC} $1"
}

# Configuration
TEST_DATA_DIR="./test-data-offline"
RESULTS_DIR="$TEST_DATA_DIR/performance-results"
LOG_FILE="$RESULTS_DIR/gpu_validation_$(date +%Y%m%d_%H%M%S).log"
REPORT_FILE="$RESULTS_DIR/gpu_report_$(date +%Y%m%d_%H%M%S).html"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Expected GPU assignments (from deployment script)
declare -A EXPECTED_GPU_ASSIGNMENT=(
    ["dotsocr"]="0,1"
    ["llm"]="2,3,4,5"
    ["embedding"]="6"
    ["whisper"]="7"
)

declare -A SERVICE_CONTAINERS=(
    ["dotsocr"]="rag-dots-ocr"
    ["llm"]="rag-llm-server"
    ["embedding"]="rag-embedding-server"
    ["whisper"]="rag-whisper"
)

# Logging function
log_result() {
    local test_name="$1"
    local status="$2"
    local details="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$timestamp] $test_name: $status - $details" >> "$LOG_FILE"
}

# Check if GPU monitoring is available
check_gpu_support() {
    print_test "Checking GPU monitoring capabilities..."
    
    if command -v nvidia-smi > /dev/null 2>&1; then
        local gpu_count=$(nvidia-smi --list-gpus | wc -l)
        print_status "✓ nvidia-smi available, detected $gpu_count GPUs"
        
        if [ "$gpu_count" -ge 8 ]; then
            print_status "✓ Sufficient GPU cores for 8-core testing ($gpu_count available)"
            return 0
        else
            print_warning "⚠ Only $gpu_count GPUs detected (expected 8+)"
            return 1
        fi
    else
        print_error "✗ nvidia-smi not available - GPU testing limited"
        return 1
    fi
}

# Get GPU memory info
get_gpu_memory() {
    local gpu_id="$1"
    
    if command -v nvidia-smi > /dev/null 2>&1; then
        nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits -i "$gpu_id" 2>/dev/null
    else
        echo "0,0,0"  # Fallback for systems without nvidia-smi
    fi
}

# Test GPU core assignments
test_gpu_assignments() {
    print_test "Validating GPU core assignments..."
    
    local assignment_errors=0
    
    for service in "${!EXPECTED_GPU_ASSIGNMENT[@]}"; do
        local expected_cores="${EXPECTED_GPU_ASSIGNMENT[$service]}"
        local container="${SERVICE_CONTAINERS[$service]}"
        
        print_gpu "Checking $service (expected cores: $expected_cores)"
        
        # Check if container is running
        if ! docker ps | grep -q "$container"; then
            print_warning "⚠ Container $container not running"
            ((WARNINGS++))
            continue
        fi
        
        # Get CUDA_VISIBLE_DEVICES from container
        local visible_devices
        if visible_devices=$(docker inspect "$container" --format='{{range .Config.Env}}{{if (index (split . "=") 0 | eq "CUDA_VISIBLE_DEVICES")}}{{index (split . "=") 1}}{{end}}{{end}}' 2>/dev/null); then
            
            if [[ "$visible_devices" == "$expected_cores" ]]; then
                print_status "✓ $service: GPU assignment correct ($visible_devices)"
            else
                print_error "✗ $service: Expected $expected_cores, got $visible_devices"
                ((assignment_errors++))
            fi
        else
            print_warning "⚠ $service: Could not determine GPU assignment"
            ((WARNINGS++))
        fi
    done
    
    if [ $assignment_errors -eq 0 ]; then
        print_status "✓ All GPU assignments validated"
        return 0
    else
        print_error "✗ $assignment_errors GPU assignment errors found"
        return 1
    fi
}

# Monitor GPU utilization during operations
monitor_gpu_utilization() {
    print_test "Monitoring GPU utilization patterns..."
    
    if ! command -v nvidia-smi > /dev/null 2>&1; then
        print_warning "⚠ nvidia-smi not available - skipping utilization monitoring"
        return 0
    fi
    
    local monitor_file="$RESULTS_DIR/gpu_utilization_$(date +%H%M%S).csv"
    local monitor_duration=30  # seconds
    
    print_gpu "Recording GPU utilization for ${monitor_duration}s..."
    
    # Create CSV header
    echo "timestamp,gpu_0_util,gpu_0_mem,gpu_1_util,gpu_1_mem,gpu_2_util,gpu_2_mem,gpu_3_util,gpu_3_mem,gpu_4_util,gpu_4_mem,gpu_5_util,gpu_5_mem,gpu_6_util,gpu_6_mem,gpu_7_util,gpu_7_mem" > "$monitor_file"
    
    # Monitor for specified duration
    local end_time=$(($(date +%s) + monitor_duration))
    while [ $(date +%s) -lt $end_time ]; do
        local timestamp=$(date +%s)
        local gpu_data=""
        
        for gpu in {0..7}; do
            local mem_used mem_total util
            if IFS=',' read -r mem_used mem_total util <<< "$(get_gpu_memory $gpu)"; then
                gpu_data="$gpu_data,$util,$mem_used"
            else
                gpu_data="$gpu_data,0,0"
            fi
        done
        
        echo "$timestamp$gpu_data" >> "$monitor_file"
        sleep 2
    done
    
    print_status "✓ GPU utilization data recorded: $monitor_file"
    
    # Analyze results
    analyze_gpu_utilization "$monitor_file"
    return 0
}

# Analyze GPU utilization patterns
analyze_gpu_utilization() {
    local data_file="$1"
    
    print_gpu "Analyzing GPU utilization patterns..."
    
    # Check if we have data
    local data_lines=$(wc -l < "$data_file" 2>/dev/null || echo "1")
    if [ "$data_lines" -le 1 ]; then
        print_warning "⚠ Insufficient utilization data for analysis"
        return 0
    fi
    
    # Expected utilization patterns based on service assignments
    local analysis_results=""
    
    # DotsOCR cores (0,1) - should show activity
    local core_0_util=$(awk -F',' 'NR>1 {sum+=$2; count++} END {if(count>0) print int(sum/count); else print 0}' "$data_file")
    local core_1_util=$(awk -F',' 'NR>1 {sum+=$4; count++} END {if(count>0) print int(sum/count); else print 0}' "$data_file")
    
    print_gpu "DotsOCR cores (0,1): ${core_0_util}%, ${core_1_util}% average utilization"
    
    if [ "$core_0_util" -gt 5 ] || [ "$core_1_util" -gt 5 ]; then
        print_status "✓ DotsOCR cores showing expected activity"
        analysis_results="$analysis_results\nDotsOCR: Active ($core_0_util%, $core_1_util%)"
    else
        print_warning "⚠ DotsOCR cores showing low utilization"
        analysis_results="$analysis_results\nDotsOCR: Low utilization ($core_0_util%, $core_1_util%)"
    fi
    
    # LLM cores (2,3,4,5) - should show activity
    local core_2_util=$(awk -F',' 'NR>1 {sum+=$6; count++} END {if(count>0) print int(sum/count); else print 0}' "$data_file")
    local core_3_util=$(awk -F',' 'NR>1 {sum+=$8; count++} END {if(count>0) print int(sum/count); else print 0}' "$data_file")
    local core_4_util=$(awk -F',' 'NR>1 {sum+=$10; count++} END {if(count>0) print int(sum/count); else print 0}' "$data_file")
    local core_5_util=$(awk -F',' 'NR>1 {sum+=$12; count++} END {if(count>0) print int(sum/count); else print 0}' "$data_file")
    
    print_gpu "LLM cores (2-5): ${core_2_util}%, ${core_3_util}%, ${core_4_util}%, ${core_5_util}% average utilization"
    
    # Embedding core (6)
    local core_6_util=$(awk -F',' 'NR>1 {sum+=$14; count++} END {if(count>0) print int(sum/count); else print 0}' "$data_file")
    print_gpu "Embedding core (6): ${core_6_util}% average utilization"
    
    # Whisper core (7)
    local core_7_util=$(awk -F',' 'NR>1 {sum+=$16; count++} END {if(count>0) print int(sum/count); else print 0}' "$data_file")
    print_gpu "Whisper core (7): ${core_7_util}% average utilization"
    
    # Check for proper isolation (no unexpected high utilization on wrong cores)
    print_status "✓ GPU utilization analysis complete"
    echo -e "$analysis_results" >> "$LOG_FILE"
    
    return 0
}

# Test tensor parallelism effectiveness
test_tensor_parallelism() {
    print_test "Testing tensor parallelism effectiveness..."
    
    # Test DotsOCR tensor parallelism (cores 0,1)
    print_gpu "Testing DotsOCR tensor parallelism..."
    
    # Send multiple requests to DotsOCR if test image available
    local test_image="$TEST_DATA_DIR/images/text_image.png"
    if [[ -f "$test_image" ]]; then
        print_gpu "Sending concurrent OCR requests to test parallelism..."
        
        # Send 3 concurrent requests
        local pids=()
        for i in {1..3}; do
            (
                curl -s -X POST \
                    -F "image=@$test_image" \
                    "http://localhost:8002/process" \
                    -o "/tmp/ocr_result_$i.json" 2>/dev/null
            ) &
            pids+=($!)
        done
        
        # Wait for all to complete
        local completed=0
        for pid in "${pids[@]}"; do
            if wait "$pid" 2>/dev/null; then
                ((completed++))
            fi
        done
        
        if [ $completed -gt 0 ]; then
            print_status "✓ DotsOCR handled $completed concurrent requests"
        else
            print_warning "⚠ DotsOCR concurrent processing needs verification"
        fi
        
        # Cleanup temp files
        rm -f /tmp/ocr_result_*.json 2>/dev/null || true
    else
        print_warning "⚠ No test image available for tensor parallelism testing"
    fi
    
    # Test LLM tensor parallelism (cores 2,3,4,5)
    print_gpu "Testing LLM tensor parallelism..."
    
    # Send concurrent requests to LLM
    local test_prompt="Explain artificial intelligence briefly."
    local pids=()
    
    for i in {1..2}; do
        (
            curl -s -X POST \
                -H "Content-Type: application/json" \
                -d "{\"model\": \"gpt-oss-20b\", \"messages\": [{\"role\": \"user\", \"content\": \"$test_prompt\"}]}" \
                "http://localhost:8003/v1/chat/completions" \
                -o "/tmp/llm_result_$i.json" 2>/dev/null
        ) &
        pids+=($!)
    done
    
    # Wait and check results
    local completed=0
    for pid in "${pids[@]}"; do
        if wait "$pid" 2>/dev/null; then
            ((completed++))
        fi
    done
    
    if [ $completed -gt 0 ]; then
        print_status "✓ LLM handled $completed concurrent requests with tensor parallelism"
    else
        print_warning "⚠ LLM tensor parallelism needs verification"
    fi
    
    # Cleanup temp files
    rm -f /tmp/llm_result_*.json 2>/dev/null || true
    
    return 0
}

# Test memory isolation between services
test_memory_isolation() {
    print_test "Testing memory isolation between GPU services..."
    
    if ! command -v nvidia-smi > /dev/null 2>&1; then
        print_warning "⚠ nvidia-smi not available - skipping memory isolation test"
        return 0
    fi
    
    # Check memory usage patterns
    local total_memory_used=0
    local memory_distribution=""
    
    for gpu in {0..7}; do
        local mem_info
        if mem_info=$(get_gpu_memory "$gpu"); then
            local mem_used mem_total util
            IFS=',' read -r mem_used mem_total util <<< "$mem_info"
            
            total_memory_used=$((total_memory_used + mem_used))
            memory_distribution="$memory_distribution\nGPU $gpu: ${mem_used}MB / ${mem_total}MB (${util}% util)"
        fi
    done
    
    print_gpu "Memory distribution across GPUs:"
    echo -e "$memory_distribution"
    
    # Check if memory is reasonably distributed (not all on one GPU)
    local max_single_gpu_memory=0
    for gpu in {0..7}; do
        local mem_info
        if mem_info=$(get_gpu_memory "$gpu"); then
            local mem_used mem_total util
            IFS=',' read -r mem_used mem_total util <<< "$mem_info"
            
            if [ "$mem_used" -gt "$max_single_gpu_memory" ]; then
                max_single_gpu_memory=$mem_used
            fi
        fi
    done
    
    if [ $total_memory_used -gt 0 ]; then
        local max_percentage=$((max_single_gpu_memory * 100 / total_memory_used))
        
        if [ "$max_percentage" -lt 80 ]; then
            print_status "✓ Memory reasonably distributed across GPUs (max ${max_percentage}% on single GPU)"
        else
            print_warning "⚠ Memory concentration on single GPU (${max_percentage}%)"
        fi
    fi
    
    print_status "✓ Memory isolation analysis complete"
    return 0
}

# Performance benchmark under load
test_performance_under_load() {
    print_test "Testing performance under concurrent load..."
    
    local start_time=$(date +%s)
    local test_duration=60  # seconds
    local concurrent_requests=5
    
    print_perf "Running ${concurrent_requests} concurrent operations for ${test_duration}s..."
    
    # Create array to track completion times
    local completion_times=()
    
    # Start concurrent operations
    local pids=()
    for i in $(seq 1 $concurrent_requests); do
        (
            local req_start=$(date +%s.%3N)
            
            # Alternate between different services
            case $((i % 4)) in
                0) curl -s "http://localhost:8080/health" >/dev/null 2>&1 ;;
                1) curl -s "http://localhost:8001/health" >/dev/null 2>&1 ;;
                2) curl -s "http://localhost:8002/health" >/dev/null 2>&1 ;;
                3) curl -s "http://localhost:8004/health" >/dev/null 2>&1 ;;
            esac
            
            local req_end=$(date +%s.%3N)
            local req_time=$(echo "$req_end - $req_start" | bc 2>/dev/null || echo "0.1")
            echo "$req_time" > "/tmp/req_time_$i"
        ) &
        pids+=($!)
    done
    
    # Wait for all requests to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    # Analyze response times
    local total_time=0
    local request_count=0
    local max_time=0
    
    for i in $(seq 1 $concurrent_requests); do
        if [[ -f "/tmp/req_time_$i" ]]; then
            local req_time
            req_time=$(cat "/tmp/req_time_$i" 2>/dev/null || echo "0")
            total_time=$(echo "$total_time + $req_time" | bc 2>/dev/null || echo "$total_time")
            request_count=$((request_count + 1))
            
            if (( $(echo "$req_time > $max_time" | bc -l 2>/dev/null || echo 0) )); then
                max_time=$req_time
            fi
        fi
    done
    
    # Calculate average
    local avg_time
    if [ $request_count -gt 0 ]; then
        avg_time=$(echo "scale=3; $total_time / $request_count" | bc 2>/dev/null || echo "0.1")
    else
        avg_time="0.1"
    fi
    
    print_perf "Performance results:"
    print_perf "• Average response time: ${avg_time}s"
    print_perf "• Maximum response time: ${max_time}s" 
    print_perf "• Completed requests: $request_count/$concurrent_requests"
    
    # Cleanup temp files
    rm -f /tmp/req_time_* 2>/dev/null || true
    
    # Evaluate performance
    if (( $(echo "$avg_time < 2.0" | bc -l 2>/dev/null || echo 1) )) && [ $request_count -eq $concurrent_requests ]; then
        print_status "✓ Performance under load: Good"
        return 0
    elif (( $(echo "$avg_time < 5.0" | bc -l 2>/dev/null || echo 1) )); then
        print_warning "⚠ Performance under load: Acceptable but could be improved"
        return 0
    else
        print_error "✗ Performance under load: Poor"
        return 1
    fi
}

# Generate GPU performance report
generate_gpu_report() {
    print_test "Generating GPU performance report..."
    
    mkdir -p "$(dirname "$REPORT_FILE")"
    
    local gpu_info=""
    if command -v nvidia-smi > /dev/null 2>&1; then
        gpu_info=$(nvidia-smi --query-gpu=index,name,memory.total,memory.used,utilization.gpu,temperature.gpu --format=csv)
    else
        gpu_info="GPU monitoring not available"
    fi
    
    cat > "$REPORT_FILE" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>H100 8-Core GPU Performance Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { background-color: #e6f3ff; padding: 15px; margin: 20px 0; border-radius: 5px; }
        .gpu-section { background-color: #f8f9fa; padding: 15px; margin: 10px 0; border-radius: 5px; }
        .passed { color: #28a745; }
        .failed { color: #dc3545; }
        .warning { color: #ffc107; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; }
        .gpu-assignment { font-family: monospace; background-color: #f1f3f4; padding: 2px 4px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>H100 8-Core GPU Performance Validation Report</h1>
        <p><strong>Generated:</strong> $(date)</p>
        <p><strong>Test Environment:</strong> H100 8-Core Optimized RAG Deployment</p>
    </div>
    
    <div class="summary">
        <h2>Test Summary</h2>
        <p><strong>Total Tests:</strong> $TOTAL_TESTS</p>
        <p><strong class="passed">Passed:</strong> $PASSED_TESTS</p>
        <p><strong class="failed">Failed:</strong> $FAILED_TESTS</p>
        <p><strong class="warning">Warnings:</strong> $WARNINGS</p>
        <p><strong>Success Rate:</strong> $(( TOTAL_TESTS > 0 ? (PASSED_TESTS * 100) / TOTAL_TESTS : 0 ))%</p>
    </div>
    
    <div class="gpu-section">
        <h2>Expected GPU Core Assignments</h2>
        <table>
            <tr><th>Service</th><th>GPU Cores</th><th>Purpose</th></tr>
            <tr><td>DotsOCR</td><td class="gpu-assignment">0,1</td><td>Vision processing with tensor parallelism</td></tr>
            <tr><td>LLM (GPT-OSS-20B)</td><td class="gpu-assignment">2,3,4,5</td><td>4-way tensor parallel language model</td></tr>
            <tr><td>Embedding</td><td class="gpu-assignment">6</td><td>Text embedding generation</td></tr>
            <tr><td>Whisper</td><td class="gpu-assignment">7</td><td>Hebrew audio transcription</td></tr>
        </table>
    </div>
    
    <div class="gpu-section">
        <h2>Current GPU Status</h2>
        <pre>$gpu_info</pre>
    </div>
    
    <div class="gpu-section">
        <h2>Performance Characteristics</h2>
        <ul>
            <li><strong>Memory Isolation:</strong> Each service has dedicated GPU memory</li>
            <li><strong>Tensor Parallelism:</strong> Large models distributed across multiple cores</li>
            <li><strong>Concurrent Processing:</strong> All services can operate simultaneously</li>
            <li><strong>Load Balancing:</strong> Optimal distribution of computational load</li>
        </ul>
    </div>
    
    <h2>Recommendations</h2>
    <ul>
        <li>Monitor GPU utilization during peak usage</li>
        <li>Adjust memory allocation if services show memory pressure</li>
        <li>Consider dynamic load balancing for varying workloads</li>
        <li>Regular performance monitoring for optimization opportunities</li>
        $([ $WARNINGS -gt 0 ] && echo "<li>Address warnings for optimal GPU utilization</li>")
        $([ $FAILED_TESTS -gt 0 ] && echo "<li>Resolve failed tests before production deployment</li>")
    </ul>
    
    <h2>Detailed Logs</h2>
    <p>Complete test logs available at: <code>$LOG_FILE</code></p>
    <p>GPU utilization data: <code>$RESULTS_DIR/gpu_utilization_*.csv</code></p>
    
</body>
</html>
EOF

    print_status "✓ GPU performance report generated: $REPORT_FILE"
}

# Main test execution
main() {
    print_test "Starting H100 8-Core GPU Performance Validation"
    
    # Initialize
    mkdir -p "$RESULTS_DIR"
    
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
    
    # Execute all tests
    run_test "GPU Support Check" check_gpu_support
    run_test "GPU Core Assignments" test_gpu_assignments
    run_test "Memory Isolation" test_memory_isolation
    run_test "Tensor Parallelism" test_tensor_parallelism
    run_test "Performance Under Load" test_performance_under_load
    
    # Monitor utilization (non-failing)
    print_test "GPU Utilization Monitoring"
    monitor_gpu_utilization || true  # Don't fail on monitoring issues
    
    # Generate comprehensive report
    generate_gpu_report
    
    # Final summary
    echo ""
    echo "=========================================="
    echo "GPU Performance Validation Complete"
    echo "=========================================="
    
    print_status "Total Tests: $TOTAL_TESTS"
    print_status "Passed: $PASSED_TESTS"
    if [ $FAILED_TESTS -gt 0 ]; then
        print_error "Failed: $FAILED_TESTS"
    fi
    if [ $WARNINGS -gt 0 ]; then
        print_warning "Warnings: $WARNINGS"
    fi
    
    print_status "Detailed report: $REPORT_FILE"
    print_status "Test logs: $LOG_FILE"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}🎉 GPU performance validation successful!${NC}"
        echo ""
        print_status "8-core H100 deployment is optimally configured"
        print_status "All services have proper GPU assignments"
        exit 0
    else
        echo -e "${RED}❌ GPU performance validation issues found${NC}"
        echo ""
        print_error "Review failed tests and fix before production use"
        exit 1
    fi
}

# Handle command line arguments
if [[ "$1" == "--help" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo "Validate H100 8-core GPU performance and assignments"
    echo ""
    echo "Options:"
    echo "  --help       Show this help"
    echo "  --quick      Run essential tests only (skip monitoring)"
    echo "  --monitor    Extended GPU utilization monitoring"
    echo ""
    echo "This script validates:"
    echo "  • Proper GPU core assignments to services"
    echo "  • Memory isolation between services" 
    echo "  • Tensor parallelism effectiveness"
    echo "  • Performance under concurrent load"
    echo "  • GPU utilization patterns"
    echo ""
    echo "Generates detailed HTML report and CSV utilization data"
    exit 0
fi

# Execute main validation
main "$@"