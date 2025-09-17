#!/bin/bash

# Build frontend+Langflow package with diagnostic scripts only

set -e

echo "=========================================="
echo "  BUILDING FRONTEND+LANGFLOW PACKAGE    "
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

# Build frontend proxy + separate Langflow images
build_frontend_langflow() {
    print_header "Building Frontend+Langflow Images for Linux"

    echo "Building frontend with Langflow proxy..."
    docker build --platform linux/amd64 -f frontend/Dockerfile.complete -t rag-frontend-complete:latest ./frontend/

    echo ""
    echo "Building separate Langflow container..."
    docker build --platform linux/amd64 -t rag-langflow:latest ./langflow/

    print_status "Frontend proxy + Langflow images built for Linux"
}

# Save frontend+Langflow images
save_frontend_images() {
    print_header "Saving Frontend+Langflow Images"

    mkdir -p package/images

    echo "Saving frontend proxy image..."
    docker save -o package/images/rag-frontend-complete.tar rag-frontend-complete:latest

    echo "Saving Langflow image..."
    docker save -o package/images/rag-langflow.tar rag-langflow:latest

    print_status "Frontend and Langflow images saved"
}

# Package diagnostic and fix scripts
package_diagnostic_scripts() {
    print_header "Packaging Diagnostic and Fix Scripts"

    mkdir -p package/scripts

    echo "Copying core fix scripts..."
    # Core fix scripts
    cp deploy/fix_all_services.sh package/scripts/
    cp deploy/unified_llm_embedding.sh package/scripts/
    cp deploy/fix_embedding_with_existing_vllm.sh package/scripts/
    cp deploy/emergency_fallbacks.sh package/scripts/

    echo "Copying embedding fix scripts..."
    # Embedding-specific fixes
    cp deploy/fix_embedding_simple.sh package/scripts/
    cp deploy/fix_embedding_offline.sh package/scripts/
    cp deploy/fallback_cpu_embeddings.sh package/scripts/

    echo "Copying frontend and model scripts..."
    # Frontend and model fixes
    cp deploy/fix_frontend_nginx.sh package/scripts/
    cp deploy/fix_model_paths.sh package/scripts/
    cp deploy/fix_llm_cache.sh package/scripts/
    cp deploy/quick_frontend_fix.sh package/scripts/

    echo "Copying diagnostic scripts..."
    # Diagnostic tools
    cp deploy/diagnose_frontend.sh package/scripts/
    cp deploy/diagnose_gpu_issues.sh package/scripts/
    cp deploy/mount_model_cache.sh package/scripts/

    echo "Copying deployment scripts..."
    # Deployment helpers
    cp deploy/deploy_a100_single_gpu.sh package/scripts/
    [[ -f "deploy/setup_network.sh" ]] && cp deploy/setup_network.sh package/scripts/
    [[ -f "deploy/rebuild_modified_services.sh" ]] && cp deploy/rebuild_modified_services.sh package/scripts/

    echo "Making scripts executable..."
    chmod +x package/scripts/*.sh

    # Create a script index
    cat > package/scripts/README.md << 'EOF'
# Diagnostic and Fix Scripts

## Core Fix Scripts
- `fix_all_services.sh` - Master script to fix all common issues
- `unified_llm_embedding.sh` - Use single LLM server for both tasks
- `emergency_fallbacks.sh` - Last resort fixes when others fail

## Embedding Service Fixes
- `fix_embedding_with_existing_vllm.sh` - Use existing vLLM container for embeddings
- `fix_embedding_simple.sh` - Simple embedding server fix
- `fix_embedding_offline.sh` - Offline embedding configuration
- `fallback_cpu_embeddings.sh` - CPU-only embedding fallback

## Frontend and Model Fixes
- `fix_frontend_nginx.sh` - Fix nginx configuration issues
- `fix_model_paths.sh` - Fix model path and cache issues
- `fix_llm_cache.sh` - Fix LLM cache mounting
- `quick_frontend_fix.sh` - Quick frontend fixes

## Diagnostic Tools
- `diagnose_frontend.sh` - Frontend troubleshooting
- `diagnose_gpu_issues.sh` - GPU access diagnostics
- `mount_model_cache.sh` - Model cache setup

## Deployment Helpers
- `deploy_a100_single_gpu.sh` - A100 deployment script
- `setup_network.sh` - Docker network setup
- `rebuild_modified_services.sh` - Rebuild specific services

## Usage
Start with `fix_all_services.sh` for most common issues. Use specialized scripts for specific problems.
EOF

    print_status "All diagnostic and fix scripts packaged"
}

# Create documentation
create_documentation() {
    print_header "Creating Documentation"

    cat > package/README.md << 'EOF'
# Frontend+Langflow Package with Diagnostic Scripts

## Contents
- `images/rag-frontend-complete.tar` - Frontend proxy with Langflow routing
- `images/rag-langflow.tar` - Separate Langflow container
- `scripts/` - Diagnostic and fix scripts for RAG services

## Quick Start

1. Load both images:
   ```bash
   docker load -i images/rag-frontend-complete.tar
   docker load -i images/rag-langflow.tar
   ```

2. Start Langflow:
   ```bash
   docker run -d \
     --name rag-langflow \
     --network rag-network \
     -p 7860:7860 \
     rag-langflow:latest
   ```

3. Start frontend proxy:
   ```bash
   docker run -d \
     --name rag-frontend \
     --network rag-network \
     -p 8087:8087 \
     rag-frontend-complete:latest
   ```

## Available Scripts

### Main Fix Script
- `fix_all_services.sh` - Master script to fix all common RAG service issues

### Specialized Fix Scripts
- `unified_llm_embedding.sh` - Use single LLM server for both generation and embeddings
- `fix_embedding_with_existing_vllm.sh` - Fix embedding server using existing vLLM container
- `emergency_fallbacks.sh` - Emergency solutions when main fixes don't work

### Other Diagnostic Scripts
- Various deployment and diagnostic scripts from the deploy directory

## Service Access Points
- Main UI: http://localhost:8087/
- Langflow: http://localhost:8087/langflow/
- API proxy: http://localhost:8087/api/ (routes to your RAG API)

## Troubleshooting

1. **Frontend Issues**: The frontend includes proper nginx configuration for Edge browser compatibility and MIME type handling

2. **RAG Service Issues**: Use the diagnostic scripts to fix common problems:
   ```bash
   ./scripts/fix_all_services.sh        # Fix all services
   ./scripts/unified_llm_embedding.sh   # Simplify to unified approach
   ./scripts/emergency_fallbacks.sh     # Last resort fixes
   ```

3. **Offline Environment**: All components are designed for offline/airgapped deployment

## Notes
- This package assumes you already have your RAG service images (API, LLM, embedding, etc.)
- The frontend is configured to work with your existing RAG services
- All scripts are designed for offline environments with no internet access
EOF

    print_status "Documentation created"
}

# Create deployment script for remote machine
create_deployment_script() {
    print_header "Creating Remote Deployment Script"

    cat > package/deploy_frontend_langflow.sh << 'EOF'
#!/bin/bash

# Deploy frontend+Langflow on remote machine

set -e

echo "=== Deploying Frontend+Langflow ===="
echo ""

# Check if we're in the right directory
if [[ ! -d "images" ]] || [[ ! -d "scripts" ]]; then
    echo "Error: Must run from extracted package directory"
    exit 1
fi

echo "1. Loading images..."
if [[ -f "images/rag-frontend-complete.tar" ]]; then
    echo "Loading rag-frontend-complete.tar..."
    docker load -i images/rag-frontend-complete.tar
else
    echo "Error: rag-frontend-complete.tar not found"
    exit 1
fi

if [[ -f "images/rag-langflow.tar" ]]; then
    echo "Loading rag-langflow.tar..."
    docker load -i images/rag-langflow.tar
else
    echo "Error: rag-langflow.tar not found"
    exit 1
fi

echo ""
echo "2. Creating Docker network..."
docker network create rag-network 2>/dev/null || echo "Network already exists"

echo ""
echo "3. Starting Langflow..."
docker run -d \
    --name rag-langflow \
    --network rag-network \
    --restart unless-stopped \
    -p 7860:7860 \
    rag-langflow:latest

echo ""
echo "4. Starting frontend proxy..."
docker run -d \
    --name rag-frontend \
    --network rag-network \
    --restart unless-stopped \
    -p 8087:8087 \
    rag-frontend-complete:latest

echo ""
echo "5. Waiting for services to start..."
sleep 15

echo ""
echo "5. Testing deployment..."
echo "Frontend: $(curl -s http://localhost:8087/frontend-health || echo 'Not ready')"

echo ""
echo "=== Frontend+Langflow Deployment Complete ===="
echo ""
echo "Access your system at:"
echo "  Main UI:  http://localhost:8087/"
echo "  Langflow: http://localhost:8087/langflow/"
echo ""
echo "To fix RAG services, use the diagnostic scripts:"
echo "  ./scripts/fix_all_services.sh"
echo "  ./scripts/unified_llm_embedding.sh"
echo "  ./scripts/emergency_fallbacks.sh"
EOF

    chmod +x package/deploy_frontend_langflow.sh
    print_status "Remote deployment script created"
}

# Create final package
create_package() {
    print_header "Creating Final Package"

    echo "Calculating package size..."
    du -sh package/

    echo ""
    echo "Creating compressed package..."
    tar -czf rag-frontend-langflow-package.tar.gz package/

    echo ""
    echo "Package created: rag-frontend-langflow-package.tar.gz"
    echo "Size: $(du -sh rag-frontend-langflow-package.tar.gz | cut -f1)"

    print_status "Package ready for transfer"
}

# Main execution
main() {
    echo "This will build a lightweight package containing:"
    echo "  ✓ Frontend UI with Langflow integration (Docker image)"
    echo "  ✓ Diagnostic and fix scripts for RAG services"
    echo "  ✓ Remote deployment script"
    echo ""
    echo "This package assumes you already have RAG service images."
    echo ""

    read -p "Continue? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    # Clean up previous package
    rm -rf package/ rag-frontend-langflow-package.tar.gz 2>/dev/null || true

    # Execute build steps
    check_prerequisites
    build_frontend_langflow
    save_frontend_images
    package_diagnostic_scripts
    create_documentation
    create_deployment_script
    create_package

    # Cleanup
    rm -rf package/

    print_header "BUILD COMPLETE!"
    echo ""
    print_status "Package ready: rag-frontend-langflow-package.tar.gz"
    echo ""
    echo "Next steps:"
    echo "1. Transfer to your remote machine:"
    echo "   scp rag-frontend-langflow-package.tar.gz user@remote-machine:~/"
    echo ""
    echo "2. On remote machine:"
    echo "   tar -xzf rag-frontend-langflow-package.tar.gz"
    echo "   cd package"
    echo "   ./deploy_frontend_langflow.sh"
    echo ""
    echo "3. Use diagnostic scripts to fix RAG services:"
    echo "   ./scripts/fix_all_services.sh"
    echo ""
}

# Run main function
main "$@"