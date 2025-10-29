#!/bin/bash
set -e

# Export and Upload to GCP - End-to-End
# Usage: ./export-and-upload.sh [VERSION] [BUCKET_NAME] [PROJECT_ID] [OPTIONS]

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
VERSION=${1:-"1.0.0"}
BUCKET_NAME=${2:-"rag-deployment-packages"}
PROJECT_ID=${3:-""}
OUTPUT_DIR=${OUTPUT_DIR:-"/tmp/rag-deployment"}

# Parse options
SKIP_OCR=false
SKIP_LLM=false

shift 3 2>/dev/null || shift $# || true

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-ocr)
            SKIP_OCR=true
            shift
            ;;
        --skip-llm)
            SKIP_LLM=true
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [VERSION] [BUCKET_NAME] [PROJECT_ID] [OPTIONS]"
            echo ""
            echo "Export Docker images and upload to GCP in one command"
            echo ""
            echo "Arguments:"
            echo "  VERSION        Version string (default: 1.0.0)"
            echo "  BUCKET_NAME    GCS bucket name (default: rag-deployment-packages)"
            echo "  PROJECT_ID     GCP project ID (optional, uses active project if not specified)"
            echo ""
            echo "Options:"
            echo "  --skip-ocr     Skip OCR image (if not available)"
            echo "  --skip-llm     Skip LLM image (if not available)"
            echo "  --output-dir   Output directory (default: /tmp/rag-deployment)"
            echo "  -h, --help     Show this help"
            echo ""
            echo "Environment Variables:"
            echo "  OUTPUT_DIR     Override output directory"
            echo ""
            echo "Examples:"
            echo "  # Full export and upload"
            echo "  $0 1.0.0 rag-deployment-packages my-gcp-project"
            echo ""
            echo "  # Skip OCR image"
            echo "  $0 1.0.0 rag-deployment-packages my-gcp-project --skip-ocr"
            echo ""
            echo "  # Use environment variable for output"
            echo "  OUTPUT_DIR=/mnt/exports $0 1.0.0 rag-deployment-packages"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use -h or --help for usage"
            exit 1
            ;;
    esac
done

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Export and Upload to GCP${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "  Version: ${VERSION}"
echo "  Bucket: ${BUCKET_NAME}"
[ -n "$PROJECT_ID" ] && echo "  Project: ${PROJECT_ID}"
echo "  Output: ${OUTPUT_DIR}"
echo ""

# Determine which images to export
IMAGES=()
IMAGES+=("rag-frontend:latest")
IMAGES+=("rag-api:latest")
IMAGES+=("rag-whisper:latest")

if [ "$SKIP_LLM" = false ]; then
    IMAGES+=("rag-llm:latest")
else
    echo -e "${YELLOW}⊘ Skipping LLM image${NC}"
fi

if [ "$SKIP_OCR" = false ]; then
    IMAGES+=("rag-dots-ocr:latest")
else
    echo -e "${YELLOW}⊘ Skipping OCR image${NC}"
fi

echo -e "${BLUE}Images to export:${NC}"
for img in "${IMAGES[@]}"; do
    echo "  • $img"
done
echo ""

# Verify images exist
echo -e "${YELLOW}Verifying images exist...${NC}"
MISSING_IMAGES=()

for img in "${IMAGES[@]}"; do
    if docker image inspect "$img" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} ${img}"
    else
        echo -e "  ${RED}✗${NC} ${img} (not found)"
        MISSING_IMAGES+=("$img")
    fi
done

if [ ${#MISSING_IMAGES[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}Error: Missing required images${NC}"
    echo "Build missing images or use --skip-ocr / --skip-llm"
    exit 1
fi
echo ""

read -p "Continue with export and upload? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi
echo ""

# ========================================
# PHASE 1: EXPORT
# ========================================

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
PACKAGE_NAME="rag-system-deployment_v${VERSION}_${TIMESTAMP}"
PACKAGE_DIR="${OUTPUT_DIR}/${PACKAGE_NAME}"

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Phase 1: Exporting Images${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

START_TIME=$(date +%s)

# Create package structure
echo -e "${YELLOW}Creating package structure...${NC}"
mkdir -p "${PACKAGE_DIR}"/{images,configs,scripts,docs}
echo -e "${GREEN}✓ Structure created${NC}"
echo ""

# Export each image
echo -e "${BLUE}Exporting Docker images...${NC}"
echo ""

cd "${PACKAGE_DIR}/images"

TOTAL_SIZE=0
IMAGE_NUM=1
TOTAL_IMAGES=${#IMAGES[@]}

for image in "${IMAGES[@]}"; do
    echo -e "${YELLOW}[${IMAGE_NUM}/${TOTAL_IMAGES}] Exporting ${image}...${NC}"

    safe_name=$(echo "$image" | sed 's/\//-/g' | sed 's/:/_/g')
    tar_file="${safe_name}.tar.gz"

    # Export and compress
    if docker save "$image" | gzip > "$tar_file"; then
        size=$(stat -f%z "$tar_file" 2>/dev/null || stat -c%s "$tar_file" 2>/dev/null)
        size_mb=$((size / 1024 / 1024))
        TOTAL_SIZE=$((TOTAL_SIZE + size))
        echo -e "${GREEN}✓ Exported: ${size_mb} MB${NC}"
    else
        echo -e "${RED}✗ Export failed${NC}"
        exit 1
    fi
    echo ""

    IMAGE_NUM=$((IMAGE_NUM + 1))
done

# Generate checksums
echo -e "${YELLOW}Generating checksums...${NC}"
sha256sum *.tar.gz > checksums.sha256
echo -e "${GREEN}✓ Checksums generated${NC}"
echo ""

# Copy configs
cd "$PACKAGE_DIR"
echo -e "${YELLOW}Copying configurations...${NC}"

if [ -d "${PROJECT_ROOT}/configs" ]; then
    cp -r "${PROJECT_ROOT}/configs/"* "${PACKAGE_DIR}/configs/" 2>/dev/null || true
    echo -e "${GREEN}✓ Configs copied${NC}"
fi

# Copy scripts
cp "${SCRIPT_DIR}/../airgapped/import-images.sh" "${PACKAGE_DIR}/scripts/" 2>/dev/null || true
cp "${SCRIPT_DIR}/../airgapped/deploy.sh" "${PACKAGE_DIR}/scripts/" 2>/dev/null || true
echo -e "${GREEN}✓ Scripts copied${NC}"

# Copy docs
if [ -d "${PROJECT_ROOT}/docs" ]; then
    cp "${PROJECT_ROOT}/docs/"*.md "${PACKAGE_DIR}/docs/" 2>/dev/null || true
    echo -e "${GREEN}✓ Docs copied${NC}"
fi
echo ""

# Create manifest
echo -e "${YELLOW}Creating manifest...${NC}"
cat > "${PACKAGE_DIR}/manifest.json" <<EOF
{
  "version": "${VERSION}",
  "timestamp": "${TIMESTAMP}",
  "package_name": "${PACKAGE_NAME}",
  "images": [
$(IFS=,; for i in "${IMAGES[@]}"; do echo "    \"$i\""; done | sed '$ ! s/$/,/')
  ],
  "total_size_bytes": ${TOTAL_SIZE},
  "total_size_gb": $((TOTAL_SIZE / 1024 / 1024 / 1024)),
  "exported_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
echo -e "${GREEN}✓ Manifest created${NC}"
echo ""

# Create README
cat > "${PACKAGE_DIR}/README.md" <<'EOFREADME'
# RAG System Deployment Package

## Quick Start

1. Import images:
   ```bash
   cd scripts/
   ./import-images.sh
   ```

2. Deploy:
   ```bash
   ./deploy.sh
   ```

3. Access: http://YOUR_IP:8087

See docs/ for detailed instructions.
EOFREADME

EXPORT_TIME=$(date +%s)
EXPORT_DURATION=$((EXPORT_TIME - START_TIME))
EXPORT_DURATION_MIN=$((EXPORT_DURATION / 60))
TOTAL_SIZE_GB=$((TOTAL_SIZE / 1024 / 1024 / 1024))

echo -e "${GREEN}✓ Export complete!${NC}"
echo "  Duration: ${EXPORT_DURATION_MIN} minutes"
echo "  Size: ${TOTAL_SIZE_GB} GB"
echo "  Location: ${PACKAGE_DIR}"
echo ""

# ========================================
# PHASE 2: UPLOAD
# ========================================

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Phase 2: Uploading to GCP${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Check gcloud
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: gcloud CLI not found${NC}"
    echo "Package exported to: ${PACKAGE_DIR}"
    echo "Install gcloud to upload, or transfer manually"
    exit 1
fi

if ! command -v gsutil &> /dev/null; then
    echo -e "${RED}Error: gsutil not found${NC}"
    echo "Package exported to: ${PACKAGE_DIR}"
    exit 1
fi

# Check authentication
echo -e "${YELLOW}Checking authentication...${NC}"
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo -e "${YELLOW}Not authenticated. Running gcloud auth login...${NC}"
    gcloud auth login
fi
echo -e "${GREEN}✓ Authenticated${NC}"
echo ""

# Set project
if [ -n "$PROJECT_ID" ]; then
    echo -e "${YELLOW}Setting project: ${PROJECT_ID}${NC}"
    gcloud config set project "$PROJECT_ID"
    echo -e "${GREEN}✓ Project set${NC}"
    echo ""
else
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}Error: No project ID${NC}"
        echo "Package exported to: ${PACKAGE_DIR}"
        echo "Upload manually with: gsutil -m rsync -r ${PACKAGE_DIR} gs://${BUCKET_NAME}/${PACKAGE_NAME}/"
        exit 1
    fi
    echo -e "${BLUE}Using project: ${PROJECT_ID}${NC}"
    echo ""
fi

# Check/create bucket
echo -e "${YELLOW}Checking bucket...${NC}"
if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
    echo -e "${GREEN}✓ Bucket exists${NC}"
else
    echo -e "${YELLOW}Creating bucket in us-central1...${NC}"
    if gsutil mb -p "$PROJECT_ID" -c STANDARD -l us-central1 "gs://${BUCKET_NAME}"; then
        echo -e "${GREEN}✓ Bucket created${NC}"
    else
        echo -e "${RED}✗ Failed to create bucket${NC}"
        exit 1
    fi
fi
echo ""

# Upload
echo -e "${YELLOW}Uploading package...${NC}"
echo "  Source: ${PACKAGE_DIR}"
echo "  Destination: gs://${BUCKET_NAME}/${PACKAGE_NAME}/"
echo ""

UPLOAD_START=$(date +%s)

if gsutil -m rsync -r "$PACKAGE_DIR" "gs://${BUCKET_NAME}/${PACKAGE_NAME}/"; then
    UPLOAD_END=$(date +%s)
    UPLOAD_DURATION=$((UPLOAD_END - UPLOAD_START))
    UPLOAD_DURATION_MIN=$((UPLOAD_DURATION / 60))

    echo ""
    echo -e "${GREEN}✓ Upload complete!${NC}"
    echo "  Duration: ${UPLOAD_DURATION_MIN} minutes"
else
    echo -e "${RED}✗ Upload failed${NC}"
    exit 1
fi
echo ""

# ========================================
# SUMMARY
# ========================================

TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - START_TIME))
TOTAL_DURATION_MIN=$((TOTAL_DURATION / 60))

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Complete!${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "${GREEN}Package: ${PACKAGE_NAME}${NC}"
echo -e "${GREEN}Location: gs://${BUCKET_NAME}/${PACKAGE_NAME}/${NC}"
echo -e "${GREEN}Size: ${TOTAL_SIZE_GB} GB${NC}"
echo ""
echo "  Export: ${EXPORT_DURATION_MIN} min"
echo "  Upload: ${UPLOAD_DURATION_MIN} min"
echo "  Total: ${TOTAL_DURATION_MIN} min"
echo ""

echo -e "${BLUE}Download on target machine:${NC}"
echo "  ./scripts/download-incremental-from-gcp.sh ${BUCKET_NAME} ${PACKAGE_NAME}"
echo ""
echo -e "${BLUE}Or download and deploy:${NC}"
echo "  ./scripts/download-from-gcp.sh ${BUCKET_NAME} ${PACKAGE_NAME}"
echo "  cd ${PACKAGE_NAME}/scripts/"
echo "  ./import-images.sh"
echo "  ./deploy.sh"
echo ""
