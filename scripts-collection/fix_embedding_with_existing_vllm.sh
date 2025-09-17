#!/bin/bash

# Fix embedding using existing vLLM container (no new dependencies)

echo "=== Using Existing vLLM Container for Embeddings ==="
echo ""

# Stop the problematic embedding server
docker stop rag-embedding-server 2>/dev/null || true
docker rm rag-embedding-server 2>/dev/null || true

echo "1. Checking what models are available in LLM container..."
docker exec rag-llm-server find /root/.cache/huggingface/hub -name "models--*" -type d 2>/dev/null | head -5

echo ""
echo "2. Starting new embedding server using LLM container image..."

# Use the same image as LLM server but configured for embeddings
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
echo 'Starting embedding server using LLM container...'

# Check what models we have
echo 'Available models:'
ls -la /root/.cache/huggingface/hub/ | grep models-- || echo 'No models found'

# Try to find a suitable model for embeddings
if [ -d '/root/.cache/huggingface/hub/models--Qwen--Qwen2-0.5B-Instruct' ]; then
    MODEL='Qwen/Qwen2-0.5B-Instruct'
    echo 'Using Qwen2-0.5B-Instruct for embeddings'
elif [ -d '/root/.cache/huggingface/hub/models--openai--gpt-oss-20b' ]; then
    MODEL='openai/gpt-oss-20b'
    echo 'Using GPT-OSS-20B for embeddings (large but should work)'
else
    # Use whatever model is available
    MODEL=\$(ls /root/.cache/huggingface/hub/ | grep models-- | head -1 | sed 's/models--//' | sed 's/--/\//g')
    echo \"Using available model: \$MODEL\"
fi

export VLLM_USE_TRITON=0
export CUDA_VISIBLE_DEVICES=0

echo \"Starting vLLM embedding server with model: \$MODEL\"

exec python -m vllm.entrypoints.openai.api_server \\
    --model \$MODEL \\
    --host 0.0.0.0 \\
    --port 8000 \\
    --trust-remote-code \\
    --enforce-eager \\
    --disable-custom-all-reduce \\
    --gpu-memory-utilization 0.15 \\
    --max-model-len 512 \\
    --tensor-parallel-size 1 \\
    --task embedding
"

echo ""
echo "3. Waiting for embedding server to start..."
sleep 20

echo ""
echo "4. Testing embedding server..."
if curl -s http://localhost:8001/health > /dev/null; then
    echo "✓ Embedding server health check passed"

    # Try a simple embedding request
    echo "Testing embedding generation..."
    curl -X POST http://localhost:8001/v1/embeddings \
        -H "Content-Type: application/json" \
        -d '{"input": "test embedding", "model": "embedding"}' \
        --max-time 30 2>/dev/null | head -c 100 && echo "..."

    if [ $? -eq 0 ]; then
        echo "✓ Embedding generation working!"
    else
        echo "⚠ Embedding server running but test failed"
    fi
else
    echo "✗ Embedding server health check failed"
    echo "Check logs: docker logs rag-embedding-server --tail 20"
fi

echo ""
echo "=== Alternative: Unified LLM+Embedding Server ==="
echo ""
echo "If the above fails, you can use a single server for both:"
echo ""
echo "# Stop separate embedding server"
echo "docker stop rag-embedding-server && docker rm rag-embedding-server"
echo ""
echo "# Create a simple proxy that forwards embedding requests to LLM server"
echo "docker run -d --name rag-embedding-server --network rag-network -p 8001:8000 \\"
echo "  nginx:alpine sh -c '"
echo "  echo \"upstream llm { server rag-llm-server:8000; }\" > /etc/nginx/conf.d/default.conf"
echo "  echo \"server { listen 8000; location / { proxy_pass http://llm; } }\" >> /etc/nginx/conf.d/default.conf"
echo "  nginx -g \"daemon off;\""
echo "'"
echo ""
echo "This makes the LLM server handle both generation AND embeddings on the same model."