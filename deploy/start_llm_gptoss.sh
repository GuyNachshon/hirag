#!/bin/bash

echo "Building and starting gpt-oss LLM server..."

# Build the gpt-oss LLM Docker image
docker build -f deploy/Dockerfile.llm -t rag-llm-gptoss:latest .

# Run the gpt-oss LLM server
docker run -d \
  --name rag-llm-server \
  --gpus all \
  -p 8001:8000 \
  -e TENSOR_PARALLEL=1 \
  -e GPU_MEMORY=0.8 \
  rag-llm-gptoss:latest

echo "gpt-oss LLM server starting on port 8001..."
echo "Container name: rag-llm-server"
echo "Model: openai/gpt-oss-20b"
echo ""
echo "Check logs with: docker logs -f rag-llm-server"
echo "Test health with: curl http://localhost:8001/health"