#!/bin/bash

# Build and test frontend in standalone mode (no API dependency)

set -e

echo "=== Building Standalone Frontend for Testing ==="

cd frontend

# Stop and remove any existing container
docker stop rag-frontend 2>/dev/null || true
docker rm rag-frontend 2>/dev/null || true

# Build standalone version
echo "Building standalone frontend image..."
docker build -f Dockerfile.standalone -t rag-frontend-standalone:latest .

echo ""
echo "Starting standalone frontend..."
docker run -d \
    --name rag-frontend \
    --restart unless-stopped \
    -p 8099:8087 \
    rag-frontend-standalone:latest

cd ..

echo ""
echo "Waiting for startup..."
sleep 3

echo ""
echo "=== Testing Frontend ==="

# Test health endpoint
echo "Testing health endpoint..."
curl -s http://localhost:8099/frontend-health || echo "Health test failed"

echo ""
echo "Testing mock API..."
curl -s http://localhost:8099/api/test || echo "API test failed"

echo ""
echo "Testing main page..."
curl -I http://localhost:8099/ | head -5

echo ""
echo "=== Results ==="
if docker ps | grep -q rag-frontend; then
    echo "✓ Frontend is running in standalone mode"
    echo "✓ Access it at: http://localhost:8099"
    echo ""
    echo "Features:"
    echo "  - Static files served with correct MIME types"
    echo "  - SPA routing (fallback to index.html)"
    echo "  - Mock API responses for /api/* requests"
    echo "  - No dependency on rag-api service"
    echo ""
    echo "This tests the frontend UI without needing the backend services."
else
    echo "✗ Frontend failed to start"
    echo "Check logs: docker logs rag-frontend"
fi