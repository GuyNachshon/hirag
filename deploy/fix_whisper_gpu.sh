#!/bin/bash

# Fix Whisper service to use GPU instead of CPU

echo "=== Fixing Whisper to Use GPU ==="
echo ""

echo "Common reasons Whisper runs on CPU:"
echo "  • Missing --gpus all flag"
echo "  • Wrong CUDA_VISIBLE_DEVICES setting"
echo "  • Model not loading with GPU device"
echo "  • Missing GPU libraries in container"
echo ""

# Stop current whisper server
echo "1. Stopping current Whisper server..."
docker stop rag-whisper 2>/dev/null || true
docker rm rag-whisper 2>/dev/null || true

echo ""
echo "2. Starting Whisper with proper GPU configuration..."

# Start whisper with explicit GPU settings
docker run -d \
    --name rag-whisper \
    --network rag-network \
    --gpus all \
    --restart unless-stopped \
    -p 8004:8004 \
    -v $(pwd)/model-cache:/root/.cache/huggingface \
    -e CUDA_VISIBLE_DEVICES=0 \
    -e HF_HOME=/root/.cache/huggingface \
    -e TRANSFORMERS_CACHE=/root/.cache/huggingface \
    -e HF_HUB_OFFLINE=1 \
    -e TRANSFORMERS_OFFLINE=1 \
    -e MODEL_NAME=ivrit-ai/whisper-large-v3 \
    -e DEVICE=cuda \
    -e TORCH_DEVICE=cuda:0 \
    --entrypoint /bin/bash \
    rag-whisper:latest \
    -c "
echo 'Starting Whisper with GPU acceleration...'
echo 'Checking GPU availability:'
python -c 'import torch; print(f\"CUDA available: {torch.cuda.is_available()}\"); print(f\"GPU count: {torch.cuda.device_count()}\"); print(f\"Current device: {torch.cuda.current_device() if torch.cuda.is_available() else \"CPU\"}\")' || echo 'PyTorch check failed'

# Export environment variables for GPU
export CUDA_VISIBLE_DEVICES=0
export DEVICE=cuda
export TORCH_DEVICE=cuda:0

# Start the Whisper service with explicit GPU device
echo 'Starting Whisper service on GPU...'
exec python -m whisper_service \
    --model-name \$MODEL_NAME \
    --device cuda \
    --host 0.0.0.0 \
    --port 8004
"

echo ""
echo "3. Waiting for Whisper server to start..."
sleep 20

echo ""
echo "4. Testing Whisper GPU usage..."

echo "Testing Whisper health..."
curl -s http://localhost:8004/health && echo " ✓ Whisper healthy" || echo " ✗ Whisper unhealthy"

echo ""
echo "Checking GPU memory usage:"
docker exec rag-whisper nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null || echo "Could not check GPU memory (nvidia-smi not available in container)"

echo ""
echo "=== Whisper GPU Fix Complete ==="
echo ""
echo "If Whisper is still using CPU:"
echo "1. Check container logs: docker logs rag-whisper --tail 20"
echo "2. Verify GPU access: docker exec rag-whisper nvidia-smi"
echo "3. Check PyTorch CUDA: docker exec rag-whisper python -c 'import torch; print(torch.cuda.is_available())'"
echo ""
echo "Alternative CPU fallback available in emergency_fallbacks.sh"