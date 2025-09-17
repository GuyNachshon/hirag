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
echo "Checking for model at: $MODEL_CACHE_PATH"

# If directory doesn't exist, try downloading
if [ ! -d "$MODEL_CACHE_PATH" ]; then
    echo "Model not found in cache, trying to download..."
    python /app/download_models.py
fi

# Now check if we have the model (either already there or just downloaded)
if [ -d "$MODEL_CACHE_PATH" ]; then
    echo "Model found in cache at: $MODEL_CACHE_PATH"
    # Find the snapshot directory
    SNAPSHOT_DIR=$(find "$MODEL_CACHE_PATH" -type d -name "snapshots" | head -1)
    if [ -n "$SNAPSHOT_DIR" ]; then
        # Get the actual snapshot hash directory
        MODEL_PATH=$(ls -d $SNAPSHOT_DIR/* 2>/dev/null | head -1)
        if [ -n "$MODEL_PATH" ] && [ -d "$MODEL_PATH" ]; then
            echo "Using model snapshot: $MODEL_PATH"
        else
            # No snapshots directory, use the model cache path directly
            MODEL_PATH=$MODEL_CACHE_PATH
            echo "Using model path directly: $MODEL_PATH"
        fi
    else
        # No snapshots directory, use the model cache path directly
        MODEL_PATH=$MODEL_CACHE_PATH
        echo "Using model path directly: $MODEL_PATH"
    fi
else
    echo "Error: Model not found after download attempt"
    echo "Falling back to repository ID: $MODEL_NAME"
    MODEL_PATH=$MODEL_NAME
fi

# Start vLLM server (modern format for v0.10.1+)
exec vllm serve $MODEL_PATH \
    --host 0.0.0.0 \
    --port $PORT \
    --tensor-parallel-size $TENSOR_PARALLEL_SIZE \
    --gpu-memory-utilization $GPU_MEMORY_UTILIZATION \
    --max-model-len $MAX_MODEL_LEN \
    --trust-remote-code