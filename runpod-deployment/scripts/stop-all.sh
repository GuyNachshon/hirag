#!/bin/bash
# Stop all RAG system services
# Usage: ./stop-all.sh [--remove]

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== RAG System - Stop All Services ===${NC}"
echo ""

REMOVE_CONTAINERS=false
if [ "$1" == "--remove" ]; then
    REMOVE_CONTAINERS=true
    echo "Will remove containers after stopping"
    echo ""
fi

# Stop all containers
echo "Stopping containers..."
docker stop rag-frontend rag-api rag-whisper rag-llm 2>/dev/null || true
echo -e "${GREEN}✓ All containers stopped${NC}"
echo ""

# Remove containers if requested
if [ "$REMOVE_CONTAINERS" = true ]; then
    echo "Removing containers..."
    docker rm rag-frontend rag-api rag-whisper rag-llm 2>/dev/null || true
    echo -e "${GREEN}✓ Containers removed${NC}"
    echo ""
fi

# Show status
echo "Container Status:"
docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep -E "(NAMES|rag-)" || echo "No RAG containers running"
echo ""

if [ "$REMOVE_CONTAINERS" = false ]; then
    echo -e "${YELLOW}To restart:${NC} docker start rag-frontend rag-api rag-whisper rag-llm"
    echo -e "${YELLOW}To remove:${NC}  ./stop-all.sh --remove"
fi
echo ""
