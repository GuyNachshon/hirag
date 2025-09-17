#!/bin/bash

# Setup frontend with Langflow proxy

echo "=== Setting up Frontend with Langflow Endpoint ==="
echo ""

# Get Langflow connection details
echo "How is Langflow running? Choose an option:"
echo "1) Langflow container on same Docker network (container name: langflow)"
echo "2) Langflow on host machine (localhost:7860)"
echo "3) Langflow on remote machine (specify IP:PORT)"
echo ""
read -p "Enter choice (1-3): " choice

case $choice in
    1)
        LANGFLOW_UPSTREAM="http://langflow:7860/"
        echo "Using Docker network: $LANGFLOW_UPSTREAM"
        ;;
    2)
        LANGFLOW_UPSTREAM="http://host.docker.internal:7860/"
        echo "Using host machine: $LANGFLOW_UPSTREAM"
        ;;
    3)
        read -p "Enter Langflow IP:PORT (e.g., 192.168.1.100:7860): " langflow_addr
        LANGFLOW_UPSTREAM="http://$langflow_addr/"
        echo "Using custom address: $LANGFLOW_UPSTREAM"
        ;;
    *)
        echo "Invalid choice, using host machine default"
        LANGFLOW_UPSTREAM="http://host.docker.internal:7860/"
        ;;
esac

echo ""
echo "Creating custom Dockerfile with Langflow proxy..."

# Create custom Dockerfile with the correct upstream
sed "s|proxy_pass http://host.docker.internal:7860/;|proxy_pass $LANGFLOW_UPSTREAM;|g" \
    frontend/Dockerfile.with-langflow > frontend/Dockerfile.custom

echo ""
echo "Building frontend with Langflow support..."
cd frontend
docker build -f Dockerfile.custom -t rag-frontend-langflow:latest .
cd ..

echo ""
echo "Deploying updated frontend..."
docker stop rag-frontend 2>/dev/null || true
docker rm rag-frontend 2>/dev/null || true

docker run -d \
    --name rag-frontend \
    --network rag-network \
    --restart unless-stopped \
    -p 8087:8087 \
    rag-frontend-langflow:latest

# If using host.docker.internal, add the extra host
if [[ $LANGFLOW_UPSTREAM == *"host.docker.internal"* ]]; then
    docker stop rag-frontend
    docker rm rag-frontend
    docker run -d \
        --name rag-frontend \
        --network rag-network \
        --restart unless-stopped \
        --add-host=host.docker.internal:host-gateway \
        -p 8087:8087 \
        rag-frontend-langflow:latest
fi

echo ""
echo "Waiting for startup..."
sleep 3

echo ""
echo "=== Testing Frontend with Langflow ==="

# Test endpoints
echo "Testing frontend health..."
curl -s http://localhost:8087/frontend-health || echo "Frontend health failed"

echo ""
echo "Testing Langflow proxy..."
curl -I http://localhost:8087/langflow/ 2>&1 | head -5 || echo "Langflow proxy test failed"

echo ""
echo "=== Results ==="
if docker ps | grep -q rag-frontend; then
    echo "✓ Frontend deployed with Langflow support"
    echo ""
    echo "Available endpoints:"
    echo "  Frontend UI:  http://localhost:8087/"
    echo "  RAG API:      http://localhost:8087/api/"
    echo "  Langflow:     http://localhost:8087/langflow/"
    echo ""
    echo "From your frontend JavaScript, you can now make requests to:"
    echo "  fetch('/langflow/api/v1/flows')  // List flows"
    echo "  fetch('/langflow/api/v1/run')    // Execute flow"
    echo ""
else
    echo "✗ Frontend deployment failed"
    echo "Check logs: docker logs rag-frontend"
fi

# Cleanup
rm -f frontend/Dockerfile.custom

echo ""
echo "=== Setup Complete ==="