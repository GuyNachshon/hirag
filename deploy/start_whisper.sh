#!/bin/bash
set -e

MODEL=${MODEL_NAME:-"openai/whisper-large-v3"}
echo "Starting Whisper transcription service with model: $MODEL"
echo "Model is pre-downloaded for offline deployment"
echo "Service available on port 8004"
echo ""

# Start the FastAPI service
python /app/whisper_service.py