#!/bin/bash

set -e  # Exit on any error

echo "=========================================="
echo "Building ESSENTIAL RAG system images for offline deployment"
echo "This will skip the large GPT-OSS model to save disk space"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

print_status "Docker is running. Starting build process..."

# Get the script directory and parent directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

print_status "Script directory: $SCRIPT_DIR"
print_status "Parent directory: $PARENT_DIR"

# Change to parent directory for correct build context
cd "$PARENT_DIR"

print_status "Changed to working directory: $(pwd)"
print_status "Listing directory contents:"
ls -la deploy/ | head -5

# Essential services only (excluding large GPT-OSS model)
BUILD_SERVICES=(
    "dots-ocr:deploy/Dockerfile.dots-ocr:rag-dots-ocr"
    "embedding:deploy/Dockerfile.embedding:rag-embedding-server" 
    "llm-small:deploy/Dockerfile.llm-small:rag-llm-small"
    "whisper:deploy/Dockerfile.whisper:rag-whisper"
    "api:Dockerfile:rag-api"
    "frontend:deploy/Dockerfile.frontend:rag-frontend"
)

print_warning "Skipping llm-gptoss due to disk space constraints (40GB+ model)"
print_status "Building essential services only..."

# Build each service
for service_info in "${BUILD_SERVICES[@]}"; do
    IFS=':' read -r service_name dockerfile image_name <<< "$service_info"
    
    print_status "Building $service_name service..."
    print_status "  Dockerfile: $dockerfile"
    print_status "  Image name: $image_name:latest"
    
    # Build with no cache to ensure fresh downloads
    if docker build --no-cache -f "$dockerfile" -t "$image_name:latest" .; then
        print_status "✓ Successfully built $service_name"
    else
        print_error "✗ Failed to build $service_name"
        exit 1
    fi
    
    echo ""
done

print_status "=========================================="
print_status "Essential services built successfully!"
print_status "=========================================="

# Show final images
print_status "Built images:"
docker images | grep -E "(rag-|REPOSITORY)" | head -20

print_status ""
print_warning "Note: GPT-OSS model was skipped to save disk space (~40GB)"
print_status "Essential RAG system is ready with:"
print_status "  • Small LLM (4B parameters) - Good for most tasks"
print_status "  • DotsOCR - Vision document processing"  
print_status "  • Embedding - Text embeddings"
print_status "  • Whisper - Hebrew transcription"
print_status "  • API + Frontend - Complete web interface"

print_status ""
print_status "Next steps:"
print_status "1. Run './create_deployment_package.sh --skip-build' to package these images"
print_status "2. Optionally add GPT-OSS later if more disk space is available"

echo ""
print_status "Essential build complete! Ready for deployment."