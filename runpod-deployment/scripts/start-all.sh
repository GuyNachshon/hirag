#!/bin/bash
# Start all RAG system services
# Usage: ./start-all.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== RAG System - Start All Services ===${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check if network exists
if ! docker network ls | grep -q rag-network; then
    echo "Creating Docker network..."
    docker network create rag-network
fi

# Check if data directories exist
if [ ! -d /data ]; then
    echo "Creating data directories..."
    mkdir -p /data/{uploads,processed}
fi

# Get external IP for CORS
EXTERNAL_IP=${EXTERNAL_IP:-$(curl -s ifconfig.me 2>/dev/null || echo "localhost")}
echo "External IP: $EXTERNAL_IP"
echo ""

# Database will be automatically initialized by the API on first startup
# at /data/transcriptions.db through the volume mount

# Start LLM Service
echo -e "${GREEN}[1/4] Starting LLM Service...${NC}"
if docker ps -a | grep -q rag-llm; then
    echo "Stopping existing rag-llm container..."
    docker stop rag-llm 2>/dev/null || true
    docker rm rag-llm 2>/dev/null || true
fi

docker run -d \
  --name rag-llm \
  --network rag-network \
  --gpus '"device=0,1"' \
  -p 8000:8000 \
  -v /data/models:/root/.cache/huggingface \
  --restart unless-stopped \
  rag-llm:latest \
  --model Qwen/Qwen2.5-7B-Instruct \
  --host 0.0.0.0 \
  --port 8000 \
  --tensor-parallel-size 2 \
  --gpu-memory-utilization 0.9 \
  --max-model-len 8192 \
  --trust-remote-code

echo -e "${GREEN}✓ LLM service started (loading model in background...)${NC}"
echo ""

# Start Whisper Service
echo -e "${GREEN}[2/4] Starting Whisper Service...${NC}"
if docker ps -a | grep -q rag-whisper; then
    echo "Stopping existing rag-whisper container..."
    docker stop rag-whisper 2>/dev/null || true
    docker rm rag-whisper 2>/dev/null || true
fi

docker run -d \
  --name rag-whisper \
  --network rag-network \
  --gpus '"device=2"' \
  -p 8004:8004 \
  -v /data/whisper-models:/root/.cache/huggingface \
  -e MODEL_NAME=ivrit-ai/whisper-large-v3-turbo-ct2 \
  -e DEVICE=cuda \
  -e HF_HUB_OFFLINE=1 \
  --restart unless-stopped \
  rag-whisper:latest

echo -e "${GREEN}✓ Whisper service started${NC}"
echo ""

# Wait a moment for Whisper to initialize
echo "Waiting for Whisper to be ready..."
sleep 5

# Start API Service
echo -e "${GREEN}[3/4] Starting API Service...${NC}"
if docker ps -a | grep -q rag-api; then
    echo "Stopping existing rag-api container..."
    docker stop rag-api 2>/dev/null || true
    docker rm rag-api 2>/dev/null || true
fi

docker run -d \
  --name rag-api \
  --network rag-network \
  -p 8080:8080 \
  -v /data:/app/data \
  -e WHISPER_SERVICE_URL=http://rag-whisper:8004 \
  -e LLM_SERVICE_URL=http://rag-llm:8000 \
  -e CORS_ORIGINS="http://localhost:3000,http://localhost:8087,http://${EXTERNAL_IP}:8087,http://${EXTERNAL_IP}:3000" \
  --restart unless-stopped \
  rag-api:latest

echo -e "${GREEN}✓ API service started${NC}"
echo ""

# Start Frontend
echo -e "${GREEN}[4/4] Starting Frontend...${NC}"
if docker ps -a | grep -q rag-frontend; then
    echo "Stopping existing rag-frontend container..."
    docker stop rag-frontend 2>/dev/null || true
    docker rm rag-frontend 2>/dev/null || true
fi

docker run -d \
  --name rag-frontend \
  --network rag-network \
  -p 8087:3000 \
  --restart unless-stopped \
  rag-frontend:latest

echo -e "${GREEN}✓ Frontend started${NC}"
echo ""

# Summary
echo -e "${GREEN}=== All Services Started ===${NC}"
echo ""
echo "Container Status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(NAMES|rag-)"
echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo "  • LLM service is loading the model (may take 5-10 minutes)"
echo "  • Check logs with: docker logs -f <container-name>"
echo "  • Verify deployment: ./scripts/verify-deployment.sh"
echo ""
echo -e "${YELLOW}Access the system:${NC}"
echo "  • Frontend: http://${EXTERNAL_IP}:8087"
echo "  • API:      http://${EXTERNAL_IP}:8080"
echo "  • API Docs: http://${EXTERNAL_IP}:8080/docs"
echo ""
