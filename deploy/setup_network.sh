#!/bin/bash

echo "Setting up Docker network for RAG system..."

# Create custom Docker network for inter-service communication
NETWORK_NAME="rag-network"

# Check if network already exists
if docker network ls | grep -q "$NETWORK_NAME"; then
    echo "Network $NETWORK_NAME already exists"
else
    echo "Creating Docker network: $NETWORK_NAME"
    docker network create --driver bridge "$NETWORK_NAME"
    echo "Network created successfully"
fi

# List networks for verification
echo "Current Docker networks:"
docker network ls

echo "Network setup complete!"