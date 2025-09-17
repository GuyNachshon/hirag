#!/bin/bash

# Configuration
MODEL_TYPE=${MODEL_TYPE:-"llm"}
MODEL_NAME=${MODEL_NAME:-"openai/gpt-oss-20b"}
PORT=${PORT:-8000}
TENSOR_PARALLEL_SIZE=${TENSOR_PARALLEL_SIZE:-1}
GPU_MEMORY_UTILIZATION=${GPU_MEMORY_UTILIZATION:-0.7}
MAX_MODEL_LEN=${MAX_MODEL_LEN:-4096}

echo "Starting vLLM server..."
echo "Model Type: $MODEL_TYPE"
echo "Model Name: $MODEL_NAME"
echo "Port: $PORT"
echo "GPU Memory Utilization: $GPU_MEMORY_UTILIZATION"

# Check GPU
nvidia-smi || echo "No GPU detected"

# Check if model exists in cache
if [ ! -d "/root/.cache/huggingface/hub/models--$(echo $MODEL_NAME | sed 's/\//-/')" ]; then
    echo "Model not found in cache, trying to download..."
    python /app/download_models.py
fi

# Start vLLM server (modern format for v0.10.1+)
exec vllm serve $MODEL_NAME \
    --host 0.0.0.0 \
    --port $PORT \
    --tensor-parallel-size $TENSOR_PARALLEL_SIZE \
    --gpu-memory-utilization $GPU_MEMORY_UTILIZATION \
    --max-model-len $MAX_MODEL_LEN \
    --trust-remote-code