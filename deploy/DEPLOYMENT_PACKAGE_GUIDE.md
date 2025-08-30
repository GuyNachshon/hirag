# RAG System Deployment Package Guide

This guide explains how to use the comprehensive deployment package creation and distribution system for the RAG system.

## Overview

The `create_deployment_package.sh` script provides a complete solution for:

1. **Building** all optimized Docker images with pre-downloaded models
2. **Exporting** images as transportable tar files  
3. **Packaging** everything with deployment scripts and documentation
4. **Uploading** to Google Cloud Storage for distribution
5. **Creating** a complete offline deployment package

## Quick Start

### Basic Usage

```bash
cd deploy
./create_deployment_package.sh
```

This will:
- Build all Docker images with optimizations
- Create deployment package with all components
- Upload to default GCP bucket: `gs://baddon-ai-deployment`

### Custom Bucket

```bash
./create_deployment_package.sh --bucket gs://my-custom-bucket
```

### Skip Build (Use Existing Images)

```bash
./create_deployment_package.sh --skip-build --bucket gs://my-bucket
```

## Prerequisites

### System Requirements

1. **Docker Engine** - Must be running
2. **Google Cloud SDK** - With `gcloud` and `gsutil`
3. **Authentication** - Valid GCP credentials
4. **Disk Space** - ~150GB free for image exports
5. **Network** - Internet access for model downloads and GCP upload

### GCP Authentication

Ensure you're authenticated with Google Cloud:

```bash
# Login if needed
gcloud auth login

# Check current authentication
gcloud auth list

# Verify bucket access (replace with your bucket)
gsutil ls gs://your-bucket-name
```

## What Gets Created

### Package Structure

```
rag-system-deployment_v1.0.0_20250830_143022/
├── README.md                           # Package overview and instructions
├── images/                             # Docker images as tar files
│   ├── rag-api_latest.tar             # FastAPI backend (~2GB)
│   ├── rag-llm-gptoss_latest.tar      # Large LLM (~16GB)
│   ├── rag-llm-small_latest.tar       # Small LLM (~8GB)
│   ├── rag-embedding-server_latest.tar # Embedding service (~3GB)
│   ├── rag-dots-ocr_latest.tar        # Vision OCR (~7GB)
│   ├── rag-whisper_latest.tar         # Hebrew transcription (~4GB)
│   ├── rag-frontend_latest.tar        # Vue.js frontend (~100MB)
│   └── MANIFEST.md                     # Image inventory and import guide
├── scripts/                            # Deployment automation
│   ├── import_images.sh               # Import all Docker images
│   ├── deploy_complete.sh             # Deploy all services
│   ├── setup_network.sh               # Configure Docker networking
│   ├── validate_offline_deployment.sh # Health checks
│   ├── test_services_sequential.sh    # GPU memory-aware testing
│   └── test_service_functions.sh      # Test utilities
├── config/                            # Configuration templates
│   └── config.yaml.template          # Service configuration
└── docs/                              # Complete documentation
    ├── OFFLINE_DEPLOYMENT.md         # Deployment guide
    ├── SEQUENTIAL_TESTING.md         # Testing strategies
    ├── TEST_QUICK_REFERENCE.md       # Quick commands
    └── DEPLOY_README.md              # Additional deployment info
```

### Final Deliverable

- **Compressed Package**: `rag-system-deployment_v1.0.0_TIMESTAMP.tar.gz` (~40GB)
- **GCP Upload**: Automatically uploaded to specified bucket
- **Complete Documentation**: All guides included in package

## Deployment on Target System

### Step 1: Download Package

```bash
# Download from GCP bucket
gsutil cp gs://your-bucket/rag-system-deployment_v1.0.0_*.tar.gz .

# Extract package
tar -xzf rag-system-deployment_v1.0.0_*.tar.gz
cd rag-system-deployment_v1.0.0_*/
```

### Step 2: Import Images

```bash
cd scripts
./import_images.sh
```

This imports all 7 Docker images and verifies they loaded correctly.

### Step 3: Deploy Services

```bash
./setup_network.sh      # Create Docker network
./deploy_complete.sh    # Start all services
```

### Step 4: Validate Deployment

```bash
./validate_offline_deployment.sh
```

### Step 5: Testing (Optional)

```bash
# For GPU-constrained environments
./test_services_sequential.sh

# Quick reference for testing commands
cat ../docs/TEST_QUICK_REFERENCE.md
```

## Advanced Usage

### Package Customization

You can modify the script to customize the package:

```bash
# Edit configuration
vim deploy/create_deployment_package.sh

# Key variables:
PACKAGE_NAME="rag-system-deployment"
PACKAGE_VERSION="v1.0.0"
GCP_BUCKET="gs://your-custom-bucket"
```

### Selective Service Building

To build only specific services, modify the `BUILD_SERVICES` array in `build_all_offline.sh`.

### Custom Documentation

Add custom documentation to the package by placing files in `deploy/docs/` - they will be automatically included.

## Troubleshooting

### Common Issues

**Docker not running:**
```bash
# Start Docker
sudo systemctl start docker  # Linux
# or open Docker Desktop      # macOS/Windows
```

**GCP authentication failed:**
```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

**Insufficient disk space:**
```bash
# Check disk space
df -h

# Clean up Docker images
docker system prune -a
```

**Upload failed:**
```bash
# Check bucket permissions
gsutil ls -l gs://your-bucket/

# Test bucket write access
echo "test" | gsutil cp - gs://your-bucket/test.txt
gsutil rm gs://your-bucket/test.txt
```

### Build Failures

If image building fails:

```bash
# Check Docker logs
docker logs [container-name]

# Build specific service manually
docker build -f deploy/Dockerfile.embedding -t rag-embedding-server:latest .

# Skip build and use existing images
./create_deployment_package.sh --skip-build
```

### Size Optimization

The script creates optimized multi-stage Docker builds, but you can further optimize:

1. **Use smaller models** - Edit Dockerfiles to use smaller model variants
2. **Remove unnecessary services** - Comment out services you don't need
3. **Compress more aggressively** - Use `xz` instead of `gzip` for better compression

## Script Output Example

```bash
$ ./create_deployment_package.sh --bucket gs://my-deployment-bucket

==========================================
RAG System Deployment Package Creator
Version: v1.0.0
==========================================

[STEP] Checking prerequisites...
[INFO] Authenticated accounts:
ACTIVE  ACCOUNT
*       user@company.com
[INFO] Using GCP bucket: gs://my-deployment-bucket

[STEP] Building all Docker images with optimizations...
[INFO] Building dots-ocr service...
[INFO] ✓ Successfully built dots-ocr
...

[STEP] Creating deployment package structure...
[INFO] ✓ Package structure created: rag-system-deployment_v1.0.0_20250830_143022

[STEP] Exporting Docker images...
[INFO] Exporting rag-frontend:latest -> rag-frontend_latest.tar
[INFO] ✓ Exported rag-frontend:latest
...

[STEP] Uploading deployment package to GCP bucket...
[INFO] ✓ Successfully uploaded to GCP bucket
[INFO] Package URL: gs://my-deployment-bucket/rag-system-deployment_v1.0.0_20250830_143022.tar.gz

======================================
🎉 RAG System Deployment Package Ready!
======================================

📦 Package: rag-system-deployment_v1.0.0_20250830_143022.tar.gz
📏 Size: 42G
🔗 GCP URL: gs://my-deployment-bucket/rag-system-deployment_v1.0.0_20250830_143022.tar.gz
📅 Created: Fri Aug 30 14:30:22 UTC 2025
```

## Security Considerations

1. **GCP Bucket Permissions** - Ensure bucket has appropriate access controls
2. **Authentication** - Use service accounts for automated deployments  
3. **Model Security** - All models are pre-downloaded and contained within images
4. **Network Security** - Configure firewall rules as needed on target systems

## Best Practices

1. **Version Control** - Tag your deployment packages with meaningful versions
2. **Testing** - Always test deployment packages on staging environments first
3. **Documentation** - Keep deployment documentation updated with any customizations
4. **Monitoring** - Set up logging and monitoring for deployed services
5. **Backup** - Keep copies of working deployment packages for rollback capability

## Support

For issues with the deployment package script:

1. Check the script output for specific error messages
2. Verify all prerequisites are met
3. Review the logs in the `docs/` directory of your package
4. Test individual components (Docker, GCP auth, etc.) separately

## Integration with CI/CD

The script can be integrated into CI/CD pipelines:

```yaml
# GitHub Actions example
- name: Create Deployment Package
  run: |
    ./deploy/create_deployment_package.sh --bucket ${{ secrets.GCP_BUCKET }}
  env:
    GOOGLE_APPLICATION_CREDENTIALS: ${{ secrets.GCP_SA_KEY }}
```

This provides a complete, automated solution for building, packaging, and distributing your RAG system for offline deployment.