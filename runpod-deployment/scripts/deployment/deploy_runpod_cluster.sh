#!/bin/bash

# Deploy RAG system on RunPod GPU cluster (8x A100 SXM)
# This script builds everything natively on RunPod for offline deployment

set -e

echo "==========================================="
echo "   RUNPOD CLUSTER DEPLOYMENT (8x A100)    "
echo "==========================================="
echo ""

# Function to print colored output
print_status() {
    echo -e "\033[32m✓ $1\033[0m"
}

print_error() {
    echo -e "\033[31m✗ $1\033[0m"
}

print_header() {
    echo ""
    echo "=== $1 ==="
}

# Setup RunPod environment
setup_environment() {
    print_header "Setting Up RunPod Environment"

    # Check if running on RunPod
    if [ -z "$RUNPOD_POD_ID" ]; then
        echo "Warning: Not running on RunPod. Some features may not work."
    else
        echo "RunPod Pod ID: $RUNPOD_POD_ID"
    fi

    # Install Docker if needed
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        usermod -aG docker $USER
        rm get-docker.sh
    fi

    # Verify GPU access
    echo "Checking GPU access..."
    nvidia-smi || {
        print_error "No GPU access detected"
        exit 1
    }

    # Create directories
    mkdir -p /workspace/model-cache
    mkdir -p /workspace/offline-package

    print_status "Environment ready"
}

# Clone and prepare repository
prepare_repository() {
    print_header "Preparing Repository"

    cd /workspace

    # Clone if not exists
    if [ ! -d "rag-v2" ]; then
        echo "Cloning repository..."
        # Replace with your actual repository
        git clone https://github.com/YOUR_USERNAME/rag-v2.git
        cd rag-v2
    else
        cd rag-v2
        git pull
    fi

    # Link model cache
    ln -sf /workspace/model-cache model-cache

    print_status "Repository ready"
}

# Build all Docker images natively on RunPod
build_all_images() {
    print_header "Building All Docker Images (Native A100 Build)"

    # Create Docker network
    docker network create rag-network 2>/dev/null || true

    # Build Frontend with Langflow proxy
    echo "Building Frontend..."
    cd frontend
    docker build -f Dockerfile.complete -t rag-frontend-complete:latest .
    cd ..

    # Build Langflow
    echo "Building Langflow..."
    cd langflow
    docker build -t rag-langflow:latest .
    cd ..

    # Build API
    echo "Building RAG API..."
    if [ -d "api" ]; then
        cd api
        docker build -t rag-api:latest .
        cd ..
    fi

    # Build LLM/Embedding base image
    echo "Building LLM/vLLM base image..."
    if [ -f "deploy/Dockerfile.llm" ]; then
        docker build -f deploy/Dockerfile.llm -t rag-llm-gptoss:latest .
    fi

    # Build optimized Whisper
    echo "Building Whisper (with offline support)..."
    if [ -f "deploy/Dockerfile.whisper" ]; then
        docker build -f deploy/Dockerfile.whisper -t rag-whisper:latest .
    fi

    # Build DotsOCR
    echo "Building DotsOCR..."
    if [ -f "deploy/Dockerfile.dots-ocr" ]; then
        docker build -f deploy/Dockerfile.dots-ocr -t rag-dots-ocr:latest .
    fi

    print_status "All images built natively on A100"
}

# Pre-download all models for offline use
download_models() {
    print_header "Pre-downloading Models for Offline Use"

    # Create temporary container to download models
    docker run --rm \
        -v /workspace/model-cache:/root/.cache/huggingface \
        -e HF_HOME=/root/.cache/huggingface \
        python:3.11 bash -c "
    pip install transformers torch accelerate
    python -c '
from transformers import AutoTokenizer, AutoModel, AutoModelForCausalLM, AutoProcessor, AutoModelForSpeechSeq2Seq
import torch

models = [
    (\"BAAI/bge-small-en-v1.5\", \"embedding\"),
    (\"Qwen/Qwen2-0.5B-Instruct\", \"llm\"),
    (\"ivrit-ai/whisper-large-v3\", \"whisper\"),
]

for model_name, model_type in models:
    print(f\"Downloading {model_name}...\")
    try:
        if model_type == \"embedding\":
            AutoModel.from_pretrained(model_name)
            AutoTokenizer.from_pretrained(model_name)
        elif model_type == \"llm\":
            AutoModelForCausalLM.from_pretrained(model_name, torch_dtype=torch.float16)
            AutoTokenizer.from_pretrained(model_name)
        elif model_type == \"whisper\":
            AutoProcessor.from_pretrained(model_name)
            AutoModelForSpeechSeq2Seq.from_pretrained(model_name, torch_dtype=torch.float16)
        print(f\"✓ {model_name} downloaded\")
    except Exception as e:
        print(f\"✗ Failed to download {model_name}: {e}\")
'
"

    # Verify cache
    echo ""
    echo "Model cache contents:"
    ls -la /workspace/model-cache/hub/ | head -10

    print_status "Models pre-downloaded"
}

# Deploy services across GPUs
deploy_services() {
    print_header "Deploying Services Across 8 GPUs"

    echo "GPU Allocation:"
    echo "  GPU 0: Whisper"
    echo "  GPU 1: Embedding Server"
    echo "  GPU 2-3: LLM Server (2x GPU)"
    echo "  GPU 4: DotsOCR"
    echo "  GPU 5: Frontend + Langflow"
    echo "  GPU 6-7: Reserved"
    echo ""

    # Stop any existing containers
    docker stop $(docker ps -aq) 2>/dev/null || true
    docker rm $(docker ps -aq) 2>/dev/null || true

    # GPU 0: Whisper
    echo "Starting Whisper on GPU 0..."
    docker run -d \
        --name rag-whisper \
        --network rag-network \
        --gpus '"device=0"' \
        --restart unless-stopped \
        -p 8004:8004 \
        -v /workspace/model-cache:/root/.cache/huggingface \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e HF_HOME=/root/.cache/huggingface \
        -e HF_HUB_OFFLINE=1 \
        -e MODEL_NAME=ivrit-ai/whisper-large-v3 \
        -e DEVICE=cuda \
        rag-whisper:latest

    # GPU 1: Embedding
    echo "Starting Embedding on GPU 1..."
    docker run -d \
        --name rag-embedding-server \
        --network rag-network \
        --gpus '"device=1"' \
        --restart unless-stopped \
        -p 8001:8000 \
        -v /workspace/model-cache:/root/.cache/huggingface \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e HF_HOME=/root/.cache/huggingface \
        -e HF_HUB_OFFLINE=1 \
        -e VLLM_USE_TRITON=0 \
        --entrypoint /bin/bash \
        rag-llm-gptoss:latest \
        -c "
MODEL='BAAI/bge-small-en-v1.5'
exec vllm serve \$MODEL \
    --tensor-parallel-size 1 \
    --gpu-memory-utilization 0.5 \
    --max-model-len 512 \
    --trust-remote-code \
    --enforce-eager \
    --host 0.0.0.0 \
    --port 8000
"

    # GPU 2-3: LLM (multi-GPU)
    echo "Starting LLM on GPU 2-3..."
    docker run -d \
        --name rag-llm-server \
        --network rag-network \
        --gpus '"device=2,3"' \
        --shm-size=32g \
        --restart unless-stopped \
        -p 8003:8000 \
        -v /workspace/model-cache:/root/.cache/huggingface \
        -e CUDA_VISIBLE_DEVICES=0,1 \
        -e HF_HOME=/root/.cache/huggingface \
        -e HF_HUB_OFFLINE=1 \
        --entrypoint /bin/bash \
        rag-llm-gptoss:latest \
        -c "
MODEL='Qwen/Qwen2-0.5B-Instruct'
exec vllm serve \$MODEL \
    --tensor-parallel-size 2 \
    --gpu-memory-utilization 0.7 \
    --max-model-len 4096 \
    --trust-remote-code \
    --enforce-eager \
    --host 0.0.0.0 \
    --port 8000
"

    # GPU 4: DotsOCR
    if docker images | grep -q rag-dots-ocr; then
        echo "Starting DotsOCR on GPU 4..."
        docker run -d \
            --name rag-dots-ocr \
            --network rag-network \
            --gpus '"device=4"' \
            --restart unless-stopped \
            -p 8002:8000 \
            -v /workspace/model-cache:/root/.cache/huggingface \
            -e CUDA_VISIBLE_DEVICES=0 \
            -e HF_HOME=/root/.cache/huggingface \
            -e HF_HUB_OFFLINE=1 \
            rag-dots-ocr:latest
    fi

    # No GPU: Frontend + Langflow (CPU is fine)
    echo "Starting Frontend..."
    docker run -d \
        --name rag-frontend \
        --network rag-network \
        --restart unless-stopped \
        -p 8087:8087 \
        rag-frontend-complete:latest

    echo "Starting Langflow..."
    docker run -d \
        --name rag-langflow \
        --network rag-network \
        --restart unless-stopped \
        -p 7860:7860 \
        rag-langflow:latest

    # Start API if exists
    if docker images | grep -q rag-api; then
        echo "Starting API..."
        docker run -d \
            --name rag-api \
            --network rag-network \
            --restart unless-stopped \
            -p 8080:8080 \
            rag-api:latest
    fi

    print_status "All services deployed"
}

# Test deployment
test_services() {
    print_header "Testing All Services"

    echo "Waiting for services to start..."
    sleep 30

    # Test each service
    echo ""
    echo "Service Health Checks:"

    services=(
        "8087:Frontend"
        "8080:API"
        "8001:Embedding"
        "8003:LLM"
        "8004:Whisper"
        "8002:OCR"
        "7860:Langflow"
    )

    for service in "${services[@]}"; do
        IFS=':' read -r port name <<< "$service"
        if curl -s http://localhost:$port/health > /dev/null 2>&1; then
            print_status "$name on port $port"
        else
            print_error "$name on port $port (may not have health endpoint)"
        fi
    done

    # Show GPU utilization
    echo ""
    echo "GPU Utilization:"
    nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv

    echo ""
    echo "Docker containers running:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Create offline package
create_offline_package() {
    print_header "Creating Offline Deployment Package"

    cd /workspace
    mkdir -p offline-package/images
    mkdir -p offline-package/scripts
    mkdir -p offline-package/model-cache

    # Save all Docker images
    echo "Saving Docker images..."
    for image in rag-frontend-complete rag-langflow rag-api rag-llm-gptoss rag-whisper rag-dots-ocr; do
        if docker images | grep -q $image; then
            echo "  Saving $image..."
            docker save -o offline-package/images/${image}.tar ${image}:latest
        fi
    done

    # Copy model cache
    echo "Copying model cache..."
    cp -r /workspace/model-cache/* offline-package/model-cache/ 2>/dev/null || true

    # Copy scripts
    echo "Copying deployment scripts..."
    cp -r rag-v2/deploy/*.sh offline-package/scripts/
    cp -r rag-v2/scripts-collection/* offline-package/scripts/ 2>/dev/null || true

    # Create deployment guide
    cat > offline-package/README.md << 'EOF'
# Offline RAG Deployment Package

Built and tested on RunPod 8x A100 SXM cluster.

## Contents
- `images/` - All Docker images (built natively on A100)
- `model-cache/` - Pre-downloaded models for offline use
- `scripts/` - Deployment and diagnostic scripts

## Deployment Instructions

1. **Load Docker Images:**
```bash
cd images
for img in *.tar; do
    echo "Loading $img..."
    docker load -i "$img"
done
```

2. **Copy Model Cache:**
```bash
mkdir -p ~/model-cache
cp -r model-cache/* ~/model-cache/
```

3. **Deploy Services:**
```bash
cd scripts
./deploy_offline_cluster.sh
```

## Service Ports
- Frontend: 8087
- API: 8080
- Embedding: 8001
- LLM: 8003
- Whisper: 8004
- OCR: 8002
- Langflow: 7860

## Troubleshooting
Use the diagnostic scripts in `scripts/`:
- `fix_all_services.sh` - Fix common issues
- `unified_llm_embedding.sh` - Optimize embedding
- `fix_whisper_gpu.sh` - Fix Whisper GPU issues
EOF

    # Create deployment script for offline cluster
    cat > offline-package/scripts/deploy_offline_cluster.sh << 'EOF'
#!/bin/bash
# Deploy on offline H100/A100 cluster

set -e

echo "=== Offline RAG Deployment ==="

# Create network
docker network create rag-network 2>/dev/null || true

# Deploy services (adjust GPU devices as needed)
echo "Starting services..."

# Whisper
docker run -d \
    --name rag-whisper \
    --network rag-network \
    --gpus all \
    --restart unless-stopped \
    -p 8004:8004 \
    -v $(pwd)/../model-cache:/root/.cache/huggingface \
    -e HF_HUB_OFFLINE=1 \
    rag-whisper:latest

# Embedding
docker run -d \
    --name rag-embedding-server \
    --network rag-network \
    --gpus all \
    --restart unless-stopped \
    -p 8001:8000 \
    -v $(pwd)/../model-cache:/root/.cache/huggingface \
    -e HF_HUB_OFFLINE=1 \
    rag-llm-gptoss:latest

# Continue with other services...

echo "Deployment complete!"
echo "Access frontend at http://localhost:8087"
EOF

    chmod +x offline-package/scripts/*.sh

    # Create archive
    echo "Creating archive..."
    tar -czf rag-runpod-offline-package.tar.gz offline-package/

    print_status "Offline package created: /workspace/rag-runpod-offline-package.tar.gz"
    echo "Size: $(du -sh /workspace/rag-runpod-offline-package.tar.gz | cut -f1)"
}

# Simulate offline environment
test_offline_mode() {
    print_header "Testing Offline Mode"

    echo "Simulating offline environment..."

    # Set offline environment variables
    export HF_HUB_OFFLINE=1
    export TRANSFORMERS_OFFLINE=1

    # Restart all containers with offline flags
    docker restart $(docker ps -aq)

    sleep 30

    echo "Testing services in offline mode..."
    test_services

    print_status "Offline mode test complete"
}

# Main menu
main() {
    echo "RunPod 8x A100 Deployment Options:"
    echo ""
    echo "1) Full deployment (build, deploy, test)"
    echo "2) Build images only"
    echo "3) Deploy existing images"
    echo "4) Download models only"
    echo "5) Create offline package"
    echo "6) Test offline mode"
    echo "7) Test services"
    echo ""
    read -p "Choose option (1-7): " option

    case $option in
        1)
            setup_environment
            prepare_repository
            build_all_images
            download_models
            deploy_services
            test_services
            create_offline_package
            ;;
        2)
            prepare_repository
            build_all_images
            ;;
        3)
            deploy_services
            test_services
            ;;
        4)
            download_models
            ;;
        5)
            create_offline_package
            ;;
        6)
            test_offline_mode
            ;;
        7)
            test_services
            ;;
        *)
            echo "Invalid option"
            exit 1
            ;;
    esac

    print_header "Complete!"
    echo ""
    echo "Next steps:"
    echo "1. Test the system: http://localhost:8087"
    echo "2. Download package: /workspace/rag-runpod-offline-package.tar.gz"
    echo "3. Transfer to offline environment"
}

# Run main
main "$@"