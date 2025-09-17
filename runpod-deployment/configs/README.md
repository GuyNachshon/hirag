# Configuration Files

This directory contains all configuration files for the RAG system deployment.

## 📄 Configuration Files

### 🐳 **docker-compose.yaml**
- **Purpose**: Docker Compose configuration for all services
- **Usage**: `docker-compose -f configs/docker-compose.yaml up -d`
- **Services**: API, Frontend, LLM, Embedding, Whisper, DotsOCR, Langflow
- **Features**:
  - Official repository integration
  - GPU allocation across 8x A100/H100
  - Offline model caching
  - Health checks and restart policies

### 🎯 **gpu-distribution.yaml**
- **Purpose**: GPU allocation strategy for multi-GPU clusters
- **Usage**: Reference for deployment scripts
- **Contains**:
  - Service-to-GPU mapping
  - VRAM usage estimates
  - Model specifications
  - Performance optimization settings

### 🧠 **hirag-config.yaml**
- **Purpose**: HiRAG system configuration
- **Usage**: Mounted to API container at `/app/configs/hirag-config.yaml`
- **Contains**:
  - Model endpoints (LLM, embedding)
  - Vector database settings
  - Clustering parameters
  - Knowledge graph configuration

## 🔧 Configuration Overview

### **Service Architecture**
```
GPU 0: Whisper (ivrit-ai/whisper-large-v3-ct2)
GPU 1: Embedding (Qwen/Qwen3-Embedding-4B)
GPU 2-3: LLM (openai/gpt-oss-20b, tensor parallel)
GPU 4: DotsOCR (rednote-hilab/dots.ocr)
GPU 5-7: Reserved for scaling
```

### **Port Mapping**
```
8080: API Server
8087: Frontend UI
8001: Embedding Service
8002: DotsOCR FastAPI
8003: LLM Service
8004: Whisper Service
8005: DotsOCR vLLM (internal)
7860: Langflow
```

### **Model Configuration**
- **LLM**: `openai/gpt-oss-20b` (20B parameters)
- **Embedding**: `Qwen/Qwen3-Embedding-4B` (4B parameters, 1024 dimensions)
- **Vision**: `rednote-hilab/dots.ocr` (1.7B parameters)
- **Audio**: `ivrit-ai/whisper-large-v3-ct2` (Hebrew optimized)

## 🚀 Usage Examples

### **Docker Compose Deployment**
```bash
# Start all services
docker-compose -f configs/docker-compose.yaml up -d

# Check service status
docker-compose -f configs/docker-compose.yaml ps

# View logs
docker-compose -f configs/docker-compose.yaml logs -f
```

### **Manual Deployment Reference**
```bash
# Scripts use these configs for:
# - GPU allocation strategy
# - Port mappings
# - Environment variables
# - Health check endpoints
```

### **Configuration Customization**
```bash
# Edit model endpoints
vi configs/hirag-config.yaml

# Modify GPU allocation
vi configs/gpu-distribution.yaml

# Update service configuration
vi configs/docker-compose.yaml
```

## 📝 Notes

- All configurations support offline/airgapped environments
- Model caching is configured for `/root/.cache/huggingface`
- Health checks are configured with appropriate timeouts
- Restart policies ensure service resilience
- All configurations are H100-compatible