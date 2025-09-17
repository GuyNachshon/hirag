# Offline Deployment Guide

This guide provides comprehensive instructions for deploying the RAG system in completely offline (airgapped) environments, including preparation, packaging, and deployment procedures.

## Overview

The offline deployment strategy enables running the RAG system without any internet connectivity, suitable for secure environments, airgapped networks, and isolated deployments.

### Key Features
- **Zero Internet Dependency**: All models and dependencies pre-cached
- **Complete Package**: Docker images, models, and configurations bundled
- **GPU Optimization**: Configured for H100 and A100 clusters
- **Hebrew Support**: Optimized for Hebrew text and audio processing
- **Verification Tools**: Built-in testing and validation scripts

---

## Prerequisites

### Source System Requirements (RunPod/Build Environment)
- **GPU**: 8x A100 SXM (640GB VRAM) recommended
- **CPU**: 32+ cores
- **Memory**: 128GB+ RAM
- **Storage**: 1TB+ available space
- **Network**: High-speed internet for initial model downloads
- **Docker**: Latest version with GPU support

### Target System Requirements (Offline Environment)
- **GPU**: H100 cluster or 8x A100 SXM minimum
- **CPU**: 32+ cores
- **Memory**: 128GB+ RAM
- **Storage**: 500GB+ for deployment
- **OS**: Ubuntu 20.04+ or compatible Linux distribution
- **Docker**: Pre-installed with NVIDIA container runtime

---

## Phase 1: Package Creation (Online Environment)

### Step 1: Deploy on RunPod

#### 1.1 Initial Deployment
```bash
# Clone repository
git clone https://github.com/your-org/rag-system.git
cd rag-system/runpod-deployment

# Build all Docker images
./scripts/build_all_images.sh

# Deploy services
docker-compose -f configs/docker-compose.yaml up -d

# Verify deployment
./scripts/test_all_services.sh
```

#### 1.2 Model Pre-caching
```bash
# Download and cache all models
./scripts/download_models.sh

# Verify model cache
ls -la /workspace/model-cache/
```

**Expected Model Cache Structure**:
```
model-cache/
├── models--ivrit-ai--whisper-v2_he/
├── models--sentence-transformers--all-MiniLM-L6-v2/
├── models--microsoft--DialoGPT-medium/
├── models--microsoft--DialoGPT-small/
└── models--huggingface--CodeBERTa-small-v1/
```

### Step 2: Package Creation

#### 2.1 Run Package Creation Script
```bash
# Create comprehensive offline package
./scripts/create_offline_package_runpod.sh
```

This script will:
- Verify all services are running
- Export Docker images to tar files
- Copy model cache (50GB+)
- Bundle deployment scripts and configurations
- Create documentation and validation tools
- Generate final archive with checksum

#### 2.2 Package Contents
```
offline-package/
├── images/                      # Docker images (tar files)
│   ├── rag-frontend-complete.tar
│   ├── rag-langflow.tar
│   ├── rag-api.tar
│   ├── rag-llm-gptoss.tar
│   ├── rag-whisper.tar
│   └── rag-dots-ocr.tar
├── model-cache/                 # Pre-downloaded models
│   └── [HuggingFace model cache structure]
├── scripts/                     # Deployment and utility scripts
│   ├── deploy_offline_cluster.sh
│   ├── test_all_services.sh
│   ├── fix_all_services.sh
│   └── emergency_fallbacks.sh
├── configs/                     # Configuration files
│   ├── docker-compose.yaml
│   ├── hirag-config.yaml
│   └── gpu-distribution.yaml
├── docs/                        # Documentation
│   ├── API_ENDPOINTS.md
│   ├── GPU_ALLOCATION.md
│   └── TROUBLESHOOTING.md
└── README.md                    # Quick start guide
```

#### 2.3 Package Verification
```bash
# Verify package integrity
sha256sum -c rag-system-offline-*.tar.gz.sha256

# Check package size
du -sh rag-system-offline-*.tar.gz
# Expected: ~80-150GB depending on models
```

---

## Phase 2: Package Transfer

### Transfer Methods

#### Method 1: Secure File Transfer
```bash
# Using SCP
scp rag-system-offline-*.tar.gz user@offline-host:~/

# Using rsync with compression
rsync -avz --progress rag-system-offline-*.tar.gz user@offline-host:~/
```

#### Method 2: Physical Media
1. Copy package to external storage device
2. Transfer to offline environment
3. Verify checksum after transfer

#### Method 3: Secure Network Transfer
```bash
# Using secure tunnel
ssh -L 8080:offline-host:22 bastion-host
scp -P 8080 rag-system-offline-*.tar.gz user@localhost:~/
```

---

## Phase 3: Offline Deployment

### Step 1: Environment Preparation

#### 1.1 System Prerequisites
```bash
# Verify Docker installation
docker --version
docker-compose --version

# Check NVIDIA Docker runtime
docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi

# Verify GPU availability
nvidia-smi
```

#### 1.2 Extract Package
```bash
# Extract deployment package
tar -xzf rag-system-offline-*.tar.gz
cd offline-package

# Verify extraction
ls -la
```

### Step 2: Load Docker Images

#### 2.1 Load All Images
```bash
# Navigate to images directory
cd images

# Load all Docker images
for img in *.tar; do
    echo "Loading $img..."
    docker load -i "$img"
done

# Verify loaded images
docker images | grep rag-
```

**Expected Images**:
```
rag-frontend-complete    latest    abc123    2GB
rag-langflow            latest    def456    1.5GB
rag-api                 latest    ghi789    800MB
rag-llm-gptoss          latest    jkl012    15GB
rag-whisper             latest    mno345    8GB
rag-dots-ocr            latest    pqr678    12GB
```

### Step 3: Model Cache Setup

#### 3.1 Create Model Cache Directory
```bash
# Create model cache directory
sudo mkdir -p /opt/model-cache
sudo chown $USER:$USER /opt/model-cache

# Copy models from package
cp -r model-cache/* /opt/model-cache/

# Set environment variable
export MODEL_CACHE_DIR=/opt/model-cache
echo "export MODEL_CACHE_DIR=/opt/model-cache" >> ~/.bashrc
```

#### 3.2 Verify Model Cache
```bash
# Check model cache structure
find /opt/model-cache -name "models--*" -type d

# Verify model sizes
du -sh /opt/model-cache/*
```

### Step 4: Service Deployment

#### 4.1 Configure Environment
```bash
# Set offline environment variables
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export VLLM_USE_TRITON=0

# Set GPU configuration
export CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
```

#### 4.2 Deploy Services
```bash
# Navigate to package root
cd /path/to/offline-package

# Deploy using the deployment script
./scripts/deploy_offline_cluster.sh
```

**Manual Deployment (Alternative)**:
```bash
# Create Docker network
docker network create rag-network

# Deploy services using docker-compose
docker-compose -f configs/docker-compose.yaml up -d

# Monitor deployment
docker-compose -f configs/docker-compose.yaml logs -f
```

### Step 5: Service Verification

#### 5.1 Health Checks
```bash
# Run comprehensive test suite
./scripts/test_all_services.sh

# Check individual services
curl http://localhost:8087/frontend-health  # Frontend
curl http://localhost:8080/health           # API
curl http://localhost:8001/health           # Embedding
curl http://localhost:8003/health           # LLM
curl http://localhost:8004/health           # Whisper
curl http://localhost:8002/health           # OCR
```

#### 5.2 Functional Testing
```bash
# Test file search
curl "http://localhost:8080/api/search/files?q=test&limit=5"

# Test chat functionality
curl -X POST http://localhost:8080/api/chat/sessions \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Session"}'

# Test embedding generation
curl -X POST http://localhost:8001/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"input": "test text", "model": "embedding"}'
```

---

## Phase 4: Optimization and Monitoring

### Performance Optimization

#### 4.1 GPU Configuration
```bash
# Check GPU allocation
nvidia-smi

# Verify service GPU usage
docker exec rag-whisper nvidia-smi
docker exec rag-llm-server nvidia-smi
```

#### 4.2 Memory Optimization
```bash
# Monitor container memory usage
docker stats --no-stream

# Adjust memory limits if needed
docker update --memory 32g rag-llm-server
```

### Monitoring Setup

#### 4.1 Log Monitoring
```bash
# Create log directories
mkdir -p logs/{api,frontend,llm,embedding,whisper,ocr}

# Monitor real-time logs
tail -f logs/api/api_main.log
tail -f logs/llm/service.log
```

#### 4.2 Performance Monitoring
```bash
# GPU monitoring
watch -n 1 nvidia-smi

# System resource monitoring
htop

# Container monitoring
docker stats
```

---

## Troubleshooting

### Common Issues

#### 1. Services Not Starting
```bash
# Check container logs
docker logs rag-llm-server

# Verify GPU access
docker exec rag-llm-server nvidia-smi

# Check model cache mounting
docker exec rag-llm-server ls -la /root/.cache/huggingface
```

#### 2. Model Loading Failures
```bash
# Verify offline environment variables
docker exec rag-llm-server env | grep HF_HUB_OFFLINE

# Check model files
docker exec rag-llm-server find /root/.cache/huggingface -name "*.bin"

# Test model loading
docker exec rag-llm-server python -c "from transformers import AutoTokenizer; AutoTokenizer.from_pretrained('microsoft/DialoGPT-medium', local_files_only=True)"
```

#### 3. Network Connectivity Issues
```bash
# Check Docker network
docker network ls
docker network inspect rag-network

# Test inter-service communication
docker exec rag-api curl http://rag-llm-server:8000/health
```

### Emergency Procedures

#### 4.1 Service Recovery
```bash
# Restart all services
docker-compose -f configs/docker-compose.yaml restart

# Individual service restart
docker restart rag-llm-server

# Check service dependencies
docker-compose -f configs/docker-compose.yaml ps
```

#### 4.2 Fallback to CPU Mode
```bash
# Run emergency fallback script
./scripts/emergency_fallbacks.sh

# This will:
# - Stop GPU services
# - Start CPU-only versions
# - Update configurations
```

---

## Validation and Testing

### Comprehensive Testing Suite

#### 1. System Integration Test
```bash
# Run full test suite
./scripts/comprehensive_test.sh

# This includes:
# - Service health checks
# - API endpoint testing
# - Model functionality verification
# - GPU utilization validation
# - Performance benchmarking
```

#### 2. Load Testing
```bash
# Test concurrent requests
./scripts/load_test.sh

# Monitor performance during load
watch -n 1 'docker stats --no-stream | head -20'
```

#### 3. Offline Compliance Verification
```bash
# Verify no external network access
./scripts/verify_offline_mode.sh

# Check for download attempts in logs
grep -r "download\|fetch\|http" logs/ | grep -v "localhost\|127.0.0.1"
```

---

## Maintenance Procedures

### Regular Maintenance

#### 1. Log Rotation
```bash
# Setup log rotation
sudo cat > /etc/logrotate.d/rag-system << EOF
/path/to/offline-package/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    copytruncate
    notifempty
}
EOF
```

#### 2. Health Monitoring
```bash
# Create monitoring script
cat > daily_health_check.sh << 'EOF'
#!/bin/bash
echo "=== Daily Health Check $(date) ==="
./scripts/test_all_services.sh
nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used --format=csv
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
EOF

# Add to crontab
crontab -e
# Add: 0 8 * * * /path/to/offline-package/daily_health_check.sh >> /var/log/rag-health.log
```

### Backup Procedures

#### 1. Configuration Backup
```bash
# Backup configurations
tar -czf rag-config-backup-$(date +%Y%m%d).tar.gz configs/ scripts/

# Backup data
tar -czf rag-data-backup-$(date +%Y%m%d).tar.gz data/ logs/
```

#### 2. Image Backup
```bash
# Export current images (if modified)
docker save -o rag-images-backup.tar \
  rag-frontend-complete:latest \
  rag-api:latest \
  rag-llm-gptoss:latest \
  rag-whisper:latest \
  rag-dots-ocr:latest
```

---

## Security Considerations

### Network Security
- **Firewall Rules**: Block all outbound internet access
- **Internal Networks**: Use isolated Docker networks
- **Access Control**: Implement API authentication
- **Log Monitoring**: Monitor for security events

### Data Security
- **Encryption**: Encrypt sensitive data at rest
- **Access Logs**: Monitor file and API access
- **User Management**: Implement proper user access controls
- **Audit Trail**: Maintain comprehensive audit logs

---

## Scaling in Offline Environment

### Horizontal Scaling
```bash
# Scale LLM service to additional GPUs
docker run -d \
  --name rag-llm-server-2 \
  --network rag-network \
  --gpus '"device=5"' \
  -v /opt/model-cache:/root/.cache/huggingface \
  rag-llm-gptoss:latest

# Update load balancer configuration
# Add new instance to nginx upstream
```

### Vertical Scaling
```bash
# Increase container resources
docker update --memory 64g --cpus 16 rag-llm-server

# Assign additional GPUs
docker stop rag-whisper
docker run -d \
  --name rag-whisper \
  --gpus '"device=0,5"' \
  rag-whisper:latest
```

This offline deployment guide ensures successful deployment and operation of the RAG system in completely isolated environments while maintaining full functionality and performance.