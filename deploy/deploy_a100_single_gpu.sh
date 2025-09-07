#!/bin/bash

set -e

echo "=========================================="
echo "A100 Single GPU RAG Deployment"
echo "Optimized for a2-highgpu-1g (40GB VRAM)"
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

print_header() {
    echo -e "${BLUE}[DEPLOY]${NC} $1"
}

# Configuration for A100 40GB
GPU_MEMORY_TOTAL=40  # GB
EXPECTED_MEMORY_USAGE=35  # GB (leave 5GB buffer)

# Memory allocation strategy for single GPU
declare -A SERVICE_MEMORY=(
    ["embedding"]="4"      # 4GB - lightweight embedding model
    ["whisper"]="6"        # 6GB - Whisper Hebrew model
    ["dotsocr"]="12"       # 12GB - DotsOCR vision model
    ["llm"]="13"          # 13GB - GPT-OSS or smaller LLM
)

# Check prerequisites
check_prerequisites() {
    print_header "Checking A100 prerequisites..."
    
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running"
        exit 1
    fi
    
    if command -v nvidia-smi > /dev/null 2>&1; then
        local gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader)
        print_status "GPU detected: $gpu_info"
        
        # Check if it's A100
        if echo "$gpu_info" | grep -q "A100"; then
            print_status "✓ A100 GPU confirmed"
        else
            print_warning "⚠ Non-A100 GPU detected - continuing with single GPU optimization"
        fi
        
        # Check memory
        local gpu_memory=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
        local gpu_memory_gb=$((gpu_memory / 1024))
        
        if [ "$gpu_memory_gb" -ge 35 ]; then
            print_status "✓ Sufficient GPU memory: ${gpu_memory_gb}GB"
        else
            print_warning "⚠ Limited GPU memory: ${gpu_memory_gb}GB (expected 40GB+)"
        fi
    else
        print_warning "⚠ nvidia-smi not available - GPU detection limited"
    fi
    
    print_status "✓ Prerequisites checked"
}

# Setup network
setup_network() {
    print_header "Setting up network..."
    
    NETWORK_NAME="rag-network"
    if ! docker network ls | grep -q "$NETWORK_NAME"; then
        docker network create "$NETWORK_NAME"
        print_status "Created network: $NETWORK_NAME"
    else
        print_status "Network already exists: $NETWORK_NAME"
    fi
}

# Cleanup existing containers
cleanup_existing() {
    print_header "Cleaning up existing containers..."
    
    local containers=("rag-dots-ocr" "rag-embedding-server" "rag-llm-server" "rag-whisper" "rag-api" "rag-frontend")
    
    for container in "${containers[@]}"; do
        if docker ps -aq -f name="$container" | grep -q .; then
            print_status "Stopping and removing $container..."
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
        fi
    done
    
    # Wait for GPU memory cleanup
    print_status "Waiting 10s for GPU memory cleanup..."
    sleep 10
}

# Deploy embedding service (lightweight, start first)
deploy_embedding_service() {
    print_header "Deploying Embedding Service (4GB GPU memory)"
    
    docker run -d \
        --name rag-embedding-server \
        --network rag-network \
        --gpus all \
        --restart unless-stopped \
        -p 8001:8000 \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e MODEL_NAME="Qwen/Qwen2-0.5B-Instruct" \
        --entrypoint /app/start_embedding.sh \
        rag-embedding-server:latest
    
    print_status "✓ Embedding Service deployed (4GB reserved)"
}

# Deploy whisper service
deploy_whisper_service() {
    print_header "Deploying Whisper Service (6GB GPU memory)"
    
    docker run -d \
        --name rag-whisper \
        --network rag-network \
        --gpus all \
        --restart unless-stopped \
        -p 8004:8004 \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e MODEL_NAME=ivrit-ai/whisper-large-v3 \
        rag-whisper:latest
    
    print_status "✓ Whisper Service deployed (6GB reserved)"
}

# Deploy DotsOCR service
deploy_dotsocr_service() {
    print_header "Deploying DotsOCR Service (12GB GPU memory)"
    
    docker run -d \
        --name rag-dots-ocr \
        --network rag-network \
        --gpus all \
        --shm-size=8g \
        --restart unless-stopped \
        -p 8002:8000 \
        -e CUDA_VISIBLE_DEVICES=0 \
        --entrypoint /bin/bash \
        rag-dots-ocr:latest \
        -c "
            echo '--- DotsOCR A100 Single GPU Mode ---'
            echo 'GPU memory allocation: 12GB of 40GB total'
            sed -i '/^from vllm\.entrypoints\.cli\.main import main/a from DotsOCR import modeling_dots_ocr_vllm' \$(which vllm)
            echo 'vllm script patched successfully'
            exec vllm serve /workspace/weights/DotsOCR \
                --tensor-parallel-size 1 \
                --gpu-memory-utilization 0.3 \
                --max-model-len 6144 \
                --chat-template-content-format string \
                --served-model-name model \
                --trust-remote-code \
                --host 0.0.0.0 \
                --port 8000
        "
    
    print_status "✓ DotsOCR Service deployed (12GB reserved)"
}

# Deploy LLM service (use remaining memory)
deploy_llm_service() {
    print_header "Deploying LLM Service (13GB GPU memory)"
    
    # For A100 40GB, we'll use a smaller model or reduced memory utilization
    docker run -d \
        --name rag-llm-server \
        --network rag-network \
        --gpus all \
        --shm-size=16g \
        --restart unless-stopped \
        -p 8003:8000 \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e TENSOR_PARALLEL_SIZE=1 \
        -e GPU_MEMORY_UTILIZATION=0.35 \
        -e HF_HUB_OFFLINE=1 \
        -e TRANSFORMERS_OFFLINE=1 \
        -e HF_DATASETS_OFFLINE=1 \
        --entrypoint /bin/bash \
        rag-llm-gptoss:latest \
        -c "
            echo '--- LLM A100 Single GPU Mode ---'
            echo 'GPU memory allocation: 13GB of 40GB total'
            echo 'Using memory-optimized settings for single GPU'
            exec vllm serve openai/gpt-oss-20b \
                --tensor-parallel-size 1 \
                --gpu-memory-utilization 0.35 \
                --max-model-len 2048 \
                --served-model-name gpt-oss-20b \
                --trust-remote-code \
                --host 0.0.0.0 \
                --port 8000
        "
    
    print_status "✓ LLM Service deployed (13GB reserved)"
}

# Deploy API service (CPU only)
deploy_api_service() {
    print_header "Deploying API Service (CPU only)"
    
    # Ensure config directory exists
    mkdir -p config
    if [[ ! -f "config/config.yaml" ]]; then
        if [[ -f "HiRAG/config.yaml" ]]; then
            cp "HiRAG/config.yaml" "config/config.yaml"
        fi
    fi
    
    docker run -d \
        --name rag-api \
        --network rag-network \
        --restart unless-stopped \
        -p 8080:8080 \
        -v $(pwd)/config:/app/config:ro \
        -v $(pwd)/data:/app/data \
        rag-api:latest
    
    print_status "✓ API Service deployed (CPU only)"
}

# Deploy frontend service (CPU only)
deploy_frontend_service() {
    print_header "Deploying Frontend Service (CPU only)"
    
    docker run -d \
        --name rag-frontend \
        --network rag-network \
        --restart unless-stopped \
        -p 3000:3000 \
        rag-frontend:latest
    
    print_status "✓ Frontend Service deployed (CPU only)"
}

# Monitor GPU memory usage
monitor_gpu_memory() {
    print_header "Monitoring GPU memory allocation..."
    
    if command -v nvidia-smi > /dev/null 2>&1; then
        local gpu_memory=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits)
        local used_memory=$(echo "$gpu_memory" | cut -d',' -f1)
        local total_memory=$(echo "$gpu_memory" | cut -d',' -f2)
        local used_gb=$((used_memory / 1024))
        local total_gb=$((total_memory / 1024))
        local usage_percent=$(((used_memory * 100) / total_memory))
        
        print_status "GPU Memory Usage: ${used_gb}GB / ${total_gb}GB (${usage_percent}%)"
        
        if [ "$usage_percent" -gt 90 ]; then
            print_warning "⚠ High GPU memory usage (${usage_percent}%) - monitor for stability"
        elif [ "$usage_percent" -gt 80 ]; then
            print_status "✓ Good GPU memory usage (${usage_percent}%)"
        else
            print_status "✓ Conservative GPU memory usage (${usage_percent}%)"
        fi
    else
        print_warning "⚠ Cannot monitor GPU memory - nvidia-smi not available"
    fi
}

# Wait for service to be ready
wait_for_service() {
    local url="$1"
    local name="$2"
    local max_attempts=120  # Longer timeout for A100 loading
    local attempt=0
    
    print_status "Waiting for $name to be ready at $url..."
    while [ $attempt -lt $max_attempts ]; do
        if curl -s -f "$url" > /dev/null 2>&1; then
            print_status "✓ $name is ready!"
            return 0
        fi
        sleep 5
        ((attempt++))
        if [[ $((attempt % 12)) -eq 0 ]]; then
            print_status "Still waiting for $name... (${attempt}/${max_attempts})"
            monitor_gpu_memory
        fi
    done
    
    print_error "✗ Timeout waiting for $name"
    return 1
}

# Validate deployment
validate_deployment() {
    print_header "Validating A100 deployment..."
    
    local services_ok=0
    local services_total=6
    
    # Test API (should be fastest)
    if wait_for_service "http://localhost:8080/health" "API Service"; then
        ((services_ok++))
    fi
    
    # Test Frontend
    if wait_for_service "http://localhost:3000/" "Frontend Service"; then
        ((services_ok++))
    fi
    
    # Test Embedding (lightweight)
    if wait_for_service "http://localhost:8001/health" "Embedding Service"; then
        ((services_ok++))
    fi
    
    # Test Whisper
    if wait_for_service "http://localhost:8004/health" "Whisper Service"; then
        ((services_ok++))
    fi
    
    # Test DotsOCR (heavy)
    if wait_for_service "http://localhost:8002/health" "DotsOCR Service"; then
        ((services_ok++))
    fi
    
    # Test LLM (heaviest)
    if wait_for_service "http://localhost:8003/health" "LLM Service"; then
        ((services_ok++))
    fi
    
    # Final GPU memory check
    monitor_gpu_memory
    
    echo ""
    echo "=========================================="
    echo "A100 Deployment Validation Results"
    echo "=========================================="
    print_status "Services Ready: $services_ok/$services_total"
    
    if [[ $services_ok -eq $services_total ]]; then
        echo -e "${GREEN}🎉 All services deployed successfully on A100!${NC}"
        echo ""
        echo "Service URLs:"
        echo "• Frontend:  http://localhost:3000"
        echo "• API:       http://localhost:8080"
        echo "• Embedding: http://localhost:8001"  
        echo "• DotsOCR:   http://localhost:8002"
        echo "• LLM:       http://localhost:8003"
        echo "• Whisper:   http://localhost:8004"
        echo ""
        echo "A100 GPU Memory Allocation:"
        echo "• Embedding:  ~4GB"
        echo "• Whisper:    ~6GB"
        echo "• DotsOCR:    ~12GB"
        echo "• LLM:        ~13GB"
        echo "• Total:      ~35GB of 40GB available"
        return 0
    else
        echo -e "${RED}❌ Some services failed to start${NC}"
        echo ""
        echo "Check logs with: docker logs <service-name>"
        echo "Monitor GPU: nvidia-smi"
        return 1
    fi
}

# Show GPU status
show_gpu_status() {
    print_header "A100 GPU Status"
    
    if command -v nvidia-smi > /dev/null; then
        nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv
        echo ""
        print_status "For detailed monitoring: watch -n 2 nvidia-smi"
    else
        print_warning "nvidia-smi not available for GPU monitoring"
    fi
}

# Main execution
main() {
    print_header "Starting A100 Single GPU RAG Deployment"
    print_status "Target: a2-highgpu-1g (12 vCPUs, 85GB RAM, A100 40GB)"
    
    check_prerequisites
    setup_network
    cleanup_existing
    
    # Deploy services in optimal order (memory usage ascending)
    deploy_api_service
    deploy_frontend_service
    deploy_embedding_service
    deploy_whisper_service
    deploy_dotsocr_service
    deploy_llm_service
    
    # Validate deployment
    if validate_deployment; then
        show_gpu_status
        echo ""
        print_status "A100 deployment completed successfully!"
        print_status "Run './deploy/test_offline_complete.sh' for comprehensive testing"
        print_status "Run './deploy/monitor_a100_single_gpu.sh' for monitoring"
    else
        print_error "A100 deployment validation failed"
        exit 1
    fi
}

# Cleanup on exit
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        print_error "Deployment failed. Run with --cleanup to remove partial deployment."
    fi
}

trap cleanup_on_exit EXIT

# Handle command line arguments
if [[ "$1" == "--cleanup" ]]; then
    print_header "Cleaning up existing deployment..."
    cleanup_existing
    docker network rm rag-network 2>/dev/null || true
    print_status "Cleanup completed"
    exit 0
fi

if [[ "$1" == "--help" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo "Deploy RAG system optimized for A100 single GPU"
    echo ""
    echo "Options:"
    echo "  --cleanup    Remove existing deployment"
    echo "  --help       Show this help"
    echo ""
    echo "A100 Memory Allocation Strategy:"
    echo "  Embedding:   4GB (10%)"
    echo "  Whisper:     6GB (15%)"  
    echo "  DotsOCR:     12GB (30%)"
    echo "  LLM:         13GB (32.5%)"
    echo "  Buffer:      5GB (12.5%)"
    echo "  Total:       40GB"
    exit 0
fi

# Run main deployment
main "$@"