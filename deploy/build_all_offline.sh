#!/bin/bash

set -e  # Exit on any error

echo "=========================================="
echo "Building ALL RAG system images for offline deployment"
echo "This will pre-download all models and dependencies"
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

# Change to parent directory for correct build context
cd "$PARENT_DIR"

print_status "Working directory: $(pwd)"

# Build order: dependencies first, then services that depend on them
BUILD_SERVICES=(
    "dots-ocr:deploy/Dockerfile.dots-ocr:rag-dots-ocr"
    "embedding:deploy/Dockerfile.embedding:rag-embedding-server" 
    "llm-small:deploy/Dockerfile.llm-small:rag-llm-small"
    "llm-gptoss:deploy/Dockerfile.llm:rag-llm-gptoss"
    "api:Dockerfile:rag-api"
    "frontend:deploy/Dockerfile.frontend:rag-frontend"
)

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
print_status "All services built successfully!"
print_status "=========================================="

# Show final images
print_status "Built images:"
docker images | grep -E "(rag-|REPOSITORY)" | head -20

print_status ""
print_status "Next steps:"
print_status "1. Run './export_for_offline.sh' to create tar files for transfer"
print_status "2. Copy the export directory to your target system"
print_status "3. Run './import_offline.sh' on the target system"
print_status "4. Run './deploy_complete.sh' to start all services"

echo ""
print_status "Build complete! All models are pre-downloaded and ready for offline deployment."