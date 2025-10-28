#!/bin/bash
# Verify RAG system deployment
# Usage: ./verify-deployment.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== RAG System - Deployment Verification ===${NC}"
echo ""

ERRORS=0

# Check Docker network
echo -e "${YELLOW}[1/7] Checking Docker network...${NC}"
if docker network ls | grep -q rag-network; then
    echo -e "${GREEN}✓ rag-network exists${NC}"
else
    echo -e "${RED}✗ rag-network not found${NC}"
    ((ERRORS++))
fi
echo ""

# Check data directories
echo -e "${YELLOW}[2/7] Checking data directories...${NC}"
for dir in /data /data/uploads /data/processed; do
    if [ -d "$dir" ]; then
        echo -e "${GREEN}✓ $dir exists${NC}"
    else
        echo -e "${RED}✗ $dir not found${NC}"
        ((ERRORS++))
    fi
done
echo ""

# Check database
echo -e "${YELLOW}[3/7] Checking database...${NC}"
if [ -f /data/transcriptions.db ]; then
    echo -e "${GREEN}✓ Database file exists${NC}"
    SIZE=$(du -h /data/transcriptions.db | cut -f1)
    echo "  Size: $SIZE"
else
    echo -e "${YELLOW}⚠ Database file not found (will be created on first API startup)${NC}"
fi
echo ""

# Check containers
echo -e "${YELLOW}[4/7] Checking containers...${NC}"
CONTAINERS=("rag-frontend" "rag-api" "rag-whisper" "rag-llm")
for container in "${CONTAINERS[@]}"; do
    if docker ps | grep -q "$container"; then
        STATUS=$(docker ps --filter "name=$container" --format "{{.Status}}")
        echo -e "${GREEN}✓ $container is running${NC} ($STATUS)"
    else
        echo -e "${RED}✗ $container is not running${NC}"
        ((ERRORS++))
    fi
done
echo ""

# Check service health
echo -e "${YELLOW}[5/7] Checking service health...${NC}"

# API
if curl -s -f http://localhost:8080/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ API service is healthy${NC}"
else
    echo -e "${RED}✗ API service not responding${NC}"
    ((ERRORS++))
fi

# Whisper
if curl -s -f http://localhost:8004/health > /dev/null 2>&1; then
    RESPONSE=$(curl -s http://localhost:8004/health)
    echo -e "${GREEN}✓ Whisper service is healthy${NC}"
    echo "  $RESPONSE"
else
    echo -e "${RED}✗ Whisper service not responding${NC}"
    ((ERRORS++))
fi

# LLM
if curl -s -f http://localhost:8000/v1/models > /dev/null 2>&1; then
    MODEL_COUNT=$(curl -s http://localhost:8000/v1/models | grep -o '"id"' | wc -l)
    echo -e "${GREEN}✓ LLM service is healthy${NC}"
    echo "  Models loaded: $MODEL_COUNT"
else
    echo -e "${YELLOW}⚠ LLM service not ready (may still be loading model)${NC}"
    echo "  Check logs: docker logs rag-llm"
fi

# Frontend
if curl -s -I http://localhost:8087 | head -n 1 | grep -q "200\|301\|302"; then
    echo -e "${GREEN}✓ Frontend is accessible${NC}"
else
    echo -e "${RED}✗ Frontend not responding${NC}"
    ((ERRORS++))
fi
echo ""

# Check GPU availability
echo -e "${YELLOW}[6/7] Checking GPU access...${NC}"
if command -v nvidia-smi &> /dev/null; then
    GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | wc -l)
    echo -e "${GREEN}✓ NVIDIA drivers installed${NC}"
    echo "  Available GPUs: $GPU_COUNT"

    # Check GPU usage by containers
    echo ""
    echo "  GPU Usage:"
    nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null | head -5 || echo "  No GPU processes detected"
else
    echo -e "${RED}✗ NVIDIA drivers not found${NC}"
    ((ERRORS++))
fi
echo ""

# Check ports
echo -e "${YELLOW}[7/7] Checking port bindings...${NC}"
PORTS=("8087" "8080" "8004" "8000")
PORT_NAMES=("Frontend" "API" "Whisper" "LLM")
for i in "${!PORTS[@]}"; do
    PORT="${PORTS[$i]}"
    NAME="${PORT_NAMES[$i]}"
    if netstat -tuln 2>/dev/null | grep -q ":$PORT " || ss -tuln 2>/dev/null | grep -q ":$PORT "; then
        echo -e "${GREEN}✓ Port $PORT is bound${NC} ($NAME)"
    else
        echo -e "${RED}✗ Port $PORT is not bound${NC} ($NAME)"
        ((ERRORS++))
    fi
done
echo ""

# Summary
echo -e "${GREEN}=== Verification Summary ===${NC}"
echo ""
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! System is ready.${NC}"
    echo ""
    EXTERNAL_IP=$(curl -s ifconfig.me 2>/dev/null || echo "localhost")
    echo -e "${YELLOW}Access the system:${NC}"
    echo "  • Frontend: http://${EXTERNAL_IP}:8087"
    echo "  • API:      http://${EXTERNAL_IP}:8080"
    echo "  • API Docs: http://${EXTERNAL_IP}:8080/docs"
    echo ""
    echo -e "${YELLOW}Monitor logs:${NC}"
    echo "  docker logs -f rag-api"
    echo "  docker logs -f rag-whisper"
    echo "  docker logs -f rag-llm"
else
    echo -e "${RED}✗ Found $ERRORS error(s). Please check the output above.${NC}"
    echo ""
    echo -e "${YELLOW}Common fixes:${NC}"
    echo "  • Run: ./scripts/start-all.sh"
    echo "  • Check logs: docker logs <container-name>"
    echo "  • Verify GPU: nvidia-smi"
    echo "  • Check network: docker network inspect rag-network"
fi
echo ""

exit $ERRORS
