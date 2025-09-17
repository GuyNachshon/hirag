#!/bin/bash

# Fallback: Run embeddings on CPU (slower but very stable)

echo "=== Fallback: CPU-based Embeddings ==="
echo ""

# Stop GPU embedding server
docker stop rag-embedding-server && docker rm rag-embedding-server

echo "Starting CPU-based embedding server (stable, slower)..."

# Run on CPU only - avoids all GPU/CUDA issues
docker run -d \
    --name rag-embedding-server \
    --network rag-network \
    --restart unless-stopped \
    --cpus="2.0" \
    --memory="4g" \
    -p 8001:8000 \
    -v $(pwd)/model-cache:/root/.cache/huggingface \
    -e HF_HOME=/root/.cache/huggingface \
    -e TRANSFORMERS_CACHE=/root/.cache/huggingface \
    -e HF_HUB_OFFLINE=1 \
    -e CUDA_VISIBLE_DEVICES="" \
    --entrypoint /bin/bash \
    rag-embedding-server:latest \
    -c "
echo 'Starting CPU-based embedding server...'

# Find available model
if [ -d '/root/.cache/huggingface/hub/models--BAAI--bge-small-en-v1.5' ]; then
    MODEL='BAAI/bge-small-en-v1.5'
elif [ -d '/root/.cache/huggingface/hub/models--Qwen--Qwen2-0.5B-Instruct' ]; then
    MODEL='Qwen/Qwen2-0.5B-Instruct'
else
    MODEL='BAAI/bge-small-en-v1.5'
fi

echo \"Using model: \$MODEL on CPU\"

exec python -m vllm.entrypoints.openai.api_server \\
    --model \$MODEL \\
    --host 0.0.0.0 \\
    --port 8000 \\
    --trust-remote-code \\
    --enforce-eager \\
    --tensor-parallel-size 1 \\
    --max-model-len 512 \\
    --task embedding \\
    --device cpu
"

echo ""
echo "CPU embedding server started"
echo "⚠ Note: This will be slower but very stable"
echo ""
echo "Testing in 20 seconds..."
sleep 20

curl -s http://localhost:8001/health && echo " - Health OK"