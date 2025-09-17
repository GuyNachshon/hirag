#!/bin/bash

# Quick fix for frontend container networking issue

echo "=== Quick Frontend Fix ==="

# First, check if rag-api is running and on which network
echo "Checking rag-api status..."
docker inspect rag-api --format='{{.NetworkSettings.Networks}}' 2>/dev/null || echo "rag-api not found"

# Stop any existing frontend container
echo "Stopping any existing frontend..."
docker stop rag-frontend 2>/dev/null || true
docker rm rag-frontend 2>/dev/null || true

# Run frontend with proper network configuration
echo "Starting frontend with correct network settings..."
docker run -d \
    --name rag-frontend \
    --network rag-network \
    --restart unless-stopped \
    -p 3000:3000 \
    rag-frontend:latest

# Wait a moment
sleep 3

# Check if it started correctly
if docker ps | grep -q rag-frontend; then
    echo "✓ Frontend started"
    
    # Check logs for errors
    if docker logs rag-frontend 2>&1 | grep -q "host not found in upstream"; then
        echo "✗ Still having upstream error. Checking network..."
        
        # Debug network
        echo "--- Network Debug ---"
        echo "Containers on rag-network:"
        docker network inspect rag-network --format='{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "Network not found"
        
        echo ""
        echo "Try creating network if missing:"
        echo "  docker network create rag-network"
        
        echo ""
        echo "Make sure rag-api is on the same network:"
        echo "  docker network connect rag-network rag-api"
    else
        echo "✓ Frontend running without upstream errors"
    fi
else
    echo "✗ Frontend failed to start"
fi

echo ""
echo "=== Debug Commands ==="
echo "Check frontend logs:  docker logs rag-frontend"
echo "Check API network:    docker inspect rag-api | grep -A5 Networks"
echo "List network members: docker network inspect rag-network"