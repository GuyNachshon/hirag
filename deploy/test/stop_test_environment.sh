#!/bin/bash

echo "Stopping test environment..."

# Stop and remove test containers
TEST_CONTAINERS=(
    "rag-test-llm"
    "rag-test-embedding"
    "rag-test-ocr"
    "rag-test-api"
    "rag-test-frontend"
)

for container in "${TEST_CONTAINERS[@]}"; do
    if docker ps -a | grep -q "$container"; then
        echo "Stopping $container..."
        docker stop "$container" 2>/dev/null || true
        docker rm "$container" 2>/dev/null || true
    fi
done

# Remove test network
if docker network ls | grep -q "rag-test-network"; then
    echo "Removing test network..."
    docker network rm rag-test-network 2>/dev/null || true
fi

# Clean up test data
if [[ -d "test-data" ]]; then
    echo "Cleaning test data..."
    rm -rf test-data
fi

if [[ -d "test-config" ]]; then
    echo "Cleaning test config..."
    rm -rf test-config
fi

echo "Test environment stopped and cleaned up."