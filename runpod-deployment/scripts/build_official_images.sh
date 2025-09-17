#!/bin/bash

# Build Docker images using official repository bases
# This script builds DotsOCR and Whisper services using their official implementations

set -e

echo "=== Building Official-Based Docker Images ==="
echo ""

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Build DotsOCR service with official vLLM base
build_dotsocr() {
    print_status "Building DotsOCR service with official repository base..."

    docker build \
        -f dockerfiles/Dockerfile.ocr-official \
        -t rag-dots-ocr-official:latest \
        --progress=plain \
        .

    if [ $? -eq 0 ]; then
        print_status "✓ DotsOCR official image built successfully"
    else
        print_error "✗ Failed to build DotsOCR official image"
        exit 1
    fi
}

# Build Whisper service with Ivrit-AI base
build_whisper() {
    print_status "Building Whisper service with Ivrit-AI base..."

    docker build \
        -f dockerfiles/Dockerfile.whisper-official \
        -t rag-whisper-official:latest \
        --progress=plain \
        .

    if [ $? -eq 0 ]; then
        print_status "✓ Whisper official image built successfully"
    else
        print_error "✗ Failed to build Whisper official image"
        exit 1
    fi
}

# Main build process
main() {
    print_status "Starting build process for official-based images..."

    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi

    # Build images
    echo ""
    print_status "Building images in parallel for faster completion..."

    # Build DotsOCR in background
    print_status "Starting DotsOCR build..."
    build_dotsocr &
    DOTSOCR_PID=$!

    # Build Whisper in background
    print_status "Starting Whisper build..."
    build_whisper &
    WHISPER_PID=$!

    # Wait for both builds to complete
    wait $DOTSOCR_PID
    DOTSOCR_EXIT_CODE=$?

    wait $WHISPER_PID
    WHISPER_EXIT_CODE=$?

    # Check results
    if [ $DOTSOCR_EXIT_CODE -eq 0 ] && [ $WHISPER_EXIT_CODE -eq 0 ]; then
        echo ""
        print_status "=== BUILD COMPLETED SUCCESSFULLY ==="
        print_status "Images built:"
        print_status "  - rag-dots-ocr-official:latest"
        print_status "  - rag-whisper-official:latest"
        echo ""
        print_status "Next steps:"
        print_status "  1. Test the images: ./scripts/test_official_images.sh"
        print_status "  2. Deploy services: ./scripts/deploy_h100_manual.sh"
        echo ""
    else
        print_error "=== BUILD FAILED ==="
        if [ $DOTSOCR_EXIT_CODE -ne 0 ]; then
            print_error "DotsOCR build failed"
        fi
        if [ $WHISPER_EXIT_CODE -ne 0 ]; then
            print_error "Whisper build failed"
        fi
        exit 1
    fi
}

# Handle cleanup on exit
cleanup() {
    print_warning "Build interrupted. Cleaning up..."
    # Kill background processes if they're still running
    kill $DOTSOCR_PID 2>/dev/null || true
    kill $WHISPER_PID 2>/dev/null || true
}

trap cleanup INT TERM

# Parse command line arguments
PARALLEL=true
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --sequential)
            PARALLEL=false
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --sequential    Build images one at a time instead of parallel"
            echo "  --verbose       Enable verbose output"
            echo "  --help          Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Build all images in parallel"
            echo "  $0 --sequential       # Build images one at a time"
            echo "  $0 --verbose          # Build with verbose output"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main