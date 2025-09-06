#!/bin/bash

set -e

echo "=========================================="
echo "Starting Whisper Hebrew Transcription Service"
echo "Model: ${MODEL_NAME:-ivrit-ai/whisper-large-v3}"
echo "Port: 8004"
echo "=========================================="

# Set default environment variables
export MODEL_NAME="${MODEL_NAME:-ivrit-ai/whisper-large-v3}"
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"

# Check if CUDA is available
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "CUDA available: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
    echo "GPU Memory: $(nvidia-smi --query-gpu=memory.total --format=csv,noheader)"
else
    echo "CUDA not available, running on CPU"
fi

# Start the service
echo "Starting Whisper service..."
exec python3 /app/whisper_service.py