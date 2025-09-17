#!/bin/bash

# Build frontend Docker image locally and prepare for transfer

set -e

echo "=== Building Frontend Docker Image Locally ==="
echo ""

# Check if we're in the right directory
if [[ ! -d "frontend" ]]; then
    echo "Error: Must run from the root directory (where frontend/ folder exists)"
    exit 1
fi

# Check if dist directory exists
if [[ ! -d "frontend/dist" ]]; then
    echo "Error: frontend/dist directory not found"
    echo "The frontend needs to be built first"
    echo ""
    echo "If you have the frontend source, run:"
    echo "  cd frontend && npm install && npm run build"
    exit 1
fi

echo "1. Building frontend Docker image..."
cd frontend

# Build the Docker image
docker build -f Dockerfile.fixed -t rag-frontend-fixed:latest .
echo "✓ Docker image built successfully"

cd ..

echo ""
echo "2. Saving Docker image to tar file..."
docker save -o rag-frontend-fixed.tar rag-frontend-fixed:latest
echo "✓ Image saved to rag-frontend-fixed.tar"

echo ""
echo "3. Image info:"
echo "Size: $(du -h rag-frontend-fixed.tar | cut -f1)"
echo "Image: rag-frontend-fixed:latest"

echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Transfer the image to your remote machine:"
echo "   scp rag-frontend-fixed.tar user@remote-machine:~/hirag/"
echo ""
echo "2. On the remote machine, load and deploy:"
echo "   cd ~/hirag"
echo "   docker load -i rag-frontend-fixed.tar"
echo "   docker stop rag-frontend 2>/dev/null || true"
echo "   docker rm rag-frontend 2>/dev/null || true"
echo "   docker run -d \\"
echo "     --name rag-frontend \\"
echo "     --network rag-network \\"
echo "     --restart unless-stopped \\"
echo "     -p 8087:8087 \\"
echo "     rag-frontend-fixed:latest"
echo ""
echo "3. Test the deployment:"
echo "   curl http://localhost:8087/frontend-health"
echo "   # Then access http://localhost:8087 in browser"
echo ""

# Create a deployment script for the remote machine
cat > deploy_frontend_image.sh << 'EOF'
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
EOF

chmod +x deploy_frontend_image.sh

echo "4. Created deployment script: deploy_frontend_image.sh"
echo "   Transfer this script along with the tar file to your remote machine"

echo ""
echo "=== Build Complete ==="