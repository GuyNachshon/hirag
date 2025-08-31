#!/bin/bash

set -e  # Exit on any error

echo "=========================================="
echo "Smart Build - RAG System Images"
echo "Only rebuilds if Dockerfile has changed"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_skip() {
    echo -e "${BLUE}[SKIP]${NC} $1"
}

# Function to calculate file hash
get_file_hash() {
    local file="$1"
    if [ -f "$file" ]; then
        # Use sha256sum for consistent hashing
        sha256sum "$file" | awk '{print $1}'
    else
        echo "FILE_NOT_FOUND"
    fi
}

# Function to get stored hash from Docker image label
get_image_hash() {
    local image="$1"
    # Check if image exists and get its dockerfile hash label
    if docker image inspect "$image" > /dev/null 2>&1; then
        docker image inspect "$image" --format='{{index .Config.Labels "dockerfile.hash"}}' 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Function to check if rebuild is needed
needs_rebuild() {
    local dockerfile="$1"
    local image_name="$2"
    local force_rebuild="${3:-false}"
    
    # Force rebuild if requested
    if [ "$force_rebuild" = "true" ]; then
        print_warning "Force rebuild requested for $image_name"
        return 0
    fi
    
    # Get current Dockerfile hash
    local current_hash=$(get_file_hash "$dockerfile")
    
    # Get hash from existing image
    local image_hash=$(get_image_hash "$image_name:latest")
    
    # Check if image exists
    if [ -z "$image_hash" ]; then
        print_status "Image $image_name doesn't exist, needs building"
        return 0
    fi
    
    # Compare hashes
    if [ "$current_hash" = "$image_hash" ]; then
        print_skip "Image $image_name is up-to-date (hash: ${current_hash:0:8}...)"
        return 1
    else
        print_status "Image $image_name needs rebuild (Dockerfile changed)"
        print_status "  Current hash: ${current_hash:0:8}..."
        print_status "  Image hash:   ${image_hash:0:8}..."
        return 0
    fi
}

# Function to build with hash label
build_with_hash() {
    local service_name="$1"
    local dockerfile="$2"
    local image_name="$3"
    local skip_gptoss="${4:-false}"
    
    # Skip GPT-OSS if requested
    if [ "$skip_gptoss" = "true" ] && [ "$service_name" = "llm-gptoss" ]; then
        print_warning "Skipping $service_name (--skip-gptoss flag)"
        return 0
    fi
    
    # Check if rebuild is needed
    if ! needs_rebuild "$dockerfile" "$image_name" "$FORCE_REBUILD"; then
        return 0
    fi
    
    # Calculate Dockerfile hash
    local dockerfile_hash=$(get_file_hash "$dockerfile")
    
    print_status "Building $service_name service..."
    print_status "  Dockerfile: $dockerfile"
    print_status "  Image name: $image_name:latest"
    print_status "  Hash: ${dockerfile_hash:0:8}..."
    
    # Build with hash label and cache if not forced
    local build_args=""
    if [ "$NO_CACHE" = "true" ]; then
        build_args="--no-cache"
    fi
    
    if docker build $build_args \
        --label "dockerfile.hash=$dockerfile_hash" \
        --label "build.date=$(date -Iseconds)" \
        --label "build.service=$service_name" \
        -f "$dockerfile" \
        -t "$image_name:latest" .; then
        print_status "✓ Successfully built $service_name"
        return 0
    else
        print_error "✗ Failed to build $service_name"
        return 1
    fi
}

# Parse command line arguments
FORCE_REBUILD=false
NO_CACHE=false
SKIP_GPTOSS=false
SHOW_STATUS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_REBUILD=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --skip-gptoss)
            SKIP_GPTOSS=true
            shift
            ;;
        --status)
            SHOW_STATUS=true
            shift
            ;;
        --help)
            cat << EOF
Usage: $0 [OPTIONS]

Smart build script that only rebuilds Docker images when Dockerfiles have changed.

OPTIONS:
    --force         Force rebuild all images regardless of changes
    --no-cache      Build without Docker cache (implies --force)
    --skip-gptoss   Skip building the large GPT-OSS model
    --status        Show current build status and exit
    --help          Show this help message

EXAMPLES:
    $0                    # Smart build - only changed images
    $0 --force            # Force rebuild all images
    $0 --skip-gptoss      # Build all except GPT-OSS
    $0 --status           # Check which images need rebuilding

The script tracks Dockerfile changes by storing SHA256 hashes as Docker labels.
Images are only rebuilt when their Dockerfile content changes.

EOF
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

# Get the script directory and parent directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Change to parent directory for correct build context
cd "$PARENT_DIR"

# Define all services
BUILD_SERVICES=(
    "dots-ocr:deploy/Dockerfile.dots-ocr:rag-dots-ocr"
    "embedding:deploy/Dockerfile.embedding:rag-embedding-server" 
    "llm-small:deploy/Dockerfile.llm-small:rag-llm-small"
    "llm-gptoss:deploy/Dockerfile.llm:rag-llm-gptoss"
    "whisper:deploy/Dockerfile.whisper:rag-whisper"
    "api:Dockerfile:rag-api"
    "frontend:deploy/Dockerfile.frontend:rag-frontend"
)

# If status only, show what needs rebuilding
if [ "$SHOW_STATUS" = "true" ]; then
    print_status "Checking build status..."
    echo ""
    
    needs_rebuild_count=0
    up_to_date_count=0
    
    for service_info in "${BUILD_SERVICES[@]}"; do
        IFS=':' read -r service_name dockerfile image_name <<< "$service_info"
        
        if [ "$SKIP_GPTOSS" = "true" ] && [ "$service_name" = "llm-gptoss" ]; then
            continue
        fi
        
        if needs_rebuild "$dockerfile" "$image_name" false > /dev/null 2>&1; then
            echo -e "${YELLOW}⚠${NC}  $service_name - needs rebuild"
            ((needs_rebuild_count++))
        else
            echo -e "${GREEN}✓${NC}  $service_name - up to date"
            ((up_to_date_count++))
        fi
    done
    
    echo ""
    print_status "Summary: $up_to_date_count up-to-date, $needs_rebuild_count need rebuilding"
    exit 0
fi

# Show build configuration
print_status "Build configuration:"
print_status "  Force rebuild: $FORCE_REBUILD"
print_status "  No cache: $NO_CACHE"
print_status "  Skip GPT-OSS: $SKIP_GPTOSS"
print_status "  Working directory: $(pwd)"
echo ""

# Track statistics
built_count=0
skipped_count=0
failed_count=0

# Build each service
for service_info in "${BUILD_SERVICES[@]}"; do
    IFS=':' read -r service_name dockerfile image_name <<< "$service_info"
    
    if build_with_hash "$service_name" "$dockerfile" "$image_name" "$SKIP_GPTOSS"; then
        if needs_rebuild "$dockerfile" "$image_name" "$FORCE_REBUILD" > /dev/null 2>&1; then
            ((built_count++))
        else
            ((skipped_count++))
        fi
    else
        ((failed_count++))
        if [ "$failed_count" -gt 0 ]; then
            print_error "Build failed. Stopping."
            exit 1
        fi
    fi
    
    echo ""
done

# Show summary
echo "=========================================="
if [ "$failed_count" -eq 0 ]; then
    print_status "Build completed successfully!"
else
    print_error "Build failed with $failed_count errors"
fi
echo "=========================================="

print_status "Summary:"
print_status "  • Built: $built_count images"
print_status "  • Skipped (up-to-date): $skipped_count images"
if [ "$failed_count" -gt 0 ]; then
    print_error "  • Failed: $failed_count images"
fi

# Show final images
echo ""
print_status "Current RAG images:"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" | grep -E "(REPOSITORY|rag-)" | head -20

echo ""
print_status "Tips:"
print_status "  • Use --status to check what needs rebuilding"
print_status "  • Use --force to rebuild everything"
print_status "  • Use --skip-gptoss to save disk space (~40GB)"
print_status "  • Images are automatically cached when unchanged"

# Save build manifest
MANIFEST_FILE="$SCRIPT_DIR/.build-manifest.json"
cat > "$MANIFEST_FILE" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "built": $built_count,
  "skipped": $skipped_count,
  "failed": $failed_count,
  "force_rebuild": $FORCE_REBUILD,
  "skip_gptoss": $SKIP_GPTOSS
}
EOF

print_status "Build manifest saved to $MANIFEST_FILE"