#!/bin/bash

# Build complete offline RAG system with Langflow and package everything

set -e

echo "=========================================="
echo "  BUILDING COMPLETE OFFLINE RAG SYSTEM  "
echo "=========================================="
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

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    if ! docker --version > /dev/null 2>&1; then
        print_error "Docker not installed or not running"
        exit 1
    fi

    if [[ ! -d "frontend/dist" ]]; then
        print_error "frontend/dist directory not found. Build frontend first."
        exit 1
    fi

    if [[ ! -d "langflow" ]]; then
        print_error "langflow directory not found"
        exit 1
    fi

    print_status "Prerequisites checked"
}

# Build all Docker images
build_images() {
    print_header "Building Docker Images for Linux"

    echo "Building Langflow container..."
    docker build --platform linux/amd64 -t rag-langflow:latest ./langflow/

    echo ""
    echo "Building complete frontend (with Langflow integration)..."
    docker build --platform linux/amd64 -f frontend/Dockerfile.complete -t rag-frontend-complete:latest ./frontend/

    print_status "All images built for Linux"
}

# Save all images
save_images() {
    print_header "Saving Docker Images"

    mkdir -p package/images

    echo "Saving frontend image..."
    docker save -o package/images/rag-frontend-complete.tar rag-frontend-complete:latest

    echo "Saving Langflow image..."
    docker save -o package/images/rag-langflow.tar rag-langflow:latest

    # Also save existing images if they exist
    echo ""
    echo "Checking for existing RAG images..."

    if docker images | grep -q "rag-api"; then
        echo "Saving RAG API image..."
        docker save -o package/images/rag-api.tar rag-api:latest
    fi

    if docker images | grep -q "rag-embedding-server"; then
        echo "Saving embedding server image..."
        docker save -o package/images/rag-embedding-server.tar rag-embedding-server:latest
    fi

    if docker images | grep -q "rag-llm-gptoss"; then
        echo "Saving LLM server image..."
        docker save -o package/images/rag-llm-gptoss.tar rag-llm-gptoss:latest
    fi

    if docker images | grep -q "rag-whisper"; then
        echo "Saving Whisper image..."
        docker save -o package/images/rag-whisper.tar rag-whisper:latest
    fi

    if docker images | grep -q "rag-dots-ocr"; then
        echo "Saving DotsOCR image..."
        docker save -o package/images/rag-dots-ocr.tar rag-dots-ocr:latest
    fi

    print_status "Docker images saved"
}

# Package all scripts
package_scripts() {
    print_header "Packaging Scripts and Configurations"

    mkdir -p package/scripts
    mkdir -p package/config

    echo "Copying deployment scripts..."
    cp deploy/*.sh package/scripts/

    echo "Copying Docker Compose files..."
    cp docker-compose.offline.yml package/ 2>/dev/null || echo "docker-compose.offline.yml not found, skipping"

    echo "Copying configurations..."
    cp -r config package/ 2>/dev/null || echo "config directory not found, skipping"

    echo "Copying model cache structure..."
    cp -r model-cache package/ 2>/dev/null || echo "model-cache not found, creating empty structure"
    mkdir -p package/model-cache

    echo "Creating documentation..."
    cat > package/README.md << 'EOF'
# Complete Offline RAG System Package

## Contents
- `images/` - Docker images for all services
- `scripts/` - Deployment and fix scripts
- `docker-compose.offline.yml` - Complete system orchestration
- `model-cache/` - Model cache directory (mount this for offline models)
- `config/` - Configuration files

## Quick Start

1. Load all Docker images:
   ```bash
   cd images
   for img in *.tar; do docker load -i "$img"; done
   cd ..
   ```

2. Deploy complete system:
   ```bash
   docker-compose -f docker-compose.offline.yml up -d
   ```

3. Or use individual scripts:
   ```bash
   ./scripts/fix_all_services.sh
   ```

## Available Services
- Frontend (port 8087): Complete UI with Langflow integration
- RAG API (port 8080): Main RAG functionality
- Langflow (port 7860): Flow-based AI workflows
- Individual services: Embedding (8001), LLM (8003), Whisper (8004), OCR (8002)

## Access Points
- Main UI: http://localhost:8087/
- Langflow: http://localhost:8087/langflow/
- RAG API: http://localhost:8087/api/

## Troubleshooting
- Use `scripts/fix_all_services.sh` to fix common issues
- Use `scripts/emergency_fallbacks.sh` for stubborn problems
- Use `scripts/unified_llm_embedding.sh` for simplified setup

EOF

    print_status "Scripts and configurations packaged"
}

# Create final package
create_package() {
    print_header "Creating Final Package"

    echo "Calculating package size..."
    du -sh package/

    echo ""
    echo "Creating compressed package..."
    tar -czf rag-system-complete-offline.tar.gz package/

    echo ""
    echo "Package created: rag-system-complete-offline.tar.gz"
    echo "Size: $(du -sh rag-system-complete-offline.tar.gz | cut -f1)"

    print_status "Package ready for transfer"
}

# Create deployment script for remote machine
create_deployment_script() {
    print_header "Creating Remote Deployment Script"

    cat > package/deploy_on_remote.sh << 'EOF'
#!/bin/bash

# Deploy complete RAG system on remote machine

set -e

echo "=== Deploying Complete RAG System ==="
echo ""

# Check if we're in the right directory
if [[ ! -d "images" ]] || [[ ! -d "scripts" ]]; then
    echo "Error: Must run from extracted package directory"
    echo "Make sure you extracted rag-system-complete-offline.tar.gz"
    exit 1
fi

echo "1. Loading Docker images..."
cd images
for img in *.tar; do
    if [[ -f "$img" ]]; then
        echo "Loading $img..."
        docker load -i "$img"
    fi
done
cd ..

echo ""
echo "2. Creating Docker network..."
docker network create rag-network 2>/dev/null || echo "Network already exists"

echo ""
echo "3. Starting complete system..."
if [[ -f "docker-compose.offline.yml" ]]; then
    echo "Using Docker Compose..."
    docker-compose -f docker-compose.offline.yml up -d
else
    echo "Using individual scripts..."
    chmod +x scripts/*.sh
    ./scripts/fix_all_services.sh
fi

echo ""
echo "4. Waiting for services to start..."
sleep 30

echo ""
echo "5. Testing deployment..."
echo "Frontend: $(curl -s http://localhost:8087/frontend-health || echo 'Not ready')"
echo "API: $(curl -s http://localhost:8080/health || echo 'Not ready')"
echo "Langflow: $(curl -s http://localhost:7860/health || echo 'Not ready')"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Access your system at:"
echo "  Main UI:  http://localhost:8087/"
echo "  Langflow: http://localhost:8087/langflow/"
echo "  API:      http://localhost:8087/api/"
echo ""
echo "If any services fail, run:"
echo "  ./scripts/fix_all_services.sh"
echo "  ./scripts/emergency_fallbacks.sh"
EOF

    chmod +x package/deploy_on_remote.sh
    print_status "Remote deployment script created"
}

# Main execution
main() {
    echo "This will build the complete offline RAG system with:"
    echo "  ✓ Frontend UI with Langflow integration"
    echo "  ✓ Langflow containerized workflow engine"
    echo "  ✓ All existing RAG services"
    echo "  ✓ Fix scripts for common issues"
    echo "  ✓ Complete deployment package"
    echo ""

    read -p "Continue? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    # Clean up previous package
    rm -rf package/ rag-system-complete-offline.tar.gz 2>/dev/null || true

    # Execute build steps
    check_prerequisites
    build_images
    save_images
    package_scripts
    create_deployment_script
    create_package

    # Cleanup
    rm -rf package/

    print_header "BUILD COMPLETE!"
    echo ""
    print_status "Package ready: rag-system-complete-offline.tar.gz"
    echo ""
    echo "Next steps:"
    echo "1. Transfer to your remote machine:"
    echo "   scp rag-system-complete-offline.tar.gz user@remote-machine:~/"
    echo ""
    echo "2. On remote machine:"
    echo "   tar -xzf rag-system-complete-offline.tar.gz"
    echo "   cd package"
    echo "   ./deploy_on_remote.sh"
    echo ""
    echo "3. Access your system:"
    echo "   http://remote-machine:8087/"
    echo ""
}

# Run main function
main "$@"