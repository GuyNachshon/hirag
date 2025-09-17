#!/bin/bash

# Create comprehensive offline package from RunPod deployment
# Run this ON RunPod after successful deployment

set -e

echo "============================================"
echo "   CREATING OFFLINE DEPLOYMENT PACKAGE     "
echo "============================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_header() { echo -e "\n=== $1 ==="; }

# Configuration
PACKAGE_DIR="/workspace/offline-package"
ARCHIVE_NAME="rag-system-offline-$(date +%Y%m%d-%H%M%S).tar.gz"
MODEL_CACHE="/workspace/model-cache"

# Check environment
check_environment() {
    print_header "Checking Environment"

    if [ ! -d "/workspace" ]; then
        print_error "Not running on RunPod (/workspace not found)"
        echo "This script should run on RunPod after deployment"
        exit 1
    fi

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker not installed"
        exit 1
    fi

    # Check GPU access
    if ! nvidia-smi &> /dev/null; then
        print_warning "No GPU access detected"
    else
        echo "GPU Status:"
        nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv
    fi

    print_status "Environment check complete"
}

# Verify services are running
verify_services() {
    print_header "Verifying Running Services"

    services=(
        "rag-frontend:8087"
        "rag-langflow:7860"
        "rag-api:8080"
        "rag-embedding-server:8001"
        "rag-llm-server:8003"
        "rag-whisper:8004"
        "rag-dots-ocr:8002"
    )

    all_healthy=true
    for service_port in "${services[@]}"; do
        IFS=':' read -r service port <<< "$service_port"

        if docker ps | grep -q $service; then
            # Try health check
            if curl -s http://localhost:$port/health > /dev/null 2>&1; then
                print_status "$service on port $port is healthy"
            else
                print_warning "$service on port $port is running (no health endpoint)"
            fi
        else
            print_error "$service is not running"
            all_healthy=false
        fi
    done

    if [ "$all_healthy" = false ]; then
        print_warning "Some services are not running"
        read -p "Continue anyway? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Create package structure
create_package_structure() {
    print_header "Creating Package Structure"

    # Clean and create directories
    rm -rf $PACKAGE_DIR
    mkdir -p $PACKAGE_DIR/{images,scripts,configs,model-cache,docs}

    print_status "Package structure created"
}

# Export Docker images
export_docker_images() {
    print_header "Exporting Docker Images"

    cd $PACKAGE_DIR/images

    # List of images to export
    images=(
        "rag-frontend-complete"
        "rag-langflow"
        "rag-api"
        "rag-llm-gptoss"
        "rag-whisper"
        "rag-dots-ocr"
        "rag-embedding-server"  # might be same as llm image
    )

    for image in "${images[@]}"; do
        if docker images | grep -q "^$image "; then
            echo "Exporting $image..."
            docker save -o "${image}.tar" "${image}:latest"
            size=$(du -sh "${image}.tar" | cut -f1)
            print_status "$image exported ($size)"
        else
            print_warning "$image not found, skipping"
        fi
    done

    # Calculate total size
    total_size=$(du -sh $PACKAGE_DIR/images | cut -f1)
    echo "Total images size: $total_size"
}

# Copy model cache
copy_model_cache() {
    print_header "Copying Model Cache"

    if [ -d "$MODEL_CACHE" ]; then
        echo "Copying models (this may take a while)..."

        # Copy with progress
        rsync -av --progress $MODEL_CACHE/ $PACKAGE_DIR/model-cache/

        # Verify models
        echo ""
        echo "Models copied:"
        find $PACKAGE_DIR/model-cache -name "models--*" -type d | while read model; do
            model_name=$(basename $model | sed 's/models--//' | sed 's/--/\//g')
            model_size=$(du -sh $model | cut -f1)
            echo "  - $model_name ($model_size)"
        done

        total_size=$(du -sh $PACKAGE_DIR/model-cache | cut -f1)
        print_status "Model cache copied ($total_size)"
    else
        print_warning "No model cache found at $MODEL_CACHE"
    fi
}

# Copy scripts and configurations
copy_scripts_configs() {
    print_header "Copying Scripts and Configurations"

    # Copy deployment scripts
    if [ -d "/workspace/rag-v2/deploy" ]; then
        cp -r /workspace/rag-v2/deploy/*.sh $PACKAGE_DIR/scripts/
        cp /workspace/rag-v2/deploy/gpu-distribution.yaml $PACKAGE_DIR/configs/ 2>/dev/null || true
    fi

    # Copy fix scripts
    if [ -d "/workspace/rag-v2/scripts-collection" ]; then
        cp -r /workspace/rag-v2/scripts-collection/* $PACKAGE_DIR/scripts/
    fi

    # Make all scripts executable
    chmod +x $PACKAGE_DIR/scripts/*.sh

    # Copy docker-compose if exists
    if [ -f "/workspace/rag-v2/docker-compose.offline.yml" ]; then
        cp /workspace/rag-v2/docker-compose.offline.yml $PACKAGE_DIR/configs/
    fi

    print_status "Scripts and configs copied"
}

# Create deployment documentation
create_documentation() {
    print_header "Creating Documentation"

    # Main README
    cat > $PACKAGE_DIR/README.md << 'EOF'
# Offline RAG System Deployment Package

Built and tested on RunPod 8x A100 SXM (640GB VRAM)
Package created: DATE_PLACEHOLDER

## Quick Start

1. **Extract Package:**
```bash
tar -xzf rag-system-offline-*.tar.gz
cd offline-package
```

2. **Load Docker Images:**
```bash
cd images
for img in *.tar; do
    echo "Loading $img..."
    docker load -i "$img"
done
cd ..
```

3. **Setup Model Cache:**
```bash
sudo mkdir -p /opt/model-cache
sudo cp -r model-cache/* /opt/model-cache/
# OR mount to your preferred location
export MODEL_CACHE_DIR=/opt/model-cache
```

4. **Deploy Services:**
```bash
cd scripts
./deploy_offline_cluster.sh
```

## Service Endpoints

| Service | Port | Health Check | GPU |
|---------|------|--------------|-----|
| Frontend | 8087 | /frontend-health | No |
| Langflow | 7860 | /health | No |
| API | 8080 | /health | No |
| Embedding | 8001 | /health | GPU 1 |
| LLM | 8003 | /health | GPU 2-3 |
| Whisper | 8004 | /health | GPU 0 |
| OCR | 8002 | /health | GPU 4 |

## GPU Allocation (8x A100 Reference)

See `configs/gpu-distribution.yaml` for detailed GPU allocation strategy.

## Troubleshooting

### Common Issues

1. **Service won't start:**
```bash
./scripts/fix_all_services.sh
```

2. **Model download attempts:**
```bash
./scripts/fix_llm_cache.sh
```

3. **Whisper on CPU:**
```bash
./scripts/fix_whisper_gpu.sh
```

4. **Embedding issues:**
```bash
./scripts/unified_llm_embedding.sh
```

### Emergency Fallbacks
```bash
./scripts/emergency_fallbacks.sh
```

## Verification

Test all services:
```bash
./scripts/test_all_services.sh
```

Monitor GPU usage:
```bash
watch -n 1 nvidia-smi
```

## Package Contents

- `images/` - Docker images (built on A100)
- `model-cache/` - Pre-downloaded models
- `scripts/` - Deployment and diagnostic scripts
- `configs/` - Configuration files
- `docs/` - Additional documentation
EOF

    # Replace date placeholder
    sed -i "s/DATE_PLACEHOLDER/$(date '+%Y-%m-%d %H:%M:%S')/g" $PACKAGE_DIR/README.md

    # Deployment script for offline environment
    cat > $PACKAGE_DIR/scripts/deploy_offline_cluster.sh << 'EOF'
#!/bin/bash

# Deploy RAG system in offline environment
set -e

echo "=== Offline RAG System Deployment ==="
echo ""

# Configuration
MODEL_CACHE_DIR="${MODEL_CACHE_DIR:-/opt/model-cache}"

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."

    # Docker
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker not installed"
        exit 1
    fi

    # GPU
    if ! nvidia-smi &> /dev/null; then
        echo "Warning: No GPU detected"
    fi

    # Model cache
    if [ ! -d "$MODEL_CACHE_DIR" ]; then
        echo "Error: Model cache not found at $MODEL_CACHE_DIR"
        echo "Set MODEL_CACHE_DIR or copy models to /opt/model-cache"
        exit 1
    fi

    echo "Prerequisites OK"
}

# Create network
create_network() {
    echo "Creating Docker network..."
    docker network create rag-network 2>/dev/null || true
}

# Deploy services
deploy_services() {
    echo "Deploying services..."

    # Stop existing
    docker stop $(docker ps -aq) 2>/dev/null || true
    docker rm $(docker ps -aq) 2>/dev/null || true

    # Whisper (GPU 0)
    docker run -d \
        --name rag-whisper \
        --network rag-network \
        --gpus '"device=0"' \
        --restart unless-stopped \
        -p 8004:8004 \
        -v $MODEL_CACHE_DIR:/root/.cache/huggingface \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e HF_HUB_OFFLINE=1 \
        rag-whisper:latest

    # Embedding (GPU 1)
    docker run -d \
        --name rag-embedding-server \
        --network rag-network \
        --gpus '"device=1"' \
        --restart unless-stopped \
        -p 8001:8000 \
        -v $MODEL_CACHE_DIR:/root/.cache/huggingface \
        -e HF_HUB_OFFLINE=1 \
        rag-llm-gptoss:latest \
        # Configure for embedding...

    # LLM (GPU 2-3)
    docker run -d \
        --name rag-llm-server \
        --network rag-network \
        --gpus '"device=2,3"' \
        --shm-size=32g \
        --restart unless-stopped \
        -p 8003:8000 \
        -v $MODEL_CACHE_DIR:/root/.cache/huggingface \
        -e HF_HUB_OFFLINE=1 \
        rag-llm-gptoss:latest \
        # Configure for LLM...

    # Frontend
    docker run -d \
        --name rag-frontend \
        --network rag-network \
        --restart unless-stopped \
        -p 8087:8087 \
        rag-frontend-complete:latest

    # Langflow
    docker run -d \
        --name rag-langflow \
        --network rag-network \
        --restart unless-stopped \
        -p 7860:7860 \
        rag-langflow:latest

    echo "Services deployed"
}

# Test services
test_services() {
    echo ""
    echo "Testing services..."
    sleep 20

    services=("8087:Frontend" "8001:Embedding" "8003:LLM" "8004:Whisper")
    for service in "${services[@]}"; do
        IFS=':' read -r port name <<< "$service"
        if curl -s http://localhost:$port/health > /dev/null 2>&1; then
            echo "✓ $name OK"
        else
            echo "✗ $name FAILED"
        fi
    done
}

# Main
check_prerequisites
create_network
deploy_services
test_services

echo ""
echo "=== Deployment Complete ==="
echo "Access the system at http://localhost:8087"
EOF

    chmod +x $PACKAGE_DIR/scripts/deploy_offline_cluster.sh

    # Test script
    cat > $PACKAGE_DIR/scripts/test_all_services.sh << 'EOF'
#!/bin/bash

echo "=== Testing All RAG Services ==="
echo ""

# Test each endpoint
endpoints=(
    "8087/frontend-health:Frontend"
    "7860/health:Langflow"
    "8080/health:API"
    "8001/health:Embedding"
    "8003/health:LLM"
    "8004/health:Whisper"
    "8002/health:OCR"
)

for endpoint in "${endpoints[@]}"; do
    IFS=':' read -r url name <<< "$endpoint"
    response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$url)

    if [ "$response" = "200" ]; then
        echo "✓ $name: OK (HTTP $response)"
    else
        echo "✗ $name: FAILED (HTTP $response)"
    fi
done

echo ""
echo "=== GPU Status ==="
nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used --format=csv || echo "No GPU info available"
EOF

    chmod +x $PACKAGE_DIR/scripts/test_all_services.sh

    print_status "Documentation created"
}

# Create final archive
create_archive() {
    print_header "Creating Final Archive"

    cd /workspace

    # Calculate package size
    package_size=$(du -sh $PACKAGE_DIR | cut -f1)
    echo "Package size: $package_size"

    # Create archive with progress
    echo "Creating archive: $ARCHIVE_NAME"
    tar -czf $ARCHIVE_NAME offline-package/ \
        --checkpoint=100 \
        --checkpoint-action=dot

    echo ""
    archive_size=$(du -sh $ARCHIVE_NAME | cut -f1)
    print_status "Archive created: $ARCHIVE_NAME ($archive_size)"

    # Create checksum
    sha256sum $ARCHIVE_NAME > ${ARCHIVE_NAME}.sha256
    print_status "Checksum created: ${ARCHIVE_NAME}.sha256"
}

# Cleanup
cleanup() {
    print_header "Cleanup"

    read -p "Remove temporary package directory? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        rm -rf $PACKAGE_DIR
        print_status "Temporary files removed"
    fi
}

# Main execution
main() {
    echo "This will create a complete offline deployment package"
    echo "from your RunPod deployment."
    echo ""
    echo "Requirements:"
    echo "  - All services should be running"
    echo "  - Models should be cached"
    echo "  - ~100GB free disk space"
    echo ""

    read -p "Continue? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 0
    fi

    check_environment
    verify_services
    create_package_structure
    export_docker_images
    copy_model_cache
    copy_scripts_configs
    create_documentation
    create_archive
    cleanup

    print_header "SUCCESS!"
    echo ""
    echo "Package created: /workspace/$ARCHIVE_NAME"
    echo ""
    echo "To deploy on offline system:"
    echo "1. Transfer: scp $ARCHIVE_NAME user@offline-host:~/"
    echo "2. Extract: tar -xzf $ARCHIVE_NAME"
    echo "3. Deploy: cd offline-package && ./scripts/deploy_offline_cluster.sh"
    echo ""
}

# Run main
main "$@"