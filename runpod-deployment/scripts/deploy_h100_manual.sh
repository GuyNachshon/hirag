#!/bin/bash

# H100 Cluster Manual Deployment (No Docker Compose)
# Deploy RAG system using individual docker run commands for isolated networks

set -e

echo "============================================"
echo "       H100 CLUSTER DEPLOYMENT             "
echo "============================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_header() { echo -e "\n=== $1 ==="; }

# Configuration
MODEL_CACHE_DIR="${MODEL_CACHE_DIR:-/opt/model-cache}"
NETWORK_NAME="rag-network"
LOG_DIR="${PWD}/logs"

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    # Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker not installed"
        exit 1
    fi

    # GPU
    if ! nvidia-smi &> /dev/null; then
        print_error "NVIDIA GPU or drivers not available"
        exit 1
    fi

    # Model cache
    if [ ! -d "$MODEL_CACHE_DIR" ]; then
        print_error "Model cache not found at $MODEL_CACHE_DIR"
        echo "Set MODEL_CACHE_DIR environment variable or ensure models are cached"
        exit 1
    fi

    # Log directory
    mkdir -p "$LOG_DIR"

    print_status "Prerequisites check passed"
}

# Create Docker network
create_network() {
    print_header "Creating Docker Network"

    # Remove existing network if it exists
    docker network rm $NETWORK_NAME 2>/dev/null || true

    # Create new network
    docker network create \
        --driver bridge \
        --subnet 172.20.0.0/16 \
        $NETWORK_NAME

    print_status "Network '$NETWORK_NAME' created"
}

# Wait for service health
wait_for_service() {
    local service_name=$1
    local health_url=$2
    local max_attempts=${3:-30}

    print_info "Waiting for $service_name to be healthy..."

    for i in $(seq 1 $max_attempts); do
        if curl -s "$health_url" > /dev/null 2>&1; then
            print_status "$service_name is healthy"
            return 0
        fi
        echo -n "."
        sleep 2
    done

    print_error "$service_name failed to become healthy"
    return 1
}

# Deploy Whisper service (GPU 0)
deploy_whisper() {
    print_header "Deploying Whisper Service (GPU 0)"

    docker stop rag-whisper 2>/dev/null || true
    docker rm rag-whisper 2>/dev/null || true

    docker run -d \
        --name rag-whisper \
        --network $NETWORK_NAME \
        --gpus '"device=0"' \
        --restart unless-stopped \
        -p 8004:8004 \
        -v "$MODEL_CACHE_DIR:/root/.cache/huggingface:ro" \
        -v "$LOG_DIR:/app/logs" \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e HF_HUB_OFFLINE=1 \
        -e TRANSFORMERS_OFFLINE=1 \
        -e DEVICE=cuda \
        -e MODEL_NAME=ivrit-ai/whisper-large-v3-ct2 \
        -e MODEL_CACHE_DIR=/root/.cache/huggingface \
        rag-whisper-official:latest

    wait_for_service "Whisper" "http://localhost:8004/health"
}

# Deploy Embedding service (GPU 1)
deploy_embedding() {
    print_header "Deploying Embedding Service (GPU 1)"

    docker stop rag-embedding-server 2>/dev/null || true
    docker rm rag-embedding-server 2>/dev/null || true

    docker run -d \
        --name rag-embedding-server \
        --network $NETWORK_NAME \
        --gpus '"device=1"' \
        --restart unless-stopped \
        -p 8001:8000 \
        -v "$MODEL_CACHE_DIR:/root/.cache/huggingface:ro" \
        -v "$LOG_DIR:/app/logs" \
        -e CUDA_VISIBLE_DEVICES=1 \
        -e HF_HUB_OFFLINE=1 \
        -e TRANSFORMERS_OFFLINE=1 \
        -e VLLM_USE_TRITON=0 \
        -e MODEL_NAME=Qwen/Qwen3-Embedding-4B \
        -e MAX_MODEL_LEN=1024 \
        -e GPU_MEMORY_UTILIZATION=0.9 \
        rag-llm-gptoss:latest

    wait_for_service "Embedding" "http://localhost:8001/health"
}

# Deploy LLM service (GPU 2-3)
deploy_llm() {
    print_header "Deploying LLM Service (GPU 2-3)"

    docker stop rag-llm-server 2>/dev/null || true
    docker rm rag-llm-server 2>/dev/null || true

    docker run -d \
        --name rag-llm-server \
        --network $NETWORK_NAME \
        --gpus '"device=2,3"' \
        --restart unless-stopped \
        --shm-size=32g \
        -p 8003:8000 \
        -v "$MODEL_CACHE_DIR:/root/.cache/huggingface:ro" \
        -v "$LOG_DIR:/app/logs" \
        -e CUDA_VISIBLE_DEVICES=2,3 \
        -e HF_HUB_OFFLINE=1 \
        -e TRANSFORMERS_OFFLINE=1 \
        -e VLLM_USE_TRITON=0 \
        -e MODEL_NAME=openai/gpt-oss-20b \
        -e MAX_MODEL_LEN=4096 \
        -e TENSOR_PARALLEL_SIZE=2 \
        -e GPU_MEMORY_UTILIZATION=0.9 \
        rag-llm-gptoss:latest

    wait_for_service "LLM" "http://localhost:8003/health"
}

# Deploy OCR service (GPU 4)
deploy_ocr() {
    print_header "Deploying OCR Service (GPU 4)"

    docker stop rag-dots-ocr 2>/dev/null || true
    docker rm rag-dots-ocr 2>/dev/null || true

    docker run -d \
        --name rag-dots-ocr \
        --network $NETWORK_NAME \
        --gpus '"device=4"' \
        --restart unless-stopped \
        -p 8002:8002 \
        -p 8005:8000 \
        -v "$MODEL_CACHE_DIR:/root/.cache/huggingface:ro" \
        -v "$LOG_DIR:/app/logs" \
        -v "${PWD}/data:/app/data" \
        -e CUDA_VISIBLE_DEVICES=4 \
        -e HF_HUB_OFFLINE=1 \
        -e TRANSFORMERS_OFFLINE=1 \
        -e VLLM_USE_TRITON=0 \
        -e MODEL_NAME=rednote-hilab/dots.ocr \
        -e MAX_MODEL_LEN=1024 \
        -e GPU_MEMORY_UTILIZATION=0.8 \
        rag-dots-ocr-official:latest

    wait_for_service "OCR" "http://localhost:8002/health"
}

# Deploy API service (CPU only)
deploy_api() {
    print_header "Deploying API Service (CPU)"

    docker stop rag-api 2>/dev/null || true
    docker rm rag-api 2>/dev/null || true

    docker run -d \
        --name rag-api \
        --network $NETWORK_NAME \
        --restart unless-stopped \
        -p 8080:8080 \
        -v "${PWD}/configs:/app/configs:ro" \
        -v "${PWD}/data:/app/data" \
        -v "$LOG_DIR:/app/logs" \
        -v "$MODEL_CACHE_DIR:/root/.cache/huggingface:ro" \
        -e HIRAG_CONFIG_PATH=/app/configs/hirag-config.yaml \
        -e LOG_LEVEL=INFO \
        -e PYTHONPATH=/app \
        rag-api:latest

    wait_for_service "API" "http://localhost:8080/health"
}

# Deploy Frontend service (CPU only)
deploy_frontend() {
    print_header "Deploying Frontend Service (CPU)"

    docker stop rag-frontend 2>/dev/null || true
    docker rm rag-frontend 2>/dev/null || true

    docker run -d \
        --name rag-frontend \
        --network $NETWORK_NAME \
        --restart unless-stopped \
        -p 8087:8087 \
        -v "$LOG_DIR:/var/log/nginx" \
        -e API_BASE_URL=http://rag-api:8080 \
        -e LANGFLOW_URL=http://rag-langflow:7860 \
        rag-frontend-complete:latest

    wait_for_service "Frontend" "http://localhost:8087/frontend-health"
}

# Deploy Langflow service (CPU only)
deploy_langflow() {
    print_header "Deploying Langflow Service (CPU)"

    docker stop rag-langflow 2>/dev/null || true
    docker rm rag-langflow 2>/dev/null || true

    docker run -d \
        --name rag-langflow \
        --network $NETWORK_NAME \
        --restart unless-stopped \
        -p 7860:7860 \
        -v "${PWD}/data/langflow:/app/data" \
        -v "$LOG_DIR:/app/logs" \
        -e LANGFLOW_HOST=0.0.0.0 \
        -e LANGFLOW_PORT=7860 \
        -e LANGFLOW_WORKERS=1 \
        rag-langflow:latest

    wait_for_service "Langflow" "http://localhost:7860/health"
}

# Test all services
test_services() {
    print_header "Testing All Services"

    services=(
        "8004:Whisper"
        "8001:Embedding"
        "8003:LLM"
        "8002:OCR"
        "8080:API"
        "8087:Frontend"
        "7860:Langflow"
    )

    healthy_count=0
    total_count=${#services[@]}

    for service in "${services[@]}"; do
        IFS=':' read -r port name <<< "$service"

        if [ "$name" = "Frontend" ]; then
            endpoint="http://localhost:$port/frontend-health"
        else
            endpoint="http://localhost:$port/health"
        fi

        if curl -s "$endpoint" > /dev/null 2>&1; then
            print_status "$name (port $port) - healthy"
            ((healthy_count++))
        else
            print_error "$name (port $port) - unhealthy"
        fi
    done

    echo ""
    echo "Service Health Summary: $healthy_count/$total_count services healthy"

    if [ $healthy_count -eq $total_count ]; then
        print_status "All services deployed successfully!"
    else
        print_warning "Some services are not healthy. Check logs for details."
    fi
}

# Show final status
show_status() {
    print_header "Deployment Complete"

    echo ""
    echo "🌐 Service URLs:"
    echo "    Main UI:     http://localhost:8087"
    echo "    Langflow:    http://localhost:8087/langflow"
    echo "    API Docs:    http://localhost:8080/docs"
    echo "    API Health:  http://localhost:8080/health"
    echo ""

    echo "🐳 Container Status:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(NAMES|rag-)"

    echo ""
    echo "📊 GPU Status:"
    nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used --format=csv || echo "GPU info not available"

    echo ""
    echo "📁 Log Files:"
    echo "    Logs are available in: $LOG_DIR"
    echo "    Docker logs: docker logs <container-name>"
}

# Cleanup function
cleanup() {
    print_header "Cleanup"

    containers=("rag-whisper" "rag-embedding-server" "rag-llm-server" "rag-dots-ocr" "rag-api" "rag-frontend" "rag-langflow")

    echo "Stopping containers..."
    for container in "${containers[@]}"; do
        docker stop "$container" 2>/dev/null || true
        docker rm "$container" 2>/dev/null || true
    done

    echo "Removing network..."
    docker network rm $NETWORK_NAME 2>/dev/null || true

    print_status "Cleanup complete"
}

# Main execution
main() {
    echo "H100 Cluster Manual Deployment"
    echo "This will deploy the RAG system without docker-compose"
    echo ""
    echo "Configuration:"
    echo "  Model Cache: $MODEL_CACHE_DIR"
    echo "  Network: $NETWORK_NAME"
    echo "  Logs: $LOG_DIR"
    echo ""

    # Check if cleanup is requested
    if [ "$1" = "cleanup" ]; then
        cleanup
        exit 0
    fi

    # Deployment sequence
    check_prerequisites
    create_network

    # Deploy services in dependency order
    deploy_whisper
    deploy_embedding
    deploy_llm
    deploy_ocr
    deploy_api
    deploy_frontend
    deploy_langflow

    # Final testing and status
    test_services
    show_status
}

# Handle signals for cleanup
trap cleanup EXIT INT TERM

# Run main function
main "$@"