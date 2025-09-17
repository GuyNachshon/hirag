#!/bin/bash

# Fix LLM server to use cached models properly

echo "=== Fixing LLM Server Cache Issues ==="
echo ""

# First, check what's actually cached
echo "1. Checking cached models in LLM container..."
docker exec rag-llm-server find /root/.cache/huggingface/hub -name "models--*" -type d 2>/dev/null | head -10 || echo "No models found in cache"

echo ""
echo "2. Checking if models are properly downloaded..."
docker exec rag-llm-server ls -la /root/.cache/huggingface/hub/models--openai--gpt-oss-20b/snapshots/ 2>/dev/null || echo "GPT-OSS-20B not fully cached"

echo ""
echo "3. Current LLM server status:"
docker logs rag-llm-server --tail 5

echo ""
echo "4. Checking environment variables:"
docker exec rag-llm-server printenv | grep -E "HF_|MODEL|TRANSFORMERS" || echo "No relevant env vars found"

echo ""
echo "=== Applying Fix ==="

# Check if model-cache is properly mounted
if [ -d "model-cache" ]; then
    echo "✓ model-cache directory exists locally"
    ls -la model-cache/hub/ 2>/dev/null | head -5 || echo "No hub directory in model-cache"
else
    echo "⚠ model-cache directory missing - creating it"
    mkdir -p model-cache
fi

# Stop current LLM server
echo ""
echo "Stopping current LLM server..."
docker stop rag-llm-server && docker rm rag-llm-server

# Check what models we actually have available
echo ""
echo "Checking available models in cache..."
if [ -d "model-cache/hub" ]; then
    echo "Models in cache:"
    ls -la model-cache/hub/ | grep models-- || echo "No models found"
fi

# Restart with proper cache mounting and environment
echo ""
echo "Restarting LLM server with proper cache configuration..."

docker run -d \
    --name rag-llm-server \
    --network rag-network \
    --gpus all \
    --shm-size=16g \
    --restart unless-stopped \
    -p 8003:8000 \
    -v $(pwd)/model-cache:/root/.cache/huggingface \
    -e CUDA_VISIBLE_DEVICES=0 \
    -e TENSOR_PARALLEL_SIZE=1 \
    -e GPU_MEMORY_UTILIZATION=0.35 \
    -e HF_HOME=/root/.cache/huggingface \
    -e TRANSFORMERS_CACHE=/root/.cache/huggingface \
    -e HF_HUB_OFFLINE=1 \
    -e TRANSFORMERS_OFFLINE=1 \
    --entrypoint /bin/bash \
    rag-llm-gptoss:latest \
    -c "
echo '=== LLM Server Starting ==='
echo 'Cache directory contents:'
ls -la /root/.cache/huggingface/hub/ | head -5

# Try to find a working model
if [ -d '/root/.cache/huggingface/hub/models--openai--gpt-oss-20b' ]; then
    MODEL='openai/gpt-oss-20b'
    echo 'Using GPT-OSS-20B from cache'
elif [ -d '/root/.cache/huggingface/hub/models--Qwen--Qwen2-0.5B-Instruct' ]; then
    MODEL='Qwen/Qwen2-0.5B-Instruct'
    echo 'Using Qwen2-0.5B-Instruct from cache'
else
    echo 'No suitable model found in cache!'
    echo 'Available models:'
    ls -la /root/.cache/huggingface/hub/ | grep models--
    echo 'Trying with GPT-OSS-20B anyway...'
    MODEL='openai/gpt-oss-20b'
fi

echo \"Starting vLLM with model: \$MODEL\"
echo 'GPU memory allocation: 35% (~14GB of 40GB)'

exec vllm serve \$MODEL \\
    --tensor-parallel-size 1 \\
    --gpu-memory-utilization 0.35 \\
    --max-model-len 2048 \\
    --served-model-name llm \\
    --trust-remote-code \\
    --enforce-eager \\
    --host 0.0.0.0 \\
    --port 8000
"

echo ""
echo "Waiting for LLM server to start..."
sleep 20

echo ""
echo "=== Testing LLM Server ==="
curl -s http://localhost:8003/health && echo " - Health check OK" || echo " - Health check failed"

echo ""
echo "Checking logs:"
docker logs rag-llm-server --tail 10

echo ""
echo "=== Fix Complete ==="
echo ""
echo "If still failing, check:"
echo "1. docker logs rag-llm-server --tail 50"
echo "2. docker exec rag-llm-server ls -la /root/.cache/huggingface/hub/"
echo "3. Consider using a smaller model if GPT-OSS-20B is causing issues"