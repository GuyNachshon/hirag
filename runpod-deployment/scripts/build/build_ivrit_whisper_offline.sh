#!/bin/bash

# Build Ivrit-AI Whisper service with offline model caching

set -e

echo "=== Building Ivrit-AI Whisper for Offline Use ==="
echo ""

# Clone Ivrit-AI repository
if [ ! -d "ivrit-whisper" ]; then
    echo "Cloning Ivrit-AI RunPod repository..."
    git clone https://github.com/ivrit-ai/runpod-serverless.git ivrit-whisper
fi

cd ivrit-whisper

# Build their image
echo "Building Ivrit-AI Whisper image..."
docker build -t ivrit-whisper-base:latest .

# Run container to cache models
echo "Running container to pre-cache models..."
docker run -d \
    --name ivrit-whisper-cache \
    --gpus all \
    -v $(pwd)/../model-cache:/runpod-volume \
    -e MODEL_NAME=ivrit-ai/whisper-large-v3-ct2 \
    ivrit-whisper-base:latest

# Wait for it to start and cache models
echo "Waiting for model caching (this may take a few minutes)..."
sleep 60

# Test that it works
echo "Testing Whisper service..."
docker logs ivrit-whisper-cache --tail 20

# Stop container
docker stop ivrit-whisper-cache

# Commit the container with cached models
echo "Creating offline image with cached models..."
docker commit ivrit-whisper-cache rag-whisper-ivrit-offline:latest

# Cleanup
docker rm ivrit-whisper-cache

echo ""
echo "✓ Offline Ivrit-AI Whisper image created: rag-whisper-ivrit-offline:latest"
echo ""
echo "To use in offline environment:"
echo "  docker run -d --name rag-whisper --gpus all -p 8004:8000 rag-whisper-ivrit-offline:latest"