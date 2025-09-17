#!/bin/bash

# Fix embedding server using only what's already in the container (offline mode)

echo "=== Fixing Embedding Server - Offline Mode ==="
echo ""

# First, check what's available in the container
echo "Checking existing container capabilities..."
docker exec rag-embedding-server python -c "
import sys
print('Python version:', sys.version)
try:
    import transformers
    print('✓ transformers available')
except:
    print('✗ transformers not available')

try:
    import torch
    print('✓ torch available')
    print('  CUDA available:', torch.cuda.is_available())
except:
    print('✗ torch not available')

try:
    import vllm
    print('✓ vllm available')
except:
    print('✗ vllm not available')
" 2>/dev/null || echo "Cannot inspect container - will try basic fixes"

echo ""
echo "Attempting vLLM embedding fix with existing packages..."

# Stop current container
docker stop rag-embedding-server && docker rm rag-embedding-server

# Restart with very conservative settings to avoid Triton compilation
docker run -d \
    --name rag-embedding-server \
    --network rag-network \
    --gpus all \
    --restart unless-stopped \
    -p 8001:8000 \
    -v $(pwd)/model-cache:/root/.cache/huggingface \
    -e CUDA_VISIBLE_DEVICES=0 \
    -e HF_HOME=/root/.cache/huggingface \
    -e TRANSFORMERS_CACHE=/root/.cache/huggingface \
    -e HF_HUB_OFFLINE=1 \
    -e VLLM_USE_TRITON=0 \
    -e DISABLE_CUSTOM_ALL_REDUCE=1 \
    --entrypoint /bin/bash \
    rag-embedding-server:latest \
    -c "
echo 'Starting embedding server with Triton disabled...'
export VLLM_USE_TRITON=0
export DISABLE_CUSTOM_ALL_REDUCE=1
export CUDA_VISIBLE_DEVICES=0

# Try to use the model that's actually cached
if [ -d '/root/.cache/huggingface/hub/models--BAAI--bge-small-en-v1.5' ]; then
    MODEL='BAAI/bge-small-en-v1.5'
elif [ -d '/root/.cache/huggingface/hub/models--Qwen--Qwen2-0.5B-Instruct' ]; then
    MODEL='Qwen/Qwen2-0.5B-Instruct'
else
    MODEL='BAAI/bge-small-en-v1.5'
fi

echo \"Using model: \$MODEL\"

exec python -m vllm.entrypoints.openai.api_server \\
    --model \$MODEL \\
    --host 0.0.0.0 \\
    --port 8000 \\
    --trust-remote-code \\
    --enforce-eager \\
    --disable-custom-all-reduce \\
    --gpu-memory-utilization 0.3 \\
    --max-model-len 512 \\
    --tensor-parallel-size 1 \\
    --task embedding
"

echo ""
echo "Waiting for startup..."
sleep 15

echo ""
echo "Testing the server..."

# Test the server
if curl -s http://localhost:8001/health > /dev/null; then
    echo "✓ Server is responding to health checks"

    # Try a basic embedding request
    curl -X POST http://localhost:8001/v1/embeddings \
        -H "Content-Type: application/json" \
        -d '{"input": "test", "model": "embedding"}' \
        --max-time 10 2>/dev/null | head -c 100 && echo "..."

    if [ $? -eq 0 ]; then
        echo "✓ Embedding server is working!"
    else
        echo "⚠ Server running but embedding test failed"
    fi
else
    echo "✗ Server not responding - check logs:"
    echo "  docker logs rag-embedding-server --tail 20"
fi

echo ""
echo "=== Fix Complete ==="
echo ""
echo "If this still fails, the alternative is:"
echo "1. Use a different model that's already cached"
echo "2. Run embeddings on CPU (slower but stable)"
echo "3. Use the LLM server for both generation AND embeddings"