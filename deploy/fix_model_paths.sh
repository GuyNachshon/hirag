#!/bin/bash

# Fix model loading to use cached models instead of downloading

echo "=== Checking Cached Models and Fixing Paths ==="
echo ""

# Function to find cached models in a container
check_cached_models() {
    local container=$1
    echo "=== $container ==="
    
    if ! docker ps -a | grep -q $container; then
        echo "Container not found"
        return
    fi
    
    echo "Searching for cached models..."
    
    # Check common cache locations
    echo "HuggingFace cache:"
    docker exec $container find /root/.cache -type d -name "models--*" 2>/dev/null | head -10 || echo "  No HF cache found"
    
    echo ""
    echo "Model directories:"
    docker exec $container find / -maxdepth 3 -type d -name "*model*" -o -name "*whisper*" -o -name "*gpt*" -o -name "*qwen*" 2>/dev/null | grep -v proc | head -10
    
    echo ""
    echo "Safetensors/bin files:"
    docker exec $container find /root/.cache -name "*.safetensors" -o -name "*.bin" 2>/dev/null | head -5 || echo "  No model files found"
    
    echo ""
    echo "Environment variables:"
    docker exec $container printenv | grep -E "MODEL|HF_|TRANSFORMERS" || echo "  No relevant env vars"
    
    echo "---"
}

# Check each service
echo "1. Checking cached models in each container:"
echo ""
check_cached_models "rag-embedding-server"
check_cached_models "rag-llm-server"
check_cached_models "rag-whisper"

# Now let's see what models are actually cached
echo ""
echo "2. Detailed model cache inspection:"
echo ""

# Embedding server
echo "=== Embedding Server Models ==="
docker exec rag-embedding-server ls -la /root/.cache/huggingface/hub/ 2>/dev/null | grep models || echo "No HF hub cache"
docker exec rag-embedding-server ls -la /app/models/ 2>/dev/null || echo "No /app/models"

# LLM server
echo ""
echo "=== LLM Server Models ==="
docker exec rag-llm-server ls -la /root/.cache/huggingface/hub/ 2>/dev/null | grep models || echo "No HF hub cache"
docker exec rag-llm-server ls -la /workspace/weights/ 2>/dev/null || echo "No /workspace/weights"

# Whisper
echo ""
echo "=== Whisper Models ==="
docker exec rag-whisper ls -la /models/ 2>/dev/null || echo "No /models directory"
docker exec rag-whisper ls -la /app/models/ 2>/dev/null || echo "No /app/models"
docker exec rag-whisper ls -la /root/.cache/whisper/ 2>/dev/null || echo "No whisper cache"
docker exec rag-whisper ls -la /root/.cache/huggingface/hub/ 2>/dev/null | grep ivrit || echo "No ivrit-ai models"

echo ""
echo "3. Fix Suggestions:"
echo ""

# Check if models exist and suggest fixes
echo "For Embedding Server:"
if docker exec rag-embedding-server test -d /root/.cache/huggingface/hub/models--Qwen--Qwen2-0.5B-Instruct 2>/dev/null; then
    echo "  ✓ Found Qwen2-0.5B-Instruct - use this instead of downloading BGE"
    echo "  Fix: Set MODEL_NAME=Qwen/Qwen2-0.5B-Instruct"
elif docker exec rag-embedding-server test -d /root/.cache/huggingface/hub/models--BAAI--bge-small-en-v1.5 2>/dev/null; then
    echo "  ✓ Found BGE model cached"
    echo "  Fix: Ensure HF_HUB_OFFLINE=1 is NOT set"
else
    echo "  ✗ No suitable embedding model cached"
fi

echo ""
echo "For LLM Server:"
if docker exec rag-llm-server test -d /root/.cache/huggingface/hub/models--openai--gpt-oss-20b 2>/dev/null; then
    echo "  ✓ Found gpt-oss-20b cached"
    echo "  Fix: The model is cached but has FlashAttention compatibility issues"
    echo "  Need to use different model or fix vLLM version"
else
    echo "  ✗ GPT-OSS-20B not properly cached"
fi

echo ""
echo "For Whisper:"
if docker exec rag-whisper test -d /models 2>/dev/null; then
    echo "  Check what's in /models:"
    docker exec rag-whisper ls -la /models/ 2>/dev/null | head -5
elif docker exec rag-whisper test -d /root/.cache/whisper 2>/dev/null; then
    echo "  ✓ Found whisper cache"
    docker exec rag-whisper ls -la /root/.cache/whisper/ 2>/dev/null
else
    echo "  ✗ No whisper model cached"
fi

echo ""
echo "4. Quick fix without restart (set environment variables):"
echo ""
echo "Unfortunately, environment variables can't be changed without restart."
echo "But we can check the startup commands:"
echo ""

for service in rag-embedding-server rag-llm-server rag-whisper; do
    echo "$service startup command:"
    docker inspect $service --format='{{.Config.Cmd}}' 2>/dev/null | head -100
    echo ""
done

echo ""
echo "5. The Real Solution:"
echo "The containers need to be rebuilt with:"
echo "  - Models pre-downloaded during docker build"
echo "  - Correct MODEL_PATH environment variables"
echo "  - HF_HUB_OFFLINE=1 set AFTER models are cached"
echo ""
echo "Or restart specific services with correct model paths pointing to cached locations."