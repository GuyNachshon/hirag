#!/bin/bash
# Build all Docker images for RAG system
# Usage: ./build-all.sh [EXTERNAL_IP]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== RAG System - Build All Images ===${NC}"
echo ""

# Get external IP (from argument or auto-detect)
EXTERNAL_IP=${1:-$(curl -s ifconfig.me 2>/dev/null || echo "localhost")}
API_URL="http://${EXTERNAL_IP}:8080"

echo -e "${YELLOW}Configuration:${NC}"
echo "  External IP: $EXTERNAL_IP"
echo "  API URL: $API_URL"
echo ""

# Navigate to base directory
cd "$(dirname "$0")/.."
BASE_DIR=$(pwd)

echo -e "${YELLOW}Base directory: $BASE_DIR${NC}"
echo ""

# Build Frontend
echo -e "${GREEN}[1/4] Building Frontend...${NC}"
cd "$BASE_DIR/source-code/frontend"
docker build \
  --build-arg NEXT_PUBLIC_API_URL=$API_URL \
  -f "$BASE_DIR/dockerfiles/Dockerfile.frontend-nextjs" \
  -t rag-frontend:latest \
  .
echo -e "${GREEN}✓ Frontend built successfully${NC}"
echo ""

# Build API
echo -e "${GREEN}[2/4] Building API...${NC}"
cd "$BASE_DIR"
docker build \
  -f dockerfiles/Dockerfile.api \
  -t rag-api:latest \
  source-code/api/
echo -e "${GREEN}✓ API built successfully${NC}"
echo ""

# Build Whisper
echo -e "${GREEN}[3/4] Building Whisper Service...${NC}"
docker build \
  -f dockerfiles/Dockerfile.whisper \
  -t rag-whisper:latest \
  .
echo -e "${GREEN}✓ Whisper built successfully${NC}"
echo ""

# Pull/Tag LLM
echo -e "${GREEN}[4/4] Pulling LLM Service...${NC}"
docker pull vllm/vllm-openai:latest
docker tag vllm/vllm-openai:latest rag-llm:latest
echo -e "${GREEN}✓ LLM image ready${NC}"
echo ""

# Summary
echo -e "${GREEN}=== Build Complete ===${NC}"
echo ""
echo "Images created:"
docker images | grep -E "(rag-|IMAGE)" | head -5
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Create network: docker network create rag-network"
echo "  2. Create data dirs: mkdir -p /data/{database,uploads,processed}"
echo "  3. Start services: ./scripts/start-all.sh"
echo ""
