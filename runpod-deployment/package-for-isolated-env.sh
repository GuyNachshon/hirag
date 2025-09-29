#!/bin/bash
set -e

# Configuration - EDIT THESE
GCP_BUCKET="gs://YOUR_BUCKET_NAME"  # Change to your GCP bucket
DEPLOYMENT_PATH="deployment/$(date +%Y%m%d_%H%M%S)"
PACKAGE_DIR="./package"

echo "========================================="
echo "Packaging for Isolated Environment"
echo "========================================="

# Clean and create package directory
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

# Step 1: Build Docker images
echo ""
echo "[1/6] Building Docker images..."
echo "Building API image..."
docker build -f dockerfiles/Dockerfile.api -t rag-api:latest . || { echo "Failed to build API image"; exit 1; }

echo "Building Frontend image..."
docker build -f dockerfiles/Dockerfile.frontend -t rag-frontend:latest . || { echo "Failed to build Frontend image"; exit 1; }

# Step 2: Save Docker images as tar files
echo ""
echo "[2/6] Saving Docker images to tar files..."
docker save rag-api:latest -o "$PACKAGE_DIR/rag-api.tar"
docker save rag-frontend:latest -o "$PACKAGE_DIR/rag-frontend.tar"

# Step 3: Copy Whisper hot-patch file
echo ""
echo "[3/6] Copying Whisper service file for hot-patching..."
cp source-code/whisper_fastapi_service.py "$PACKAGE_DIR/"

# Step 4: Create config fixes script
echo ""
echo "[4/6] Creating config fixes script..."
cat > "$PACKAGE_DIR/config-fixes.sh" << 'EOF'
#!/bin/bash
# Config fixes to run after deployment

echo "Applying configuration fixes..."

# Fix LLM hostname
echo "1. Fixing LLM hostname..."
docker exec rag-api sed -i 's|http://rag-llm-server:8000|http://rag-llm:8000|g' /app/HiRAG/config.yaml

# Fix VLLM section
echo "2. Fixing VLLM section..."
docker exec rag-api sed -i 's|http://localhost:8000/v1|http://rag-llm:8000/v1|g' /app/HiRAG/config.yaml

# Get correct model name from vLLM
echo "3. Getting model name from vLLM..."
MODEL_NAME=$(docker exec rag-api curl -s http://rag-llm:8000/v1/models | python3 -c "import sys, json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null)

if [ -z "$MODEL_NAME" ]; then
    echo "WARNING: Could not get model name from vLLM. Using default path."
    MODEL_NAME="/root/.cache/huggingface/models--openai--gpt-oss-20b/snapshots/6cee5e81ee83917806bbde320786a8fb61efebee"
fi

echo "   Model name: $MODEL_NAME"

# Update config with correct model name
echo "4. Updating model name in config..."
docker exec rag-api sed -i "s|openai/gpt-oss-20b|${MODEL_NAME}|g" /app/HiRAG/config.yaml

# Restart API to apply changes
echo "5. Restarting API container..."
docker restart rag-api

echo ""
echo "Configuration fixes applied successfully!"
echo "Waiting for API to start..."
sleep 5
EOF

chmod +x "$PACKAGE_DIR/config-fixes.sh"

# Step 5: Create checksums
echo ""
echo "[5/6] Generating checksums..."
cd "$PACKAGE_DIR"
sha256sum rag-api.tar rag-frontend.tar whisper_fastapi_service.py config-fixes.sh > checksums.txt
cd ..

# Step 6: Upload to GCP bucket
echo ""
echo "[6/6] Uploading to GCP bucket..."
echo "Destination: ${GCP_BUCKET}/${DEPLOYMENT_PATH}/"

gsutil -m cp -r "$PACKAGE_DIR"/* "${GCP_BUCKET}/${DEPLOYMENT_PATH}/"

# Create a "latest" marker
echo "$DEPLOYMENT_PATH" | gsutil cp - "${GCP_BUCKET}/latest-deployment.txt"

echo ""
echo "========================================="
echo "✓ Packaging Complete!"
echo "========================================="
echo "Package location: ${GCP_BUCKET}/${DEPLOYMENT_PATH}/"
echo ""
echo "Files packaged:"
echo "  - rag-api.tar ($(du -h $PACKAGE_DIR/rag-api.tar | cut -f1))"
echo "  - rag-frontend.tar ($(du -h $PACKAGE_DIR/rag-frontend.tar | cut -f1))"
echo "  - whisper_fastapi_service.py"
echo "  - config-fixes.sh"
echo "  - checksums.txt"
echo ""
echo "Next step: Run download-from-gcp.sh on your local machine"