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
# Replace forward slash with double dash for HuggingFace cache format
MODEL_CACHE_PATH="/root/.cache/huggingface/models--$(echo $MODEL_NAME | sed 's/\//-/-/')"
echo "Checking for model at: $MODEL_CACHE_PATH"

# If directory doesn't exist, try downloading
if [ ! -d "$MODEL_CACHE_PATH" ]; then
    echo "Model not found in cache, trying to download..."
    python /app/download_models.py
fi

# Now check if we have the model (either already there or just downloaded)
if [ -d "$MODEL_CACHE_PATH" ]; then
    echo "Model found in cache at: $MODEL_CACHE_PATH"
    # Look for the config.json file to find the actual model directory
    CONFIG_FILE=$(find "$MODEL_CACHE_PATH" -name "config.json" -type f 2>/dev/null | head -1)
    if [ -n "$CONFIG_FILE" ]; then
        # Get the directory containing config.json
        MODEL_PATH=$(dirname "$CONFIG_FILE")
        echo "Found model with config.json at: $MODEL_PATH"
    else
        echo "Warning: No config.json found in model cache"
        # Try to find snapshots directory
        SNAPSHOT_DIR="$MODEL_CACHE_PATH/snapshots"
        if [ -d "$SNAPSHOT_DIR" ]; then
            MODEL_PATH=$(ls -d $SNAPSHOT_DIR/* 2>/dev/null | head -1)
            echo "Using first snapshot directory: $MODEL_PATH"
        else
            MODEL_PATH=$MODEL_CACHE_PATH
            echo "Using model cache root: $MODEL_PATH"
        fi
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