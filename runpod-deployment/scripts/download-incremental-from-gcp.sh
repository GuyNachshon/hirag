#!/bin/bash
set -e

# Incremental Download from GCP with Polling
# Downloads files as they become available during upload
# Usage: ./download-incremental-from-gcp.sh [BUCKET_NAME] [PACKAGE_NAME] [DESTINATION]

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BUCKET_NAME=${1:-""}
PACKAGE_NAME=${2:-""}
DESTINATION=${3:-"./"}
POLL_INTERVAL=10  # seconds
MAX_WAIT=7200     # 2 hours maximum wait

# Expected files (based on manifest)
EXPECTED_FILES=(
    "manifest.json"
    "README.md"
    "images/checksums.sha256"
    "images/rag-frontend_latest.tar.gz"
    "images/rag-api_latest.tar.gz"
    "images/rag-whisper_latest.tar.gz"
    "images/rag-llm_latest.tar.gz"
    "images/rag-dots-ocr_latest.tar.gz"
    "configs/"
    "scripts/"
    "docs/"
)

# Validate inputs
if [ -z "$BUCKET_NAME" ]; then
    echo -e "${RED}Error: BUCKET_NAME is required${NC}"
    echo "Usage: $0 <BUCKET_NAME> [PACKAGE_NAME] [DESTINATION]"
    echo ""
    echo "Examples:"
    echo "  # List packages and wait for new one"
    echo "  $0 rag-deployment-packages"
    echo ""
    echo "  # Download specific package as files arrive"
    echo "  $0 rag-deployment-packages rag-system-deployment_v1.0.0_20250128_120000"
    exit 1
fi

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Incremental Download from GCP${NC}"
echo -e "${BLUE}  Bucket: ${BUCKET_NAME}${NC}"
if [ -n "$PACKAGE_NAME" ]; then
    echo -e "${BLUE}  Package: ${PACKAGE_NAME}${NC}"
fi
echo -e "${BLUE}  Destination: ${DESTINATION}${NC}"
echo -e "${BLUE}  Poll Interval: ${POLL_INTERVAL}s${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Check if gsutil is installed
if ! command -v gsutil &> /dev/null; then
    echo -e "${RED}Error: gsutil not found${NC}"
    echo "Install gcloud CLI and gsutil"
    exit 1
fi

# Check authentication
echo -e "${YELLOW}Checking GCP authentication...${NC}"
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo -e "${YELLOW}Not authenticated. Running gcloud auth login...${NC}"
    gcloud auth login
fi
echo -e "${GREEN}✓ Authenticated${NC}"
echo ""

# Check if bucket exists
echo -e "${YELLOW}Checking bucket...${NC}"
if ! gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
    echo -e "${RED}✗ Bucket not found: gs://${BUCKET_NAME}${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Bucket found${NC}"
echo ""

# If no package name, wait for new package
if [ -z "$PACKAGE_NAME" ]; then
    echo -e "${YELLOW}Waiting for new package in bucket...${NC}"
    echo "Press Ctrl+C to cancel"
    echo ""

    LAST_PACKAGE=""
    START_TIME=$(date +%s)

    while true; do
        # List packages
        LATEST_PACKAGE=$(gsutil ls "gs://${BUCKET_NAME}/" | \
                        grep -E "rag-system-deployment" | \
                        sort -r | head -1 | \
                        xargs basename)

        if [ -n "$LATEST_PACKAGE" ] && [ "$LATEST_PACKAGE" != "$LAST_PACKAGE" ]; then
            echo -e "${GREEN}✓ New package detected: ${LATEST_PACKAGE}${NC}"
            PACKAGE_NAME="$LATEST_PACKAGE"
            break
        fi

        # Check timeout
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))

        if [ $ELAPSED -gt $MAX_WAIT ]; then
            echo -e "${RED}Timeout waiting for package (${MAX_WAIT}s)${NC}"
            exit 1
        fi

        echo -ne "\rWaiting... (${ELAPSED}s elapsed)"
        sleep $POLL_INTERVAL
    done
    echo ""
fi

# Create destination
DEST_PATH="${DESTINATION}/${PACKAGE_NAME}"
mkdir -p "$DEST_PATH"

echo -e "${BLUE}Package: ${PACKAGE_NAME}${NC}"
echo -e "${BLUE}Destination: ${DEST_PATH}${NC}"
echo ""

# Track downloaded files
DOWNLOADED_FILES=()
DOWNLOADED_COUNT=0
TOTAL_SIZE=0

# Function to download file if available
download_if_available() {
    local file_path=$1
    local gs_path="gs://${BUCKET_NAME}/${PACKAGE_NAME}/${file_path}"
    local local_path="${DEST_PATH}/${file_path}"

    # Check if file exists in bucket
    if gsutil -q stat "$gs_path" 2>/dev/null; then
        # Check if already downloaded
        if [[ ! " ${DOWNLOADED_FILES[@]} " =~ " ${file_path} " ]]; then
            echo -e "${YELLOW}Downloading: ${file_path}${NC}"

            # Create directory if needed
            mkdir -p "$(dirname "$local_path")"

            # Download file
            if gsutil -m cp -r "$gs_path" "$local_path" 2>/dev/null; then
                DOWNLOADED_FILES+=("$file_path")
                DOWNLOADED_COUNT=$((DOWNLOADED_COUNT + 1))

                # Get file size
                if [ -f "$local_path" ]; then
                    size=$(stat -f%z "$local_path" 2>/dev/null || stat -c%s "$local_path" 2>/dev/null)
                    size_mb=$((size / 1024 / 1024))
                    TOTAL_SIZE=$((TOTAL_SIZE + size))
                    echo -e "${GREEN}✓ Downloaded: ${file_path} (${size_mb} MB)${NC}"
                elif [ -d "$local_path" ]; then
                    echo -e "${GREEN}✓ Downloaded: ${file_path} (directory)${NC}"
                fi

                return 0
            else
                echo -e "${RED}✗ Download failed: ${file_path}${NC}"
                return 1
            fi
        fi
    fi

    return 1
}

# Function to check if manifest is complete
check_manifest_complete() {
    local manifest_path="${DEST_PATH}/manifest.json"

    if [ ! -f "$manifest_path" ]; then
        return 1
    fi

    # Check if manifest has all expected fields
    if ! jq -e '.version and .timestamp and .images' "$manifest_path" &>/dev/null; then
        return 1
    fi

    return 0
}

echo -e "${BLUE}Starting incremental download...${NC}"
echo "Polling bucket every ${POLL_INTERVAL}s"
echo ""

START_TIME=$(date +%s)
MANIFEST_COMPLETE=false
ALL_IMAGES_DOWNLOADED=false

# Main polling loop
while true; do
    DOWNLOADED_THIS_ROUND=0

    # Try to download each expected file
    for file in "${EXPECTED_FILES[@]}"; do
        if download_if_available "$file"; then
            DOWNLOADED_THIS_ROUND=$((DOWNLOADED_THIS_ROUND + 1))
        fi
    done

    # Check if manifest is complete
    if [ "$MANIFEST_COMPLETE" = false ]; then
        if check_manifest_complete; then
            MANIFEST_COMPLETE=true
            echo ""
            echo -e "${GREEN}✓ Manifest complete${NC}"

            # Read expected images from manifest
            MANIFEST_IMAGES=$(jq -r '.images[]' "${DEST_PATH}/manifest.json" 2>/dev/null || echo "")
            if [ -n "$MANIFEST_IMAGES" ]; then
                echo -e "${BLUE}Expected images from manifest:${NC}"
                echo "$MANIFEST_IMAGES" | sed 's/^/  /'
            fi
            echo ""
        fi
    fi

    # If manifest is complete, check for all images including chunked files
    if [ "$MANIFEST_COMPLETE" = true ] && [ "$ALL_IMAGES_DOWNLOADED" = false ]; then
        # List all files in images directory on bucket
        ALL_BUCKET_FILES=$(gsutil ls "gs://${BUCKET_NAME}/${PACKAGE_NAME}/images/" 2>/dev/null || echo "")

        if [ -n "$ALL_BUCKET_FILES" ]; then
            while IFS= read -r bucket_file; do
                # Extract relative path
                relative_file=$(echo "$bucket_file" | sed "s|gs://${BUCKET_NAME}/${PACKAGE_NAME}/||")
                download_if_available "$relative_file"
            done <<< "$ALL_BUCKET_FILES"
        fi

        # Check if checksums file exists and all images downloaded
        if [ -f "${DEST_PATH}/images/checksums.sha256" ]; then
            CHECKSUM_FILES=$(cat "${DEST_PATH}/images/checksums.sha256" | awk '{print $2}')
            ALL_PRESENT=true

            while IFS= read -r checksum_file; do
                if [ ! -f "${DEST_PATH}/images/${checksum_file}" ]; then
                    ALL_PRESENT=false
                    break
                fi
            done <<< "$CHECKSUM_FILES"

            if [ "$ALL_PRESENT" = true ]; then
                ALL_IMAGES_DOWNLOADED=true
                echo ""
                echo -e "${GREEN}✓ All images downloaded${NC}"
            fi
        fi
    fi

    # Check if download is complete
    if [ "$MANIFEST_COMPLETE" = true ] && [ "$ALL_IMAGES_DOWNLOADED" = true ]; then
        echo ""
        echo -e "${GREEN}Download appears complete!${NC}"
        break
    fi

    # Show progress
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    ELAPSED_MIN=$((ELAPSED / 60))

    if [ $DOWNLOADED_THIS_ROUND -eq 0 ]; then
        echo -ne "\rWaiting for files... (${DOWNLOADED_COUNT} files, ${ELAPSED_MIN}m elapsed)"
    fi

    # Check timeout
    if [ $ELAPSED -gt $MAX_WAIT ]; then
        echo ""
        echo -e "${YELLOW}⚠ Maximum wait time reached (${MAX_WAIT}s)${NC}"
        echo "Downloaded ${DOWNLOADED_COUNT} files so far"
        break
    fi

    # Wait before next poll
    sleep $POLL_INTERVAL
done

echo ""

# Verify checksums if available
if [ -f "${DEST_PATH}/images/checksums.sha256" ]; then
    echo -e "${YELLOW}Verifying checksums...${NC}"
    cd "${DEST_PATH}/images"

    if sha256sum -c checksums.sha256 --quiet 2>/dev/null; then
        echo -e "${GREEN}✓ All checksums verified${NC}"
    else
        echo -e "${YELLOW}⚠ Some checksums failed (files may still be uploading)${NC}"
    fi
    cd - > /dev/null
    echo ""
fi

# Summary
TOTAL_SIZE_GB=$((TOTAL_SIZE / 1024 / 1024 / 1024))
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_MIN=$((DURATION / 60))

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Download Summary${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo "  Package: ${PACKAGE_NAME}"
echo "  Location: ${DEST_PATH}"
echo "  Files downloaded: ${DOWNLOADED_COUNT}"
echo "  Total size: ${TOTAL_SIZE_GB} GB"
echo "  Duration: ${DURATION_MIN} minutes"
echo ""

if [ "$ALL_IMAGES_DOWNLOADED" = true ]; then
    echo -e "${GREEN}✓ Download complete!${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Verify package: cd ${DEST_PATH}"
    echo "  2. Import images: cd scripts && ./import-images.sh"
    echo "  3. Deploy: ./deploy.sh"
else
    echo -e "${YELLOW}⚠ Download incomplete${NC}"
    echo "Some files may still be uploading. Run script again or wait and download manually."
fi
echo ""
