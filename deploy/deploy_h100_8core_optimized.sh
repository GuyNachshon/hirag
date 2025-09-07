#!/bin/bash

set -e

echo "=========================================="
echo "H100 8-Core Optimized RAG Deployment"
echo "Distributing services across 8 GPU cores"
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

# Check prerequisites
check_prerequisites() {
    print_header "Checking prerequisites..."
    
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    if ! nvidia-smi > /dev/null 2>&1; then
        print_warning "nvidia-smi not available. GPU detection may not work properly."
    else
        GPU_COUNT=$(nvidia-smi --list-gpus | wc -l)
        print_status "Detected $GPU_COUNT GPUs"
        
        if [ "$GPU_COUNT" -lt 8 ]; then
            print_warning "Only $GPU_COUNT GPUs detected. This script is optimized for 8+ GPUs."
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
    
    print_status "Prerequisites check completed"
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

# Deploy services with optimized GPU assignments
deploy_embedding_server() {
    print_header "Deploying Embedding Server (GPU Core 6)"
    
    docker run -d \
        --name rag-embedding-server \
        --network rag-network \
        --gpus '"device=6"' \
        --restart unless-stopped \
        -p 8001:8000 \
        -e CUDA_VISIBLE_DEVICES=6 \
        -e MODEL_ID=Qwen/Qwen3-Embedding-4B \
        -e TENSOR_PARALLEL_SIZE=1 \
        -e GPU_MEMORY_UTILIZATION=0.9 \
        rag-embedding-server:latest
    
    print_status "✓ Embedding Server deployed on GPU core 6"
}

deploy_whisper_service() {
    print_header "Deploying Whisper Service (GPU Core 7)"
    
    docker run -d \
        --name rag-whisper \
        --network rag-network \
        --gpus '"device=7"' \
        --restart unless-stopped \
        -p 8004:8004 \
        -e CUDA_VISIBLE_DEVICES=7 \
        -e MODEL_NAME=ivrit-ai/whisper-large-v3 \
        rag-whisper:latest
    
    print_status "✓ Whisper Service deployed on GPU core 7"
}

deploy_dotsocr_service() {
    print_header "Deploying DotsOCR Service (GPU Cores 0-1, Tensor Parallel)"
    
    docker run -d \
        --name rag-dots-ocr \
        --network rag-network \
        --gpus '"device=0,1"' \
        --shm-size=16g \
        --restart unless-stopped \
        -p 8002:8000 \
        -e CUDA_VISIBLE_DEVICES=0,1 \
        --entrypoint /bin/bash \
        rag-dots-ocr:latest \
        -c "
            echo '--- DotsOCR 8-Core Optimized Mode ---'
            echo 'Using GPU cores 0,1 with tensor parallelism'
            sed -i '/^from vllm\.entrypoints\.cli\.main import main/a from DotsOCR import modeling_dots_ocr_vllm' \$(which vllm)
            echo 'vllm script patched successfully'
            exec vllm serve /workspace/weights/DotsOCR \
                --tensor-parallel-size 2 \
                --gpu-memory-utilization 0.85 \
                --max-model-len 8192 \
                --chat-template-content-format string \
                --served-model-name model \
                --trust-remote-code \
                --host 0.0.0.0 \
                --port 8000
        "
    
    print_status "✓ DotsOCR Service deployed on GPU cores 0-1 with tensor parallelism"
}

deploy_llm_service() {
    print_header "Deploying LLM Service (GPU Cores 2-5, Tensor Parallel)"
    
    docker run -d \
        --name rag-llm-server \
        --network rag-network \
        --gpus '"device=2,3,4,5"' \
        --shm-size=32g \
        --restart unless-stopped \
        -p 8003:8000 \
        -e CUDA_VISIBLE_DEVICES=2,3,4,5 \
        -e TENSOR_PARALLEL_SIZE=4 \
        -e GPU_MEMORY_UTILIZATION=0.9 \
        -e HF_HUB_OFFLINE=1 \
        -e TRANSFORMERS_OFFLINE=1 \
        -e HF_DATASETS_OFFLINE=1 \
        --entrypoint /bin/bash \
        rag-llm-gptoss:latest \
        -c "
            echo '--- GPT-OSS 8-Core Optimized Mode ---'
            echo 'Using GPU cores 2,3,4,5 with 4-way tensor parallelism'
            exec vllm serve /workspace/weights/openai/gpt-oss-20b \
                --tensor-parallel-size 4 \
                --gpu-memory-utilization 0.9 \
                --max-model-len 4096 \
                --served-model-name gpt-oss-20b \
                --trust-remote-code \
                --host 0.0.0.0 \
                --port 8000
        "
    
    print_status "✓ LLM Service deployed on GPU cores 2-5 with 4-way tensor parallelism"
}

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

# Wait for service to be ready
wait_for_service() {
    local url="$1"
    local name="$2"
    local max_attempts=90
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
        fi
    done
    
    print_error "✗ Timeout waiting for $name"
    return 1
}

# Validate deployment
validate_deployment() {
    print_header "Validating deployment..."
    
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
    
    # Test Embedding (medium startup time)
    if wait_for_service "http://localhost:8001/health" "Embedding Service"; then
        ((services_ok++))
    fi
    
    # Test Whisper (medium startup time)
    if wait_for_service "http://localhost:8004/health" "Whisper Service"; then
        ((services_ok++))
    fi
    
    # Test DotsOCR (heavy startup)
    if wait_for_service "http://localhost:8002/health" "DotsOCR Service"; then
        ((services_ok++))
    fi
    
    # Test LLM (heaviest startup)
    if wait_for_service "http://localhost:8003/health" "LLM Service"; then
        ((services_ok++))
    fi
    
    echo ""
    echo "=========================================="
    echo "Deployment Validation Results"
    echo "=========================================="
    print_status "Services Ready: $services_ok/$services_total"
    
    if [[ $services_ok -eq $services_total ]]; then
        echo -e "${GREEN}🎉 All services deployed successfully!${NC}"
        echo ""
        echo "Service URLs:"
        echo "• Frontend:  http://localhost:3000"
        echo "• API:       http://localhost:8080"
        echo "• Embedding: http://localhost:8001"  
        echo "• DotsOCR:   http://localhost:8002"
        echo "• LLM:       http://localhost:8003"
        echo "• Whisper:   http://localhost:8004"
        echo ""
        echo "GPU Core Assignment:"
        echo "• Cores 0-1: DotsOCR (tensor parallel)"
        echo "• Cores 2-5: LLM GPT-OSS-20B (4-way tensor parallel)"
        echo "• Core 6:    Embedding Server"
        echo "• Core 7:    Whisper Service"
        return 0
    else
        echo -e "${RED}❌ Some services failed to start${NC}"
        echo ""
        echo "Check logs with: docker logs <service-name>"
        return 1
    fi
}

# Show GPU utilization
show_gpu_status() {
    print_header "GPU Utilization Status"
    
    if command -v nvidia-smi > /dev/null; then
        nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv,noheader
        echo ""
        print_status "For detailed monitoring: watch -n 1 nvidia-smi"
    else
        print_warning "nvidia-smi not available for GPU monitoring"
    fi
}

# Main execution
main() {
    print_header "Starting H100 8-Core Optimized RAG Deployment"
    
    check_prerequisites
    setup_network
    cleanup_existing
    
    # Deploy services in optimal order (fastest to slowest startup)
    deploy_api_service
    deploy_frontend_service
    deploy_embedding_server
    deploy_whisper_service
    deploy_dotsocr_service
    deploy_llm_service
    
    # Validate deployment
    if validate_deployment; then
        show_gpu_status
        echo ""
        print_status "Deployment completed successfully!"
        print_status "Run './deploy/validate_h100_deployment.sh' for comprehensive testing"
    else
        print_error "Deployment validation failed"
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
    echo "Deploy RAG system optimized for H100 8-core GPU"
    echo ""
    echo "Options:"
    echo "  --cleanup    Remove existing deployment"
    echo "  --help       Show this help"
    echo ""
    echo "GPU Core Assignment:"
    echo "  Cores 0-1:   DotsOCR (tensor parallel)"
    echo "  Cores 2-5:   LLM GPT-OSS-20B (4-way tensor parallel)" 
    echo "  Core 6:      Embedding Server"
    echo "  Core 7:      Whisper Service"
    exit 0
fi

# Run main deployment
main "$@"