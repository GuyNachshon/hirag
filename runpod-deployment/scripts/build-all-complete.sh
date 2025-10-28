#!/bin/bash
set -e

# Build All Docker Images from Scratch
# This script builds all 5 core Docker images needed for airgapped deployment
# Usage: ./build-all-complete.sh [VERSION]

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Version and timestamp
VERSION=${1:-"1.0.0"}
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TAG="${VERSION}_${TIMESTAMP}"

# Project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Building All Docker Images${NC}"
echo -e "${BLUE}  Version: ${VERSION}${NC}"
echo -e "${BLUE}  Tag: ${TAG}${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Track build status
BUILDS_SUCCEEDED=()
BUILDS_FAILED=()

# Function to build and track
build_image() {
    local name=$1
    local dockerfile=$2
    local tag=$3
    local context=${4:-$PROJECT_ROOT}

    echo -e "${YELLOW}Building ${name}...${NC}"
    echo "  Dockerfile: ${dockerfile}"
    echo "  Tag: ${tag}"
    echo "  Context: ${context}"
    echo ""

    if docker build -f "${PROJECT_ROOT}/${dockerfile}" -t "${tag}" "${context}"; then
        echo -e "${GREEN}✓ Successfully built ${name}${NC}"
        BUILDS_SUCCEEDED+=("${name}")

        # Tag with version
        docker tag "${tag}" "${tag%:*}:${TAG}"
        docker tag "${tag}" "${tag%:*}:latest"
        echo -e "${GREEN}  Tagged as: ${tag%:*}:${TAG}${NC}"
        echo -e "${GREEN}  Tagged as: ${tag%:*}:latest${NC}"
    else
        echo -e "${RED}✗ Failed to build ${name}${NC}"
        BUILDS_FAILED+=("${name}")
        return 1
    fi
    echo ""
}

# Build Frontend (Next.js)
echo -e "${BLUE}[1/5] Building Frontend${NC}"
build_image \
    "Frontend" \
    "dockerfiles/Dockerfile.frontend-nextjs" \
    "rag-frontend:latest" \
    "$PROJECT_ROOT"

# Build API (FastAPI)
echo -e "${BLUE}[2/5] Building API${NC}"
build_image \
    "API" \
    "dockerfiles/Dockerfile.api" \
    "rag-api:latest" \
    "$PROJECT_ROOT"

# Build Whisper (Ivrit-AI)
echo -e "${BLUE}[3/5] Building Whisper${NC}"
build_image \
    "Whisper" \
    "dockerfiles/Dockerfile.whisper-official" \
    "rag-whisper:latest" \
    "$PROJECT_ROOT"

# Build LLM (vLLM with Qwen)
echo -e "${BLUE}[4/5] Building LLM${NC}"
build_image \
    "LLM" \
    "dockerfiles/Dockerfile.llm" \
    "rag-llm:latest" \
    "$PROJECT_ROOT"

# Build DotsOCR (Vision LLM)
echo -e "${BLUE}[5/5] Building DotsOCR${NC}"
build_image \
    "DotsOCR" \
    "dockerfiles/Dockerfile.ocr-official" \
    "rag-dots-ocr:latest" \
    "$PROJECT_ROOT"

# Summary
echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Build Summary${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

if [ ${#BUILDS_SUCCEEDED[@]} -gt 0 ]; then
    echo -e "${GREEN}Succeeded (${#BUILDS_SUCCEEDED[@]}):${NC}"
    for build in "${BUILDS_SUCCEEDED[@]}"; do
        echo -e "  ${GREEN}✓${NC} ${build}"
    done
    echo ""
fi

if [ ${#BUILDS_FAILED[@]} -gt 0 ]; then
    echo -e "${RED}Failed (${#BUILDS_FAILED[@]}):${NC}"
    for build in "${BUILDS_FAILED[@]}"; do
        echo -e "  ${RED}✗${NC} ${build}"
    done
    echo ""
    exit 1
fi

echo -e "${GREEN}All images built successfully!${NC}"
echo ""
echo -e "${BLUE}Tagged versions:${NC}"
docker images | grep -E "rag-(frontend|api|whisper|llm|dots-ocr)" | grep -E "(latest|${TAG})"
echo ""
echo -e "${GREEN}Build complete. Version: ${TAG}${NC}"
