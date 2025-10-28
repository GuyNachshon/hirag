#!/bin/bash

# Create manifest for already uploaded images
# This script only creates the manifest file without re-uploading images

set -e

# Configuration
BUCKET_NAME="${GCP_BUCKET:-hirag-docker-images}"
TIMESTAMP="20250917_225650"  # Use the timestamp from your upload

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

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Images that were uploaded
IMAGES=(
    "hirag-api:latest"
    "hirag-llm:latest"
    "rag-ocr-official:latest"
    "rag-whisper-official:latest"
    "rag-frontend:latest"
)

echo_info "Creating manifest for timestamp: ${TIMESTAMP}"

# Set gcloud/gsutil path
GCLOUD_PATH="${GCLOUD_PATH:-/Users/guynachshon/Documents/baddon-ai/rag-v2/google-cloud-sdk/bin/gcloud}"
GSUTIL_PATH="${GSUTIL_PATH:-/Users/guynachshon/Documents/baddon-ai/rag-v2/google-cloud-sdk/bin/gsutil}"

# Try system commands if custom path doesn't exist
if [ ! -x "$GCLOUD_PATH" ]; then
    if command -v gcloud &> /dev/null; then
        GCLOUD_PATH="gcloud"
        GSUTIL_PATH="gsutil"
    else
        echo_error "gcloud not found"
        exit 1
    fi
fi

# Create manifest file
MANIFEST_FILE="manifest_${TIMESTAMP}.json"
echo_info "Creating manifest file: ${MANIFEST_FILE}"

cat > "${MANIFEST_FILE}" << EOF
{
  "timestamp": "${TIMESTAMP}",
  "upload_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "bucket": "${BUCKET_NAME}",
  "images": [
EOF

# Add image information to manifest
first=true
for image in "${IMAGES[@]}"; do
    if [ "$first" = true ]; then
        first=false
    else
        echo "," >> "${MANIFEST_FILE}"
    fi

    # For already uploaded images, use estimated sizes
    case "$image" in
        "hirag-api:latest")
            image_size="2900000000"  # ~2.7GB
            ;;
        "hirag-llm:latest")
            image_size="62000000000"  # ~57.9GB
            ;;
        "rag-ocr-official:latest")
            image_size="37000000000"  # ~34.5GB
            ;;
        "rag-whisper-official:latest")
            image_size="18500000000"  # ~17.3GB
            ;;
        "rag-frontend:latest")
            image_size="55000000"  # ~52.9MB
            ;;
        *)
            image_size="0"
            ;;
    esac

    safe_name=$(echo "$image" | tr ':/' '_')

    cat >> "${MANIFEST_FILE}" << EOF
    {
      "name": "${image}",
      "id": "sha256:placeholder",
      "size_bytes": ${image_size},
      "filename": "${safe_name}_${TIMESTAMP}.tar.gz"
    }
EOF
done

cat >> "${MANIFEST_FILE}" << EOF

  ]
}
EOF

echo_success "Manifest created locally: ${MANIFEST_FILE}"

# Upload manifest to GCS
echo_info "Uploading manifest to gs://${BUCKET_NAME}/..."
if $GSUTIL_PATH cp "${MANIFEST_FILE}" "gs://${BUCKET_NAME}/"; then
    echo_success "Manifest uploaded successfully!"
    echo_info "Manifest URL: gs://${BUCKET_NAME}/${MANIFEST_FILE}"

    # List the uploaded files
    echo_info "Verifying uploaded files with this timestamp:"
    $GSUTIL_PATH ls -lh "gs://${BUCKET_NAME}/*${TIMESTAMP}*" || true
else
    echo_error "Failed to upload manifest"
    exit 1
fi

echo_success "Done! The manifest has been created and uploaded."
echo_info "You can now run the download script with: ./prepare_runpod_transfer.sh wait"