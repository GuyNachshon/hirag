# RAG System Offline Deployment Guide

This guide provides complete instructions for deploying the RAG system in air-gapped/offline environments where internet access is not available.

## Overview

The RAG (Retrieval-Augmented Generation) system consists of:
- **DotsOCR**: Vision-language model for document processing
- **Embedding Server**: Text embedding generation using vLLM
- **LLM Server**: Large language model for chat and response generation
- **API Server**: FastAPI backend providing REST endpoints
- **Pre-downloaded Models**: All models are baked into Docker images

## Prerequisites

### System Requirements
- Docker Engine 20.10+
- NVIDIA GPU with 16GB+ VRAM (recommended for optimal performance)
- NVIDIA Container Toolkit installed
- 100GB+ free disk space for Docker images
- 32GB+ RAM recommended

### Software Dependencies
- Linux-based system (Ubuntu 20.04+ recommended)
- bash shell
- curl (for testing)

## Quick Start

### On Source System (with internet)

1. **Build all images with pre-downloaded models:**
   ```bash
   cd deploy
   ./build_all_offline.sh
   ```

2. **Export images for transfer:**
   ```bash
   ./export_for_offline.sh
   ```

3. **Transfer the export directory to target system**

### On Target System (air-gapped)

1. **Import images:**
   ```bash
   cd rag-system-export
   ./import_images.sh
   ```

2. **Setup and deploy:**
   ```bash
   cd ../deploy
   ./setup_network.sh
   ./deploy_complete.sh
   ```

3. **Validate deployment:**
   ```bash
   ./validate_offline_deployment.sh
   ./test_full_pipeline.sh
   ```

## Detailed Instructions

### Step 1: Building Images (Source System)

The build process downloads all models and dependencies into Docker images:

```bash
# Navigate to deployment directory
cd deploy

# Build all services with pre-downloaded models
./build_all_offline.sh
```

This script builds:
- **rag-dots-ocr**: DotsOCR vision model (pre-downloaded)
- **rag-embedding-server**: Qwen2-0.5B-Instruct for embeddings (pre-downloaded)
- **rag-llm-small**: Qwen3-4B-Thinking-2507 for chat (pre-downloaded)
- **rag-llm-gptoss**: gpt-oss-20b alternative model (pre-downloaded)
- **rag-api**: FastAPI application with HiRAG

### Step 2: Exporting Images

Export all built images as tar files for transfer:

```bash
./export_for_offline.sh
```

This creates a `rag-system-export/` directory containing:
- Individual `.tar` files for each service
- `import_images.sh` script for target system
- `MANIFEST.txt` with export details

### Step 3: Transfer to Target System

Copy the entire `rag-system-export/` directory to your air-gapped target system using your preferred method:
- USB drive
- Network transfer
- Physical media

### Step 4: Import and Deploy (Target System)

On the target system:

```bash
# Import Docker images
cd rag-system-export
./import_images.sh

# Navigate to deployment directory
cd ../deploy

# Setup Docker network
./setup_network.sh

# Deploy all services
./deploy_complete.sh
```

## Configuration

### Configuration File

The system uses `deploy/config/config.yaml` for configuration. A template is provided:

```bash
cp config/config.yaml.template config/config.yaml
# Edit config.yaml as needed
```

Key configuration options:

```yaml
# Choose LLM model
VLLM:
  llm:
    # Small model (4GB VRAM)
    model: "Qwen/Qwen3-4B-Thinking-2507"
    # OR large model (requires 20GB+ VRAM)
    # model: "openai/gpt-oss-20b"
```

### Data Directories

The system creates and uses these directories:

- `deploy/data/input/`: Documents to be indexed
- `deploy/data/working/`: HiRAG working directory
- `deploy/data/logs/`: Application logs
- `deploy/data/cache/`: Model cache and embeddings

### Service Endpoints

Once deployed, services are available at:

- **API**: http://localhost:8080 (REST API and documentation)
- **LLM**: http://localhost:8003 (internal)
- **Embedding**: http://localhost:8001 (internal)
- **DotsOCR**: http://localhost:8002 (internal)

## Validation and Testing

### Health Check

Verify all services are running:

```bash
./validate_offline_deployment.sh
```

### Full Pipeline Test

Test complete functionality:

```bash
./test_full_pipeline.sh
```

### Manual Testing

Test API endpoints manually:

```bash
# Health check
curl http://localhost:8080/health

# API documentation
open http://localhost:8080/docs

# File search
curl -X POST "http://localhost:8080/api/search" \
  -H "Content-Type: application/json" \
  -d '{"query": "test", "max_results": 5}'
```

## Usage

### Adding Documents

1. Place documents in the input directory:
   ```bash
   cp /path/to/documents/* deploy/data/input/
   ```

2. Documents will be automatically processed by the indexing system

### File Search

Search for documents via API:

```bash
curl -X POST "http://localhost:8080/api/search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "search terms",
    "max_results": 10
  }'
```

### Chat with RAG

1. Create a chat session:
   ```bash
   curl -X POST "http://localhost:8080/api/chat/sessions" \
     -H "Content-Type: application/json" \
     -d '{
       "user_id": "user1",
       "title": "My Chat"
     }'
   ```

2. Send messages with RAG enhancement:
   ```bash
   curl -X POST "http://localhost:8080/api/chat/sessions/{session_id}/messages" \
     -H "Content-Type: application/json" \
     -d '{
       "content": "What information do you have about X?",
       "use_rag": true
     }'
   ```

## Troubleshooting

### Common Issues

1. **Out of GPU memory**
   - Use smaller model: Set `model: "Qwen/Qwen3-4B-Thinking-2507"` in config
   - Reduce GPU memory utilization in Dockerfiles

2. **Service not responding**
   - Check logs: `docker logs rag-api`
   - Verify network: `docker network ls | grep rag-network`
   - Restart services: `./deploy_complete.sh`

3. **Models not loading**
   - Verify images were built with models: `docker images`
   - Check container logs for download errors
   - Rebuild with: `./build_all_offline.sh`

### Log Locations

- Container logs: `docker logs <container-name>`
- Application logs: `deploy/data/logs/`
- API logs: `docker logs rag-api`

### Monitoring

Monitor system status:

```bash
# Check all containers
docker ps

# Monitor API logs
docker logs -f rag-api

# Check GPU usage
nvidia-smi

# Check disk space
df -h
```

## Maintenance

### Updating Models

To update models, rebuild images on source system:

1. Modify Dockerfile model references
2. Run `./build_all_offline.sh`
3. Export and transfer updated images
4. Import and redeploy on target system

### Scaling

For higher load, consider:
- Running multiple LLM instances
- Using larger GPU instances
- Implementing load balancing

### Backup

Important directories to backup:
- `deploy/data/working/` (indexed data)
- `deploy/config/` (configuration)
- `deploy/data/input/` (source documents)

## Security Considerations

- All communication within Docker network
- No external network dependencies
- Models and data remain on local system
- Configure firewall rules for external access as needed

## Support

For issues or questions:
1. Check logs for specific error messages
2. Verify system requirements are met
3. Run validation scripts to identify problems
4. Review this documentation for configuration options