#!/bin/bash

set -e  # Exit on any error

echo "=========================================="
echo "Complete RAG System Offline Deployment"
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
CONFIG_FILE="./config/config.yaml"
DATA_DIR="./data"

# Check prerequisites
print_header "1. Checking prerequisites..."

if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

print_status "✓ Docker is running"

# Check required images exist
REQUIRED_IMAGES=(
    "rag-dots-ocr:latest"
    "rag-embedding-server:latest"
    "rag-api:latest"
)

# Check for either small or gptoss model
if docker images | grep -q "rag-llm-small:latest"; then
    REQUIRED_IMAGES+=("rag-llm-small:latest")
    LLM_IMAGE="rag-llm-small:latest"
    print_status "✓ Using small LLM model"
elif docker images | grep -q "rag-llm-gptoss:latest"; then
    REQUIRED_IMAGES+=("rag-llm-gptoss:latest")
    LLM_IMAGE="rag-llm-gptoss:latest"
    print_status "✓ Using gpt-oss LLM model"
else
    print_error "No LLM image found. Please build or import images first."
    exit 1
fi

for image in "${REQUIRED_IMAGES[@]}"; do
    if docker images | grep -q "$image"; then
        print_status "✓ $image found"
    else
        print_error "✗ $image not found. Please build or import images first."
        exit 1
    fi
done

# Setup network
print_header "2. Setting up Docker network..."
./setup_network.sh

# Create data directories if they don't exist
print_header "3. Setting up data directories..."
mkdir -p "$DATA_DIR"/{input,working,logs,cache}
print_status "✓ Data directories created"

# Check configuration
print_header "4. Checking configuration..."
if [[ ! -f "$CONFIG_FILE" ]]; then
    if [[ -f "./config/config.yaml.template" ]]; then
        print_warning "config.yaml not found. Copying from template..."
        cp "./config/config.yaml.template" "$CONFIG_FILE"
        print_status "✓ Created config.yaml from template"
    else
        print_error "No configuration file found. Please create config.yaml"
        exit 1
    fi
else
    print_status "✓ Configuration file found"
fi

# Stop any existing containers
print_header "5. Cleaning up existing containers..."
CONTAINERS=("rag-dots-ocr" "rag-embedding-server" "rag-llm-server" "rag-api")

for container in "${CONTAINERS[@]}"; do
    if docker ps -a | grep -q "$container"; then
        print_status "Stopping and removing existing $container..."
        docker stop "$container" 2>/dev/null || true
        docker rm "$container" 2>/dev/null || true
    fi
done

# Start services in order
print_header "6. Starting services..."

# Start DotsOCR
print_status "Starting DotsOCR service..."
docker run -d \
    --name rag-dots-ocr \
    --network "$NETWORK_NAME" \
    --gpus all \
    -p 8002:8000 \
    rag-dots-ocr:latest

print_status "✓ DotsOCR started"

# Start Embedding server
print_status "Starting Embedding service..."
docker run -d \
    --name rag-embedding-server \
    --network "$NETWORK_NAME" \
    --gpus all \
    -p 8001:8000 \
    rag-embedding-server:latest

print_status "✓ Embedding server started"

# Start LLM server
print_status "Starting LLM service..."
docker run -d \
    --name rag-llm-server \
    --network "$NETWORK_NAME" \
    --gpus all \
    -p 8003:8000 \
    "$LLM_IMAGE"

print_status "✓ LLM server started"

# Wait a bit for services to initialize
print_status "Waiting 10 seconds for services to initialize..."
sleep 10

# Start API server
print_status "Starting API service..."
docker run -d \
    --name rag-api \
    --network "$NETWORK_NAME" \
    -p 8080:8080 \
    -v "$(pwd)/config/config.yaml:/app/HiRAG/config.yaml:ro" \
    -v "$(pwd)/data/input:/app/data/input" \
    -v "$(pwd)/data/working:/app/data/working" \
    -v "$(pwd)/data/logs:/app/data/logs" \
    rag-api:latest

print_status "✓ API server started"

print_header "7. Deployment Summary"
print_status "=========================================="
print_status "RAG System Successfully Deployed!"
print_status "=========================================="
print_status "Services running:"
print_status "  • DotsOCR:    http://localhost:8002"
print_status "  • Embedding:  http://localhost:8001"
print_status "  • LLM:        http://localhost:8003"
print_status "  • API:        http://localhost:8080"
print_status ""
print_status "Data directories:"
print_status "  • Input:      $(pwd)/data/input"
print_status "  • Working:    $(pwd)/data/working"
print_status "  • Logs:       $(pwd)/data/logs"
print_status "  • Cache:      $(pwd)/data/cache"
print_status ""
print_status "Next steps:"
print_status "1. Add documents to: $(pwd)/data/input/"
print_status "2. Test API: curl http://localhost:8080/health"
print_status "3. Monitor logs: docker logs -f rag-api"
print_status ""
print_status "Use './validate_offline_deployment.sh' to verify all services"