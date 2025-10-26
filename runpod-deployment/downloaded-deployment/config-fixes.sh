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
