# RunPod Deployment Package for Offline RAG System

This directory contains everything needed to deploy the complete RAG system on RunPod 8x A100 cluster and create an offline package for your H100 environment.

## 📋 Prerequisites from Main README

Based on the main README.md, our system requires:

### ✅ Required Services (All Included)
- **vLLM Server**: For both LLM and embedding models ✓
- **Python 3.9+**: Included in containers ✓
- **Docker**: Required on RunPod ✓

### ✅ Models Required (All Cached)
- **LLM Model**: `openai/gpt-oss-20b` or `Qwen/Qwen2-0.5B-Instruct` ✓
- **Embedding Model**: `BAAI/bge-small-en-v1.5` or `Qwen/Qwen3-Embedding-4B` ✓
- **Vision Model**: DotsOCR integration ✓
- **Whisper Model**: `ivrit-ai/whisper-large-v3` ✓

### ✅ Core Components (All Deployed)
- **HiRAG System**: Hierarchical knowledge processing ✓
- **API Server**: FastAPI with all endpoints ✓
- **File Search**: Semantic search with DotsOCR ✓
- **Chat System**: RAG-enhanced conversations ✓
- **Frontend**: Complete UI with Langflow integration ✓

## 🚀 Quick Deployment Options

### 1. Official Repository Integration (NEW - Recommended)
```bash
# Build using official DotsOCR and Ivrit-AI repositories
./scripts/build_official_images.sh

# Test the official-based images
./scripts/test_official_images.sh

# Deploy with official implementations
./scripts/deploy_h100_manual.sh
```

**Benefits:**
- ✅ Uses official DotsOCR vLLM server (rednote-hilab/dots.ocr)
- ✅ Uses official Ivrit-AI Whisper models (ivrit-ai/whisper-large-v3-ct2)
- ✅ FastAPI adapters for seamless RAG integration
- ✅ Latest optimizations and bug fixes from upstream
- ✅ Full offline support with model caching

### 2. H100 Cluster Deployment
```bash
# H100-optimized deployment (no docker-compose)
./scripts/deploy_h100_optimized.sh

# Manual deployment for isolated networks
./scripts/deploy_h100_manual.sh

# Sequential service startup with dependency management
./scripts/start_services_sequential.sh start
```

### 2. RunPod Testing Environment
```bash
# Original RunPod deployment script
./scripts/deploy_runpod_cluster.sh

# Build Ivrit-AI Whisper for offline use
./scripts/build_ivrit_whisper_offline.sh
```

### 3. Test All Components
```bash
# Comprehensive service testing
./scripts/test_all_services.sh

# Test in offline mode simulation
sudo ./scripts/simulate_offline_mode.sh
```

### 4. Create Offline Package
```bash
# Package everything for H100 deployment
./scripts/create_offline_package_runpod.sh
```

## 📁 Directory Structure

```
runpod-deployment/
├── README.md                           # This file
├── scripts/                            # Deployment scripts
│   ├── deploy_runpod_cluster.sh       # Main deployment
│   ├── build_ivrit_whisper_offline.sh # Whisper setup
│   ├── create_offline_package_runpod.sh # Package creator
│   ├── simulate_offline_mode.sh       # Offline testing
│   └── test_all_services.sh           # Service testing
├── configs/                            # Configuration files
│   ├── gpu-distribution.yaml          # GPU allocation
│   ├── hirag-config.yaml             # HiRAG settings
│   └── docker-compose.yaml           # Service orchestration
├── dockerfiles/                       # Container definitions
│   ├── Dockerfile.api                 # RAG API server
│   ├── Dockerfile.frontend            # Frontend + Langflow
│   ├── Dockerfile.whisper-optimized   # Ivrit-AI Whisper
│   └── Dockerfile.llm                 # vLLM base image
└── docs/                              # Documentation
    ├── API_ENDPOINTS.md               # Complete API reference
    ├── GPU_ALLOCATION.md              # GPU distribution guide
    └── OFFLINE_DEPLOYMENT.md         # H100 deployment guide
```

## 🎯 Service Endpoints (Matches README)

| Service | Port | Health Check | Purpose |
|---------|------|--------------|---------|
| **API Server** | 8080 | `/health` | Main RAG API |
| **Frontend** | 8087 | `/frontend-health` | Complete UI |
| **Langflow** | 7860 | `/health` | Workflow engine |
| **LLM Server** | 8003 | `/health` | Text generation |
| **Embedding** | 8001 | `/health` | Vector search |
| **Whisper** | 8004 | `/health` | Audio transcription |
| **DotsOCR** | 8002 | `/health` | Document parsing (FastAPI adapter) |
| **DotsOCR vLLM** | 8005 | `/health` | Internal vLLM server |

## 📊 API Compatibility

All endpoints from main README are supported:

### ✅ Health & System
- `GET /health` - System health check
- `GET /api/search/health` - File search service health
- `GET /api/chat/health` - Chat service health

### ✅ File Search
- `GET /api/search/files?q={query}&limit=10&file_types=.pdf,.txt`

### ✅ Chat Sessions
- `POST /api/chat/sessions` - Create new session
- `GET /api/chat/sessions/{session_id}` - Get session info
- `DELETE /api/chat/sessions/{session_id}` - Delete session
- `GET /api/chat/sessions/{session_id}/history` - Get history

### ✅ Chat Messaging
- `POST /api/chat/{session_id}/message` - Send message, get RAG response
- `POST /api/chat/{session_id}/upload` - Upload file to session

## 🔧 Configuration Alignment

### HiRAG Configuration (matches main README)
```yaml
VLLM:
    api_key: 0
    llm:
        model: "openai/gpt-oss-20b"
        base_url: "http://rag-llm-server:8000/v1"
    embedding:
        model: "BAAI/bge-small-en-v1.5"
        base_url: "http://rag-embedding-server:8000/v1"

hirag:
    working_dir: "/workspace/hirag_data"
    enable_llm_cache: false
    enable_hierarchical_mode: true
    embedding_batch_num: 6
    embedding_func_max_async: 8
    enable_naive_rag: true

model_params:
    vllm_embedding_dim: 2560
    max_token_size: 8192
```

## 🐳 Deployment Process

### Phase 1: Build on RunPod
1. **Environment Setup**: Install Docker, NVIDIA runtime
2. **Repository Clone**: Get latest code
3. **Model Caching**: Pre-download all models
4. **Image Building**: Build all containers natively
5. **Service Deployment**: Deploy across 8 GPUs
6. **Testing**: Verify all endpoints work

### Phase 2: Package for Offline
1. **Image Export**: Save all Docker images
2. **Model Export**: Copy complete model cache
3. **Script Packaging**: Include all deployment scripts
4. **Documentation**: Generate deployment guides
5. **Archive Creation**: Create transfer package

### Phase 3: H100 Deployment
1. **Package Transfer**: Move to H100 cluster
2. **Image Loading**: Load all Docker images
3. **Service Deployment**: Deploy with GPU allocation
4. **Offline Testing**: Verify no internet access needed

## 📝 Logging System (Matches README)

All log files from main README are supported:
- `api_main.log` - Application lifecycle
- `api_access.log` - HTTP requests (JSON)
- `api_errors.log` - Error details
- `api_performance.log` - Performance metrics (JSON)
- `rag_operations.log` - RAG operations (JSON)

## 🔒 Security & Offline Features

### ✅ Offline Design Principles (All Implemented)
- **No External Dependencies**: All models cached ✓
- **Pre-baked Containers**: Self-contained packages ✓
- **Local Model Serving**: vLLM with cached models ✓
- **Secure by Design**: No data leaves environment ✓

### ✅ Security Features (All Included)
- **Input Validation**: Comprehensive validation ✓
- **Error Handling**: Secure error responses ✓
- **Session Isolation**: Independent session management ✓
- **File Upload Security**: Controlled processing ✓

## 🎯 Next Steps

1. **Deploy on RunPod**: Run `./scripts/deploy_runpod_cluster.sh`
2. **Test Everything**: Verify all services work
3. **Create Package**: Generate offline deployment package
4. **Transfer to H100**: Move package to production environment
5. **Deploy Offline**: Install on H100 cluster

## 📞 Support

- Check `logs/` directory for all application logs
- Use `./scripts/test_all_services.sh` for diagnostics
- Review GPU allocation in `configs/gpu-distribution.yaml`
- All scripts include help and error handling