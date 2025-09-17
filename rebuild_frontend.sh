#!/bin/bash

# Rebuild frontend Docker image with correct configuration

set -e

echo "=== Rebuilding Frontend Docker Image ==="
echo ""

# Check if we're in the right directory
if [[ ! -d "frontend" ]]; then
    echo "Error: Must run from the root directory (where frontend/ folder exists)"
    exit 1
fi

# Check if dist directory exists
if [[ ! -d "frontend/dist" ]]; then
    echo "Error: frontend/dist directory not found"
    echo "Make sure the frontend is built first"
    exit 1
fi

echo "1. Building new frontend Docker image..."
cd frontend
docker build -f Dockerfile.fixed -t rag-frontend-fixed:latest .
cd ..

echo ""
echo "2. Stopping old frontend container..."
docker stop rag-frontend 2>/dev/null || echo "Container not running"
docker rm rag-frontend 2>/dev/null || echo "Container not found"

echo ""
echo "3. Starting new frontend container with correct configuration..."
docker run -d \
    --name rag-frontend \
    --network rag-network \
    --restart unless-stopped \
    -p 8087:8087 \
    rag-frontend-fixed:latest

echo ""
echo "4. Waiting for container to start..."
sleep 3

echo ""
echo "5. Testing the new frontend..."
if docker ps | grep -q rag-frontend; then
    echo "✓ Container is running"

    # Test internal connectivity
    echo "Testing internal port 8087..."
    docker exec rag-frontend curl -I http://localhost:8087/frontend-health 2>/dev/null | head -5 || echo "Internal test failed"

    echo ""
    echo "✓ Frontend rebuilt and deployed!"
    echo ""
    echo "You can now access it at: http://localhost:8087"
    echo ""
    echo "Test commands:"
    echo "  curl http://localhost:8087/frontend-health"
    echo "  curl http://localhost:8087/api/health"
    echo ""
else
    echo "✗ Container failed to start"
    echo "Check logs: docker logs rag-frontend"
fi

echo ""
echo "=== Frontend Rebuild Complete ==="