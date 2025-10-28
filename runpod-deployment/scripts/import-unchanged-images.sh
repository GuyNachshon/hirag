#!/bin/bash
set -e

# Import Unchanged Images from Previous Package
# Useful when doing selective builds - imports LLM and OCR from older package
# Usage: ./import-unchanged-images.sh [PACKAGE_DIR] [IMAGES...]

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PACKAGE_DIR=${1:-""}

# Default images to import (unchanged ones)
DEFAULT_IMAGES=("rag-llm:latest" "rag-dots-ocr:latest")

shift || true
IMAGES_TO_IMPORT=("$@")

if [ ${#IMAGES_TO_IMPORT[@]} -eq 0 ]; then
    IMAGES_TO_IMPORT=("${DEFAULT_IMAGES[@]}")
fi

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Import Unchanged Images${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# If no package directory, try to find latest
if [ -z "$PACKAGE_DIR" ]; then
    echo -e "${YELLOW}Searching for existing package...${NC}"

    # Search common locations
    SEARCH_PATHS=(
        "/tmp/rag-deployment/rag-system-deployment_v*"
        "$HOME/rag-system-deployment_v*"
        "./rag-system-deployment_v*"
        "../rag-system-deployment_v*"
    )

    for search_pattern in "${SEARCH_PATHS[@]}"; do
        FOUND=$(ls -d $search_pattern 2>/dev/null | sort -r | head -1 || true)
        if [ -n "$FOUND" ]; then
            PACKAGE_DIR="$FOUND"
            break
        fi
    done

    if [ -z "$PACKAGE_DIR" ]; then
        echo -e "${RED}Error: No package directory found${NC}"
        echo ""
        echo "Usage: $0 <PACKAGE_DIR> [IMAGE_NAMES...]"
        echo ""
        echo "Examples:"
        echo "  # Import default unchanged images (LLM, OCR)"
        echo "  $0 /path/to/rag-system-deployment_v1.0.0_*"
        echo ""
        echo "  # Import specific images"
        echo "  $0 /path/to/package rag-llm:latest rag-dots-ocr:latest"
        exit 1
    fi

    echo -e "${GREEN}Found package: ${PACKAGE_DIR}${NC}"
    echo ""
fi

# Validate package directory
if [ ! -d "$PACKAGE_DIR" ]; then
    echo -e "${RED}Error: Package directory not found: ${PACKAGE_DIR}${NC}"
    exit 1
fi

IMAGES_DIR="${PACKAGE_DIR}/images"
if [ ! -d "$IMAGES_DIR" ]; then
    echo -e "${RED}Error: Images directory not found: ${IMAGES_DIR}${NC}"
    exit 1
fi

echo -e "${BLUE}Package: ${PACKAGE_DIR}${NC}"
echo -e "${BLUE}Images to import:${NC}"
for img in "${IMAGES_TO_IMPORT[@]}"; do
    echo "  • $img"
done
echo ""

# Track imports
IMPORTED=()
SKIPPED=()
FAILED=()

# Import each image
for image in "${IMAGES_TO_IMPORT[@]}"; do
    image_name=$(echo "$image" | cut -d':' -f1)
    image_tag=$(echo "$image" | cut -d':' -f2)
    safe_name=$(echo "$image_name" | sed 's/\//-/g')

    # Check if image already exists
    if docker image inspect "$image" &> /dev/null; then
        echo -e "${YELLOW}Image already exists: ${image}${NC}"
        read -p "Overwrite? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            SKIPPED+=("$image")
            continue
        fi
    fi

    # Find image file
    tar_gz="${IMAGES_DIR}/${safe_name}_${image_tag}.tar.gz"

    if [ ! -f "$tar_gz" ]; then
        echo -e "${RED}✗ Image file not found: ${tar_gz}${NC}"
        FAILED+=("$image")
        continue
    fi

    echo -e "${YELLOW}Importing ${image}...${NC}"
    size=$(stat -f%z "$tar_gz" 2>/dev/null || stat -c%s "$tar_gz" 2>/dev/null)
    size_mb=$((size / 1024 / 1024))
    echo "  File: ${tar_gz}"
    echo "  Size: ${size_mb} MB"

    # Check if file is chunked
    if ls "${tar_gz}.part_"* &> /dev/null; then
        echo "  Reassembling chunked file..."
        cat "${tar_gz}.part_"* > "$tar_gz"
    fi

    # Import
    if gunzip -c "$tar_gz" | docker load; then
        echo -e "${GREEN}✓ Imported ${image}${NC}"
        IMPORTED+=("$image")
    else
        echo -e "${RED}✗ Failed to import ${image}${NC}"
        FAILED+=("$image")
    fi
    echo ""
done

# Summary
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Import Summary${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

if [ ${#IMPORTED[@]} -gt 0 ]; then
    echo -e "${GREEN}Imported (${#IMPORTED[@]}):${NC}"
    for img in "${IMPORTED[@]}"; do
        echo -e "  ${GREEN}✓${NC} ${img}"
    done
    echo ""
fi

if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo -e "${YELLOW}Skipped (${#SKIPPED[@]}):${NC}"
    for img in "${SKIPPED[@]}"; do
        echo -e "  ${YELLOW}⊘${NC} ${img}"
    done
    echo ""
fi

if [ ${#FAILED[@]} -gt 0 ]; then
    echo -e "${RED}Failed (${#FAILED[@]}):${NC}"
    for img in "${FAILED[@]}"; do
        echo -e "  ${RED}✗${NC} ${img}"
    done
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Import complete!${NC}"
echo ""
echo "Available images:"
docker images | grep -E "rag-(llm|dots-ocr)"
echo ""
