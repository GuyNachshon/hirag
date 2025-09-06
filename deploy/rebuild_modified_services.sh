#!/bin/bash

set -e

echo "=========================================="
echo "Selective Rebuild: Modified Services Only"
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
    echo -e "${BLUE}[BUILD]${NC} $1"
}

# Check prerequisites
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

print_status "Docker is running"
print_status "Starting selective rebuild of modified services..."
echo ""

# Service 1: TGI Embedding Server (NEW - CMD syntax fix)
print_header "1. Building TGI-Optimized Embedding Server"
print_status "Fixed: CMD syntax for TGI compatibility"
if docker build -f Dockerfile.embedding-tgi-optimized -t rag-embedding-server:tgi-optimized .; then
    print_status "✓ rag-embedding-server:tgi-optimized built successfully"
else
    print_error "✗ Failed to build TGI embedding server"
    exit 1
fi
echo ""

# Service 2: Whisper (MODIFIED - FastAPI lifespan + accelerate)  
print_header "2. Building Fixed Whisper Service"
print_status "Fixed: FastAPI lifespan, added accelerate + safetensors"
if docker build -f deploy/Dockerfile.whisper -t rag-whisper:latest .; then
    print_status "✓ rag-whisper:latest built successfully"
else
    print_error "✗ Failed to build Whisper service"
    exit 1
fi
echo ""

# Service 3: DotsOCR (MODIFIED - GPU memory reduced)
print_header "3. Building Memory-Optimized DotsOCR"
print_status "Fixed: GPU memory utilization 0.95 → 0.4, added max-model-len"
if docker build -f deploy/Dockerfile.dots-ocr -t rag-dots-ocr:latest .; then
    print_status "✓ rag-dots-ocr:latest built successfully"
else
    print_error "✗ Failed to build DotsOCR service"
    exit 1
fi
echo ""

# Service 4: GPT-OSS LLM (MODIFIED - offline environment)
print_header "4. Building Offline-Enabled GPT-OSS LLM"
print_status "Fixed: Added HF_HUB_OFFLINE, TRANSFORMERS_OFFLINE environment variables"
if docker build -f deploy/Dockerfile.llm -t rag-llm-gptoss:latest .; then
    print_status "✓ rag-llm-gptoss:latest built successfully"
else
    print_error "✗ Failed to build GPT-OSS LLM"
    exit 1
fi
echo ""

# Verify images exist
print_header "5. Verifying Built Images"
BUILT_IMAGES=(
    "rag-embedding-server:tgi-optimized"
    "rag-whisper:latest"
    "rag-dots-ocr:latest" 
    "rag-llm-gptoss:latest"
)

for image in "${BUILT_IMAGES[@]}"; do
    if docker images | grep -q "$image"; then
        local size=$(docker images "$image" --format "table {{.Size}}" | tail -n +2)
        print_status "✓ $image ($size)"
    else
        print_error "✗ $image not found after build"
    fi
done

echo ""
echo "=========================================="
echo "🎉 Selective Rebuild Complete!"
echo "=========================================="
echo ""
print_status "Modified services rebuilt:"
echo "• Embedding: TGI-optimized with fixed CMD syntax"
echo "• Whisper: FastAPI lifespan + accelerate dependency"
echo "• DotsOCR: Memory-optimized (40% GPU utilization)"
echo "• GPT-OSS: Offline-enabled with cached models"
echo ""
print_status "Unchanged services (reusing existing):"
echo "• Frontend: rag-frontend:latest"
echo "• API: rag-api:optimized"
echo ""
print_status "Next steps:"
echo "• Deploy: ./deploy/deploy_sequential_h100.sh"
echo "• Validate: ./deploy/validate_h100_deployment.sh"
echo "• Alternative: Use runtime overrides: ./deploy/create_runtime_fixes.sh"