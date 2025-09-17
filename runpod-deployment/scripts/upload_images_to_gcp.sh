#!/bin/bash

# GCP Image Upload Script
# Saves Docker images and uploads them to Google Cloud Storage

set -e

# Configuration
BUCKET_NAME="${GCP_BUCKET:-hirag-docker-images}"
PROJECT_ID="${GCP_PROJECT_ID:-your-project-id}"
UPLOAD_DIR="./docker-images"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

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

# Images to save (latest working versions)
IMAGES=(
    "hirag-api:latest"
    "hirag-llm:latest"
    "rag-ocr-official:latest"
    "rag-whisper-official:latest"
    "rag-frontend:latest"
)

echo_info "Starting Docker image export and GCP upload process..."
echo_info "Bucket: gs://${BUCKET_NAME}"
echo_info "Timestamp: ${TIMESTAMP}"

# Create upload directory
mkdir -p "${UPLOAD_DIR}"

# Check if gcloud is authenticated
if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | grep -q .; then
    echo_error "No active gcloud authentication found. Please run: gcloud auth login"
    exit 1
fi

# Create bucket if it doesn't exist
echo_info "Ensuring bucket gs://${BUCKET_NAME} exists..."
if ! gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
    echo_info "Creating bucket gs://${BUCKET_NAME}..."
    gsutil mb -p "${PROJECT_ID}" "gs://${BUCKET_NAME}"
    echo_success "Bucket created successfully"
else
    echo_info "Bucket already exists"
fi

# Function to save and upload an image
save_and_upload_image() {
    local image_name="$1"
    local safe_name=$(echo "$image_name" | tr ':/' '_')
    local tar_file="${UPLOAD_DIR}/${safe_name}_${TIMESTAMP}.tar"
    local gz_file="${tar_file}.gz"

    echo_info "Processing image: ${image_name}"

    # Check if image exists
    if ! docker image inspect "${image_name}" &>/dev/null; then
        echo_error "Image ${image_name} not found locally"
        return 1
    fi

    # Get image size
    local image_size=$(docker image inspect "${image_name}" --format='{{.Size}}' | numfmt --to=iec)
    echo_info "Image size: ${image_size}"

    # Save image to tar file
    echo_info "Saving ${image_name} to ${tar_file}..."
    docker save "${image_name}" -o "${tar_file}"

    # Compress the tar file
    echo_info "Compressing ${tar_file}..."
    gzip "${tar_file}"

    # Get compressed size
    local compressed_size=$(ls -lh "${gz_file}" | awk '{print $5}')
    echo_info "Compressed size: ${compressed_size}"

    # Upload to GCS
    echo_info "Uploading ${gz_file} to gs://${BUCKET_NAME}/..."
    gsutil -m cp "${gz_file}" "gs://${BUCKET_NAME}/"

    # Verify upload
    if gsutil ls "gs://${BUCKET_NAME}/$(basename ${gz_file})" &>/dev/null; then
        echo_success "Successfully uploaded $(basename ${gz_file})"
        # Clean up local file
        rm "${gz_file}"
        echo_info "Cleaned up local file: ${gz_file}"
    else
        echo_error "Failed to upload $(basename ${gz_file})"
        return 1
    fi
}

# Save and upload each image
echo_info "Starting image processing..."
total_images=${#IMAGES[@]}
current=0

for image in "${IMAGES[@]}"; do
    current=$((current + 1))
    echo_info "Processing image ${current}/${total_images}: ${image}"

    if save_and_upload_image "${image}"; then
        echo_success "Completed ${image}"
    else
        echo_error "Failed to process ${image}"
        # Continue with other images
    fi
    echo ""
done

# Create a manifest file with image information
MANIFEST_FILE="${UPLOAD_DIR}/manifest_${TIMESTAMP}.json"
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
    if docker image inspect "${image}" &>/dev/null; then
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "${MANIFEST_FILE}"
        fi

        local image_id=$(docker image inspect "${image}" --format='{{.Id}}')
        local image_size=$(docker image inspect "${image}" --format='{{.Size}}')
        local safe_name=$(echo "$image" | tr ':/' '_')

        cat >> "${MANIFEST_FILE}" << EOF
    {
      "name": "${image}",
      "id": "${image_id}",
      "size_bytes": ${image_size},
      "filename": "${safe_name}_${TIMESTAMP}.tar.gz"
    }
EOF
    fi
done

cat >> "${MANIFEST_FILE}" << EOF

  ]
}
EOF

# Upload manifest
echo_info "Uploading manifest to gs://${BUCKET_NAME}/..."
gsutil cp "${MANIFEST_FILE}" "gs://${BUCKET_NAME}/"
rm "${MANIFEST_FILE}"

# List uploaded files
echo_info "Files in bucket:"
gsutil ls -lh "gs://${BUCKET_NAME}/*${TIMESTAMP}*"

# Cleanup
rm -rf "${UPLOAD_DIR}"

echo_success "All images uploaded successfully!"
echo_info "To download on another machine, use the companion download script"
echo_info "Bucket URL: https://console.cloud.google.com/storage/browser/${BUCKET_NAME}"

# Print download commands for reference
echo_info "Download commands for reference:"
echo "gsutil -m cp 'gs://${BUCKET_NAME}/*${TIMESTAMP}*' ./"