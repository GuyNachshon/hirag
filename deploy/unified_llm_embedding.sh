#!/bin/bash

# Create separate dedicated embedding server using existing LLM image

echo "=== Dedicated Embedding Server Setup (Using LLM Image) ==="
echo ""

echo "This approach creates a SEPARATE embedding server using your existing LLM image"
echo "Advantage: Dedicated embedding performance, uses cached models"
echo "Disadvantage: Uses more GPU memory (but you have plenty on A100/H100)"
echo ""

# Stop current embedding server if running
echo "1. Stopping current embedding server..."
docker stop rag-embedding-server 2>/dev/null || true
docker rm rag-embedding-server 2>/dev/null || true

echo ""
echo "2. Starting dedicated embedding server using LLM image..."

# Start dedicated embedding server using the LLM image
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
    --entrypoint /bin/bash \
    rag-llm-gptoss:latest \
    -c "
echo 'Starting dedicated embedding server using vLLM...'

# Find the best available embedding model
if [ -d '/root/.cache/huggingface/hub/models--BAAI--bge-small-en-v1.5' ]; then
    MODEL='BAAI/bge-small-en-v1.5'
    echo 'Using BAAI/bge-small-en-v1.5 (dedicated embedding model)'
elif [ -d '/root/.cache/huggingface/hub/models--Qwen--Qwen2-0.5B-Instruct' ]; then
    MODEL='Qwen/Qwen2-0.5B-Instruct'
    echo 'Using Qwen2-0.5B-Instruct (good for embeddings)'
elif [ -d '/root/.cache/huggingface/hub/models--openai--gpt-oss-20b' ]; then
    MODEL='openai/gpt-oss-20b'
    echo 'Using GPT-OSS-20B for embeddings (large but works)'
else
    MODEL=\$(ls /root/.cache/huggingface/hub/ | grep models-- | head -1 | sed 's/models--//' | sed 's/--/\//g')
    echo \"Using available model for embeddings: \$MODEL\"
fi

echo \"Starting dedicated vLLM embedding server with model: \$MODEL\"

export VLLM_USE_TRITON=0
export DISABLE_CUSTOM_ALL_REDUCE=1

exec vllm serve \$MODEL \\
    --tensor-parallel-size 1 \\
    --gpu-memory-utilization 0.15 \\
    --max-model-len 512 \\
    --served-model-name embedding-model \\
    --trust-remote-code \\
    --enforce-eager \\
    --disable-custom-all-reduce \\
    --host 0.0.0.0 \\
    --port 8000
"

echo ""
echo "3. Keep LLM server separate..."
echo "(Your existing LLM server on port 8003 remains unchanged)"

echo ""
echo "4. Waiting for embedding server to start..."
sleep 25

echo ""
echo "5. Testing dedicated embedding server..."

echo "Testing embedding server health (port 8001)..."
curl -s http://localhost:8001/health && echo " ✓ Embedding server healthy" || echo " ✗ Embedding server unhealthy"

echo ""
echo "Testing embedding generation..."
curl -X POST http://localhost:8001/v1/embeddings \
    -H "Content-Type: application/json" \
    -d '{"input": "test embedding", "model": "embedding-model"}' \
    --max-time 30 2>/dev/null | head -c 100 && echo "..." || echo "❌ Embedding test failed"

echo ""
echo "=== Dedicated Embedding Server Ready ==="
echo ""
echo "Usage:"
echo "• Text Generation: POST http://localhost:8003/v1/completions (your existing LLM server)"
echo "• Embeddings:      POST http://localhost:8001/v1/embeddings (new dedicated server)"
echo "• Each uses its own model: optimal performance"
echo ""
echo "Architecture:"
echo "  - LLM Server (port 8003): Your existing text generation server"
echo "  - Embedding Server (port 8001): New dedicated embedding server using same vLLM image"
echo ""
echo "If you need to debug:"
echo "  docker logs rag-llm-server --tail 20"
echo "  docker logs rag-embedding-server --tail 20"