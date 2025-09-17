#!/bin/bash

# Deploy the transferred frontend image

set -e

echo "=== Deploying Frontend Image ==="

# Check if the tar file exists
if [[ ! -f "rag-frontend-fixed.tar" ]]; then
    echo "Error: rag-frontend-fixed.tar not found"
    echo "Make sure you transferred the file to this directory"
    exit 1
fi

echo "1. Loading Docker image..."
docker load -i rag-frontend-fixed.tar

echo ""
echo "2. Stopping old frontend..."
docker stop rag-frontend 2>/dev/null || echo "Container not running"
docker rm rag-frontend 2>/dev/null || echo "Container not found"

echo ""
echo "3. Starting new frontend container..."
docker run -d \
    --name rag-frontend \
    --network rag-network \
    --restart unless-stopped \
    -p 8087:8087 \
    rag-frontend-fixed:latest

echo ""
echo "4. Testing deployment..."
sleep 3

if docker ps | grep -q rag-frontend; then
    echo "✓ Frontend container is running"

    # Test health endpoint
    echo "Testing health endpoint..."
    curl -s http://localhost:8087/frontend-health || echo "Health check failed"

    echo ""
    echo "✓ Frontend deployed successfully!"
    echo "Access it at: http://localhost:8087"
else
    echo "✗ Frontend container failed to start"
    echo "Check logs: docker logs rag-frontend"
fi

echo ""
echo "=== Deployment Complete ==="
