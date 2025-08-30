#!/bin/bash

# Build all Docker images for offline RAG deployment

set -e

echo "🔨 Building Docker images for offline RAG deployment..."

# Set model choices (can be overridden via environment variables)
GPT_OSS_MODEL=${GPT_OSS_MODEL:-"openai/gpt-oss-20b"}
EMBEDDING_MODEL=${EMBEDDING_MODEL:-"Qwen/Qwen2-0.5B-Instruct"}

echo "🔧 Building with models:"
echo "   gpt-oss: $GPT_OSS_MODEL" 
echo "   embedding: $EMBEDDING_MODEL"

# Build DotsOCR server image (includes model download)
echo "📦 Building DotsOCR server image..."
docker build -f deploy/Dockerfile.dots-ocr -t rag-dots-ocr:latest .

# Build gpt-oss LLM server image  
echo "📦 Building gpt-oss LLM server image..."
docker build -f deploy/Dockerfile.llm \
    --build-arg GPT_OSS_MODEL=$GPT_OSS_MODEL \
    -t rag-llm-server:latest .

# Build Embedding server image
echo "📦 Building Embedding server image..."
docker build -f deploy/Dockerfile.embedding \
    --build-arg EMBEDDING_MODEL=$EMBEDDING_MODEL \
    -t rag-embedding-server:latest .

# Build RAG API image
echo "📦 Building RAG API image..."
docker build -t rag-api:latest .

echo "✅ All images built successfully!"

# List built images
echo "📋 Built images:"
docker images | grep -E "(rag-|rednotehilab/dots.ocr|vllm/vllm-openai)"

echo ""
echo "🚀 Next steps:"
echo "   Start services: ./scripts/start_services.sh"
echo ""
echo "📝 Note: Models will be downloaded automatically when containers start"
echo "   - DotsOCR model is embedded in the image"
echo "   - gpt-oss and embedding models download on first run"