#!/bin/bash

# H100 Transfer Preparation Script
# Downloads Docker images from GCP and prepares everything for H100 isolated environment
# Keeps files compressed, checks for existing downloads, uses caffeinate

set -e

# Configuration
BUCKET_NAME="${GCP_BUCKET:-hirag-docker-images}"
TIMESTAMP="${1:-}"
CHUNK_SIZE_GB=20
CHUNK_SIZE_BYTES=$((CHUNK_SIZE_GB * 1024 * 1024 * 1024))

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
    echo "Usage: $0 [COMMAND|TIMESTAMP]"
    echo ""
    echo "Downloads Docker images from GCP and prepares complete RunPod transfer package"
    echo ""
    echo "Features:"
    echo "  - Downloads and chunks files >20GB for easy transfer"
    echo "  - Includes deployment guide and scripts"
    echo "  - Creates load scripts for RunPod"
    echo "  - Uses caffeinate to prevent sleep during download"
    echo "  - Waits for upload completion before downloading"
    echo ""
    echo "Commands:"
    echo "  wait         Wait for all Docker images to be uploaded, then download latest"
    echo "  TIMESTAMP    Download specific timestamp version"
    echo "  (no args)    List available versions"
    echo ""
    echo "Environment Variables:"
    echo "  GCP_BUCKET   GCP bucket name (default: hirag-docker-images)"
    echo ""
    echo "Examples:"
    echo "  $0                           # List available versions"
    echo "  $0 wait                      # Wait for upload completion, then download"
    echo "  $0 20240117_143052          # Download specific timestamp"
    echo ""
    echo "Expected Images (for wait mode):"
    for image in "${EXPECTED_IMAGES[@]}"; do
        echo "  - $image"
    done
    echo ""
}

# Check if gcloud is installed and authenticated
check_gcloud() {
    # Set gcloud path
    GCLOUD_PATH="${GCLOUD_PATH:-/Users/guynachshon/Documents/baddon-ai/rag-v2/google-cloud-sdk/bin/gcloud}"
    GSUTIL_PATH="${GSUTIL_PATH:-/Users/guynachshon/Documents/baddon-ai/rag-v2/google-cloud-sdk/bin/gsutil}"

    # Check if gcloud exists
    if [ ! -x "$GCLOUD_PATH" ]; then
        # Try system gcloud as fallback
        if command -v gcloud &> /dev/null; then
            GCLOUD_PATH="gcloud"
            GSUTIL_PATH="gsutil"
        else
            echo_error "gcloud not found at $GCLOUD_PATH or in system PATH"
            echo_info "Please ensure Google Cloud SDK is installed"
            echo_info "Or set GCLOUD_PATH environment variable"
            echo_info "Expected location: ./google-cloud-sdk/bin/gcloud"
            exit 1
        fi
    fi

    if ! $GCLOUD_PATH auth list --filter="status:ACTIVE" --format="value(account)" | grep -q .; then
        echo_error "No active gcloud authentication found"
        echo_info "Please run: $GCLOUD_PATH auth login"
        exit 1
    fi

    # Check if bucket exists
    if ! $GSUTIL_PATH ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        echo_error "Bucket gs://${BUCKET_NAME} not found or not accessible"
        exit 1
    fi

    echo_info "Using gcloud: $GCLOUD_PATH"
    echo_info "Using gsutil: $GSUTIL_PATH"
}

# Expected Docker images that should be uploaded
EXPECTED_IMAGES=(
    "hirag-api:latest"
    "hirag-llm:latest"
    "rag-ocr-official:latest"
    "rag-whisper-official:latest"
    "rag-frontend:latest"
)

# Wait for all images to be uploaded and return the timestamp
wait_for_upload_completion() {
    echo_info "🔍 Checking for upload completion..." >&2
    echo_info "Expected images: ${EXPECTED_IMAGES[*]}" >&2
    echo "" >&2

    local check_count=0
    local max_checks=480  # Wait up to 8 hours (480 * 60s)
    local check_interval=60  # Check every 60 seconds

    while [ $check_count -lt $max_checks ]; do
        check_count=$((check_count + 1))
        echo_info "Check $check_count/$max_checks - Looking for manifest files..." >&2

        # Get all manifest files
        local manifests=$($GSUTIL_PATH ls "gs://${BUCKET_NAME}/manifest_*.json" 2>/dev/null || true)

        if [ -n "$manifests" ]; then
            # Found manifest files, check the latest one
            local latest_manifest=$(echo "$manifests" | sort | tail -1)
            local timestamp=$(basename "$latest_manifest" | sed 's/manifest_\(.*\)\.json/\1/')

            echo_info "✅ Found manifest: $timestamp" >&2

            # Download and check manifest content
            local temp_manifest="/tmp/manifest_${timestamp}.json"
            if $GSUTIL_PATH cp "$latest_manifest" "$temp_manifest" &>/dev/null; then

                if command -v jq &> /dev/null; then
                    local manifest_images=($(jq -r '.images[].name' "$temp_manifest" 2>/dev/null || true))
                    local image_count=${#manifest_images[@]}
                    local expected_count=${#EXPECTED_IMAGES[@]}

                    echo_info "Found $image_count images in manifest (expected: $expected_count)" >&2

                    # Check if all expected images are present
                    local missing_images=()
                    for expected in "${EXPECTED_IMAGES[@]}"; do
                        local found=false
                        for manifest_image in "${manifest_images[@]}"; do
                            if [ "$expected" = "$manifest_image" ]; then
                                found=true
                                break
                            fi
                        done
                        if [ "$found" = false ]; then
                            missing_images+=("$expected")
                        fi
                    done

                    if [ ${#missing_images[@]} -eq 0 ]; then
                        echo_success "🎉 All images uploaded successfully!" >&2
                        echo_info "Timestamp: $timestamp" >&2
                        rm -f "$temp_manifest"
                        # Output the timestamp for the caller to stdout
                        echo "$timestamp"
                        return 0
                    else
                        echo_warning "⏳ Missing images: ${missing_images[*]}" >&2
                    fi
                else
                    echo_warning "jq not available, cannot parse manifest" >&2
                fi

                rm -f "$temp_manifest"
            fi
        else
            echo_info "📤 No manifest files found yet - upload still in progress" >&2
        fi

        echo_info "⏰ Waiting ${check_interval}s before next check... (${check_count}/${max_checks})" >&2
        sleep $check_interval
    done

    echo_error "❌ Timeout waiting for upload completion after $((max_checks * check_interval / 60)) minutes" >&2
    echo_info "Current bucket contents:" >&2
    $GSUTIL_PATH ls -lh "gs://${BUCKET_NAME}/" >&2
    return 1
}

# List available versions in bucket
list_available_versions() {
    echo_info "Available versions in gs://${BUCKET_NAME}:"
    echo ""

    # Get all manifest files to show available timestamps
    local manifests=$($GSUTIL_PATH ls "gs://${BUCKET_NAME}/manifest_*.json" 2>/dev/null || true)

    if [ -z "$manifests" ]; then
        echo_warning "No manifest files found in bucket"
        echo_info "Listing all files:"
        $GSUTIL_PATH ls -lh "gs://${BUCKET_NAME}/"
        echo ""
        echo_info "💡 If upload is in progress, use 'wait' mode:"
        echo_info "$0 wait"
        return
    fi

    echo "Available timestamps:"
    for manifest in $manifests; do
        local timestamp=$(basename "$manifest" | sed 's/manifest_\(.*\)\.json/\1/')
        echo "  - $timestamp"

        # Download and show manifest content
        local temp_manifest="/tmp/manifest_${timestamp}.json"
        $GSUTIL_PATH cp "$manifest" "$temp_manifest" &>/dev/null

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

# Function to chunk large files
chunk_file() {
    local file_path="$1"
    local base_name=$(basename "$file_path")
    local dir_name=$(dirname "$file_path")

    local file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null)

    if [ "$file_size" -gt "$CHUNK_SIZE_BYTES" ]; then
        echo_info "File $base_name is $(numfmt --to=iec $file_size), chunking into ${CHUNK_SIZE_GB}GB pieces..."

        # Create chunks
        split -b "${CHUNK_SIZE_GB}g" "$file_path" "${file_path}.chunk"

        # Remove original large file
        rm "$file_path"

        # List chunks created
        local chunks=($(ls "${file_path}.chunk"*))
        echo_info "Created ${#chunks[@]} chunks for $base_name"

        return 0
    else
        echo_info "File $base_name is $(numfmt --to=iec $file_size), no chunking needed"
        return 1
    fi
}

# REMOVED - Function to create load script for chunked files
create_load_script_removed() {
    local transfer_dir="$1"
    local script_file="${transfer_dir}/load_images.sh"

    cat > "$script_file" << 'EOF'
#!/bin/bash

# RunPod Image Loading Script
# Automatically loads all Docker images from transfer package

set -e

echo "🚀 HiRAG RunPod Image Loading Script"
echo "====================================="

# Function to rejoin chunked files
rejoin_chunks() {
    local base_file="$1"

    if ls "${base_file}.chunk"* 1> /dev/null 2>&1; then
        echo "📦 Rejoining chunks for $(basename "$base_file")..."
        cat "${base_file}.chunk"* > "$base_file"
        rm "${base_file}.chunk"*
        echo "✅ Rejoined $(basename "$base_file")"
        return 0
    fi
    return 1
}

# Function to load a Docker image
load_image() {
    local tar_file="$1"
    local base_name=$(basename "$tar_file" .tar)

    echo "🐳 Loading Docker image: $base_name"

    if docker load -i "$tar_file"; then
        echo "✅ Successfully loaded: $base_name"

        # Get image size
        local image_name=$(docker load -i "$tar_file" 2>&1 | grep "Loaded image:" | sed 's/Loaded image: //')
        if [ -n "$image_name" ]; then
            local size=$(docker image inspect "$image_name" --format='{{.Size}}' 2>/dev/null | numfmt --to=iec 2>/dev/null || echo "Unknown")
            echo "   Size: $size"
        fi

        # Clean up tar file
        rm "$tar_file"
        echo "🗑️  Cleaned up: $(basename "$tar_file")"

        return 0
    else
        echo "❌ Failed to load: $base_name"
        return 1
    fi
}

echo ""
echo "Step 1: Rejoining chunked files..."
echo "================================="

# Find all potential chunked files and rejoin them
for chunk in *.chunk*; do
    if [ -f "$chunk" ]; then
        base_file=$(echo "$chunk" | sed 's/\.chunk.*//')
        if [ ! -f "$base_file" ]; then
            rejoin_chunks "$base_file"
        fi
    fi
done

echo ""
echo "Step 2: Loading Docker images..."
echo "==============================="

# Load all tar files
success_count=0
total_count=0

for tar_file in *.tar; do
    if [ -f "$tar_file" ]; then
        total_count=$((total_count + 1))
        if load_image "$tar_file"; then
            success_count=$((success_count + 1))
        fi
        echo ""
    fi
done

echo ""
echo "Step 3: Verification..."
echo "======================"

# List loaded images
echo "📋 Loaded Docker images:"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E "(hirag|rag-)" || echo "No HiRAG images found"

echo ""
echo "📊 Summary:"
echo "  Successfully loaded: $success_count/$total_count images"

if [ "$success_count" -eq "$total_count" ] && [ "$total_count" -gt 0 ]; then
    echo "🎉 All images loaded successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Review the deployment guide: cat RUNPOD_DEPLOYMENT_GUIDE.md"
    echo "2. Start services using the provided commands"
    echo "3. Verify services with: curl http://localhost:8000/health"
else
    echo "⚠️  Some images failed to load. Check the output above."
fi

echo ""
echo "🚀 Ready for RunPod deployment!"
EOF

    chmod +x "$script_file"
    echo_success "Created load script: $script_file"
}

# Main function to prepare RunPod transfer
prepare_runpod_transfer() {
    local timestamp="$1"

    echo_info "🚀 Preparing RunPod transfer package for timestamp: $timestamp"
    echo_info "📦 Files >20GB will be chunked for easier transfer"

    # Create transfer directory
    local transfer_dir="runpod-transfer-${timestamp}"
    local temp_dir="temp-download"

    mkdir -p "$transfer_dir"
    mkdir -p "$temp_dir"

    echo_info "📁 Transfer package: $transfer_dir"

    # Download manifest
    local manifest_file="manifest_${timestamp}.json"
    local local_manifest="${temp_dir}/${manifest_file}"

    echo_info "📄 Downloading manifest: $manifest_file"
    if ! $GSUTIL_PATH cp "gs://${BUCKET_NAME}/${manifest_file}" "$local_manifest"; then
        echo_error "Failed to download manifest for timestamp: $timestamp"
        list_available_versions
        exit 1
    fi

    # Copy manifest to transfer directory
    cp "$local_manifest" "$transfer_dir/"

    # Parse manifest
    if ! command -v jq &> /dev/null; then
        echo_error "jq not found. Please install jq: brew install jq"
        exit 1
    fi

    local image_files=($(jq -r '.images[].filename' "$local_manifest"))
    local image_names=($(jq -r '.images[].name' "$local_manifest"))
    local total_images=${#image_files[@]}

    echo_info "📦 Found $total_images images to download"

    # Function to download and process image
    download_and_process_image() {
        local filename="$1"
        local image_name="$2"
        local index="$3"

        echo_info "[$index/$total_images] 📥 Processing: $image_name"

        local compressed_file="${transfer_dir}/${filename}"
        local tar_file="${transfer_dir}/${filename%.gz}"
        local temp_compressed="${temp_dir}/${filename}"

        # Check if file already exists in transfer directory
        if [ -f "$compressed_file" ]; then
            local existing_size=$(ls -lh "$compressed_file" | awk '{print $5}')
            echo_info "   ✅ Already exists: $compressed_file ($existing_size)"
            echo_info "   Skipping download"
            return 0
        elif [ -f "$tar_file" ]; then
            local existing_size=$(ls -lh "$tar_file" | awk '{print $5}')
            echo_info "   ✅ Already exists (uncompressed): $tar_file ($existing_size)"
            echo_info "   Compressing it back..."
            gzip -c "$tar_file" > "$compressed_file"
            rm "$tar_file"
            echo_info "   ✅ Compressed to: $(basename "$compressed_file")"
            return 0
        fi

        # Check if file exists in temp-download directory
        if [ -f "$temp_compressed" ]; then
            local existing_size=$(ls -lh "$temp_compressed" | awk '{print $5}')
            echo_info "   ✅ Found in temp-download: $(basename "$temp_compressed") ($existing_size)"
            echo_info "   Moving to transfer directory..."
            mv "$temp_compressed" "$compressed_file"
            echo_info "   ✅ Moved to: $(basename "$compressed_file")"
            return 0
        fi

        echo_info "   Downloading from GCS..."

        # Download compressed file directly to transfer directory
        if ! $GSUTIL_PATH cp "gs://${BUCKET_NAME}/${filename}" "$compressed_file"; then
            echo_error "   Failed to download: $filename"
            return 1
        fi

        local download_size=$(ls -lh "$compressed_file" | awk '{print $5}')
        echo_info "   Downloaded: $download_size"

        # Check if compressed file needs chunking (for files >20GB compressed)
        local file_size=$(stat -f%z "$compressed_file" 2>/dev/null || stat -c%s "$compressed_file" 2>/dev/null)
        if [ "$file_size" -gt "$CHUNK_SIZE_BYTES" ]; then
            echo_info "   ✂️  Compressed file is >20GB, chunking..."
            if chunk_file "$compressed_file"; then
                echo_info "   ✂️  File chunked into pieces"
            fi
        fi

        echo_success "   ✅ Ready: $(basename "$compressed_file")"
        return 0
    }

    # Use caffeinate wrapper
    run_with_caffeinate() {
        if [ -n "$CAFFEINATE_CMD" ]; then
            $CAFFEINATE_CMD "$@"
        else
            "$@"
        fi
    }

    # Download all images
    echo_info "🔄 Starting downloads..."
    echo ""

    success_count=0
    for i in "${!image_files[@]}"; do
        index=$((i + 1))
        if download_and_process_image "${image_files[i]}" "${image_names[i]}" "$index"; then
            success_count=$((success_count + 1))
        fi
        echo ""
    done

    echo_info "📊 Download Summary:"
    echo_info "   Successfully processed: $success_count/$total_images images"

    # Copy deployment documentation
    echo_info "📚 Adding deployment documentation..."

    # Copy deployment guide
    if [ -f "RUNPOD_DEPLOYMENT_GUIDE.md" ]; then
        cp "RUNPOD_DEPLOYMENT_GUIDE.md" "$transfer_dir/"
        echo_info "   ✅ Added: RUNPOD_DEPLOYMENT_GUIDE.md"
    fi

    # Create simple load script for H100 environment
    cat > "${transfer_dir}/load_images.sh" << 'EOF'
#!/bin/bash

# Load Docker images on H100 environment

echo "Loading Docker images..."

for file in *.tar.gz; do
    if [ -f "$file" ]; then
        echo "Processing $file..."
        # Decompress and load
        gunzip -c "$file" | docker load
        echo "Loaded $file"
    fi
done

echo "All images loaded!"
docker images | grep -E "(hirag|rag-)"
EOF

    chmod +x "${transfer_dir}/load_images.sh"
    echo_info "   ✅ Added: load_images.sh"

    # Create quick start script
    cat > "${transfer_dir}/quick_start.sh" << 'EOF'
#!/bin/bash

echo "🚀 HiRAG RunPod Quick Start"
echo "=========================="
echo ""
echo "1. Load all Docker images:"
echo "   ./load_images.sh"
echo ""
echo "2. Start services (run each in separate terminal):"
echo ""
echo "   # LLM Service (Chat)"
echo "   docker run --rm --gpus all -p 8000:8000 hirag-llm:latest \\"
echo "     vllm serve /root/.cache/huggingface/models--openai--gpt-oss-20b/snapshots/6cee5e81ee83917806bbde320786a8fb61efebee \\"
echo "     --host 0.0.0.0 --port 8000 --tensor-parallel-size 1 --gpu-memory-utilization 0.7 --max-model-len 4096 --trust-remote-code"
echo ""
echo "   # Embedding Service"
echo "   docker run --rm --gpus all -p 8001:8001 hirag-llm:latest \\"
echo "     vllm serve /root/.cache/huggingface/models--Qwen--Qwen3-Embedding-4B/snapshots/5cf2132abc99cad020ac570b19d031efec650f2b \\"
echo "     --host 0.0.0.0 --port 8001 --trust-remote-code --task embed"
echo ""
echo "   # API Service"
echo "   docker run --rm -p 8080:8080 --network host hirag-api:latest"
echo ""
echo "3. Verify services:"
echo "   curl http://localhost:8000/v1/models  # LLM"
echo "   curl http://localhost:8001/v1/models  # Embedding"
echo "   curl http://localhost:8080/health     # API"
echo ""
echo "📖 For complete guide: cat RUNPOD_DEPLOYMENT_GUIDE.md"
EOF

    chmod +x "${transfer_dir}/quick_start.sh"
    echo_info "   ✅ Added: quick_start.sh"

    # Create README
    cat > "${transfer_dir}/README.md" << EOF
# HiRAG RunPod Transfer Package

Generated: $(date)
Timestamp: $timestamp

## Contents

- **Docker Images**: All required images (chunked if >20GB)
- **load_images.sh**: Automatic image loading script
- **quick_start.sh**: Quick deployment commands
- **RUNPOD_DEPLOYMENT_GUIDE.md**: Complete deployment guide
- **manifest_${timestamp}.json**: Image metadata

## Quick Start

1. Upload this entire directory to your RunPod instance
2. Run: \`./load_images.sh\`
3. Follow commands in: \`./quick_start.sh\`

## Transfer Notes

- Files >20GB have been chunked for easier upload
- The load script will automatically rejoin chunks
- All models are embedded in the Docker images
- No internet connection required on RunPod

## Support

See RUNPOD_DEPLOYMENT_GUIDE.md for complete instructions and troubleshooting.
EOF

    echo_info "   ✅ Added: README.md"

    # Calculate total transfer size
    local total_size=$(du -sh "$transfer_dir" | awk '{print $1}')

    # Create transfer summary
    echo ""
    echo_success "🎉 RunPod transfer package ready!"
    echo_info "📁 Location: $transfer_dir"
    echo_info "📦 Total size: $total_size"
    echo_info "🗂️  Contents:"
    ls -la "$transfer_dir" | tail -n +2 | awk '{print "   " $9 " (" $5 " bytes)"}'

    # Cleanup temp directory
    rm -rf "$temp_dir"

    echo ""
    echo_info "📤 Transfer Instructions:"
    echo_info "1. Upload entire '$transfer_dir' directory to RunPod"
    echo_info "2. On RunPod: cd $transfer_dir && ./load_images.sh"
    echo_info "3. Follow quick_start.sh for service deployment"

    echo ""
    echo_warning "💡 Transfer Tips:"
    echo_warning "- Use scp, rsync, or cloud storage for upload"
    echo_warning "- Verify all files transferred before running load_images.sh"
    echo_warning "- Check available disk space on RunPod (need ~${total_size} free)"
}

# Main script logic
main() {
    echo_info "🚀 HiRAG RunPod Transfer Preparation"
    echo_info "Bucket: gs://${BUCKET_NAME}"
    echo_info "Chunk size: ${CHUNK_SIZE_GB}GB"
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
            echo_info "To prepare transfer package, run:"
            echo_info "$0 <TIMESTAMP>"
            echo_info ""
            echo_info "To wait for upload completion, run:"
            echo_info "$0 wait"
            exit 0
            ;;
        "wait")
            echo_info "🔄 Waiting for all Docker images to be uploaded..."
            local timestamp=$(wait_for_upload_completion)
            local wait_result=$?

            if [ $wait_result -eq 0 ] && [ -n "$timestamp" ]; then
                echo_info "✅ Upload complete! Now preparing transfer package..."
                prepare_runpod_transfer "$timestamp"
            else
                echo_error "Failed to wait for upload completion"
                exit 1
            fi
            ;;
        *)
            prepare_runpod_transfer "$1"
            ;;
    esac
}

# Run main function
main "$@"