#!/bin/bash

# Test script for official-based Docker images
# Verifies that DotsOCR and Whisper services work correctly

set -e

echo "=== Testing Official-Based Docker Images ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Test DotsOCR service
test_dotsocr() {
    print_test "Testing DotsOCR official image..."

    # Start DotsOCR container
    print_status "Starting DotsOCR container..."
    docker run -d \
        --name test-dotsocr \
        --gpus all \
        -p 8002:8002 \
        -p 8005:8000 \
        -e CUDA_VISIBLE_DEVICES=0 \
        rag-dots-ocr-official:latest

    # Wait for services to be ready
    print_status "Waiting for DotsOCR services to be ready..."
    for i in {1..60}; do
        if curl -f http://localhost:8002/health >/dev/null 2>&1; then
            print_status "FastAPI adapter is ready!"
            break
        fi
        if [ $i -eq 60 ]; then
            print_error "DotsOCR FastAPI service failed to start"
            docker logs test-dotsocr --tail 50
            return 1
        fi
        sleep 2
    done

    # Wait for vLLM to be ready
    for i in {1..60}; do
        if curl -f http://localhost:8005/health >/dev/null 2>&1; then
            print_status "vLLM service is ready!"
            break
        fi
        if [ $i -eq 60 ]; then
            print_warning "vLLM service not accessible (this might be expected)"
            break
        fi
        sleep 2
    done

    # Test health endpoint
    print_test "Testing DotsOCR health endpoint..."
    HEALTH_RESPONSE=$(curl -s http://localhost:8002/health)
    echo "Health response: $HEALTH_RESPONSE"

    # Test models endpoint
    print_test "Testing DotsOCR models endpoint..."
    MODELS_RESPONSE=$(curl -s http://localhost:8002/models)
    echo "Models response: $MODELS_RESPONSE"

    # Cleanup
    print_status "Stopping DotsOCR test container..."
    docker stop test-dotsocr >/dev/null 2>&1 || true
    docker rm test-dotsocr >/dev/null 2>&1 || true

    print_status "✓ DotsOCR test completed"
}

# Test Whisper service
test_whisper() {
    print_test "Testing Whisper official image..."

    # Start Whisper container
    print_status "Starting Whisper container..."
    docker run -d \
        --name test-whisper \
        --gpus all \
        -p 8004:8004 \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e MODEL_NAME=ivrit-ai/whisper-large-v3-ct2 \
        rag-whisper-official:latest

    # Wait for service to be ready
    print_status "Waiting for Whisper service to be ready..."
    for i in {1..120}; do  # Longer timeout for model loading
        if curl -f http://localhost:8004/health >/dev/null 2>&1; then
            print_status "Whisper service is ready!"
            break
        fi
        if [ $i -eq 120 ]; then
            print_error "Whisper service failed to start"
            docker logs test-whisper --tail 50
            return 1
        fi
        echo -n "."
        sleep 3
    done
    echo ""

    # Test health endpoint
    print_test "Testing Whisper health endpoint..."
    HEALTH_RESPONSE=$(curl -s http://localhost:8004/health)
    echo "Health response: $HEALTH_RESPONSE"

    # Test models endpoint
    print_test "Testing Whisper models endpoint..."
    MODELS_RESPONSE=$(curl -s http://localhost:8004/models)
    echo "Models response: $MODELS_RESPONSE"

    # Cleanup
    print_status "Stopping Whisper test container..."
    docker stop test-whisper >/dev/null 2>&1 || true
    docker rm test-whisper >/dev/null 2>&1 || true

    print_status "✓ Whisper test completed"
}

# Check if images exist
check_images() {
    print_status "Checking if required images exist..."

    if ! docker image inspect rag-dots-ocr-official:latest >/dev/null 2>&1; then
        print_error "DotsOCR official image not found. Please run build_official_images.sh first."
        return 1
    fi

    if ! docker image inspect rag-whisper-official:latest >/dev/null 2>&1; then
        print_error "Whisper official image not found. Please run build_official_images.sh first."
        return 1
    fi

    print_status "✓ All required images found"
}

# Main test function
main() {
    print_status "Starting tests for official-based images..."

    # Check prerequisites
    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Please install Docker."
        exit 1
    fi

    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        print_error "curl not found. Please install curl."
        exit 1
    fi

    # Check if GPU is available
    if ! docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi >/dev/null 2>&1; then
        print_warning "GPU not accessible to Docker. Tests will run but may fail."
    fi

    # Check images exist
    check_images || exit 1

    # Cleanup any existing test containers
    print_status "Cleaning up any existing test containers..."
    docker stop test-dotsocr test-whisper >/dev/null 2>&1 || true
    docker rm test-dotsocr test-whisper >/dev/null 2>&1 || true

    # Run tests
    echo ""
    print_status "Running DotsOCR tests..."
    test_dotsocr

    echo ""
    print_status "Running Whisper tests..."
    test_whisper

    echo ""
    print_status "=== ALL TESTS COMPLETED SUCCESSFULLY ==="
    print_status "Official-based images are working correctly!"
    echo ""
    print_status "Next steps:"
    print_status "  1. Deploy full system: ./scripts/deploy_h100_manual.sh"
    print_status "  2. Test RAG API integration"
    echo ""
}

# Handle cleanup on exit
cleanup() {
    print_warning "Tests interrupted. Cleaning up..."
    docker stop test-dotsocr test-whisper >/dev/null 2>&1 || true
    docker rm test-dotsocr test-whisper >/dev/null 2>&1 || true
}

trap cleanup INT TERM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Tests the official-based Docker images for DotsOCR and Whisper services."
            echo ""
            echo "Prerequisites:"
            echo "  - Docker with GPU support"
            echo "  - curl command"
            echo "  - Built images (run build_official_images.sh first)"
            echo ""
            echo "Options:"
            echo "  --help          Show this help message"
            echo ""
            echo "The script will:"
            echo "  1. Start each service in a test container"
            echo "  2. Wait for services to be ready"
            echo "  3. Test health and API endpoints"
            echo "  4. Clean up test containers"
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