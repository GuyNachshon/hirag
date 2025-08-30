#!/bin/bash

set -e  # Exit on any error

# Source additional test functions if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/test_service_functions.sh" ]]; then
    source "$SCRIPT_DIR/test_service_functions.sh"
fi

echo "=========================================="
echo "Sequential Service Testing (GPU Memory Efficient)"
echo "Tests each GPU service individually to manage memory constraints"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SERVICES_TESTED=0

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

print_service() {
    echo -e "${YELLOW}[SERVICE]${NC} $1"
}

# Configuration
NETWORK_NAME="rag-sequential-test"
TEST_DATA_DIR="./test-data-sequential"
CLEANUP_WAIT=10  # Seconds to wait for GPU memory cleanup

# Parse command line arguments
SPECIFIC_SERVICE=""
SKIP_GPU=false
INTEGRATION_ONLY=false
MEMORY_LIMIT=8  # GB
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --service)
            SPECIFIC_SERVICE="$2"
            shift 2
            ;;
        --skip-gpu)
            SKIP_GPU=true
            shift
            ;;
        --integration-only)
            INTEGRATION_ONLY=true
            shift
            ;;
        --memory-limit)
            MEMORY_LIMIT="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --service <name>     Test specific service only (dotsocr|embedding|llm-small|llm-gptoss|whisper)"
            echo "  --skip-gpu          Run only CPU services and integration tests"
            echo "  --integration-only  Skip individual tests, run integration only"
            echo "  --memory-limit <gb> GPU memory limit in GB (default: 8)"
            echo "  --verbose           Show detailed output"
            echo "  --help              Show this help"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Service definitions with resource requirements
declare -A GPU_SERVICES=(
    ["dotsocr"]="rag-dots-ocr:latest:8002:8000:7:DotsOCR Vision Service"
    ["embedding"]="rag-embedding-server:latest:8001:8000:3:Embedding Service" 
    ["llm-small"]="rag-llm-small:latest:8003:8000:8:Small LLM Service"
    ["llm-gptoss"]="rag-llm-gptoss:latest:8003:8000:16:GPT-OSS LLM Service"
    ["whisper"]="rag-whisper:latest:8004:8004:4:Whisper Transcription Service"
)

declare -A CPU_SERVICES=(
    ["api"]="rag-api:latest:8080:8080:0:RAG API Service"
    ["frontend"]="rag-frontend:latest:3000:3000:0:Frontend Service"
)

# Utility functions
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
}

check_gpu() {
    if ! nvidia-smi > /dev/null 2>&1; then
        print_warning "nvidia-smi not available. GPU tests may not work."
        return 1
    fi
    return 0
}

cleanup_containers() {
    print_status "Cleaning up existing containers..."
    local containers=("rag-dots-ocr" "rag-embedding-server" "rag-llm-server" "rag-whisper" "rag-api" "rag-frontend")
    
    for container in "${containers[@]}"; do
        if docker ps -a | grep -q "$container"; then
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
        fi
    done
    
    # Clean up GPU memory
    if check_gpu; then
        print_status "Waiting ${CLEANUP_WAIT}s for GPU memory cleanup..."
        sleep $CLEANUP_WAIT
        docker system prune -f > /dev/null 2>&1 || true
    fi
}

setup_network() {
    print_header "Setting up test network..."
    if ! docker network ls | grep -q "$NETWORK_NAME"; then
        docker network create "$NETWORK_NAME"
        print_status "Created network: $NETWORK_NAME"
    else
        print_status "Network already exists: $NETWORK_NAME"
    fi
}

setup_test_data() {
    print_header "Setting up test data..."
    mkdir -p "$TEST_DATA_DIR"/{input,working,logs,cache,audio,images}
    
    # Create test files if they don't exist
    if [[ ! -f "$TEST_DATA_DIR/audio/test.wav" ]]; then
        # Create a simple test audio file (silence)
        if command -v ffmpeg > /dev/null; then
            ffmpeg -f lavfi -i "sine=frequency=440:duration=2" -ar 16000 "$TEST_DATA_DIR/audio/test.wav" -loglevel quiet 2>/dev/null || true
        fi
    fi
    
    # Create test text file
    echo "This is a test document for RAG system testing." > "$TEST_DATA_DIR/input/test_document.txt"
    
    print_status "Test data prepared"
}

wait_for_service() {
    local url="$1"
    local name="$2"
    local max_attempts=60
    local attempt=0
    
    print_status "Waiting for $name to be ready at $url..."
    while [ $attempt -lt $max_attempts ]; do
        if curl -s -f "$url" > /dev/null 2>&1; then
            print_status "✓ $name is ready!"
            return 0
        fi
        sleep 2
        ((attempt++))
        if [[ $((attempt % 15)) -eq 0 ]]; then
            print_status "Still waiting for $name... (${attempt}/${max_attempts})"
        fi
    done
    
    print_error "✗ Timeout waiting for $name"
    return 1
}

check_gpu_memory() {
    local required_gb="$1"
    
    if ! check_gpu; then
        return 1
    fi
    
    # Get available GPU memory (rough estimate)
    local gpu_mem=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1)
    local available_gb=$((gpu_mem / 1024))
    
    if [[ $available_gb -lt $required_gb ]]; then
        print_warning "GPU memory may be insufficient: ${available_gb}GB available, ${required_gb}GB required"
        if [[ $available_gb -lt $((required_gb / 2)) ]]; then
            return 1
        fi
    fi
    
    return 0
}

test_service_health() {
    local url="$1"
    local name="$2"
    
    print_test "Testing $name health check..."
    ((TOTAL_TESTS++))
    
    if response=$(curl -s "$url" 2>/dev/null); then
        if echo "$response" | grep -q "health"; then
            print_status "✓ $name health check passed"
            ((PASSED_TESTS++))
            return 0
        fi
    fi
    
    print_error "✗ $name health check failed"
    ((FAILED_TESTS++))
    return 1
}

start_service() {
    local service_name="$1"
    local image="$2" 
    local host_port="$3"
    local container_port="$4"
    local memory_gb="$5"
    local description="$6"
    
    print_service "Starting $description..."
    
    # Check memory requirements
    if [[ $memory_gb -gt 0 ]] && [[ $memory_gb -gt $MEMORY_LIMIT ]]; then
        print_warning "Skipping $service_name: requires ${memory_gb}GB, limit is ${MEMORY_LIMIT}GB"
        return 1
    fi
    
    if [[ $memory_gb -gt 0 ]] && ! check_gpu_memory $memory_gb; then
        print_warning "Insufficient GPU memory for $service_name"
        return 1
    fi
    
    # Build docker run command
    local docker_cmd="docker run -d --name $service_name --network $NETWORK_NAME"
    
    # Add GPU support for GPU services
    if [[ $memory_gb -gt 0 ]] && check_gpu; then
        docker_cmd="$docker_cmd --gpus all"
    fi
    
    # Add port mapping
    docker_cmd="$docker_cmd -p $host_port:$container_port"
    
    # Add volumes for API service
    if [[ "$service_name" == "rag-api" ]]; then
        docker_cmd="$docker_cmd -v $(pwd)/config/config.yaml:/app/HiRAG/config.yaml:ro"
        docker_cmd="$docker_cmd -v $(pwd)/$TEST_DATA_DIR/input:/app/data/input"
        docker_cmd="$docker_cmd -v $(pwd)/$TEST_DATA_DIR/working:/app/data/working"
    fi
    
    # Run the container
    docker_cmd="$docker_cmd $image"
    
    if $VERBOSE; then
        print_status "Command: $docker_cmd"
    fi
    
    if eval $docker_cmd; then
        print_status "✓ $description started"
        ((SERVICES_TESTED++))
        return 0
    else
        print_error "✗ Failed to start $description"
        return 1
    fi
}

stop_service() {
    local service_name="$1"
    local description="$2"
    
    print_status "Stopping $description..."
    docker stop "$service_name" 2>/dev/null || true
    docker rm "$service_name" 2>/dev/null || true
    
    # Wait for cleanup
    sleep 3
}

test_dotsocr() {
    local service_name="rag-dots-ocr"
    local url="http://localhost:8002"
    
    print_header "Testing DotsOCR Service"
    
    # Parse service info
    IFS=':' read -r image host_port container_port memory_gb description <<< "${GPU_SERVICES[dotsocr]}"
    
    if ! start_service "$service_name" "$image" "$host_port" "$container_port" "$memory_gb" "$description"; then
        return 1
    fi
    
    if wait_for_service "$url/health" "DotsOCR"; then
        test_service_health "$url/health" "DotsOCR"
        
        # Run detailed tests if available
        if declare -f test_dotsocr_detailed > /dev/null; then
            test_dotsocr_detailed "$service_name" "$url"
        fi
        
        # GPU monitoring and benchmarking
        if declare -f monitor_gpu_usage > /dev/null && $VERBOSE; then
            monitor_gpu_usage "$service_name"
            benchmark_service "$service_name" "$url/health" "health"
        fi
        
    else
        print_error "DotsOCR service failed to start properly"
        ((FAILED_TESTS++))
    fi
    
    stop_service "$service_name" "DotsOCR"
    cleanup_containers
}

test_embedding() {
    local service_name="rag-embedding-server"
    local url="http://localhost:8001"
    
    print_header "Testing Embedding Service"
    
    IFS=':' read -r image host_port container_port memory_gb description <<< "${GPU_SERVICES[embedding]}"
    
    if ! start_service "$service_name" "$image" "$host_port" "$container_port" "$memory_gb" "$description"; then
        return 1
    fi
    
    if wait_for_service "$url/health" "Embedding Service"; then
        test_service_health "$url/health" "Embedding Service"
        
        # Run detailed tests if available
        if declare -f test_embedding_detailed > /dev/null; then
            test_embedding_detailed "$service_name" "$url"
        fi
        
        # GPU monitoring and benchmarking
        if declare -f monitor_gpu_usage > /dev/null && $VERBOSE; then
            monitor_gpu_usage "$service_name"
            benchmark_service "$service_name" "$url/health" "health"
        fi
        
    else
        print_error "Embedding service failed to start properly"
        ((FAILED_TESTS++))
    fi
    
    stop_service "$service_name" "Embedding Service"
    cleanup_containers
}

test_llm_small() {
    local service_name="rag-llm-server"
    local url="http://localhost:8003"
    
    print_header "Testing Small LLM Service"
    
    IFS=':' read -r image host_port container_port memory_gb description <<< "${GPU_SERVICES[llm-small]}"
    
    if ! start_service "$service_name" "$image" "$host_port" "$container_port" "$memory_gb" "$description"; then
        return 1
    fi
    
    if wait_for_service "$url/health" "Small LLM Service"; then
        test_service_health "$url/health" "Small LLM Service"
        
        # Run detailed tests if available
        if declare -f test_llm_detailed > /dev/null; then
            test_llm_detailed "$service_name" "$url" "Qwen/Qwen3-4B-Thinking-2507"
        fi
        
        # GPU monitoring and benchmarking
        if declare -f monitor_gpu_usage > /dev/null && $VERBOSE; then
            monitor_gpu_usage "$service_name"
            benchmark_service "$service_name" "$url/health" "health"
        fi
        
    else
        print_error "Small LLM service failed to start properly"
        ((FAILED_TESTS++))
    fi
    
    stop_service "$service_name" "Small LLM Service"
    cleanup_containers
}

test_llm_gptoss() {
    local service_name="rag-llm-server"
    local url="http://localhost:8003"
    
    print_header "Testing GPT-OSS LLM Service"
    
    IFS=':' read -r image host_port container_port memory_gb description <<< "${GPU_SERVICES[llm-gptoss]}"
    
    if ! start_service "$service_name" "$image" "$host_port" "$container_port" "$memory_gb" "$description"; then
        return 1
    fi
    
    if wait_for_service "$url/health" "GPT-OSS LLM Service"; then
        test_service_health "$url/health" "GPT-OSS LLM Service"
        
        # Run detailed tests if available
        if declare -f test_llm_detailed > /dev/null; then
            test_llm_detailed "$service_name" "$url" "openai/gpt-oss-20b"
        fi
        
        # GPU monitoring and benchmarking
        if declare -f monitor_gpu_usage > /dev/null && $VERBOSE; then
            monitor_gpu_usage "$service_name"
            benchmark_service "$service_name" "$url/health" "health"
        fi
        
    else
        print_error "GPT-OSS LLM service failed to start properly"
        ((FAILED_TESTS++))
    fi
    
    stop_service "$service_name" "GPT-OSS LLM Service"
    cleanup_containers
}

test_whisper() {
    local service_name="rag-whisper"
    local url="http://localhost:8004"
    
    print_header "Testing Whisper Service"
    
    IFS=':' read -r image host_port container_port memory_gb description <<< "${GPU_SERVICES[whisper]}"
    
    if ! start_service "$service_name" "$image" "$host_port" "$container_port" "$memory_gb" "$description"; then
        return 1
    fi
    
    if wait_for_service "$url/health" "Whisper Service"; then
        test_service_health "$url/health" "Whisper Service"
        
        # Run detailed tests if available
        if declare -f test_whisper_detailed > /dev/null; then
            test_whisper_detailed "$service_name" "$url"
        else
            # Fallback to simple transcription test
            if [[ -f "$TEST_DATA_DIR/audio/test.wav" ]]; then
                print_test "Testing audio transcription..."
                ((TOTAL_TESTS++))
                
                if response=$(curl -s -F "file=@$TEST_DATA_DIR/audio/test.wav" "$url/transcribe" 2>/dev/null); then
                    if echo "$response" | grep -q "success.*true\|text"; then
                        print_status "✓ Audio transcription test passed"
                        ((PASSED_TESTS++))
                    else
                        print_error "✗ Audio transcription test failed"
                        ((FAILED_TESTS++))
                        if $VERBOSE; then
                            echo "Response: $response"
                        fi
                    fi
                else
                    print_error "✗ Audio transcription test failed - no response"
                    ((FAILED_TESTS++))
                fi
            fi
        fi
        
        # GPU monitoring and benchmarking
        if declare -f monitor_gpu_usage > /dev/null && $VERBOSE; then
            monitor_gpu_usage "$service_name"
            benchmark_service "$service_name" "$url/health" "health"
        fi
        
    else
        print_error "Whisper service failed to start properly"
        ((FAILED_TESTS++))
    fi
    
    stop_service "$service_name" "Whisper Service"
    cleanup_containers
}

test_integration() {
    print_header "Testing Integration with API and Frontend"
    
    # Start API service (CPU only)
    IFS=':' read -r api_image api_host_port api_container_port api_memory_gb api_description <<< "${CPU_SERVICES[api]}"
    
    # Create minimal config for testing
    mkdir -p config
    if [[ ! -f "config/config.yaml" ]]; then
        cp "config/config.yaml.template" "config/config.yaml" 2>/dev/null || true
    fi
    
    if start_service "rag-api" "$api_image" "$api_host_port" "$api_container_port" "$api_memory_gb" "$api_description"; then
        if wait_for_service "http://localhost:8080/health" "API Service"; then
            test_service_health "http://localhost:8080/health" "API Service"
            
            # Run detailed API tests if available
            if declare -f test_api_detailed > /dev/null; then
                test_api_detailed "http://localhost:8080"
            else
                # Fallback to simple API test
                print_test "Testing API root endpoint..."
                ((TOTAL_TESTS++))
                if response=$(curl -s "http://localhost:8080/" 2>/dev/null); then
                    if echo "$response" | grep -q "RAG API\|healthy"; then
                        print_status "✓ API root endpoint test passed"
                        ((PASSED_TESTS++))
                    else
                        print_error "✗ API root endpoint test failed"
                        ((FAILED_TESTS++))
                    fi
                else
                    print_error "✗ API root endpoint test failed - no response"
                    ((FAILED_TESTS++))
                fi
            fi
            
        fi
        
        stop_service "rag-api" "API Service"
    fi
    
    # Start Frontend service
    IFS=':' read -r frontend_image frontend_host_port frontend_container_port frontend_memory_gb frontend_description <<< "${CPU_SERVICES[frontend]}"
    
    if start_service "rag-frontend" "$frontend_image" "$frontend_host_port" "$frontend_container_port" "$frontend_memory_gb" "$frontend_description"; then
        if wait_for_service "http://localhost:3000/" "Frontend Service"; then
            test_service_health "http://localhost:3000/frontend-health" "Frontend Service"
            
            # Run detailed frontend tests if available
            if declare -f test_frontend_detailed > /dev/null; then
                test_frontend_detailed "http://localhost:3000"
            fi
        fi
        
        stop_service "rag-frontend" "Frontend Service"
    fi
    
    cleanup_containers
}

cleanup_test_environment() {
    print_header "Cleaning up test environment..."
    cleanup_containers
    
    # Remove test network
    if docker network ls | grep -q "$NETWORK_NAME"; then
        docker network rm "$NETWORK_NAME" 2>/dev/null || true
    fi
    
    # Clean up test data if desired
    # rm -rf "$TEST_DATA_DIR" 2>/dev/null || true
    
    print_status "Cleanup complete"
}

print_final_report() {
    echo ""
    echo "=========================================="
    echo "Sequential Service Testing Results"
    echo "=========================================="
    echo -e "${GREEN}Services Tested:${NC} $SERVICES_TESTED"
    echo -e "${GREEN}Tests Passed:${NC} $PASSED_TESTS"
    echo -e "${RED}Tests Failed:${NC} $FAILED_TESTS"
    echo -e "${BLUE}Total Tests:${NC} $TOTAL_TESTS"
    echo ""
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}🎉 All tests passed!${NC}"
        echo "Your RAG system is ready for deployment!"
        return 0
    else
        echo -e "${RED}❌ Some tests failed${NC}"
        echo "Please check the failed services and try again."
        echo ""
        echo "Troubleshooting tips:"
        echo "1. Check Docker logs: docker logs <container-name>"
        echo "2. Verify GPU memory: nvidia-smi"
        echo "3. Check available disk space: df -h"
        echo "4. Run with --verbose for detailed output"
        return 1
    fi
}

# Main execution
main() {
    print_header "Sequential Service Testing Started"
    print_status "Memory limit: ${MEMORY_LIMIT}GB"
    print_status "GPU available: $(check_gpu && echo "Yes" || echo "No")"
    
    # Initial setup
    check_docker
    cleanup_containers
    setup_network
    setup_test_data
    
    if [[ "$INTEGRATION_ONLY" == true ]]; then
        test_integration
    elif [[ -n "$SPECIFIC_SERVICE" ]]; then
        case "$SPECIFIC_SERVICE" in
            dotsocr) test_dotsocr ;;
            embedding) test_embedding ;;
            llm-small) test_llm_small ;;
            llm-gptoss) test_llm_gptoss ;;
            whisper) test_whisper ;;
            *) print_error "Unknown service: $SPECIFIC_SERVICE"; exit 1 ;;
        esac
    elif [[ "$SKIP_GPU" == true ]]; then
        test_integration
    else
        # Test all GPU services sequentially
        test_dotsocr
        test_embedding
        test_llm_small
        test_whisper
        
        # Test GPT-OSS only if memory allows
        if [[ $MEMORY_LIMIT -ge 16 ]]; then
            test_llm_gptoss
        else
            print_warning "Skipping GPT-OSS test: requires 16GB, limit is ${MEMORY_LIMIT}GB"
        fi
        
        # Test integration
        test_integration
    fi
    
    # Cleanup and report
    cleanup_test_environment
    print_final_report
}

# Trap for cleanup on exit
trap cleanup_test_environment EXIT

# Run main function
main "$@"