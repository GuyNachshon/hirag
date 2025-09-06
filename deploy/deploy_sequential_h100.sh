#!/bin/bash

set -e  # Exit on any error

echo "=========================================="
echo "Sequential RAG System Deployment for H100"
echo "Memory-Optimized Startup Order"
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
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Configuration
NETWORK_NAME="rag-network"
MAX_WAIT_TIME=300  # 5 minutes max wait per service
HEALTH_CHECK_INTERVAL=10

# GPU Memory monitoring function
check_gpu_memory() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        local used_mem=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
        local total_mem=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
        local free_mem=$((total_mem - used_mem))
        
        print_status "GPU Memory: ${used_mem}MB used / ${total_mem}MB total (${free_mem}MB free)"
        
        # Return free memory in MB
        echo $free_mem
    else
        print_warning "nvidia-smi not available, skipping GPU memory check"
        echo 99999  # Return large number if can't check
    fi
}

# Health check function
wait_for_health() {
    local service_name=$1
    local health_url=$2
    local max_wait=$3
    local wait_time=0
    
    print_status "Waiting for $service_name to become healthy..."
    
    while [ $wait_time -lt $max_wait ]; do
        if curl -f -s "$health_url" >/dev/null 2>&1; then
            print_status "✓ $service_name is healthy"
            return 0
        fi
        
        sleep $HEALTH_CHECK_INTERVAL
        wait_time=$((wait_time + HEALTH_CHECK_INTERVAL))
        echo -n "."
    done
    
    print_error "✗ $service_name failed to become healthy within ${max_wait}s"
    return 1
}

# Stop all services function
stop_all_services() {
    print_header "Stopping all RAG services..."
    
    docker stop rag-frontend rag-api rag-embedding-server rag-dots-ocr rag-llm-server rag-whisper 2>/dev/null || true
    docker rm rag-frontend rag-api rag-embedding-server rag-dots-ocr rag-llm-server rag-whisper 2>/dev/null || true
    
    print_status "All services stopped"
}

# Check prerequisites
print_header "1. Checking prerequisites..."

if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

print_status "✓ Docker is running"

# Check GPU
if ! command -v nvidia-smi >/dev/null 2>&1; then
    print_warning "nvidia-smi not found. GPU monitoring disabled."
else
    print_status "✓ NVIDIA GPU detected"
    check_gpu_memory >/dev/null
fi

# Setup network
print_header "2. Setting up Docker network..."
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    docker network create "$NETWORK_NAME"
    print_status "✓ Created network: $NETWORK_NAME"
else
    print_status "✓ Network exists: $NETWORK_NAME"
fi

# Clean up any existing containers
print_header "3. Cleaning up existing containers..."
stop_all_services

# Create data directories
print_header "4. Setting up data directories..."
mkdir -p ./data/{input,working,logs,cache}
print_status "✓ Data directories created"

echo ""
print_header "Starting services sequentially with GPU memory monitoring..."
echo ""

# Service 1: Embedding Server (4GB expected)
print_header "5. Starting Embedding Server (~4GB GPU)"
free_mem=$(check_gpu_memory)
if [ "$free_mem" -lt 5000 ]; then
    print_warning "Low GPU memory: ${free_mem}MB free. Proceeding anyway..."
fi

docker run -d \
    --name rag-embedding-server \
    --network "$NETWORK_NAME" \
    --gpus all \
    --restart unless-stopped \
    -p 8001:8000 \
    rag-embedding-server:tgi-optimized

if wait_for_health "Embedding Server" "http://localhost:8001/health" $MAX_WAIT_TIME; then
    check_gpu_memory >/dev/null
    echo ""
else
    print_error "Embedding Server failed to start. Aborting deployment."
    exit 1
fi

# Service 2: Whisper (~5GB expected)
print_header "6. Starting Whisper Service (~5GB GPU)"
free_mem=$(check_gpu_memory)
if [ "$free_mem" -lt 6000 ]; then
    print_warning "Low GPU memory: ${free_mem}MB free. Consider stopping other processes."
fi

docker run -d \
    --name rag-whisper \
    --network "$NETWORK_NAME" \
    --gpus all \
    --restart unless-stopped \
    -p 8004:8004 \
    -e CUDA_VISIBLE_DEVICES=0 \
    rag-whisper:latest

if wait_for_health "Whisper Service" "http://localhost:8004/health" $MAX_WAIT_TIME; then
    check_gpu_memory >/dev/null
    echo ""
else
    print_error "Whisper Service failed to start. Aborting deployment."
    exit 1
fi

# Service 3: API Server (~2GB expected)
print_header "7. Starting API Server (~2GB RAM)"
docker run -d \
    --name rag-api \
    --network "$NETWORK_NAME" \
    --restart unless-stopped \
    -p 8080:8080 \
    -v $(pwd)/data:/app/data \
    -v $(pwd)/config:/app/config \
    -e ENVIRONMENT=production \
    rag-api:optimized

if wait_for_health "API Server" "http://localhost:8080/health" $MAX_WAIT_TIME; then
    print_status "API Server running on CPU as expected"
    echo ""
else
    print_error "API Server failed to start. Aborting deployment."
    exit 1
fi

# Service 4: DotsOCR (~16GB expected - 40% of available)
print_header "8. Starting DotsOCR Server (~16GB GPU)"
free_mem=$(check_gpu_memory)
if [ "$free_mem" -lt 17000 ]; then
    print_error "Insufficient GPU memory: ${free_mem}MB free, need ~17GB. Please free up memory or adjust configuration."
    exit 1
fi

docker run -d \
    --name rag-dots-ocr \
    --network "$NETWORK_NAME" \
    --gpus all \
    --shm-size=8g \
    --restart unless-stopped \
    -p 8002:8000 \
    -e CUDA_VISIBLE_DEVICES=0 \
    rag-dots-ocr:latest

if wait_for_health "DotsOCR Server" "http://localhost:8002/health" $MAX_WAIT_TIME; then
    check_gpu_memory >/dev/null
    echo ""
else
    print_error "DotsOCR Server failed to start. Aborting deployment."
    exit 1
fi

# Service 5: LLM Server (~40GB expected)
print_header "9. Starting LLM Server (~40GB GPU)"
free_mem=$(check_gpu_memory)
if [ "$free_mem" -lt 42000 ]; then
    print_error "Insufficient GPU memory: ${free_mem}MB free, need ~42GB for LLM. Please free up memory or use sequential testing."
    print_warning "You can use ./test_services_sequential.sh to test services one at a time."
    exit 1
fi

# Determine which LLM image to use
if docker images | grep -q "rag-llm-gptoss:latest"; then
    LLM_IMAGE="rag-llm-gptoss:latest"
    print_status "Using GPT-OSS LLM model"
elif docker images | grep -q "rag-llm-small:latest"; then
    LLM_IMAGE="rag-llm-small:latest" 
    print_status "Using Small LLM model"
else
    print_error "No LLM image found. Please build or import LLM images first."
    exit 1
fi

docker run -d \
    --name rag-llm-server \
    --network "$NETWORK_NAME" \
    --gpus all \
    --shm-size=16g \
    --restart unless-stopped \
    -p 8003:8000 \
    -e CUDA_VISIBLE_DEVICES=0 \
    -e TENSOR_PARALLEL=1 \
    -e GPU_MEMORY=0.5 \
    "$LLM_IMAGE"

if wait_for_health "LLM Server" "http://localhost:8003/health" $MAX_WAIT_TIME; then
    check_gpu_memory >/dev/null
    echo ""
else
    print_error "LLM Server failed to start. This is expected if GPU memory is insufficient."
    print_warning "Consider using sequential testing: ./test_services_sequential.sh"
fi

# Service 6: Frontend (<1GB expected)
print_header "10. Starting Frontend (~100MB RAM)"
docker run -d \
    --name rag-frontend \
    --network "$NETWORK_NAME" \
    --restart unless-stopped \
    -p 3000:3000 \
    rag-frontend:latest

if wait_for_health "Frontend" "http://localhost:3000/frontend-health" $MAX_WAIT_TIME; then
    print_status "Frontend running on CPU as expected"
    echo ""
else
    print_error "Frontend failed to start. Aborting deployment."
    exit 1
fi

# Final status
print_header "11. Final System Status"
echo ""
echo "=========================================="
echo "🎉 RAG System Sequential Deployment Complete!"
echo "=========================================="
echo ""

print_status "Services running:"
echo "• Frontend:      http://localhost:3000"
echo "• API:           http://localhost:8080"
echo "• Embedding:     http://localhost:8001"
echo "• DotsOCR:       http://localhost:8002" 
echo "• LLM:           http://localhost:8003"
echo "• Whisper:       http://localhost:8004"
echo ""

print_status "Final GPU Memory Usage:"
check_gpu_memory >/dev/null

print_status "Next steps:"
echo "• Test the system: ./validate_offline_deployment.sh"
echo "• For GPU-constrained testing: ./test_services_sequential.sh"
echo "• Monitor logs: docker logs <service-name>"
echo ""

# Create monitoring script
cat > monitor_gpu.sh << 'EOF'
#!/bin/bash
echo "=== RAG System GPU Memory Monitor ==="
while true; do
    echo "$(date): $(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits)"
    sleep 30
done
EOF
chmod +x monitor_gpu.sh

print_status "GPU monitoring script created: ./monitor_gpu.sh"
print_status "Deployment complete!"