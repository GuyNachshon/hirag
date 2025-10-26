#!/bin/bash
set -e

echo "=== Building Production Langflow with HiRAG Integration ==="
echo ""

cd "$(dirname "$0")"

# Build the image
echo "Building Docker image..."
docker build \
  -f dockerfiles/Dockerfile.langflow-production \
  -t rag-langflow-production:latest \
  --progress=plain \
  .

echo ""
echo "✓ Build complete!"
echo ""

# Ask if user wants to deploy
read -p "Deploy Langflow now? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Creating Docker network (if not exists)..."
    docker network create rag-network 2>/dev/null || echo "Network already exists"

    echo ""
    echo "Stopping existing Langflow container (if running)..."
    docker stop rag-langflow 2>/dev/null || true
    docker rm rag-langflow 2>/dev/null || true

    echo ""
    echo "Creating data directory for persistence..."
    mkdir -p $(pwd)/langflow-data

    echo ""
    echo "Starting Langflow..."
    docker run -d \
      --name rag-langflow \
      --network rag-network \
      -p 7860:7860 \
      -v $(pwd)/langflow-data:/app/langflow/data \
      -e VLLM_BASE_URL=http://hirag-llm:8000/v1 \
      -e HIRAG_WHISPER_URL=http://rag-whisper:8004 \
      -e HIRAG_API_URL=http://rag-api:8080 \
      rag-langflow-production:latest

    echo ""
    echo "Connecting existing services to network..."
    docker network connect rag-network rag-whisper 2>/dev/null || echo "Whisper already connected or not running"

    echo ""
    echo "Waiting for Langflow to start..."
    sleep 10

    echo ""
    echo "✓ Deployment complete!"
    echo ""
    echo "=== Access Langflow ==="
    echo "URL: http://localhost:7860"
    echo ""
    echo "=== View Logs ==="
    echo "docker logs -f rag-langflow"
    echo ""
    echo "=== Custom Components Available ==="
    echo "  - vLLM Chat (your LLM)"
    echo "  - Whisper with Diarization"
    echo "  - HiRAG Search"
    echo ""
    echo "=== Data Persistence ==="
    echo "Flows saved to: $(pwd)/langflow-data"
    echo ""
fi

echo "Done!"
