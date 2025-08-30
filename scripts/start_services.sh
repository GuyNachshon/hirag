#!/bin/bash

# Start all services for offline RAG deployment

set -e

echo "🚀 Starting offline RAG services..."

# Set model choices (can be overridden via environment variables)
GPT_OSS_MODEL=${GPT_OSS_MODEL:-"openai/gpt-oss-20b"}
EMBEDDING_MODEL=${EMBEDDING_MODEL:-"Qwen/Qwen3-Embedding-4B"}

echo "🔧 Starting with models:"
echo "   gpt-oss: $GPT_OSS_MODEL" 
echo "   embedding: $EMBEDDING_MODEL"

# Create Docker network
echo "🌐 Creating Docker network..."
docker network create rag-network 2>/dev/null || echo "Network already exists"

# Start DotsOCR server (model embedded in image)
echo "📄 Starting DotsOCR server..."
docker run -d \
  --name rag-dots-ocr \
  --network rag-network \
  --gpus all \
  -p 8002:8000 \
  -v $(pwd)/data:/app/data \
  --restart unless-stopped \
  rag-dots-ocr:latest

# Wait for DotsOCR to start
echo "⏳ Waiting for DotsOCR server to start..."
sleep 30

# Start gpt-oss LLM server (vLLM auto-downloads model)
echo "🧠 Starting gpt-oss LLM server..."
docker run -d \
  --name rag-llm-server \
  --network rag-network \
  --gpus all \
  -p 8000:8000 \
  -e MODEL_NAME="$GPT_OSS_MODEL" \
  -e TENSOR_PARALLEL=1 \
  -e GPU_MEMORY=0.8 \
  --restart unless-stopped \
  rag-llm-server:latest

# Wait for LLM server to start
echo "⏳ Waiting for LLM server to start..."
sleep 30

# Start Embedding server (vLLM auto-downloads model)
echo "🔍 Starting Embedding server..."
docker run -d \
  --name rag-embedding-server \
  --network rag-network \
  --gpus all \
  -p 8001:8000 \
  -e MODEL_NAME="$EMBEDDING_MODEL" \
  --restart unless-stopped \
  rag-embedding-server:latest

# Wait for Embedding server to start
echo "⏳ Waiting for Embedding server to start..."
sleep 30

# Start RAG API server
echo "🔄 Starting RAG API server..."
docker run -d \
  --name rag-api \
  --network rag-network \
  -p 8080:8080 \
  -v $(pwd)/logs:/app/logs \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/HiRAG/config.yaml:/app/HiRAG/config.yaml \
  --restart unless-stopped \
  rag-api:latest

# Wait for API server to start
echo "⏳ Waiting for RAG API server to start..."
sleep 15

echo "✅ All services started!"

# Show service status
echo "📊 Service Status:"
echo "DotsOCR Server: http://localhost:8002"
echo "LLM Server: http://localhost:8000"  
echo "Embedding Server: http://localhost:8001"
echo "RAG API: http://localhost:8080"
echo ""

# Health checks
echo "🏥 Health Checks:"
curl -s http://localhost:8002/health && echo "✅ DotsOCR OK" || echo "❌ DotsOCR Failed"
curl -s http://localhost:8000/health && echo "✅ LLM Server OK" || echo "❌ LLM Server Failed"
curl -s http://localhost:8001/health && echo "✅ Embedding Server OK" || echo "❌ Embedding Server Failed"
curl -s http://localhost:8080/health && echo "✅ RAG API OK" || echo "❌ RAG API Failed"

echo ""
echo "🎉 Deployment complete! Access the API at: http://localhost:8080/docs"