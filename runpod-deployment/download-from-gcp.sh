#!/bin/bash

# Configuration - EDIT THESE
GCP_BUCKET="gs://YOUR_BUCKET_NAME"  # Change to your GCP bucket
LOCAL_DIR="./downloaded-deployment"
CHECK_INTERVAL=10  # Seconds between checks

echo "========================================="
echo "Download from GCP (Caffeine Mode)"
echo "========================================="
echo "Bucket: $GCP_BUCKET"
echo "Will check every $CHECK_INTERVAL seconds..."
echo ""

# Clean and create local directory
rm -rf "$LOCAL_DIR"
mkdir -p "$LOCAL_DIR"

# Function to check if files exist
check_files() {
    echo -n "$(date '+%H:%M:%S') - Checking for deployment... "

    # Get latest deployment path
    DEPLOYMENT_PATH=$(gsutil cat "${GCP_BUCKET}/latest-deployment.txt" 2>/dev/null)

    if [ -z "$DEPLOYMENT_PATH" ]; then
        echo "not ready"
        return 1
    fi

    # Check if all required files exist
    REQUIRED_FILES=(
        "rag-api.tar"
        "rag-frontend.tar"
        "whisper_fastapi_service.py"
        "config-fixes.sh"
        "checksums.txt"
    )

    for file in "${REQUIRED_FILES[@]}"; do
        if ! gsutil -q stat "${GCP_BUCKET}/${DEPLOYMENT_PATH}/${file}"; then
            echo "not ready (missing $file)"
            return 1
        fi
    done

    echo "✓ READY!"
    return 0
}

# Loop until files are available
echo "Starting caffeine loop..."
while true; do
    if check_files; then
        break
    fi
    sleep $CHECK_INTERVAL
done

echo ""
echo "========================================="
echo "Files found! Starting download..."
echo "========================================="

# Get deployment path
DEPLOYMENT_PATH=$(gsutil cat "${GCP_BUCKET}/latest-deployment.txt")
echo "Deployment path: $DEPLOYMENT_PATH"
echo ""

# Download all files
echo "[1/2] Downloading files..."
gsutil -m cp -r "${GCP_BUCKET}/${DEPLOYMENT_PATH}/*" "$LOCAL_DIR/"

# Verify checksums
echo ""
echo "[2/2] Verifying checksums..."
cd "$LOCAL_DIR"

if sha256sum -c checksums.txt; then
    echo ""
    echo "========================================="
    echo "✓ Download Complete and Verified!"
    echo "========================================="
    echo "Files downloaded to: $LOCAL_DIR"
    echo ""
    echo "Files:"
    ls -lh rag-*.tar whisper_fastapi_service.py config-fixes.sh
    echo ""
    echo "Next step: Transfer these files to isolated environment and run deploy-in-isolated-env.sh"
else
    echo ""
    echo "========================================="
    echo "✗ Checksum verification FAILED!"
    echo "========================================="
    echo "Please check the files and try again."
    exit 1
fi