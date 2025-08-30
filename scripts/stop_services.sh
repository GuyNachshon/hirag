#!/bin/bash

# Stop all RAG services

echo "🛑 Stopping offline RAG services..."

# Stop containers
docker stop rag-api rag-embedding-server rag-llm-server rag-dots-ocr 2>/dev/null || true

# Remove containers
docker rm rag-api rag-embedding-server rag-llm-server rag-dots-ocr 2>/dev/null || true

# Remove network
docker network rm rag-network 2>/dev/null || true

echo "✅ All services stopped and cleaned up!"