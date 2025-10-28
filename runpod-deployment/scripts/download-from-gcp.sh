#!/bin/bash
set -e

# Download Airgapped Package from GCP Bucket
# Downloads deployment package from Google Cloud Storage
# Usage: ./download-from-gcp.sh [BUCKET_NAME] [PACKAGE_NAME] [DESTINATION]

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

# Validate inputs
if [ -z "$BUCKET_NAME" ]; then
    echo -e "${RED}Error: BUCKET_NAME is required${NC}"
    echo "Usage: $0 <BUCKET_NAME> [PACKAGE_NAME] [DESTINATION]"
    echo ""
    echo "Examples:"
    echo "  # List available packages"
    echo "  $0 rag-deployment-packages"
    echo ""
    echo "  # Download specific package"
    echo "  $0 rag-deployment-packages rag-system-deployment_v1.0.0_20250128_120000"
    exit 1
fi

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Downloading from GCP Bucket${NC}"
echo -e "${BLUE}  Bucket: ${BUCKET_NAME}${NC}"
if [ -n "$PACKAGE_NAME" ]; then
    echo -e "${BLUE}  Package: ${PACKAGE_NAME}${NC}"
fi
echo -e "${BLUE}  Destination: ${DESTINATION}${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Check if gsutil is installed
if ! command -v gsutil &> /dev/null; then
    echo -e "${RED}Error: gsutil not found${NC}"
    echo ""
    echo "Install gcloud CLI:"
    echo "  https://cloud.google.com/sdk/docs/install"
    echo ""
    echo "Then install gsutil:"
    echo "  gcloud components install gsutil"
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
echo -e "${YELLOW}Checking if bucket exists...${NC}"
if ! gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
    echo -e "${RED}✗ Bucket not found: gs://${BUCKET_NAME}${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Bucket found${NC}"
echo ""

# If no package name provided, list available packages
if [ -z "$PACKAGE_NAME" ]; then
    echo -e "${BLUE}Available packages in gs://${BUCKET_NAME}/:${NC}"
    echo ""

    # List packages
    PACKAGES=$(gsutil ls "gs://${BUCKET_NAME}/" | grep -E "rag-system-deployment" || true)

    if [ -z "$PACKAGES" ]; then
        echo -e "${YELLOW}No packages found${NC}"
        exit 0
    fi

    # Parse and display packages with details
    echo "Package Name                                          | Upload Date         | Size"
    echo "------------------------------------------------------+---------------------+--------"

    while IFS= read -r package_url; do
        pkg_name=$(basename "$package_url" | sed 's/\/$//')

        # Try to get manifest for details
        manifest_url="${package_url}manifest.json"
        if gsutil -q stat "$manifest_url" 2>/dev/null; then
            version=$(gsutil cat "$manifest_url" 2>/dev/null | grep -o '"version": *"[^"]*"' | cut -d'"' -f4 || echo "unknown")
            timestamp=$(gsutil cat "$manifest_url" 2>/dev/null | grep -o '"timestamp": *"[^"]*"' | cut -d'"' -f4 || echo "unknown")
            size_gb=$(gsutil cat "$manifest_url" 2>/dev/null | grep -o '"total_size_gb": *[0-9]*' | grep -o '[0-9]*' || echo "?")

            printf "%-50s | %-19s | %s GB\n" "$pkg_name" "$timestamp" "$size_gb"
        else
            printf "%-50s | %-19s | %s\n" "$pkg_name" "unknown" "?"
        fi
    done <<< "$PACKAGES"

    echo ""
    echo -e "${BLUE}To download a package:${NC}"
    echo "  $0 ${BUCKET_NAME} <PACKAGE_NAME>"
    exit 0
fi

# Verify package exists
echo -e "${YELLOW}Verifying package exists...${NC}"
if ! gsutil ls "gs://${BUCKET_NAME}/${PACKAGE_NAME}/" &> /dev/null; then
    echo -e "${RED}✗ Package not found: ${PACKAGE_NAME}${NC}"
    echo ""
    echo "Run without PACKAGE_NAME to list available packages:"
    echo "  $0 ${BUCKET_NAME}"
    exit 1
fi
echo -e "${GREEN}✓ Package found${NC}"
echo ""

# Show package details
echo -e "${BLUE}Package details:${NC}"
MANIFEST_URL="gs://${BUCKET_NAME}/${PACKAGE_NAME}/manifest.json"
if gsutil -q stat "$MANIFEST_URL" 2>/dev/null; then
    gsutil cat "$MANIFEST_URL" | grep -E '"(version|timestamp|total_size_gb)"' | sed 's/^/  /'
else
    echo "  (manifest not found)"
fi
echo ""

# Confirm download
DEST_PATH="${DESTINATION}/${PACKAGE_NAME}"
if [ -d "$DEST_PATH" ]; then
    echo -e "${YELLOW}Warning: Destination directory already exists: ${DEST_PATH}${NC}"
    read -p "Overwrite? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Create destination
mkdir -p "$DEST_PATH"

# Download package
echo -e "${YELLOW}Downloading package...${NC}"
echo "  Source: gs://${BUCKET_NAME}/${PACKAGE_NAME}/"
echo "  Destination: ${DEST_PATH}/"
echo ""

START_TIME=$(date +%s)

# Use gsutil rsync for efficient download with progress
if gsutil -m rsync -r "gs://${BUCKET_NAME}/${PACKAGE_NAME}/" "$DEST_PATH/"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    DURATION_MIN=$((DURATION / 60))

    echo ""
    echo -e "${GREEN}✓ Download complete${NC}"
    echo "  Duration: ${DURATION_MIN} minutes (${DURATION} seconds)"
else
    echo -e "${RED}✗ Download failed${NC}"
    exit 1
fi
echo ""

# Verify checksums if available
CHECKSUMS_FILE="${DEST_PATH}/images/checksums.sha256"
if [ -f "$CHECKSUMS_FILE" ]; then
    echo -e "${YELLOW}Verifying checksums...${NC}"
    cd "${DEST_PATH}/images"

    if sha256sum -c checksums.sha256 --quiet; then
        echo -e "${GREEN}✓ All checksums verified${NC}"
    else
        echo -e "${RED}✗ Checksum verification failed${NC}"
        echo "Some files may be corrupted. Re-download recommended."
        exit 1
    fi
    cd - > /dev/null
    echo ""
fi

# Summary
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Download Summary${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "${GREEN}Package downloaded successfully!${NC}"
echo ""
echo "  Location: ${DEST_PATH}/"
echo ""

# Check package contents
FILE_COUNT=$(find "$DEST_PATH" -type f | wc -l)
TOTAL_SIZE=$(du -sh "$DEST_PATH" 2>/dev/null | cut -f1)
echo "  Files: ${FILE_COUNT}"
echo "  Size: ${TOTAL_SIZE}"
echo ""

echo -e "${BLUE}Next steps:${NC}"
echo ""
echo "1. Review package contents:"
echo "   ls -lah ${DEST_PATH}/"
echo "   cat ${DEST_PATH}/README.md"
echo ""
echo "2. Import Docker images:"
echo "   cd ${DEST_PATH}/scripts"
echo "   ./import-images.sh"
echo ""
echo "3. Deploy services:"
echo "   ./deploy.sh"
echo ""
echo "For detailed instructions, see:"
echo "   ${DEST_PATH}/docs/QUICK_START.md"
echo ""
echo -e "${GREEN}✓ Ready for deployment!${NC}"
