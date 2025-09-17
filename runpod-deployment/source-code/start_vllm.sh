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

# Check if model exists in cache and set model path
MODEL_CACHE_PATH="/root/.cache/huggingface/models--$(echo $MODEL_NAME | sed 's/\//-/')"
if [ -d "$MODEL_CACHE_PATH" ]; then
    echo "Model found in cache at: $MODEL_CACHE_PATH"
    MODEL_PATH="$MODEL_CACHE_PATH/snapshots/*"
    # Get the actual snapshot directory
    MODEL_PATH=$(ls -d $MODEL_PATH | head -1)
    echo "Using model snapshot: $MODEL_PATH"
else
    echo "Model not found in cache, trying to download..."
    python /app/download_models.py
    # Check again after download
    if [ -d "$MODEL_CACHE_PATH" ]; then
        MODEL_PATH="$MODEL_CACHE_PATH/snapshots/*"
        MODEL_PATH=$(ls -d $MODEL_PATH | head -1)
    else
        echo "Error: Model download failed or path not found"
        MODEL_PATH=$MODEL_NAME  # Fallback to repo ID
    fi
fi

# Start vLLM server (modern format for v0.10.1+)
exec vllm serve $MODEL_PATH \
    --host 0.0.0.0 \
    --port $PORT \
    --tensor-parallel-size $TENSOR_PARALLEL_SIZE \
    --gpu-memory-utilization $GPU_MEMORY_UTILIZATION \
    --max-model-len $MAX_MODEL_LEN \
    --trust-remote-code