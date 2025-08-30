#!/bin/bash

set -e

echo "=========================================="
echo "RAG System TEST Deployment (No GPU Required)"
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
NETWORK_NAME="rag-test-network"
TEST_MODE="${1:-mock}"  # 'mock' or 'cpu'

print_header "Test Deployment Mode: $TEST_MODE"

# Check Docker
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

# Create network
print_header "1. Setting up test network..."
if ! docker network ls | grep -q "$NETWORK_NAME"; then
    docker network create "$NETWORK_NAME"
    print_status "Created test network: $NETWORK_NAME"
else
    print_status "Test network already exists"
fi

# Clean up existing test containers
print_header "2. Cleaning up existing test containers..."
TEST_CONTAINERS=(
    "rag-test-llm"
    "rag-test-embedding" 
    "rag-test-ocr"
    "rag-test-api"
    "rag-test-frontend"
)

for container in "${TEST_CONTAINERS[@]}"; do
    if docker ps -a | grep -q "$container"; then
        docker stop "$container" 2>/dev/null || true
        docker rm "$container" 2>/dev/null || true
        print_status "Removed $container"
    fi
done

# Build and run services based on mode
print_header "3. Starting test services..."

if [[ "$TEST_MODE" == "mock" ]]; then
    print_status "Using MOCK services (no GPU/models required)"
    
    # Build mock services
    print_status "Building mock LLM service..."
    docker build -f Dockerfile.mock-llm -t rag-mock-llm:test .
    
    print_status "Building mock OCR service..."
    docker build -f Dockerfile.mock-ocr -t rag-mock-ocr:test .
    
    # Run mock LLM
    docker run -d \
        --name rag-test-llm \
        --network "$NETWORK_NAME" \
        -p 8003:8000 \
        rag-mock-llm:test
    print_status "✓ Mock LLM started on port 8003"
    
    # Run mock Embedding (same as LLM for simplicity)
    docker run -d \
        --name rag-test-embedding \
        --network "$NETWORK_NAME" \
        -p 8001:8000 \
        rag-mock-llm:test
    print_status "✓ Mock Embedding started on port 8001"
    
    # Run mock OCR
    docker run -d \
        --name rag-test-ocr \
        --network "$NETWORK_NAME" \
        -p 8002:8000 \
        rag-mock-ocr:test
    print_status "✓ Mock OCR started on port 8002"
    
elif [[ "$TEST_MODE" == "cpu" ]]; then
    print_status "Using CPU-only mode with tiny models"
    print_warning "This mode requires pre-built CPU images"
    
    # You would need CPU-compatible versions of your images
    # For now, we'll show the structure
    
    print_warning "CPU mode requires special CPU-only Docker images"
    print_warning "Build them with CPU-only base images and tiny models"
    
    # Example for CPU-only deployment
    # docker run -d \
    #     --name rag-test-llm \
    #     --network "$NETWORK_NAME" \
    #     -p 8003:8000 \
    #     -e CUDA_VISIBLE_DEVICES="" \
    #     rag-llm-cpu:test
    
    print_error "CPU-only images not yet built. Use 'mock' mode instead."
    exit 1
fi

# Wait for services to start
print_status "Waiting for services to initialize..."
sleep 5

# Start API (always use real API, just with mock backends)
print_status "Starting API service..."
if docker images | grep -q "rag-api:latest"; then
    # Create test config
    mkdir -p test-config test-data/{input,working,logs}
    
    # Create test config file
    cat > test-config/config.yaml << EOF
# Test Configuration
VLLM:
    api_key: 0
    llm:
        model: "mock-model"
        base_url: "http://rag-test-llm:8000/v1"
    embedding:
        model: "mock-embedding"
        base_url: "http://rag-test-embedding:8000/v1"

dots_ocr:
  ip: "rag-test-ocr"
  port: 8000
  model_name: "mock-ocr"

model_params:
  openai_embedding_dim: 768
  glm_embedding_dim: 768
  vllm_embedding_dim: 768
  max_token_size: 8192

hirag:
  working_dir: "/app/data/working"
  enable_llm_cache: false
  enable_hierarchical_mode: true
  embedding_batch_num: 6
  embedding_func_max_async: 8
  enable_naive_rag: true
EOF
    
    docker run -d \
        --name rag-test-api \
        --network "$NETWORK_NAME" \
        -p 8080:8080 \
        -v "$(pwd)/test-config/config.yaml:/app/HiRAG/config.yaml:ro" \
        -v "$(pwd)/test-data/input:/app/data/input" \
        -v "$(pwd)/test-data/working:/app/data/working" \
        -v "$(pwd)/test-data/logs:/app/data/logs" \
        rag-api:latest
    
    print_status "✓ API started on port 8080"
else
    print_warning "API image not found. Build it first with ../build_all_offline.sh"
fi

# Start Frontend
print_status "Starting Frontend service..."
if docker images | grep -q "rag-frontend:latest"; then
    docker run -d \
        --name rag-test-frontend \
        --network "$NETWORK_NAME" \
        -p 3000:3000 \
        -e VITE_API_URL="" \
        --add-host "rag-api:host-gateway" \
        rag-frontend:latest
    
    print_status "✓ Frontend started on port 3000"
else
    print_warning "Frontend image not found. Build it first with ../build_all_offline.sh"
fi

# Test services
print_header "4. Testing services..."

# Function to test endpoint
test_endpoint() {
    local name="$1"
    local url="$2"
    
    if curl -s -f "$url" > /dev/null 2>&1; then
        print_status "✓ $name is responding"
        return 0
    else
        print_error "✗ $name is not responding"
        return 1
    fi
}

sleep 3

# Test each service
test_endpoint "Mock LLM" "http://localhost:8003/health"
test_endpoint "Mock Embedding" "http://localhost:8001/health"
test_endpoint "Mock OCR" "http://localhost:8002/health"
test_endpoint "API" "http://localhost:8080/health"
test_endpoint "Frontend" "http://localhost:3000/"

# Summary
print_header "5. Test Deployment Summary"
echo "=========================================="
print_status "Test environment is ready!"
echo "=========================================="
print_status "Services:"
print_status "  • Frontend:   http://localhost:3000"
print_status "  • API:        http://localhost:8080"
print_status "  • Mock LLM:   http://localhost:8003"
print_status "  • Mock Embed: http://localhost:8001"
print_status "  • Mock OCR:   http://localhost:8002"
print_status ""
print_status "Test the system:"
print_status "1. Open http://localhost:3000 in your browser"
print_status "2. Try the chat feature (will use mock responses)"
print_status "3. Try file search (will use mock embeddings)"
print_status ""
print_status "Monitor logs:"
print_status "  docker logs -f rag-test-api"
print_status "  docker logs -f rag-test-llm"
print_status ""
print_status "Stop test environment:"
print_status "  ./stop_test_environment.sh"