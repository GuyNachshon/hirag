# Offline RAG Deployment Guide

Complete deployment guide for the offline RAG system using individual Docker containers.

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   DotsOCR       │    │   LLM Server    │    │ Embedding       │    │   RAG API       │
│   (Port 8002)   │    │   (Port 8000)   │    │ (Port 8001)     │    │   (Port 8080)   │
│                 │    │                 │    │                 │    │                 │
│ Document OCR    │    │ Chat Responses  │    │ Vector Search   │    │ REST API        │
│ Vision Model    │    │ Text Generation │    │ Embeddings      │    │ Session Mgmt    │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📋 Prerequisites

- **Docker** with GPU support (nvidia-docker2)
- **NVIDIA GPUs** (minimum 3 GPUs recommended)
- **CUDA** drivers installed
- **Python 3.9+**
- **Sufficient disk space** (100GB+ for models)

## 🚀 Quick Start

### 1. Build Docker Images
```bash
# Build all required Docker images
./scripts/build_images.sh
```

### 2. Start Services
```bash
# Start all services in the correct order
./scripts/start_services.sh
```

### 3. Verify Deployment
```bash
# Check service health
curl http://localhost:8002/health  # DotsOCR
curl http://localhost:8000/health  # LLM Server  
curl http://localhost:8001/health  # Embedding Server
curl http://localhost:8080/health  # RAG API

# Access API documentation
open http://localhost:8080/docs
```

## 📦 Individual Services

### DotsOCR Server (Document Processing)
- **Image**: `rag-dots-ocr:latest`
- **Port**: 8002
- **GPU**: Device 0
- **Purpose**: OCR and document structure extraction
- **Model**: rednote-hilab/dots.ocr

### LLM Server (Chat Responses)
- **Image**: `rag-llm-server:latest` 
- **Port**: 8000
- **GPU**: Device 1
- **Purpose**: Generate conversational responses
- **Model**: Configure in `start_services.sh`

### Embedding Server (Vector Search)
- **Image**: `rag-embedding-server:latest`
- **Port**: 8001  
- **GPU**: Device 2
- **Purpose**: Create embeddings for semantic search
- **Model**: Configure in `start_services.sh`

### RAG API (Application Layer)
- **Image**: `rag-api:latest`
- **Port**: 8080
- **Purpose**: REST API, session management, orchestration

## 🔧 Configuration

### Model Configuration
Models are configured via environment variables in `scripts/start_services.sh`:

```bash
# Set model choices (can be overridden via environment variables)
GPT_OSS_MODEL=${GPT_OSS_MODEL:-"openai/gpt-oss-20b"}
EMBEDDING_MODEL=${EMBEDDING_MODEL:-"Qwen/Qwen2-0.5B-Instruct"}
```

### API Configuration
Update `HiRAG/config.yaml` with correct service endpoints:

```yaml
VLLM:
    api_key: 0
    llm:
        model: "openai/gpt-oss-20b"
        base_url: "http://rag-llm-server:8000/v1"
    embedding:
        model: "Qwen/Qwen2-0.5B-Instruct"
        base_url: "http://rag-embedding-server:8000/v1"

# DotsOCR configuration
dots_ocr:
  ip: "rag-dots-ocr"
  port: 8000
  model_name: "model"
```

## 🛠️ Service Management

### Start Services
```bash
./scripts/start_services.sh
```

### Stop Services
```bash
./scripts/stop_services.sh
```

### Restart Services
```bash
./scripts/restart_services.sh
```

### Individual Service Control
```bash
# Start individual service
docker run -d --name rag-dots-ocr --network rag-network --gpus device=0 -p 8002:8000 rag-dots-ocr:latest

# Stop individual service
docker stop rag-dots-ocr
docker rm rag-dots-ocr
```

## 📊 Resource Requirements

### Minimum Configuration (3 GPUs)
- **GPU 0**: DotsOCR (16GB VRAM)
- **GPU 1**: LLM Server (24GB VRAM for 7B model)  
- **GPU 2**: Embedding Server (8GB VRAM)
- **RAM**: 64GB system RAM
- **Storage**: 200GB free space

### Recommended Configuration (4+ GPUs)
- **GPU 0**: DotsOCR (24GB VRAM)
- **GPU 1-2**: LLM Server with tensor parallelism (48GB VRAM)
- **GPU 3**: Embedding Server (16GB VRAM)
- **RAM**: 128GB system RAM
- **Storage**: 500GB free space

## 🔍 Troubleshooting

### Common Issues

1. **GPU Memory Errors**
   ```bash
   # Reduce GPU memory utilization
   -e GPU_MEMORY=0.7
   ```

2. **Network Connection Issues**
   ```bash
   # Recreate Docker network
   docker network rm rag-network
   docker network create rag-network
   ```

3. **Model Loading Errors**
   ```bash
   # Check model paths and permissions
   ls -la models/DotsOCR/
   docker logs rag-dots-ocr
   ```

4. **Service Startup Order**
   ```bash
   # Ensure services start in order with delays
   # DotsOCR -> LLM -> Embedding -> API
   ```

### Debugging Commands
```bash
# Check container logs
docker logs rag-dots-ocr
docker logs rag-llm-server  
docker logs rag-embedding-server
docker logs rag-api

# Check GPU usage
nvidia-smi

# Check network connectivity
docker network inspect rag-network

# Test individual services
curl -X POST http://localhost:8002/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "model", "messages": [{"role": "user", "content": [{"type": "text", "text": "test"}]}]}'
```

## 📈 Scaling

### For Higher Load
1. **Multiple LLM Instances**:
   ```bash
   # Start multiple LLM containers with load balancer
   docker run -d --name rag-llm-server-1 ...
   docker run -d --name rag-llm-server-2 ...
   ```

2. **Larger Models**:
   ```bash
   # Use tensor parallelism for 70B+ models
   -e TENSOR_PARALLEL=4
   ```

3. **More Embedding Servers**:
   ```bash
   # Distribute embedding load
   docker run -d --name rag-embedding-1 ...
   docker run -d --name rag-embedding-2 ...
   ```

## 🔒 Security

### Container Security
- All containers run with `--restart unless-stopped`
- Services communicate via internal Docker network
- Only necessary ports exposed to host
- No root access required inside containers

### Data Security  
- Models stored in local volumes
- No external network access during runtime
- Logs stored locally in `./logs/`
- Uploaded files stored in `./data/uploads/`

---

**Note**: This deployment is designed for completely offline operation. Ensure all models are downloaded before deployment and no external network access is required during runtime.