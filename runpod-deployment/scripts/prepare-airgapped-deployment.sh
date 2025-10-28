#!/bin/bash
set -e

# Master Orchestration Script for Airgapped Deployment
# Builds, exports, and uploads complete deployment package
# Usage: ./prepare-airgapped-deployment.sh [OPTIONS]

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default configuration
VERSION="1.0.0"
OUTPUT_DIR="/tmp/rag-deployment"
BUCKET_NAME="rag-deployment-packages"
PROJECT_ID=""
SKIP_BUILD=false
SKIP_EXPORT=false
SKIP_UPLOAD=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -b|--bucket)
            BUCKET_NAME="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT_ID="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --skip-export)
            SKIP_EXPORT=true
            shift
            ;;
        --skip-upload)
            SKIP_UPLOAD=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -v, --version VERSION     Version string (default: 1.0.0)"
            echo "  -o, --output DIR          Output directory (default: /tmp/rag-deployment)"
            echo "  -b, --bucket BUCKET       GCS bucket name (default: rag-deployment-packages)"
            echo "  -p, --project PROJECT_ID  GCP project ID"
            echo "  --skip-build              Skip Docker image building"
            echo "  --skip-export             Skip package export"
            echo "  --skip-upload             Skip GCP upload"
            echo "  -h, --help                Show this help message"
            echo ""
            echo "Examples:"
            echo "  # Full workflow"
            echo "  $0 -v 2.0.0 -p my-gcp-project"
            echo ""
            echo "  # Only build and export (no upload)"
            echo "  $0 --skip-upload"
            echo ""
            echo "  # Only export and upload (images already built)"
            echo "  $0 --skip-build"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}  RAG System - Airgapped Deployment Preparation${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "  Version: ${VERSION}"
echo "  Output: ${OUTPUT_DIR}"
echo "  Bucket: ${BUCKET_NAME}"
[ -n "$PROJECT_ID" ] && echo "  Project: ${PROJECT_ID}"
echo ""
echo -e "${BLUE}Workflow:${NC}"
[ "$SKIP_BUILD" = false ] && echo "  ✓ Build Docker images" || echo "  ⊘ Skip build"
[ "$SKIP_EXPORT" = false ] && echo "  ✓ Export package" || echo "  ⊘ Skip export"
[ "$SKIP_UPLOAD" = false ] && echo "  ✓ Upload to GCP" || echo "  ⊘ Skip upload"
echo ""

read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

START_TIME=$(date +%s)

# Step 1: Build Docker images
if [ "$SKIP_BUILD" = false ]; then
    echo ""
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}  Step 1/3: Building Docker Images${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo ""

    if [ -f "${SCRIPT_DIR}/build-all-complete.sh" ]; then
        "${SCRIPT_DIR}/build-all-complete.sh" "$VERSION"
    else
        echo -e "${RED}Error: build-all-complete.sh not found${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Build complete${NC}"
else
    echo -e "${YELLOW}⊘ Skipping build (--skip-build)${NC}"
fi

# Step 2: Export package
PACKAGE_DIR=""
if [ "$SKIP_EXPORT" = false ]; then
    echo ""
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}  Step 2/3: Exporting Deployment Package${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo ""

    if [ -f "${SCRIPT_DIR}/export-airgapped-package.sh" ]; then
        "${SCRIPT_DIR}/export-airgapped-package.sh" "$OUTPUT_DIR" "$VERSION"

        # Find the generated package directory
        TIMESTAMP=$(date +"%Y%m%d")
        PACKAGE_DIR=$(find "$OUTPUT_DIR" -maxdepth 1 -type d -name "rag-system-deployment_v${VERSION}_${TIMESTAMP}*" | sort -r | head -1)

        if [ -z "$PACKAGE_DIR" ]; then
            echo -e "${RED}Error: Package directory not found${NC}"
            exit 1
        fi

        echo -e "${GREEN}✓ Export complete${NC}"
        echo -e "${GREEN}  Package: ${PACKAGE_DIR}${NC}"
    else
        echo -e "${RED}Error: export-airgapped-package.sh not found${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⊘ Skipping export (--skip-export)${NC}"

    # Try to find existing package
    TIMESTAMP=$(date +"%Y%m%d")
    PACKAGE_DIR=$(find "$OUTPUT_DIR" -maxdepth 1 -type d -name "rag-system-deployment_v${VERSION}_${TIMESTAMP}*" | sort -r | head -1)

    if [ -z "$PACKAGE_DIR" ]; then
        echo -e "${RED}Error: No existing package found for version ${VERSION}${NC}"
        echo "Run without --skip-export to create a new package"
        exit 1
    fi

    echo -e "${BLUE}Using existing package: ${PACKAGE_DIR}${NC}"
fi

# Step 3: Upload to GCP
if [ "$SKIP_UPLOAD" = false ]; then
    echo ""
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}  Step 3/3: Uploading to GCP Bucket${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo ""

    if [ -z "$PACKAGE_DIR" ]; then
        echo -e "${RED}Error: No package directory specified${NC}"
        exit 1
    fi

    if [ -f "${SCRIPT_DIR}/upload-to-gcp.sh" ]; then
        if [ -n "$PROJECT_ID" ]; then
            "${SCRIPT_DIR}/upload-to-gcp.sh" "$PACKAGE_DIR" "$BUCKET_NAME" "$PROJECT_ID"
        else
            "${SCRIPT_DIR}/upload-to-gcp.sh" "$PACKAGE_DIR" "$BUCKET_NAME"
        fi
    else
        echo -e "${RED}Error: upload-to-gcp.sh not found${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Upload complete${NC}"
else
    echo -e "${YELLOW}⊘ Skipping upload (--skip-upload)${NC}"
fi

# Summary
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_MIN=$((DURATION / 60))

echo ""
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}  Deployment Preparation Complete!${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""
echo -e "${GREEN}Summary:${NC}"
[ "$SKIP_BUILD" = false ] && echo "  ✓ Docker images built (version: ${VERSION})"
[ "$SKIP_EXPORT" = false ] && echo "  ✓ Package exported to: ${PACKAGE_DIR}"
[ "$SKIP_UPLOAD" = false ] && echo "  ✓ Package uploaded to: gs://${BUCKET_NAME}/"
echo ""
echo "  Duration: ${DURATION_MIN} minutes (${DURATION} seconds)"
echo ""

if [ "$SKIP_UPLOAD" = false ]; then
    PACKAGE_NAME=$(basename "$PACKAGE_DIR")
    echo -e "${BLUE}Next steps:${NC}"
    echo ""
    echo "1. On airgapped machine, download package:"
    echo "   ./download-from-gcp.sh ${BUCKET_NAME} ${PACKAGE_NAME}"
    echo ""
    echo "2. Import images:"
    echo "   cd ${PACKAGE_NAME}/scripts"
    echo "   ./import-images.sh"
    echo ""
    echo "3. Deploy services:"
    echo "   ./deploy.sh"
    echo ""
    echo "See ${PACKAGE_NAME}/docs/ for detailed documentation"
else
    echo -e "${BLUE}Next steps:${NC}"
    echo ""
    echo "1. Transfer package to airgapped machine:"
    echo "   rsync -avz ${PACKAGE_DIR} user@host:/destination/"
    echo ""
    echo "2. On airgapped machine:"
    echo "   cd ${PACKAGE_DIR}/scripts"
    echo "   ./import-images.sh"
    echo "   ./deploy.sh"
fi
echo ""
echo -e "${GREEN}✓ All done!${NC}"
