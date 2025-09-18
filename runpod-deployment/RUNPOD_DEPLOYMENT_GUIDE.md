# HiRAG RunPod Deployment Guide

Complete deployment guide for the HiRAG system on RunPod with 8x A100 GPUs.

## Overview

The HiRAG system consists of 5 containerized services:
- **LLM Service** (Chat): gpt-oss-20b on port 8000
- **Embedding Service**: Qwen3-Embedding-4B on port 8001
- **API Service**: FastAPI backend on port 8080
- **OCR Service**: DotsOCR with vLLM on port 8002
- **Whisper Service**: Hebrew transcription on port 8004

## Prerequisites

### RunPod Environment
- **Pod Type**: 8x A100 SXM (640GB VRAM total)
- **Storage**: At least 500GB for Docker images
- **Network**: All ports accessible between services

### Docker Images Required
- `hirag-llm:latest` (57.9GB) - Contains all models
- `hirag-api:latest` (2.8GB) - API backend
- `rag-ocr-official:latest` (34.5GB) - OCR service
- `rag-whisper-official:latest` (17.3GB) - Whisper service
- `rag-frontend:latest` (52.9MB) - Web interface

## Step 1: Upload Images to GCP (Build Machine)

On your build machine (A100 instance):

```bash
# Set environment variables
export GCP_BUCKET="hirag-docker-images"
export GCP_PROJECT_ID="your-project-id"

# Make script executable
chmod +x scripts/upload_images_to_gcp.sh

# Upload all images
./scripts/upload_images_to_gcp.sh
```

This will:
- Save all Docker images as compressed tar.gz files
- Upload to Google Cloud Storage
- Create a manifest file with metadata
- Provide download commands

## Step 2: Download Images (Local Machine)

On your local machine:

```bash
# Download the download script
curl -O https://raw.githubusercontent.com/your-repo/download_images_from_gcp.sh
chmod +x download_images_from_gcp.sh

# Set bucket name
export GCP_BUCKET="hirag-docker-images"

# List available versions
./download_images_from_gcp.sh

# Download specific timestamp (uses caffeinate to prevent sleep)
./download_images_from_gcp.sh 20240117_143052
```

## Step 3: RunPod Deployment

### 3.1 Start RunPod Instance

1. **Create Pod**:
   - Template: Custom
   - GPU: 8x A100 SXM
   - Image: `runpod/pytorch:2.1.0-py3.10-cuda12.1.1-devel-ubuntu22.04`
   - Container Disk: 500GB+
   - Volume: Optional (for persistent data)

2. **Connect via SSH** and transfer images:
   ```bash
   # Option 1: Transfer from local machine
   scp *.tar.gz root@runpod-instance:/workspace/

   # Option 2: Download directly on RunPod
   gsutil -m cp 'gs://hirag-docker-images/*TIMESTAMP*' ./
   ```

### 3.2 Load Docker Images

```bash
# Load all images
for file in *.tar.gz; do
    echo "Loading $file..."
    gunzip "$file"
    docker load -i "${file%.gz}"
    rm "${file%.gz}"
done

# Verify images
docker images | grep -E "(hirag|rag-)"
```

### 3.3 Start Services

**Terminal 1: LLM Service (Chat)**
```bash
docker run --rm --gpus all -p 8000:8000 \
    --name hirag-llm \
    hirag-llm:latest \
    vllm serve /root/.cache/huggingface/models--openai--gpt-oss-20b/snapshots/6cee5e81ee83917806bbde320786a8fb61efebee \
    --host 0.0.0.0 \
    --port 8000 \
    --tensor-parallel-size 1 \
    --gpu-memory-utilization 0.7 \
    --max-model-len 4096 \
    --trust-remote-code
```

**Terminal 2: Embedding Service**
```bash
docker run --rm --gpus all -p 8001:8001 \
    --name hirag-embedding \
    hirag-llm:latest \
    vllm serve /root/.cache/huggingface/models--Qwen--Qwen3-Embedding-4B/snapshots/5cf2132abc99cad020ac570b19d031efec650f2b \
    --host 0.0.0.0 \
    --port 8001 \
    --trust-remote-code \
    --task embed
```

**Terminal 3: API Service**
```bash
docker run --rm -p 8080:8080 \
    --name hirag-api \
    --network host \
    hirag-api:latest
```

**Terminal 4: OCR Service**
```bash
docker run --rm --gpus all -p 8002:8002 \
    --name hirag-ocr \
    rag-ocr-official:latest
```

**Terminal 5: Whisper Service**
```bash
docker run --rm --gpus all -p 8004:8004 \
    --name hirag-whisper \
    rag-whisper-official:latest
```

### 3.4 Service Verification

Check each service is running:

```bash
# LLM Service (Chat)
curl http://localhost:8000/v1/models

# Embedding Service
curl http://localhost:8001/v1/models

# API Service
curl http://localhost:8080/health

# OCR Service
curl http://localhost:8002/health

# Whisper Service
curl http://localhost:8004/health
```

## Step 4: Service Configuration

### 4.1 GPU Allocation Strategy

| Service | GPUs | Memory | Purpose |
|---------|------|--------|---------|
| LLM | 2-3 GPUs | ~14GB | gpt-oss-20b chat model |
| Embedding | 1 GPU | ~8GB | Qwen3-Embedding-4B |
| OCR | 1 GPU | ~10GB | Vision model inference |
| Whisper | 1 GPU | ~4GB | Audio transcription |
| Reserve | 2 GPUs | - | Buffer for scaling |

### 4.2 Port Mapping

| Service | Internal Port | External Port | Purpose |
|---------|---------------|---------------|---------|
| LLM | 8000 | 8000 | Chat completions |
| Embedding | 8001 | 8001 | Text embeddings |
| API | 8080 | 8080 | Main API |
| OCR | 8002 | 8002 | Document processing |
| Whisper | 8004 | 8004 | Audio transcription |
| Frontend | 8087 | 8087 | Web interface |

## Step 5: Advanced Configuration

### 5.1 Production Deployment with Docker Compose

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  llm:
    image: hirag-llm:latest
    ports:
      - "8000:8000"
    command: >
      vllm serve /root/.cache/huggingface/models--openai--gpt-oss-20b/snapshots/6cee5e81ee83917806bbde320786a8fb61efebee
      --host 0.0.0.0 --port 8000 --tensor-parallel-size 1
      --gpu-memory-utilization 0.7 --max-model-len 4096 --trust-remote-code
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 2
              capabilities: [gpu]

  embedding:
    image: hirag-llm:latest
    ports:
      - "8001:8001"
    command: >
      vllm serve /root/.cache/huggingface/models--Qwen--Qwen3-Embedding-4B/snapshots/5cf2132abc99cad020ac570b19d031efec650f2b
      --host 0.0.0.0 --port 8001 --trust-remote-code --task embed
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]

  api:
    image: hirag-api:latest
    ports:
      - "8080:8080"
    depends_on:
      - llm
      - embedding
    network_mode: host

  ocr:
    image: rag-ocr-official:latest
    ports:
      - "8002:8002"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]

  whisper:
    image: rag-whisper-official:latest
    ports:
      - "8004:8004"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

Deploy with:
```bash
docker-compose up -d
```

### 5.2 Resource Monitoring

Monitor GPU usage:
```bash
# Install nvidia-ml-py if not available
pip install nvidia-ml-py

# Monitor GPU usage
nvidia-smi -l 1

# Monitor Docker containers
docker stats
```

### 5.3 Scaling Configuration

For higher load, adjust these parameters:

**LLM Service Scaling:**
```bash
# Increase tensor parallelism for larger models
--tensor-parallel-size 4

# Increase GPU memory utilization
--gpu-memory-utilization 0.9

# Adjust batch size
--max-num-batched-tokens 4096
```

**API Service Scaling:**
```bash
# Multiple API instances behind load balancer
docker run --rm -p 8080:8080 hirag-api:latest
docker run --rm -p 8081:8080 hirag-api:latest
docker run --rm -p 8082:8080 hirag-api:latest
```

## Troubleshooting

### Common Issues

**1. Service Won't Start**
```bash
# Check logs
docker logs hirag-llm
docker logs hirag-api

# Check port conflicts
netstat -tlnp | grep :8000
```

**2. GPU Not Detected**
```bash
# Verify GPU access in container
docker run --rm --gpus all nvidia/cuda:12.1-runtime-ubuntu22.04 nvidia-smi

# Check Docker GPU runtime
docker info | grep nvidia
```

**3. Model Loading Errors**
```bash
# Verify model paths inside container
docker run --rm hirag-llm:latest ls -la /root/.cache/huggingface/

# Check model permissions
docker run --rm hirag-llm:latest find /root/.cache/huggingface -name "config.json"
```

**4. API Connection Errors**
```bash
# Test service connectivity
curl -v http://localhost:8000/v1/models
curl -v http://localhost:8001/v1/models

# Check API config
docker run --rm hirag-api:latest cat /app/HiRAG/config.yaml | grep -A 10 VLLM
```

### Performance Optimization

**Memory Optimization:**
- Reduce `--gpu-memory-utilization` if OOM errors occur
- Use `--quantization gptq` for lower memory usage
- Monitor with `nvidia-smi`

**Latency Optimization:**
- Enable `--enable-prefix-caching`
- Use `--disable-log-stats` for production
- Optimize `--max-model-len` based on use case

## API Endpoints

Once deployed, the following endpoints will be available:

### LLM Service (8000)
- `GET /v1/models` - List available models
- `POST /v1/chat/completions` - Chat completions
- `POST /v1/completions` - Text completions

### Embedding Service (8001)
- `GET /v1/models` - List available models
- `POST /v1/embeddings` - Generate embeddings

### API Service (8080)
- `GET /health` - Health check
- `GET /api/file-search` - File search
- `POST /api/chat/sessions` - Create chat session
- `POST /api/transcription/upload` - Upload audio

### OCR Service (8002)
- `GET /health` - Health check
- `POST /process` - Process documents

### Whisper Service (8004)
- `GET /health` - Health check
- `POST /transcribe` - Transcribe audio

## Security Notes

- All services run with `--network host` for simplicity
- In production, use proper Docker networking
- Configure firewalls to restrict external access
- Use environment variables for sensitive configuration
- Enable TLS/SSL for external connections

## Support

For issues or questions:
1. Check service logs: `docker logs <container-name>`
2. Verify GPU access: `nvidia-smi`
3. Test individual services before full deployment
4. Monitor resource usage during operation

The system is designed for offline operation with all models embedded in the Docker images.