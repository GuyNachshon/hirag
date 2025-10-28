#!/bin/bash
set -e

# Build Only Changed Docker Images
# Skips LLM and OCR images if not modified
# Usage: ./build-changed-only.sh [VERSION] [OPTIONS]

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

# Parse options
BUILD_FRONTEND=true
BUILD_API=true
BUILD_WHISPER=true
BUILD_LLM=false      # Skip by default (unchanged)
BUILD_OCR=false      # Skip by default (unchanged)

shift || true  # Skip version argument

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            BUILD_LLM=true
            BUILD_OCR=true
            shift
            ;;
        --llm)
            BUILD_LLM=true
            shift
            ;;
        --ocr)
            BUILD_OCR=true
            shift
            ;;
        --skip-frontend)
            BUILD_FRONTEND=false
            shift
            ;;
        --skip-api)
            BUILD_API=false
            shift
            ;;
        --skip-whisper)
            BUILD_WHISPER=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [VERSION] [OPTIONS]"
            echo ""
            echo "Build only modified Docker images (skips LLM and OCR by default)"
            echo ""
            echo "Options:"
            echo "  --all              Build all images including LLM and OCR"
            echo "  --llm              Include LLM image"
            echo "  --ocr              Include OCR image"
            echo "  --skip-frontend    Skip frontend build"
            echo "  --skip-api         Skip API build"
            echo "  --skip-whisper     Skip Whisper build"
            echo "  -h, --help         Show this help"
            echo ""
            echo "Examples:"
            echo "  # Build only changed images (Frontend, API, Whisper)"
            echo "  $0 1.0.0"
            echo ""
            echo "  # Build everything"
            echo "  $0 1.0.0 --all"
            echo ""
            echo "  # Build only API"
            echo "  $0 1.0.0 --skip-frontend --skip-whisper"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use -h or --help for usage"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Building Modified Docker Images${NC}"
echo -e "${BLUE}  Version: ${VERSION}${NC}"
echo -e "${BLUE}  Tag: ${TAG}${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

echo -e "${BLUE}Build Plan:${NC}"
[ "$BUILD_FRONTEND" = true ] && echo -e "  ${GREEN}✓${NC} Frontend" || echo -e "  ${YELLOW}⊘${NC} Frontend (skipped)"
[ "$BUILD_API" = true ] && echo -e "  ${GREEN}✓${NC} API" || echo -e "  ${YELLOW}⊘${NC} API (skipped)"
[ "$BUILD_WHISPER" = true ] && echo -e "  ${GREEN}✓${NC} Whisper" || echo -e "  ${YELLOW}⊘${NC} Whisper (skipped)"
[ "$BUILD_LLM" = true ] && echo -e "  ${GREEN}✓${NC} LLM" || echo -e "  ${YELLOW}⊘${NC} LLM (skipped - unchanged)"
[ "$BUILD_OCR" = true ] && echo -e "  ${GREEN}✓${NC} DotsOCR" || echo -e "  ${YELLOW}⊘${NC} DotsOCR (skipped - unchanged)"
echo ""

read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi
echo ""

# Track build status
BUILDS_SUCCEEDED=()
BUILDS_FAILED=()
BUILDS_SKIPPED=()

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

# Build counter
BUILD_NUM=1
TOTAL_BUILDS=0
[ "$BUILD_FRONTEND" = true ] && TOTAL_BUILDS=$((TOTAL_BUILDS + 1))
[ "$BUILD_API" = true ] && TOTAL_BUILDS=$((TOTAL_BUILDS + 1))
[ "$BUILD_WHISPER" = true ] && TOTAL_BUILDS=$((TOTAL_BUILDS + 1))
[ "$BUILD_LLM" = true ] && TOTAL_BUILDS=$((TOTAL_BUILDS + 1))
[ "$BUILD_OCR" = true ] && TOTAL_BUILDS=$((TOTAL_BUILDS + 1))

# Build Frontend
if [ "$BUILD_FRONTEND" = true ]; then
    echo -e "${BLUE}[${BUILD_NUM}/${TOTAL_BUILDS}] Building Frontend${NC}"
    build_image \
        "Frontend" \
        "dockerfiles/Dockerfile.frontend-nextjs" \
        "rag-frontend:latest" \
        "$PROJECT_ROOT"
    BUILD_NUM=$((BUILD_NUM + 1))
else
    BUILDS_SKIPPED+=("Frontend")
fi

# Build API
if [ "$BUILD_API" = true ]; then
    echo -e "${BLUE}[${BUILD_NUM}/${TOTAL_BUILDS}] Building API${NC}"
    build_image \
        "API" \
        "dockerfiles/Dockerfile.api" \
        "rag-api:latest" \
        "$PROJECT_ROOT"
    BUILD_NUM=$((BUILD_NUM + 1))
else
    BUILDS_SKIPPED+=("API")
fi

# Build Whisper
if [ "$BUILD_WHISPER" = true ]; then
    echo -e "${BLUE}[${BUILD_NUM}/${TOTAL_BUILDS}] Building Whisper${NC}"
    build_image \
        "Whisper" \
        "dockerfiles/Dockerfile.whisper-official" \
        "rag-whisper:latest" \
        "$PROJECT_ROOT"
    BUILD_NUM=$((BUILD_NUM + 1))
else
    BUILDS_SKIPPED+=("Whisper")
fi

# Build LLM (optional)
if [ "$BUILD_LLM" = true ]; then
    echo -e "${BLUE}[${BUILD_NUM}/${TOTAL_BUILDS}] Building LLM${NC}"
    build_image \
        "LLM" \
        "dockerfiles/Dockerfile.llm" \
        "rag-llm:latest" \
        "$PROJECT_ROOT"
    BUILD_NUM=$((BUILD_NUM + 1))
else
    BUILDS_SKIPPED+=("LLM")
fi

# Build DotsOCR (optional)
if [ "$BUILD_OCR" = true ]; then
    echo -e "${BLUE}[${BUILD_NUM}/${TOTAL_BUILDS}] Building DotsOCR${NC}"
    build_image \
        "DotsOCR" \
        "dockerfiles/Dockerfile.ocr-official" \
        "rag-dots-ocr:latest" \
        "$PROJECT_ROOT"
    BUILD_NUM=$((BUILD_NUM + 1))
else
    BUILDS_SKIPPED+=("DotsOCR")
fi

# Summary
echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Build Summary${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

if [ ${#BUILDS_SUCCEEDED[@]} -gt 0 ]; then
    echo -e "${GREEN}Built (${#BUILDS_SUCCEEDED[@]}):${NC}"
    for build in "${BUILDS_SUCCEEDED[@]}"; do
        echo -e "  ${GREEN}✓${NC} ${build}"
    done
    echo ""
fi

if [ ${#BUILDS_SKIPPED[@]} -gt 0 ]; then
    echo -e "${YELLOW}Skipped (${#BUILDS_SKIPPED[@]}):${NC}"
    for build in "${BUILDS_SKIPPED[@]}"; do
        echo -e "  ${YELLOW}⊘${NC} ${build}"
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

# Check if skipped images exist
if [ ${#BUILDS_SKIPPED[@]} -gt 0 ]; then
    echo -e "${YELLOW}Verifying skipped images exist...${NC}"
    MISSING_IMAGES=()

    for build in "${BUILDS_SKIPPED[@]}"; do
        case $build in
            "Frontend")
                image="rag-frontend:latest"
                ;;
            "API")
                image="rag-api:latest"
                ;;
            "Whisper")
                image="rag-whisper:latest"
                ;;
            "LLM")
                image="rag-llm:latest"
                ;;
            "DotsOCR")
                image="rag-dots-ocr:latest"
                ;;
        esac

        if docker image inspect "$image" &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} ${image} exists"
        else
            echo -e "  ${RED}✗${NC} ${image} NOT FOUND"
            MISSING_IMAGES+=("$build")
        fi
    done
    echo ""

    if [ ${#MISSING_IMAGES[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required images that were skipped:${NC}"
        for img in "${MISSING_IMAGES[@]}"; do
            echo -e "  ${RED}✗${NC} ${img}"
        done
        echo ""
        echo "Options:"
        echo "  1. Build missing images: $0 $VERSION --llm --ocr"
        echo "  2. Pull from registry: docker pull <image>"
        echo "  3. Import from previous package"
        exit 1
    fi
fi

echo -e "${GREEN}All images ready!${NC}"
echo ""
echo -e "${BLUE}Available images:${NC}"
docker images | grep -E "rag-(frontend|api|whisper|llm|dots-ocr)" | grep -E "(latest|${TAG})"
echo ""
echo -e "${GREEN}Build complete. Version: ${TAG}${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Export package: ./export-airgapped-package.sh /tmp/rag-deployment ${VERSION}"
echo "  2. Upload to GCP: ./upload-to-gcp.sh /tmp/rag-deployment/rag-system-* <bucket>"
echo ""
