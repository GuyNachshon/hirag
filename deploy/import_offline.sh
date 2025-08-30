#!/bin/bash

set -e  # Exit on any error

echo "=========================================="
echo "Importing RAG system Docker images"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
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

# Check if we're in the export directory or if tar files exist
if [[ ! -f "rag-dots-ocr_latest.tar" ]]; then
    print_error "RAG system export files not found in current directory"
    print_error "Please ensure you're in the rag-system-export directory"
    print_error "Or copy the .tar files to the current directory"
    exit 1
fi

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

print_status "Docker is running. Starting import process..."

# Import all tar files
TAR_FILES=(
    "rag-dots-ocr_latest.tar"
    "rag-embedding-server_latest.tar"
    "rag-llm-small_latest.tar"
    "rag-llm-gptoss_latest.tar"
    "rag-api_latest.tar"
)

print_status "Found export files:"
for tar_file in "${TAR_FILES[@]}"; do
    if [[ -f "$tar_file" ]]; then
        size=$(du -h "$tar_file" | cut -f1)
        print_status "  ✓ $tar_file ($size)"
    else
        print_warning "  ✗ $tar_file (missing)"
    fi
done

echo ""

# Import each file
for tar_file in "${TAR_FILES[@]}"; do
    if [[ -f "$tar_file" ]]; then
        print_status "Importing $tar_file..."
        if docker load -i "$tar_file"; then
            print_status "✓ Successfully imported $tar_file"
        else
            print_error "✗ Failed to import $tar_file"
            exit 1
        fi
    else
        print_warning "Skipping missing file: $tar_file"
    fi
done

print_status "=========================================="
print_status "Import complete!"
print_status "=========================================="

# Verify imported images
print_status "Imported RAG system images:"
docker images | grep -E "rag-|REPOSITORY" | head -10

print_status ""
print_status "Next steps:"
print_status "1. Run './setup_network.sh' to create Docker network"
print_status "2. Copy configuration files to deploy/config/"
print_status "3. Run './deploy_complete.sh' to start all services"
print_status ""
print_status "All images are now ready for offline deployment!"