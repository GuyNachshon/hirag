#!/bin/bash

# Build complete offline RAG system with Langflow integration

set -e

echo "=== Building Complete Offline RAG System ==="
echo ""

# Check prerequisites
if [[ ! -d "frontend/dist" ]]; then
    echo "Error: frontend/dist not found. Build frontend first."
    exit 1
fi

if [[ ! -f "docker-compose.offline.yml" ]]; then
    echo "Error: docker-compose.offline.yml not found"
    exit 1
fi

echo "1. Creating model-cache directory..."
mkdir -p model-cache

echo ""
echo "2. Building all services..."

# Build Langflow
echo "Building Langflow container..."
docker build -t rag-langflow:latest ./langflow/

# Build complete frontend
echo "Building frontend with all endpoints..."
docker build -f frontend/Dockerfile.complete -t rag-frontend-complete:latest ./frontend/

echo ""
echo "3. Testing the complete system..."
docker-compose -f docker-compose.offline.yml down 2>/dev/null || true

# Start with docker-compose
echo "Starting all services..."
docker-compose -f docker-compose.offline.yml up -d

echo ""
echo "4. Waiting for services to start..."
sleep 30

echo ""
echo "5. Testing endpoints..."

# Test frontend
echo "Testing frontend..."
curl -s http://localhost:8087/frontend-health || echo "Frontend test failed"

# Test Langflow
echo "Testing Langflow..."
curl -s http://localhost:8087/langflow/health || echo "Langflow test failed"

# Test API
echo "Testing RAG API..."
curl -s http://localhost:8087/api/health || echo "API test failed"

echo ""
echo "=== System Status ==="
docker-compose -f docker-compose.offline.yml ps

echo ""
echo "=== Available Endpoints ==="
echo "🌐 Frontend UI:       http://localhost:8087/"
echo "🤖 RAG API:           http://localhost:8087/api/"
echo "⚡ Langflow:          http://localhost:8087/langflow/"
echo "📝 Embedding:         http://localhost:8087/embedding/"
echo "🧠 LLM:               http://localhost:8087/llm/"
echo "🎤 Whisper:           http://localhost:8087/whisper/"
echo "👁️ OCR:                http://localhost:8087/ocr/"

echo ""
echo "=== JavaScript Integration Examples ==="
cat << 'EOF'

// RAG API calls
fetch('/api/search', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({query: 'your question'})
})

// Langflow integration
fetch('/langflow/api/v1/flows').then(r => r.json()).then(console.log)

fetch('/langflow/api/v1/run/flow-id', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({input_value: 'your input'})
})

// Direct service access
fetch('/embedding/v1/embeddings', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({input: 'text to embed'})
})

EOF

echo ""
echo "=== Package for Offline Deployment ==="
echo "To package this system for offline deployment:"
echo ""
echo "1. Save all images:"
echo "   docker-compose -f docker-compose.offline.yml config --services | xargs -I {} docker save -o {}.tar {}:latest"
echo ""
echo "2. Create deployment package:"
echo "   tar -czf rag-system-offline.tar.gz *.tar docker-compose.offline.yml model-cache/"
echo ""
echo "3. Transfer to offline machine and load:"
echo "   tar -xzf rag-system-offline.tar.gz"
echo "   ls *.tar | xargs -I {} docker load -i {}"
echo "   docker-compose -f docker-compose.offline.yml up -d"
echo ""

echo "=== Build Complete ==="