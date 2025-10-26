#!/bin/bash

# Build API Docker image with transcription chat support
# This script builds the API service with the new TranscriptionChatService and database migrations

set -e

echo "=== Building RAG API with Transcription Chat Support ==="
echo ""

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."

    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi

    # Check if source-code directory exists
    if [ ! -d "source-code" ]; then
        print_error "source-code directory not found. Are you in the right directory?"
        exit 1
    fi

    # Check if migration script exists
    if [ ! -f "source-code/migrate_add_embeddings.py" ]; then
        print_error "Migration script not found at source-code/migrate_add_embeddings.py"
        print_error "Please ensure the migration script is in place."
        exit 1
    fi

    # Check if API Dockerfile exists
    if [ ! -f "dockerfiles/Dockerfile.api" ]; then
        print_error "API Dockerfile not found at dockerfiles/Dockerfile.api"
        exit 1
    fi

    print_status "✓ All prerequisites satisfied"
}

# Build API service
build_api() {
    print_status "Building API service with transcription chat..."

    docker build \
        -f dockerfiles/Dockerfile.api \
        -t rag-api:latest \
        --progress=plain \
        .

    if [ $? -eq 0 ]; then
        print_status "✓ API image built successfully"
        return 0
    else
        print_error "✗ Failed to build API image"
        return 1
    fi
}

# Main build process
main() {
    print_status "Starting build process for RAG API..."
    echo ""

    # Check prerequisites
    check_prerequisites
    echo ""

    # Build API
    if build_api; then
        echo ""
        print_status "=== BUILD COMPLETED SUCCESSFULLY ==="
        print_status "Image built: rag-api:latest"
        echo ""
        print_status "What's new in this build:"
        print_status "  ✓ TranscriptionChatService with adaptive context strategy"
        print_status "  ✓ Eager background embedding generation"
        print_status "  ✓ Database migration for embedding columns"
        print_status "  ✓ New /api/transcription/chat/* endpoints"
        echo ""
        print_status "Next steps:"
        print_status "  1. Test the API: docker run -p 8080:8080 rag-api:latest"
        print_status "  2. Or deploy full stack: cd configs && docker-compose up -d"
        print_status "  3. Check health: curl http://localhost:8080/health"
        print_status "  4. Check chat health: curl http://localhost:8080/api/transcription/chat/health"
        echo ""
    else
        print_error "=== BUILD FAILED ==="
        exit 1
    fi
}

# Handle cleanup on exit
cleanup() {
    print_warning "Build interrupted. Cleaning up..."
}

trap cleanup INT TERM

# Parse command line arguments
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --verbose       Enable verbose output"
            echo "  --help          Show this help message"
            echo ""
            echo "What this script does:"
            echo "  - Builds the RAG API Docker image with transcription chat support"
            echo "  - Includes database migration for embedding columns"
            echo "  - Enables adaptive context strategy for chat"
            echo "  - Supports eager background embedding generation"
            echo ""
            echo "Examples:"
            echo "  $0                    # Build API image"
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
