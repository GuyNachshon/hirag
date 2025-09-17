#!/bin/bash
echo "Starting Ivrit-AI Whisper FastAPI Service"
echo "Model: $MODEL_NAME"
echo "Device: $DEVICE"
echo "Offline Mode: $HF_HUB_OFFLINE"

# Ensure GPU is accessible
if [ "$DEVICE" = "cuda" ]; then
    python -c "import torch; print(f'CUDA Available: {torch.cuda.is_available()}')"
fi

# Start service
exec python whisper_fastapi_service.py