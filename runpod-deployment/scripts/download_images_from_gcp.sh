#!/bin/bash

# Local Download Script with Caffeinate
# Downloads Docker images from GCP bucket and loads them locally
# Uses caffeinate to prevent system sleep during download

set -e

# Configuration
BUCKET_NAME="${GCP_BUCKET:-hirag-docker-images}"
DOWNLOAD_DIR="./docker-images"
TIMESTAMP="${1:-}" # Optional timestamp argument

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're on macOS (for caffeinate)
if [[ "$OSTYPE" == "darwin"* ]]; then
    CAFFEINATE_CMD="caffeinate -i"
    echo_info "macOS detected - using caffeinate to prevent sleep"
else
    CAFFEINATE_CMD=""
    echo_warning "Not on macOS - caffeinate not available"
fi

# Function to show usage
show_usage() {
    echo "Usage: $0 [TIMESTAMP]"
    echo ""
    echo "Downloads Docker images from GCP bucket and loads them into Docker"
    echo ""
    echo "Arguments:"
    echo "  TIMESTAMP    Optional timestamp to download specific version"
    echo "               If not provided, will list available versions"
    echo ""
    echo "Environment Variables:"
    echo "  GCP_BUCKET   GCP bucket name (default: hirag-docker-images)"
    echo ""
    echo "Examples:"
    echo "  $0                           # List available versions"
    echo "  $0 20240117_143052          # Download specific timestamp"
    echo ""
}

# Check if gcloud is installed and authenticated
check_gcloud() {
    if ! command -v gcloud &> /dev/null; then
        echo_error "gcloud CLI not found. Please install Google Cloud SDK"
        echo_info "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | grep -q .; then
        echo_error "No active gcloud authentication found"
        echo_info "Please run: gcloud auth login"
        exit 1
    fi

    # Check if bucket exists
    if ! gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        echo_error "Bucket gs://${BUCKET_NAME} not found or not accessible"
        exit 1
    fi
}

# List available versions in bucket
list_available_versions() {
    echo_info "Available versions in gs://${BUCKET_NAME}:"
    echo ""

    # Get all manifest files to show available timestamps
    local manifests=$(gsutil ls "gs://${BUCKET_NAME}/manifest_*.json" 2>/dev/null || true)

    if [ -z "$manifests" ]; then
        echo_warning "No manifest files found in bucket"
        echo_info "Listing all files:"
        gsutil ls -lh "gs://${BUCKET_NAME}/"
        return
    fi

    echo "Available timestamps:"
    for manifest in $manifests; do
        local timestamp=$(basename "$manifest" | sed 's/manifest_\(.*\)\.json/\1/')
        echo "  - $timestamp"

        # Download and show manifest content
        local temp_manifest="/tmp/manifest_${timestamp}.json"
        gsutil cp "$manifest" "$temp_manifest" &>/dev/null

        if [ -f "$temp_manifest" ]; then
            local upload_date=$(jq -r '.upload_date // "Unknown"' "$temp_manifest" 2>/dev/null || echo "Unknown")
            local image_count=$(jq '.images | length' "$temp_manifest" 2>/dev/null || echo "Unknown")
            echo "    Upload Date: $upload_date"
            echo "    Images: $image_count"

            # Show image sizes
            if command -v jq &> /dev/null; then
                echo "    Total Size: $(jq -r '.images | map(.size_bytes) | add | . / 1024 / 1024 / 1024 | floor' "$temp_manifest" 2>/dev/null || echo "Unknown")GB"
            fi

            rm -f "$temp_manifest"
            echo ""
        fi
    done
}

# Download and prepare for transfer
download_and_prepare_for_transfer() {
    local timestamp="$1"

    echo_info "Starting download and preparation for RunPod transfer: $timestamp"
    echo_info "Using caffeinate to prevent system sleep during download"

    # Create download directory
    TRANSFER_DIR="./runpod-transfer-${timestamp}"
    mkdir -p "$TRANSFER_DIR"
    mkdir -p "$DOWNLOAD_DIR"

    # Find manifest file
    local manifest_file="manifest_${timestamp}.json"
    local local_manifest="${DOWNLOAD_DIR}/${manifest_file}"

    echo_info "Downloading manifest: $manifest_file"
    if ! gsutil cp "gs://${BUCKET_NAME}/${manifest_file}" "$local_manifest"; then
        echo_error "Failed to download manifest for timestamp: $timestamp"
        echo_info "Available timestamps:"
        list_available_versions
        exit 1
    fi

    # Parse manifest and get image list
    if ! command -v jq &> /dev/null; then
        echo_error "jq not found. Please install jq to parse manifest"
        echo_info "Install with: brew install jq (macOS) or apt-get install jq (Ubuntu)"
        exit 1
    fi

    local image_files=($(jq -r '.images[].filename' "$local_manifest"))
    local image_names=($(jq -r '.images[].name' "$local_manifest"))
    local total_images=${#image_files[@]}

    echo_info "Found $total_images images to download and load"

    # Function to download and load a single image
    download_and_load_image() {
        local filename="$1"
        local image_name="$2"
        local index="$3"

        echo_info "[$index/$total_images] Processing: $image_name"

        local local_file="${DOWNLOAD_DIR}/${filename}"
        local tar_file="${local_file%.gz}"

        # Download compressed image
        echo_info "Downloading: $filename"
        if ! gsutil cp "gs://${BUCKET_NAME}/${filename}" "$local_file"; then
            echo_error "Failed to download: $filename"
            return 1
        fi

        # Get download size
        local download_size=$(ls -lh "$local_file" | awk '{print $5}')
        echo_info "Downloaded size: $download_size"

        # Decompress
        echo_info "Decompressing: $filename"
        gunzip "$local_file"

        # Load into Docker
        echo_info "Loading into Docker: $image_name"
        if docker load -i "$tar_file"; then
            echo_success "Successfully loaded: $image_name"
        else
            echo_error "Failed to load: $image_name"
            return 1
        fi

        # Clean up
        rm -f "$tar_file"
        echo_info "Cleaned up: $tar_file"

        return 0
    }

    # Use caffeinate wrapper function
    run_with_caffeinate() {
        if [ -n "$CAFFEINATE_CMD" ]; then
            $CAFFEINATE_CMD "$@"
        else
            "$@"
        fi
    }

    # Download and load all images with caffeinate
    echo_info "Starting downloads with caffeinate..."

    run_with_caffeinate bash -c "
        success_count=0
        for i in \"\${!image_files[@]}\"; do
            index=\$((i + 1))
            if download_and_load_image \"\${image_files[i]}\" \"\${image_names[i]}\" \"\$index\"; then
                success_count=\$((success_count + 1))
            fi
            echo \"\"
        done

        echo_info \"Download and load process completed\"
        echo_info \"Successfully processed: \$success_count/$total_images images\"

        # Verify loaded images
        echo_info \"Verifying loaded images:\"
        for image_name in \"\${image_names[@]}\"; do
            if docker image inspect \"\$image_name\" &>/dev/null; then
                local size=\$(docker image inspect \"\$image_name\" --format='{{.Size}}' | numfmt --to=iec)
                echo_success \"✓ \$image_name (Size: \$size)\"
            else
                echo_error \"✗ \$image_name (Not found)\"
            fi
        done
    "

    # Clean up
    rm -f "$local_manifest"
    rmdir "$DOWNLOAD_DIR" 2>/dev/null || true

    echo_success "All operations completed!"
    echo_info "Images are now available in your local Docker environment"
}

# Main script logic
main() {
    echo_info "HiRAG Docker Image Download Script"
    echo_info "Bucket: gs://${BUCKET_NAME}"
    echo ""

    # Check prerequisites
    check_gcloud

    # Parse arguments
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        "")
            list_available_versions
            echo ""
            echo_info "To download a specific version, run:"
            echo_info "$0 <TIMESTAMP>"
            exit 0
            ;;
        *)
            download_and_load_images "$1"
            ;;
    esac
}

# Export functions for use in subshells
export -f echo_info echo_success echo_warning echo_error download_and_load_image

# Run main function
main "$@"