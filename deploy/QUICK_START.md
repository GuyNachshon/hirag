# Quick Start Guide

## Complete Deployment Package Creation

### 1. Basic Usage (Full Pipeline)

```bash
cd deploy
./create_deployment_package.sh --bucket gs://baddon-ai-deployment
```

This will:
- ✅ Build all Docker images with optimized multi-stage builds
- ✅ Export 7 Docker images as tar files (~40GB total)
- ✅ Create complete deployment package with scripts and docs
- ✅ Upload compressed package to GCP bucket
- ✅ Provide download instructions for target systems

### 2. Test with Existing Images

If you already have images built and want to test the packaging:

```bash
./create_deployment_package.sh --skip-build --bucket gs://baddon-ai-deployment
```

### 3. Custom Bucket (Auto-Created if Needed)

```bash
./create_deployment_package.sh --bucket gs://your-custom-bucket-name
```

**Note**: If the bucket doesn't exist, you'll be prompted to create it automatically with a 90-day lifecycle policy.

## What You'll Get

### Package Contents
```
📦 rag-system-deployment_v1.0.0_20250830_143022.tar.gz (42GB)
├── 🗂️ images/           # 7 Docker images as tar files
├── 🛠️ scripts/          # All deployment scripts
├── 📚 docs/             # Complete documentation  
├── ⚙️ config/           # Configuration templates
└── 📋 README.md         # Package instructions
```

### Services Included
- **API Backend** (FastAPI + HiRAG) - 2GB
- **Large LLM** (GPT-OSS 20B) - 16GB  
- **Small LLM** (Qwen 4B) - 8GB
- **Embedding** (Qwen 0.5B) - 3GB
- **DotsOCR** (Vision OCR) - 7GB
- **Whisper** (Hebrew transcription) - 4GB
- **Frontend** (Vue.js) - 100MB

## Deployment on Target System

### Download and Extract
```bash
gsutil cp gs://baddon-ai-deployment/rag-system-deployment_*.tar.gz .
tar -xzf rag-system-deployment_*.tar.gz
cd rag-system-deployment_*/
```

### Deploy (3 Commands)
```bash
cd scripts
./import_images.sh      # Import all Docker images
./deploy_complete.sh    # Start all services
./validate_offline_deployment.sh  # Verify everything works
```

## Expected Output

```bash
[INFO] Checking prerequisites...
[INFO] Using GCP bucket: gs://baddon-ai-deployment

[STEP] Building all Docker images with optimizations...
[INFO] Building dots-ocr service...
[INFO] ✓ Successfully built dots-ocr
[INFO] Building embedding service...
[INFO] ✓ Successfully built embedding
# ... (builds all 7 services)

[STEP] Exporting Docker images...
[INFO] Exporting rag-frontend:latest -> rag-frontend_latest.tar
[INFO] ✓ Exported rag-frontend:latest
# ... (exports all images)

[STEP] Creating deployment package...
[INFO] ✓ Package structure created

[STEP] Uploading to GCP bucket...
[INFO] ✓ Successfully uploaded to GCP bucket

======================================
🎉 RAG System Deployment Package Ready!
======================================
📦 Package: rag-system-deployment_v1.0.0_20250830_143022.tar.gz
📏 Size: 42G
🔗 GCP URL: gs://baddon-ai-deployment/rag-system-deployment_v1.0.0_20250830_143022.tar.gz
```

## Troubleshooting

### Authentication
```bash
gcloud auth list  # Check if authenticated
gcloud auth login  # Login if needed
```

### Docker Issues
```bash
docker info  # Check if Docker is running
sudo systemctl start docker  # Start Docker (Linux)
```

### Disk Space
```bash
df -h  # Check available space (need ~150GB)
docker system prune -a  # Clean up old images
```

## Help

```bash
./create_deployment_package.sh --help
```

For detailed documentation, see `DEPLOYMENT_PACKAGE_GUIDE.md`.