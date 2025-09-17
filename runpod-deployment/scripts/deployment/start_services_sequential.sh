#!/bin/bash

# Sequential Service Startup with Dependency Management
# Ensures services start in correct order with health checks

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }

# Configuration
MODEL_CACHE_DIR="${MODEL_CACHE_DIR:-/opt/model-cache}"
NETWORK_NAME="rag-network"
STARTUP_TIMEOUT=120  # 2 minutes per service

# Check if service is running and healthy
check_service_health() {
    local container_name=$1
    local health_url=$2
    local timeout=${3:-$STARTUP_TIMEOUT}

    print_info "Checking $container_name health..."

    # Check if container is running
    if ! docker ps | grep -q "$container_name"; then
        print_error "$container_name is not running"
        return 1
    fi

    # Check health endpoint
    local count=0
    while [ $count -lt $timeout ]; do
        if curl -s --max-time 5 "$health_url" > /dev/null 2>&1; then
            print_status "$container_name is healthy"
            return 0
        fi

        if [ $((count % 10)) -eq 0 ]; then
            echo -n "Waiting for $container_name"
        fi
        echo -n "."
        sleep 1
        ((count++))
    done

    echo ""
    print_error "$container_name failed to become healthy within $timeout seconds"

    # Show container logs for debugging
    echo "Container logs (last 20 lines):"
    docker logs "$container_name" --tail 20 || true

    return 1
}

# Start individual services with dependency checks
start_whisper() {
    echo "=== Starting Whisper Service (GPU 0) ==="

    if docker ps | grep -q "rag-whisper"; then
        print_warning "Whisper service already running"
        return 0
    fi

    docker run -d \
        --name rag-whisper \
        --network $NETWORK_NAME \
        --gpus '"device=0"' \
        --restart unless-stopped \
        -p 8004:8004 \
        -v "$MODEL_CACHE_DIR:/root/.cache/huggingface:ro" \
        -v "$(pwd)/logs:/app/logs" \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e HF_HUB_OFFLINE=1 \
        -e TRANSFORMERS_OFFLINE=1 \
        -e DEVICE=cuda \
        rag-whisper:latest

    check_service_health "rag-whisper" "http://localhost:8004/health"
}

start_embedding() {
    echo "=== Starting Embedding Service (GPU 1) ==="

    if docker ps | grep -q "rag-embedding-server"; then
        print_warning "Embedding service already running"
        return 0
    fi

    docker run -d \
        --name rag-embedding-server \
        --network $NETWORK_NAME \
        --gpus '"device=1"' \
        --restart unless-stopped \
        -p 8001:8000 \
        -v "$MODEL_CACHE_DIR:/root/.cache/huggingface:ro" \
        -v "$(pwd)/logs:/app/logs" \
        -e CUDA_VISIBLE_DEVICES=1 \
        -e HF_HUB_OFFLINE=1 \
        -e TRANSFORMERS_OFFLINE=1 \
        -e VLLM_USE_TRITON=0 \
        -e MODEL_NAME=Qwen/Qwen3-Embedding-4B \
        -e MAX_MODEL_LEN=1024 \
        -e GPU_MEMORY_UTILIZATION=0.9 \
        rag-llm-gptoss:latest

    check_service_health "rag-embedding-server" "http://localhost:8001/health"
}

start_llm() {
    echo "=== Starting LLM Service (GPU 2-3) ==="

    if docker ps | grep -q "rag-llm-server"; then
        print_warning "LLM service already running"
        return 0
    fi

    docker run -d \
        --name rag-llm-server \
        --network $NETWORK_NAME \
        --gpus '"device=2,3"' \
        --restart unless-stopped \
        --shm-size=32g \
        -p 8003:8000 \
        -v "$MODEL_CACHE_DIR:/root/.cache/huggingface:ro" \
        -v "$(pwd)/logs:/app/logs" \
        -e CUDA_VISIBLE_DEVICES=2,3 \
        -e HF_HUB_OFFLINE=1 \
        -e TRANSFORMERS_OFFLINE=1 \
        -e VLLM_USE_TRITON=0 \
        -e MODEL_NAME=openai/gpt-oss-20b \
        -e MAX_MODEL_LEN=4096 \
        -e TENSOR_PARALLEL_SIZE=2 \
        -e GPU_MEMORY_UTILIZATION=0.9 \
        rag-llm-gptoss:latest

    check_service_health "rag-llm-server" "http://localhost:8003/health"
}

start_ocr() {
    echo "=== Starting OCR Service (GPU 4) ==="

    if docker ps | grep -q "rag-dots-ocr"; then
        print_warning "OCR service already running"
        return 0
    fi

    docker run -d \
        --name rag-dots-ocr \
        --network $NETWORK_NAME \
        --gpus '"device=4"' \
        --restart unless-stopped \
        -p 8002:8002 \
        -v "$MODEL_CACHE_DIR:/root/.cache/huggingface:ro" \
        -v "$(pwd)/data:/app/data" \
        -v "$(pwd)/logs:/app/logs" \
        -e CUDA_VISIBLE_DEVICES=4 \
        -e HF_HUB_OFFLINE=1 \
        -e TRANSFORMERS_OFFLINE=1 \
        -e VLLM_USE_TRITON=0 \
        -e MODEL_NAME=rednote-hilab/dots.ocr \
        -e MAX_MODEL_LEN=1024 \
        -e GPU_MEMORY_UTILIZATION=0.8 \
        rag-dots-ocr-official:latest

    check_service_health "rag-dots-ocr" "http://localhost:8002/health"
}

start_api() {
    echo "=== Starting API Service (CPU) ==="

    # API depends on LLM and Embedding services
    print_info "Verifying LLM and Embedding services are healthy..."

    if ! curl -s --max-time 5 "http://localhost:8003/health" > /dev/null; then
        print_error "LLM service not healthy - cannot start API"
        return 1
    fi

    if ! curl -s --max-time 5 "http://localhost:8001/health" > /dev/null; then
        print_error "Embedding service not healthy - cannot start API"
        return 1
    fi

    if docker ps | grep -q "rag-api"; then
        print_warning "API service already running"
        return 0
    fi

    docker run -d \
        --name rag-api \
        --network $NETWORK_NAME \
        --restart unless-stopped \
        -p 8080:8080 \
        -v "$(pwd)/configs:/app/configs:ro" \
        -v "$(pwd)/data:/app/data" \
        -v "$(pwd)/logs:/app/logs" \
        -v "$MODEL_CACHE_DIR:/root/.cache/huggingface:ro" \
        -e HIRAG_CONFIG_PATH=/app/configs/hirag-config.yaml \
        -e LOG_LEVEL=INFO \
        -e PYTHONPATH=/app \
        rag-api:latest

    check_service_health "rag-api" "http://localhost:8080/health"
}

start_langflow() {
    echo "=== Starting Langflow Service (CPU) ==="

    if docker ps | grep -q "rag-langflow"; then
        print_warning "Langflow service already running"
        return 0
    fi

    docker run -d \
        --name rag-langflow \
        --network $NETWORK_NAME \
        --restart unless-stopped \
        -p 7860:7860 \
        -v "$(pwd)/data/langflow:/app/data" \
        -v "$(pwd)/logs:/app/logs" \
        -e LANGFLOW_HOST=0.0.0.0 \
        -e LANGFLOW_PORT=7860 \
        -e LANGFLOW_WORKERS=1 \
        rag-langflow:latest

    check_service_health "rag-langflow" "http://localhost:7860/health"
}

start_frontend() {
    echo "=== Starting Frontend Service (CPU) ==="

    # Frontend depends on API and Langflow
    print_info "Verifying API and Langflow services are healthy..."

    if ! curl -s --max-time 5 "http://localhost:8080/health" > /dev/null; then
        print_error "API service not healthy - cannot start Frontend"
        return 1
    fi

    if ! curl -s --max-time 5 "http://localhost:7860/health" > /dev/null; then
        print_error "Langflow service not healthy - cannot start Frontend"
        return 1
    fi

    if docker ps | grep -q "rag-frontend"; then
        print_warning "Frontend service already running"
        return 0
    fi

    docker run -d \
        --name rag-frontend \
        --network $NETWORK_NAME \
        --restart unless-stopped \
        -p 8087:8087 \
        -v "$(pwd)/logs:/var/log/nginx" \
        -e API_BASE_URL=http://rag-api:8080 \
        -e LANGFLOW_URL=http://rag-langflow:7860 \
        rag-frontend-complete:latest

    check_service_health "rag-frontend" "http://localhost:8087/frontend-health"
}

# Create network if it doesn't exist
ensure_network() {
    if ! docker network ls | grep -q "$NETWORK_NAME"; then
        print_info "Creating network $NETWORK_NAME..."
        docker network create --driver bridge --subnet 172.20.0.0/16 $NETWORK_NAME
        print_status "Network created"
    else
        print_info "Network $NETWORK_NAME already exists"
    fi
}

# Stop specific service
stop_service() {
    local service_name=$1
    if docker ps | grep -q "$service_name"; then
        print_info "Stopping $service_name..."
        docker stop "$service_name"
        docker rm "$service_name"
        print_status "$service_name stopped"
    else
        print_warning "$service_name not running"
    fi
}

# Show usage
usage() {
    echo "Usage: $0 [command] [service]"
    echo ""
    echo "Commands:"
    echo "  start [service]  - Start all services or specific service"
    echo "  stop [service]   - Stop all services or specific service"
    echo "  restart [service] - Restart all services or specific service"
    echo "  status           - Show service status"
    echo "  logs [service]   - Show logs for all or specific service"
    echo ""
    echo "Services: whisper, embedding, llm, ocr, api, langflow, frontend"
    echo ""
    echo "Examples:"
    echo "  $0 start           # Start all services"
    echo "  $0 start llm       # Start only LLM service"
    echo "  $0 stop            # Stop all services"
    echo "  $0 restart api     # Restart API service"
    echo "  $0 status          # Show status of all services"
    echo "  $0 logs llm        # Show LLM logs"
}

# Show service status
show_status() {
    echo "=== Service Status ==="
    echo ""

    services=("rag-whisper:8004" "rag-embedding-server:8001" "rag-llm-server:8003" "rag-dots-ocr:8002" "rag-api:8080" "rag-langflow:7860" "rag-frontend:8087")

    for service_port in "${services[@]}"; do
        IFS=':' read -r service port <<< "$service_port"

        if docker ps | grep -q "$service"; then
            container_status=$(docker ps --format "{{.Status}}" --filter "name=$service")

            # Check health
            if [ "$service" = "rag-frontend" ]; then
                health_url="http://localhost:$port/frontend-health"
            else
                health_url="http://localhost:$port/health"
            fi

            if curl -s --max-time 2 "$health_url" > /dev/null 2>&1; then
                health_status="${GREEN}healthy${NC}"
            else
                health_status="${RED}unhealthy${NC}"
            fi

            echo -e "$service: ${GREEN}running${NC} ($container_status) - $health_status"
        else
            echo -e "$service: ${RED}stopped${NC}"
        fi
    done
}

# Show logs
show_logs() {
    local service=$1

    if [ -n "$service" ]; then
        if docker ps | grep -q "$service"; then
            docker logs -f "$service"
        else
            print_error "Service $service not running"
        fi
    else
        echo "=== All Service Logs ==="
        docker logs rag-whisper --tail 10 2>/dev/null || echo "Whisper: not running"
        docker logs rag-embedding-server --tail 10 2>/dev/null || echo "Embedding: not running"
        docker logs rag-llm-server --tail 10 2>/dev/null || echo "LLM: not running"
        docker logs rag-dots-ocr --tail 10 2>/dev/null || echo "OCR: not running"
        docker logs rag-api --tail 10 2>/dev/null || echo "API: not running"
        docker logs rag-langflow --tail 10 2>/dev/null || echo "Langflow: not running"
        docker logs rag-frontend --tail 10 2>/dev/null || echo "Frontend: not running"
    fi
}

# Main execution
main() {
    local command=${1:-start}
    local service=$2

    case $command in
        start)
            ensure_network

            if [ -n "$service" ]; then
                case $service in
                    whisper) start_whisper ;;
                    embedding) start_embedding ;;
                    llm) start_llm ;;
                    ocr) start_ocr ;;
                    api) start_api ;;
                    langflow) start_langflow ;;
                    frontend) start_frontend ;;
                    *) print_error "Unknown service: $service"; usage; exit 1 ;;
                esac
            else
                # Start all services in dependency order
                start_whisper
                start_embedding
                start_llm
                start_ocr
                start_api
                start_langflow
                start_frontend

                echo ""
                print_status "All services started successfully!"
                show_status
            fi
            ;;

        stop)
            if [ -n "$service" ]; then
                stop_service "rag-$service"
            else
                print_info "Stopping all services..."
                for container in rag-frontend rag-langflow rag-api rag-dots-ocr rag-llm-server rag-embedding-server rag-whisper; do
                    stop_service "$container"
                done
            fi
            ;;

        restart)
            if [ -n "$service" ]; then
                stop_service "rag-$service"
                sleep 2
                main start "$service"
            else
                main stop
                sleep 5
                main start
            fi
            ;;

        status)
            show_status
            ;;

        logs)
            show_logs "rag-$service"
            ;;

        *)
            usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"