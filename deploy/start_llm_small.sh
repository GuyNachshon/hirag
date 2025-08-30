#!/bin/bash

echo "Building and starting small LLM server..."

# Build the small LLM Docker image
docker build -f deploy/Dockerfile.llm-small -t rag-llm-small:latest .

# Run the small LLM server
docker run -d \
  --name rag-llm-server \
  --gpus all \
  -p 8001:8000 \
  -e TENSOR_PARALLEL=1 \
  -e GPU_MEMORY=0.3 \
  rag-llm-small:latest

echo "Small LLM server starting on port 8001..."
echo "Container name: rag-llm-server"
echo "Model: Qwen/Qwen3-4B-Thinking-2507"
echo ""
echo "Check logs with: docker logs -f rag-llm-server"
echo "Test health with: curl http://localhost:8001/health"