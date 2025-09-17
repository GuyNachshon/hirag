#!/bin/bash

# H100 Cluster Optimized Deployment
# Optimized for H100 GPU architecture with enhanced performance settings

set -e

echo "============================================"
echo "    H100 CLUSTER OPTIMIZED DEPLOYMENT      "
echo "============================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_header() { echo -e "\n=== $1 ==="; }

# Configuration for H100 optimization
MODEL_CACHE_DIR="${MODEL_CACHE_DIR:-/opt/model-cache}"
NETWORK_NAME="rag-network"
LOG_DIR="${PWD}/logs"

# H100-specific optimizations
H100_OPTIMIZATIONS=(
    "CUDA_LAUNCH_BLOCKING=0"
    "TORCH_CUDA_ARCH_LIST=9.0"  # H100 compute capability
    "NCCL_ALGO=Tree"
    "NCCL_P2P_DISABLE=0"
    "CUDA_DEVICE_MAX_CONNECTIONS=1"
)

# Check for H100 GPUs
check_h100_gpus() {
    print_header "Checking H100 GPU Configuration"

    if ! nvidia-smi &> /dev/null; then
        print_error "NVIDIA GPU drivers not available"
        exit 1
    fi

    # Check for H100 GPUs
    gpu_info=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits)
    h100_count=$(echo "$gpu_info" | grep -c "H100" || echo "0")

    if [ "$h100_count" -gt 0 ]; then
        print_status "Detected $h100_count H100 GPU(s)"
        echo "H100 GPUs detected:"
        nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader | grep H100
    else
        print_warning "No H100 GPUs detected. Using A100 optimizations."
        # Fallback to A100 settings
        H100_OPTIMIZATIONS[1]="TORCH_CUDA_ARCH_LIST=8.0,8.6"
    fi

    # Show full GPU status
    echo ""
    nvidia-smi --query-gpu=index,name,memory.total,compute_cap --format=csv
}

# Apply H100 optimizations
apply_h100_optimizations() {
    print_header "Applying H100 Optimizations"

    for opt in "${H100_OPTIMIZATIONS[@]}"; do
        export "$opt"
        echo "Applied: $opt"
    done

    # Set additional H100-specific environment variables
    export NVIDIA_TF32_OVERRIDE=1  # Enable TF32 for better performance
    export CUDA_MODULE_LOADING=LAZY  # Lazy loading for faster startup
    export TORCH_CUDNN_V8_API_ENABLED=1  # Enhanced cuDNN performance

    print_status "H100 optimizations applied"
}

# Enhanced network creation with performance settings
create_optimized_network() {
    print_header "Creating Optimized Docker Network"

    # Remove existing network
    docker network rm $NETWORK_NAME 2>/dev/null || true

    # Create network with optimized settings
    docker network create \
        --driver bridge \
        --subnet 172.20.0.0/16 \
        --opt com.docker.network.bridge.enable_icc=true \
        --opt com.docker.network.bridge.enable_ip_masquerade=true \
        --opt com.docker.network.driver.mtu=9000 \
        $NETWORK_NAME

    print_status "Optimized network '$NETWORK_NAME' created"
}

# Deploy Whisper with H100 optimizations
deploy_whisper_h100() {
    print_header "Deploying Whisper Service (GPU 0) - H100 Optimized"

    docker stop rag-whisper 2>/dev/null || true
    docker rm rag-whisper 2>/dev/null || true

    docker run -d \
        --name rag-whisper \
        --network $NETWORK_NAME \
        --gpus '"device=0"' \
        --restart unless-stopped \
        --shm-size=4g \
        --ulimit memlock=-1 \
        --ulimit stack=67108864 \
        -p 8004:8004 \
        -v "$MODEL_CACHE_DIR:/root/.cache/huggingface:ro" \
        -v "$LOG_DIR:/app/logs" \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e HF_HUB_OFFLINE=1 \
        -e TRANSFORMERS_OFFLINE=1 \
        -e DEVICE=cuda \
        -e TORCH_CUDA_ARCH_LIST=9.0 \
        -e CUDA_LAUNCH_BLOCKING=0 \
        -e NVIDIA_TF32_OVERRIDE=1 \
        rag-whisper:latest

    wait_for_service "Whisper" "http://localhost:8004/health" 180
}

# Deploy Embedding with H100 optimizations
deploy_embedding_h100() {
    print_header "Deploying Embedding Service (GPU 1) - H100 Optimized"

    docker stop rag-embedding-server 2>/dev/null || true
    docker rm rag-embedding-server 2>/dev/null || true

    docker run -d \
        --name rag-embedding-server \
        --network $NETWORK_NAME \
        --gpus '"device=1"' \
        --restart unless-stopped \
        --shm-size=8g \
        --ulimit memlock=-1 \
        --ulimit stack=67108864 \
        -p 8001:8000 \
        -v "$MODEL_CACHE_DIR:/root/.cache/huggingface:ro" \
        -v "$LOG_DIR:/app/logs" \
        -e CUDA_VISIBLE_DEVICES=1 \
        -e HF_HUB_OFFLINE=1 \
        -e TRANSFORMERS_OFFLINE=1 \
        -e VLLM_USE_TRITON=0 \
        -e MODEL_NAME=Qwen/Qwen3-Embedding-4B \
        -e MAX_MODEL_LEN=1024 \
        -e GPU_MEMORY_UTILIZATION=0.95 \
        -e TORCH_CUDA_ARCH_LIST=9.0 \
        -e CUDA_LAUNCH_BLOCKING=0 \
        -e NVIDIA_TF32_OVERRIDE=1 \
        -e ENABLE_PREFIX_CACHING=true \
        rag-llm-gptoss:latest

    wait_for_service "Embedding" "http://localhost:8001/health" 300
}

# Deploy LLM with H100 multi-GPU optimizations
deploy_llm_h100() {
    print_header "Deploying LLM Service (GPU 2-3) - H100 Multi-GPU Optimized"

    docker stop rag-llm-server 2>/dev/null || true
    docker rm rag-llm-server 2>/dev/null || true

    docker run -d \
        --name rag-llm-server \
        --network $NETWORK_NAME \
        --gpus '"device=2,3"' \
        --restart unless-stopped \
        --shm-size=64g \
        --ulimit memlock=-1 \
        --ulimit stack=67108864 \
        --ipc=host \
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
        -e GPU_MEMORY_UTILIZATION=0.95 \
        -e TORCH_CUDA_ARCH_LIST=9.0 \
        -e CUDA_LAUNCH_BLOCKING=0 \
        -e NVIDIA_TF32_OVERRIDE=1 \
        -e NCCL_ALGO=Tree \
        -e NCCL_P2P_DISABLE=0 \
        -e ENABLE_PREFIX_CACHING=true \
        -e MAX_NUM_SEQS=512 \
        -e ENABLE_CHUNKED_PREFILL=true \
        rag-llm-gptoss:latest

    wait_for_service "LLM" "http://localhost:8003/health" 600
}

# Deploy OCR with H100 optimizations
deploy_ocr_h100() {
    print_header "Deploying OCR Service (GPU 4) - H100 Optimized"

    docker stop rag-dots-ocr 2>/dev/null || true
    docker rm rag-dots-ocr 2>/dev/null || true

    docker run -d \
        --name rag-dots-ocr \
        --network $NETWORK_NAME \
        --gpus '"device=4"' \
        --restart unless-stopped \
        --shm-size=8g \
        --ulimit memlock=-1 \
        -p 8002:8002 \
        -v "$MODEL_CACHE_DIR:/root/.cache/huggingface:ro" \
        -v "$LOG_DIR:/app/logs" \
        -v "${PWD}/data:/app/data" \
        -e CUDA_VISIBLE_DEVICES=4 \
        -e HF_HUB_OFFLINE=1 \
        -e TRANSFORMERS_OFFLINE=1 \
        -e VLLM_USE_TRITON=0 \
        -e MODEL_NAME=rednote-hilab/dots.ocr \
        -e MAX_MODEL_LEN=1024 \
        -e GPU_MEMORY_UTILIZATION=0.9 \
        -e TORCH_CUDA_ARCH_LIST=9.0 \
        -e CUDA_LAUNCH_BLOCKING=0 \
        -e NVIDIA_TF32_OVERRIDE=1 \
        rag-dots-ocr-official:latest

    wait_for_service "OCR" "http://localhost:8002/health" 180
}

# Deploy API with enhanced configuration
deploy_api_enhanced() {
    print_header "Deploying API Service - Enhanced Configuration"

    docker stop rag-api 2>/dev/null || true
    docker rm rag-api 2>/dev/null || true

    docker run -d \
        --name rag-api \
        --network $NETWORK_NAME \
        --restart unless-stopped \
        --cpus="8" \
        --memory="16g" \
        -p 8080:8080 \
        -v "${PWD}/configs:/app/configs:ro" \
        -v "${PWD}/data:/app/data" \
        -v "$LOG_DIR:/app/logs" \
        -v "$MODEL_CACHE_DIR:/root/.cache/huggingface:ro" \
        -e HIRAG_CONFIG_PATH=/app/configs/hirag-config.yaml \
        -e LOG_LEVEL=INFO \
        -e PYTHONPATH=/app \
        -e WORKERS=4 \
        -e MAX_CONCURRENT_REQUESTS=100 \
        rag-api:latest

    wait_for_service "API" "http://localhost:8080/health" 120
}

# Deploy Frontend with performance optimizations
deploy_frontend_optimized() {
    print_header "Deploying Frontend Service - Performance Optimized"

    docker stop rag-frontend 2>/dev/null || true
    docker rm rag-frontend 2>/dev/null || true

    docker run -d \
        --name rag-frontend \
        --network $NETWORK_NAME \
        --restart unless-stopped \
        --cpus="4" \
        --memory="4g" \
        -p 8087:8087 \
        -v "$LOG_DIR:/var/log/nginx" \
        -e API_BASE_URL=http://rag-api:8080 \
        -e LANGFLOW_URL=http://rag-langflow:7860 \
        -e NGINX_WORKER_PROCESSES=auto \
        -e NGINX_WORKER_CONNECTIONS=2048 \
        rag-frontend-complete:latest

    wait_for_service "Frontend" "http://localhost:8087/frontend-health" 60
}

# Deploy Langflow with enhanced settings
deploy_langflow_enhanced() {
    print_header "Deploying Langflow Service - Enhanced Configuration"

    docker stop rag-langflow 2>/dev/null || true
    docker rm rag-langflow 2>/dev/null || true

    docker run -d \
        --name rag-langflow \
        --network $NETWORK_NAME \
        --restart unless-stopped \
        --cpus="4" \
        --memory="8g" \
        -p 7860:7860 \
        -v "${PWD}/data/langflow:/app/data" \
        -v "$LOG_DIR:/app/logs" \
        -e LANGFLOW_HOST=0.0.0.0 \
        -e LANGFLOW_PORT=7860 \
        -e LANGFLOW_WORKERS=2 \
        -e LANGFLOW_MAX_FILE_SIZE=100MB \
        rag-langflow:latest

    wait_for_service "Langflow" "http://localhost:7860/health" 120
}

# Enhanced service health check with performance metrics
wait_for_service() {
    local service_name=$1
    local health_url=$2
    local max_attempts=${3:-30}

    print_info "Waiting for $service_name to be healthy (timeout: ${max_attempts}s)..."

    for i in $(seq 1 $max_attempts); do
        if curl -s "$health_url" > /dev/null 2>&1; then
            # Get service performance metrics
            response=$(curl -s "$health_url" 2>/dev/null || echo "{}")
            print_status "$service_name is healthy"

            # Show GPU utilization if available
            if [[ "$service_name" =~ (Whisper|Embedding|LLM|OCR) ]]; then
                gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo "N/A")
                echo "    GPU Utilization: $gpu_util%"
            fi

            return 0
        fi

        if [ $((i % 10)) -eq 0 ]; then
            echo -n " [$i/${max_attempts}]"
        fi
        echo -n "."
        sleep 1
    done

    echo ""
    print_error "$service_name failed to become healthy within $max_attempts seconds"

    # Show detailed error information
    echo "Service logs (last 10 lines):"
    docker logs "rag-${service_name,,}" --tail 10 2>/dev/null || echo "No logs available"

    return 1
}

# Performance monitoring and optimization
monitor_performance() {
    print_header "Performance Monitoring"

    echo "GPU Status:"
    nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv

    echo ""
    echo "Container Resource Usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"

    echo ""
    echo "Network Performance:"
    docker exec rag-api curl -s http://rag-llm-server:8000/health -w "LLM Response Time: %{time_total}s\n" -o /dev/null || true
    docker exec rag-api curl -s http://rag-embedding-server:8000/health -w "Embedding Response Time: %{time_total}s\n" -o /dev/null || true
}

# Main deployment function
main() {
    echo "H100 Cluster Optimized Deployment"
    echo "Deploying RAG system with H100-specific optimizations"
    echo ""

    # Check command line arguments
    case "${1:-deploy}" in
        "deploy")
            check_h100_gpus
            apply_h100_optimizations
            create_optimized_network

            # Deploy services in optimized order
            deploy_whisper_h100
            deploy_embedding_h100
            deploy_llm_h100
            deploy_ocr_h100
            deploy_api_enhanced
            deploy_langflow_enhanced
            deploy_frontend_optimized

            monitor_performance
            show_final_status
            ;;

        "monitor")
            monitor_performance
            ;;

        "cleanup")
            cleanup_all_services
            ;;

        *)
            echo "Usage: $0 [deploy|monitor|cleanup]"
            echo ""
            echo "Commands:"
            echo "  deploy  - Deploy all services with H100 optimizations (default)"
            echo "  monitor - Show performance monitoring"
            echo "  cleanup - Clean up all services and networks"
            exit 1
            ;;
    esac
}

# Show final deployment status
show_final_status() {
    print_header "H100 Deployment Complete"

    echo ""
    echo "🚀 H100 Optimized RAG System Deployed Successfully!"
    echo ""
    echo "🌐 Service URLs:"
    echo "    Main UI:     http://localhost:8087"
    echo "    API Docs:    http://localhost:8080/docs"
    echo "    Langflow:    http://localhost:8087/langflow"
    echo ""

    echo "🔧 H100 Optimizations Applied:"
    for opt in "${H100_OPTIMIZATIONS[@]}"; do
        echo "    $opt"
    done

    echo ""
    echo "📊 Current Performance:"
    monitor_performance
}

# Cleanup function
cleanup_all_services() {
    print_header "Cleaning Up All Services"

    containers=("rag-whisper" "rag-embedding-server" "rag-llm-server" "rag-dots-ocr" "rag-api" "rag-frontend" "rag-langflow")

    for container in "${containers[@]}"; do
        docker stop "$container" 2>/dev/null || true
        docker rm "$container" 2>/dev/null || true
    done

    docker network rm $NETWORK_NAME 2>/dev/null || true

    print_status "Cleanup complete"
}

# Handle signals
trap cleanup_all_services EXIT INT TERM

# Run main function
main "$@"