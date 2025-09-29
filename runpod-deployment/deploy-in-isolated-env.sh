#!/bin/bash
set -e

# Configuration
WORKSPACE_DIR="/root/workspace"  # Adjust if different

echo "========================================="
echo "Deploy in Isolated Environment"
echo "========================================="
echo ""
echo "This script will:"
echo "  - Load new API and Frontend images"
echo "  - Restart API and Frontend containers"
echo "  - Hot-patch Whisper service (NO rebuild)"
echo "  - Apply config fixes"
echo "  - Verify all services"
echo ""
echo "Existing LLM and Whisper containers will be reused."
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Step 1: Load Docker images
echo ""
echo "[1/6] Loading Docker images..."
if [ -f "rag-api.tar" ]; then
    echo "Loading API image..."
    docker load -i rag-api.tar
else
    echo "ERROR: rag-api.tar not found!"
    exit 1
fi

if [ -f "rag-frontend.tar" ]; then
    echo "Loading Frontend image..."
    docker load -i rag-frontend.tar
else
    echo "ERROR: rag-frontend.tar not found!"
    exit 1
fi

# Step 2: Stop and remove old API container
echo ""
echo "[2/6] Restarting API container..."
if docker ps -a | grep -q rag-api; then
    echo "Stopping and removing old API container..."
    docker stop rag-api || true
    docker rm rag-api || true
fi

echo "Starting new API container..."
docker run -d \
  --name rag-api \
  --network hirag-network \
  -p 8080:8000 \
  -v ${WORKSPACE_DIR}:/data \
  rag-api:latest

echo "Waiting for API to initialize..."
sleep 10

# Step 3: Hot-patch Whisper service
echo ""
echo "[3/6] Hot-patching Whisper service..."
if [ -f "whisper_fastapi_service.py" ]; then
    if docker ps | grep -q rag-whisper; then
        echo "Copying fixed Whisper service file..."
        docker cp whisper_fastapi_service.py rag-whisper:/app/whisper_fastapi_service.py

        echo "Restarting Whisper container..."
        docker restart rag-whisper

        echo "Waiting for Whisper to start..."
        sleep 5
    else
        echo "WARNING: rag-whisper container not found. Skipping hot-patch."
    fi
else
    echo "WARNING: whisper_fastapi_service.py not found. Skipping hot-patch."
fi

# Step 4: Apply config fixes
echo ""
echo "[4/6] Applying configuration fixes..."
if [ -f "config-fixes.sh" ]; then
    chmod +x config-fixes.sh
    ./config-fixes.sh
else
    echo "WARNING: config-fixes.sh not found. Applying fixes manually..."

    # Manual fixes
    docker exec rag-api sed -i 's|http://rag-llm-server:8000|http://rag-llm:8000|g' /app/HiRAG/config.yaml
    docker exec rag-api sed -i 's|http://localhost:8000/v1|http://rag-llm:8000/v1|g' /app/HiRAG/config.yaml

    MODEL_NAME=$(docker exec rag-api curl -s http://rag-llm:8000/v1/models | python3 -c "import sys, json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null)

    if [ -n "$MODEL_NAME" ]; then
        docker exec rag-api sed -i "s|openai/gpt-oss-20b|${MODEL_NAME}|g" /app/HiRAG/config.yaml
    fi

    docker restart rag-api
    sleep 10
fi

# Step 5: Restart Frontend
echo ""
echo "[5/6] Restarting Frontend container..."
if docker ps -a | grep -q rag-frontend; then
    echo "Stopping and removing old Frontend container..."
    docker stop rag-frontend || true
    docker rm rag-frontend || true
fi

echo "Starting new Frontend container..."
docker run -d \
  --name rag-frontend \
  --network hirag-network \
  -p 8087:80 \
  -e VITE_API_URL=http://localhost:8080 \
  rag-frontend:latest

echo "Waiting for Frontend to start..."
sleep 5

# Step 6: Verify services
echo ""
echo "[6/6] Verifying services..."
echo ""

# Check LLM
echo -n "LLM Service (rag-llm): "
if docker ps | grep -q rag-llm; then
    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        echo "✓ Running"
    else
        echo "⚠ Container running but not responding"
    fi
else
    echo "✗ Not running"
fi

# Check Whisper
echo -n "Whisper Service (rag-whisper): "
if docker ps | grep -q rag-whisper; then
    if curl -sf http://localhost:8080/api/transcribe/health > /dev/null 2>&1; then
        echo "✓ Running"
    else
        echo "⚠ Container running but not responding"
    fi
else
    echo "✗ Not running"
fi

# Check API
echo -n "API Service (rag-api): "
if docker ps | grep -q rag-api; then
    if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
        echo "✓ Running"
    else
        echo "⚠ Container running but not responding"
    fi
else
    echo "✗ Not running"
fi

# Check Frontend
echo -n "Frontend (rag-frontend): "
if docker ps | grep -q rag-frontend; then
    if curl -sf http://localhost:8087 > /dev/null 2>&1; then
        echo "✓ Running"
    else
        echo "⚠ Container running but not responding"
    fi
else
    echo "✗ Not running"
fi

echo ""
echo "========================================="
echo "✓ Deployment Complete!"
echo "========================================="
echo ""
echo "Access the application at: http://localhost:8087"
echo ""
echo "Service Status:"
echo "  - Frontend: http://localhost:8087"
echo "  - API: http://localhost:8080"
echo "  - LLM: http://localhost:8000"
echo ""
echo "To view logs:"
echo "  docker logs rag-api"
echo "  docker logs rag-frontend"
echo "  docker logs rag-whisper"
echo "  docker logs rag-llm"
echo ""
echo "Note: RAG toggle is OFF by default (no embedding service needed)"