# RAG System Deployment

This directory contains everything needed for offline/air-gapped deployment of the complete RAG (Retrieval-Augmented Generation) system.

## 🚀 Quick Start

### For Internet-Connected Systems (Build & Export)

```bash
# Build all images with pre-downloaded models
./build_all_offline.sh

# Export for air-gapped transfer
./export_for_offline.sh

# Transfer rag-system-export/ directory to target system
```

### For Air-Gapped Systems (Import & Deploy)

```bash
# Import Docker images
cd rag-system-export
./import_images.sh

# Deploy system
cd ../deploy
./setup_network.sh
./deploy_complete.sh

# Validate deployment
./validate_offline_deployment.sh
```

## 📁 File Structure

```
deploy/
├── build_all_offline.sh          # Build all images with pre-downloaded models
├── export_for_offline.sh         # Export images as tar files for transfer
├── import_offline.sh             # Import images on target system
├── setup_network.sh              # Create Docker network
├── deploy_complete.sh            # Complete deployment script
├── validate_offline_deployment.sh # Validate all services
├── test_full_pipeline.sh         # Test complete functionality
├── 
├── Dockerfile.llm-small          # Small LLM model (Qwen3-4B) with pre-download
├── Dockerfile.llm                # Large LLM model (gpt-oss-20b) with pre-download
├── Dockerfile.embedding          # Embedding model with pre-download
├── Dockerfile.dots-ocr           # DotsOCR vision model with pre-download
├── 
├── config/
│   ├── config.yaml.template      # Configuration template
│   └── config.yaml               # Your configuration (created from template)
├── 
└── data/                         # Data directories (auto-created)
    ├── input/                    # Documents to be indexed
    ├── working/                  # HiRAG working directory
    ├── logs/                     # Application logs
    └── cache/                    # Model cache and embeddings
```

## 🐳 Docker Images Built

| Image | Description | Model Size | Purpose |
|-------|-------------|------------|---------|
| `rag-dots-ocr:latest` | DotsOCR vision model | ~3GB | Document OCR processing |
| `rag-embedding-server:latest` | Qwen2-0.5B embedding model | ~1GB | Text embeddings |
| `rag-llm-small:latest` | Qwen3-4B-Thinking model | ~4GB | Chat/generation (recommended) |
| `rag-llm-gptoss:latest` | gpt-oss-20b model | ~20GB | Chat/generation (alternative) |
| `rag-api:latest` | FastAPI + HiRAG | ~2GB | REST API server |

## 🔧 Configuration Options

Edit `config/config.yaml` to customize:

```yaml
# Choose your LLM model
VLLM:
  llm:
    # Small model (recommended, 4GB VRAM)
    model: "Qwen/Qwen3-4B-Thinking-2507"
    
    # OR large model (requires 20GB+ VRAM)
    # model: "openai/gpt-oss-20b"
```

## 🌐 Service Endpoints

Once deployed:

- **API & Documentation**: http://localhost:8080
- **API Health**: http://localhost:8080/health
- **Swagger Docs**: http://localhost:8080/docs

Internal services (for monitoring):
- **LLM Service**: http://localhost:8003
- **Embedding Service**: http://localhost:8001  
- **DotsOCR Service**: http://localhost:8002

## 📋 System Requirements

### Minimum Requirements
- Docker Engine 20.10+
- NVIDIA GPU with 8GB+ VRAM
- 32GB RAM
- 100GB free disk space
- Ubuntu 20.04+ or similar Linux

### Recommended Requirements
- NVIDIA GPU with 16GB+ VRAM (for gpt-oss model)
- 64GB RAM
- 200GB free disk space
- SSD storage for better performance

## 🧪 Testing & Validation

### Health Check
```bash
./validate_offline_deployment.sh
```

### Complete Pipeline Test
```bash
./test_full_pipeline.sh
```

### Manual API Tests
```bash
# Test health
curl http://localhost:8080/health

# Test file search
curl -X POST "http://localhost:8080/api/search" \
  -H "Content-Type: application/json" \
  -d '{"query": "test", "max_results": 5}'

# Create chat session
curl -X POST "http://localhost:8080/api/chat/sessions" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "user1", "title": "Test"}'
```

## 📖 Usage Examples

### File Search API
```bash
curl -X POST "http://localhost:8080/api/search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "artificial intelligence",
    "max_results": 10
  }'
```

### Chat with RAG
```bash
# 1. Create session
SESSION_ID=$(curl -s -X POST "http://localhost:8080/api/chat/sessions" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "user1", "title": "My Chat"}' | \
  grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)

# 2. Send RAG-enhanced message
curl -X POST "http://localhost:8080/api/chat/sessions/$SESSION_ID/messages" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "What information do you have about machine learning?",
    "use_rag": true
  }'
```

## 🛠️ Troubleshooting

### Common Issues

1. **GPU Memory Error**
   - Switch to small model in `config.yaml`
   - Reduce `gpu_memory_utilization` in Dockerfiles

2. **Service Not Starting**
   ```bash
   docker logs rag-api
   docker ps -a
   ```

3. **Network Issues**
   ```bash
   docker network ls
   ./setup_network.sh
   ```

4. **Model Loading Fails**
   - Check if models were pre-downloaded in images
   - Rebuild with: `./build_all_offline.sh`

### Getting Help

1. Check service logs: `docker logs <service-name>`
2. Run validation: `./validate_offline_deployment.sh`
3. Review full documentation: `OFFLINE_DEPLOYMENT.md`

## 📊 Monitoring

### Container Status
```bash
docker ps
docker stats
```

### GPU Usage
```bash
nvidia-smi
watch -n 1 nvidia-smi
```

### Logs
```bash
# Real-time API logs
docker logs -f rag-api

# All service logs
docker logs rag-llm-server
docker logs rag-embedding-server
docker logs rag-dots-ocr
```

## 🔒 Security Notes

- All services communicate via internal Docker network
- No external dependencies during runtime
- All models and data remain local
- Configure external access controls as needed

## 📝 Next Steps

1. **Add Documents**: Copy files to `data/input/`
2. **Configure System**: Edit `config/config.yaml`
3. **Test API**: Use provided test scripts
4. **Integrate**: Use API endpoints in your applications

For complete documentation, see [OFFLINE_DEPLOYMENT.md](./OFFLINE_DEPLOYMENT.md)