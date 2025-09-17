#!/bin/bash

# Mount model-cache directory to running containers

echo "=== Setting up Model Cache Mounting ==="
echo ""

# Check if model-cache exists
if [[ ! -d "model-cache" ]]; then
    echo "Creating model-cache directory..."
    mkdir -p model-cache
fi

echo "Model cache directory: $(pwd)/model-cache"
echo ""

# Check what's in model-cache
echo "Contents of model-cache:"
ls -la model-cache/ | head -20
echo ""

# For each service, we need to restart with model-cache mounted
# The cache should be mounted to /root/.cache/huggingface for HF models

echo "To mount model-cache, services need to be restarted with volume mounts."
echo ""
echo "Quick fix commands for each service:"
echo ""

echo "1. Embedding Server:"
echo "docker stop rag-embedding-server && docker rm rag-embedding-server"
echo "docker run -d \\"
echo "    --name rag-embedding-server \\"
echo "    --network rag-network \\"
echo "    --gpus all \\"
echo "    --restart unless-stopped \\"
echo "    -p 8001:8000 \\"
echo "    -v $(pwd)/model-cache:/root/.cache/huggingface \\"
echo "    -e HF_HOME=/root/.cache/huggingface \\"
echo "    -e TRANSFORMERS_CACHE=/root/.cache/huggingface \\"
echo "    -e HF_HUB_OFFLINE=1 \\"
echo "    rag-embedding-server:latest"
echo ""

echo "2. LLM Server:"
echo "docker stop rag-llm-server && docker rm rag-llm-server"
echo "docker run -d \\"
echo "    --name rag-llm-server \\"
echo "    --network rag-network \\"
echo "    --gpus all \\"
echo "    --shm-size=16g \\"
echo "    --restart unless-stopped \\"
echo "    -p 8003:8000 \\"
echo "    -v $(pwd)/model-cache:/root/.cache/huggingface \\"
echo "    -e HF_HOME=/root/.cache/huggingface \\"
echo "    -e TRANSFORMERS_CACHE=/root/.cache/huggingface \\"
echo "    -e HF_HUB_OFFLINE=1 \\"
echo "    rag-llm-gptoss:latest"
echo ""

echo "3. Whisper Server:"
echo "docker stop rag-whisper && docker rm rag-whisper"
echo "docker run -d \\"
echo "    --name rag-whisper \\"
echo "    --network rag-network \\"
echo "    --gpus all \\"
echo "    --restart unless-stopped \\"
echo "    -p 8004:8004 \\"
echo "    -v $(pwd)/model-cache:/root/.cache/huggingface \\"
echo "    -e HF_HOME=/root/.cache/huggingface \\"
echo "    -e TRANSFORMERS_CACHE=/root/.cache/huggingface \\"
echo "    -e HF_HUB_OFFLINE=1 \\"
echo "    rag-whisper:latest"
echo ""

echo "=== Checking what models should be in cache ==="
echo ""
echo "For offline operation, model-cache should contain:"
echo "  hub/"
echo "  ├── models--BAAI--bge-small-en-v1.5/     # Embedding model"
echo "  ├── models--openai--gpt-oss-20b/         # LLM model"
echo "  └── models--ivrit-ai--whisper-large-v3/  # Whisper model"
echo ""

echo "=== Downloading models to cache (if online) ==="
echo "If you're online now and want to populate the cache:"
echo ""
echo "python3 -c \""
echo "from transformers import AutoModel, AutoTokenizer"
echo "import os"
echo "os.environ['HF_HOME'] = './model-cache'"
echo "# Download embedding model"
echo "AutoModel.from_pretrained('BAAI/bge-small-en-v1.5')"
echo "AutoTokenizer.from_pretrained('BAAI/bge-small-en-v1.5')"
echo "# Download whisper"
echo "# AutoModel.from_pretrained('ivrit-ai/whisper-large-v3')"
echo "\""