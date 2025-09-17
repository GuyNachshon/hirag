#!/bin/bash

# Build frontend with Edge browser compatibility fix

set -e

echo "=== Building Frontend with Edge Compatibility ==="

cd frontend

echo "1. Building Docker image with proper MIME types..."
docker build --platform linux/amd64 -f Dockerfile.edge-fix -t rag-frontend-edge:latest .

echo ""
echo "2. Saving image for transfer..."
docker save -o ../rag-frontend-edge.tar rag-frontend-edge:latest

cd ..

echo ""
echo "3. Image ready: rag-frontend-edge.tar"
echo "   Size: $(du -h rag-frontend-edge.tar | cut -f1)"

echo ""
echo "=== Deployment Instructions ==="
echo ""
echo "Transfer to Ubuntu machine:"
echo "  scp rag-frontend-edge.tar user@ubuntu-machine:~/hirag/"
echo ""
echo "On Ubuntu machine:"
echo "  docker load -i rag-frontend-edge.tar"
echo "  docker stop rag-frontend && docker rm rag-frontend"
echo "  docker run -d \\"
echo "    --name rag-frontend \\"
echo "    --network rag-network \\"
echo "    --restart unless-stopped \\"
echo "    -p 8087:8087 \\"
echo "    rag-frontend-edge:latest"
echo ""
echo "Then clear Edge browser cache (Ctrl+Shift+Delete) and try again!"
echo ""
echo "=== Build Complete ===