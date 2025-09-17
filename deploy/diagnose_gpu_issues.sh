#!/bin/bash

# Diagnose GPU and offline issues without restarting services

echo "=== GPU and Offline Diagnostics ==="
echo ""

# 1. Check Docker GPU runtime
echo "1. Docker GPU Runtime Check:"
docker info | grep -i runtime || echo "Could not find runtime info"
echo ""

# 2. Test GPU access directly
echo "2. Testing GPU Access with Test Container:"
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi 2>&1 | head -20 || {
    echo "ERROR: Cannot access GPU through Docker!"
    echo "Possible fixes:"
    echo "  - Install nvidia-docker2: sudo apt-get install nvidia-docker2"
    echo "  - Configure runtime: sudo nvidia-ctk runtime configure --runtime=docker"
    echo "  - Restart docker: sudo systemctl restart docker"
}
echo ""

# 3. Check how services were started
echo "3. Current Service Configuration:"
echo ""
for service in rag-embedding-server rag-whisper rag-llm-server; do
    echo "=== $service ==="
    if docker ps -a | grep -q $service; then
        echo "Inspect GPU config:"
        docker inspect $service | grep -A2 -i "gpu\|nvidia\|cuda" | head -10
        echo ""
        echo "Environment variables:"
        docker inspect $service --format='{{range .Config.Env}}{{println .}}{{end}}' | grep -E "CUDA|NVIDIA|HF_|TRANSFORMERS|MODEL"
        echo ""
        echo "Runtime:"
        docker inspect $service --format='{{.HostConfig.Runtime}}'
        echo ""
    else
        echo "Container not found"
    fi
    echo "---"
done

# 4. Check if services can see GPU from inside
echo ""
echo "4. GPU Detection Inside Containers:"
for service in rag-embedding-server rag-whisper rag-llm-server rag-dots-ocr; do
    echo -n "$service: "
    if docker ps | grep -q $service; then
        docker exec $service python3 -c "import torch; print(f'CUDA={torch.cuda.is_available()}, GPUs={torch.cuda.device_count()}')" 2>/dev/null || \
        docker exec $service python -c "import torch; print(f'CUDA={torch.cuda.is_available()}, GPUs={torch.cuda.device_count()}')" 2>/dev/null || \
        echo "Cannot check (Python/PyTorch not accessible)"
    else
        echo "Not running"
    fi
done

echo ""
echo "5. Quick Fixes Without Restart:"
echo ""
echo "If GPU not detected, the containers need to be restarted with --gpus all flag."
echo "The issue is they were started without GPU access."
echo ""
echo "For offline mode issues:"
echo "- Whisper: Needs model at /models/whisper-large-v3 or similar"
echo "- LLM: Needs model cached in /root/.cache/huggingface/"
echo "- Embedding: Currently using small model that downloads on demand"
echo ""
echo "The real fix: Build Docker images with models pre-included for offline use."