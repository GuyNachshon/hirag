#!/bin/bash
set -e

# Upload Airgapped Package to GCP Bucket
# Uploads deployment package to Google Cloud Storage
# Usage: ./upload-to-gcp.sh [PACKAGE_DIR] [BUCKET_NAME] [PROJECT_ID]

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PACKAGE_DIR=${1:-""}
BUCKET_NAME=${2:-"rag-deployment-packages"}
PROJECT_ID=${3:-""}

# Validate inputs
if [ -z "$PACKAGE_DIR" ]; then
    echo -e "${RED}Error: PACKAGE_DIR is required${NC}"
    echo "Usage: $0 <PACKAGE_DIR> [BUCKET_NAME] [PROJECT_ID]"
    exit 1
fi

if [ ! -d "$PACKAGE_DIR" ]; then
    echo -e "${RED}Error: Package directory not found: ${PACKAGE_DIR}${NC}"
    exit 1
fi

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Uploading to GCP Bucket${NC}"
echo -e "${BLUE}  Package: ${PACKAGE_DIR}${NC}"
echo -e "${BLUE}  Bucket: ${BUCKET_NAME}${NC}"
if [ -n "$PROJECT_ID" ]; then
    echo -e "${BLUE}  Project: ${PROJECT_ID}${NC}"
fi
echo -e "${BLUE}================================================${NC}"
echo ""

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: gcloud CLI not found${NC}"
    echo "Install: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if gsutil is installed
if ! command -v gsutil &> /dev/null; then
    echo -e "${RED}Error: gsutil not found${NC}"
    echo "Install: gcloud components install gsutil"
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

# Set project if provided
if [ -n "$PROJECT_ID" ]; then
    echo -e "${YELLOW}Setting active project to ${PROJECT_ID}...${NC}"
    gcloud config set project "$PROJECT_ID"
    echo -e "${GREEN}✓ Project set${NC}"
    echo ""
else
    # Get current project
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}Error: No project ID specified and no active project${NC}"
        echo "Set project: gcloud config set project PROJECT_ID"
        exit 1
    fi
    echo -e "${BLUE}Using active project: ${PROJECT_ID}${NC}"
    echo ""
fi

# Check if bucket exists
echo -e "${YELLOW}Checking if bucket exists...${NC}"
if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
    echo -e "${GREEN}✓ Bucket exists: gs://${BUCKET_NAME}${NC}"
else
    echo -e "${YELLOW}Bucket does not exist. Creating...${NC}"

    # Prompt for region
    echo ""
    echo "Select region for bucket:"
    echo "  1) us-central1 (Iowa)"
    echo "  2) us-east1 (South Carolina)"
    echo "  3) us-west1 (Oregon)"
    echo "  4) europe-west1 (Belgium)"
    echo "  5) asia-east1 (Taiwan)"
    echo "  6) Custom"
    read -p "Enter choice (1-6): " region_choice

    case $region_choice in
        1) REGION="us-central1" ;;
        2) REGION="us-east1" ;;
        3) REGION="us-west1" ;;
        4) REGION="europe-west1" ;;
        5) REGION="asia-east1" ;;
        6)
            read -p "Enter region: " REGION
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac

    echo ""
    echo -e "${YELLOW}Creating bucket in ${REGION}...${NC}"

    if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://${BUCKET_NAME}"; then
        echo -e "${GREEN}✓ Bucket created successfully${NC}"
    else
        echo -e "${RED}✗ Failed to create bucket${NC}"
        exit 1
    fi
fi
echo ""

# Get package name from directory
PACKAGE_NAME=$(basename "$PACKAGE_DIR")

# Upload package
echo -e "${YELLOW}Uploading package...${NC}"
echo "  Source: ${PACKAGE_DIR}"
echo "  Destination: gs://${BUCKET_NAME}/${PACKAGE_NAME}/"
echo ""

# Use gsutil rsync for efficient upload with progress
if gsutil -m rsync -r -x ".*\.DS_Store$" "$PACKAGE_DIR" "gs://${BUCKET_NAME}/${PACKAGE_NAME}/"; then
    echo -e "${GREEN}✓ Upload complete${NC}"
else
    echo -e "${RED}✗ Upload failed${NC}"
    exit 1
fi
echo ""

# Verify upload
echo -e "${YELLOW}Verifying upload...${NC}"
UPLOADED_FILES=$(gsutil ls -r "gs://${BUCKET_NAME}/${PACKAGE_NAME}/" | wc -l)
LOCAL_FILES=$(find "$PACKAGE_DIR" -type f | wc -l)

echo "  Local files: ${LOCAL_FILES}"
echo "  Uploaded files: ${UPLOADED_FILES}"

if [ "$UPLOADED_FILES" -ge "$LOCAL_FILES" ]; then
    echo -e "${GREEN}✓ Verification passed${NC}"
else
    echo -e "${YELLOW}⚠ File count mismatch (may include directories in count)${NC}"
fi
echo ""

# Generate download URL
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Upload Summary${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "${GREEN}Package uploaded successfully!${NC}"
echo ""
echo -e "${BLUE}Bucket details:${NC}"
echo "  Name: ${BUCKET_NAME}"
echo "  Path: gs://${BUCKET_NAME}/${PACKAGE_NAME}/"
echo "  Project: ${PROJECT_ID}"
echo ""

# Get package size
PACKAGE_SIZE=$(gsutil du -s "gs://${BUCKET_NAME}/${PACKAGE_NAME}/" | awk '{print $1}')
PACKAGE_SIZE_GB=$((PACKAGE_SIZE / 1024 / 1024 / 1024))
echo "  Size: ${PACKAGE_SIZE_GB} GB"
echo ""

echo -e "${BLUE}Download instructions:${NC}"
echo ""
echo "1. Authenticate on target machine:"
echo "   gcloud auth login"
echo ""
echo "2. Download package:"
echo "   gsutil -m rsync -r gs://${BUCKET_NAME}/${PACKAGE_NAME}/ ./${PACKAGE_NAME}/"
echo ""
echo "   Or use the download script:"
echo "   ./download-from-gcp.sh ${BUCKET_NAME} ${PACKAGE_NAME}"
echo ""

# Check if manifest exists
if gsutil ls "gs://${BUCKET_NAME}/${PACKAGE_NAME}/manifest.json" &> /dev/null; then
    echo -e "${BLUE}Manifest preview:${NC}"
    gsutil cat "gs://${BUCKET_NAME}/${PACKAGE_NAME}/manifest.json" | head -20
    echo ""
fi

echo -e "${GREEN}✓ Upload complete!${NC}"
