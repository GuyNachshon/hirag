# Offline RAG System Deployment Plan for H100 Cluster

## Project Overview
Deploy a fully functional Hebrew RAG (Retrieval-Augmented Generation) system on an **airgapped H100 GPU cluster** with no internet access. The system must be completely self-contained and operational in an offline environment.

## Testing Environment (Current)
- **Machine Type**: a2-highgpu-1g (A100 single GPU)
- **CPUs**: 12 vCPUs (Intel Cascade Lake)
- **Memory**: 85 GB RAM
- **GPU**: 1 x NVIDIA A100 40GB
- **Purpose**: Test and validate deployment before H100 production

## Target Production Environment
- **Machine Type**: a3-megagpu-8g (or similar)
- **CPUs**: 208 vCPUs
- **Memory**: 1,872 GB RAM
- **GPU**: 8 x NVIDIA H100 80GB (640GB total VRAM)
- **Environment**: Completely airgapped (no internet access)
- **OS**: Linux-based system

## System Architecture

### Core Services Required
1. **API Service** (Port 8080)
   - Orchestrates all RAG operations
   - CPU-only service
   - Status: ✅ Working

2. **Embedding Service** (Port 8001)
   - Generates embeddings for documents and queries
   - GPU-accelerated
   - Status: ⚠️ Working with test model, needs production model

3. **LLM Service** (Port 8003)
   - Main language model for generation
   - GPU-accelerated
   - Status: ❌ Needs compatible model

4. **DotsOCR Service** (Port 8002)
   - Vision model for document OCR
   - GPU-accelerated
   - Status: ✅ Working

5. **Whisper Service** (Port 8004)
   - Hebrew audio transcription
   - GPU-accelerated
   - Status: ✅ Working

6. **Frontend Service** (Port 3000)
   - Web interface
   - CPU-only
   - Status: ✅ Working

## Current Status

### ✅ Completed
- Created A100-specific deployment scripts
- Fixed GPU memory allocation strategy
- Successfully deployed DotsOCR, Whisper, API, and Frontend services
- Tested embedding service with small model (BAAI/bge-small-en-v1.5)
- Identified and documented all compatibility issues

### ⚠️ Issues Identified
1. **LLM Model Compatibility**
   - GPT-OSS-20B requires FlashAttention 3 (not available in current vLLM)
   - Need alternative model or upgraded vLLM version

2. **Embedding Model Size**
   - Qwen3-Embedding-4B requires more memory than initially allocated
   - Need to adjust memory allocation or use different model

3. **Offline Mode Requirements**
   - Models must be pre-cached in Docker containers
   - Environment variables must be set correctly for offline operation

## GPU Memory Allocation Strategy

### Testing Allocation (Single A100 40GB)
```
Service          | Memory | Status
-----------------|--------|--------
DotsOCR          | 12 GB  | ✅ Working
Whisper          | 6 GB   | ✅ Working  
Embedding        | 6 GB   | ⚠️ Needs production model
LLM              | 13 GB  | ❌ Needs compatible model
System Buffer    | 3 GB   | Reserved
-----------------|--------|--------
Total            | 40 GB  | 
```

### Production Allocation (H100 8-GPU Cluster - 640GB Total)
```
Service          | GPUs | Memory per GPU | Total Memory | Model
-----------------|------|----------------|--------------|-------
LLM Server       | 4    | 80 GB          | 320 GB       | Large Hebrew LLM (70B+)
DotsOCR          | 2    | 80 GB          | 160 GB       | Vision models
Embedding        | 1    | 80 GB          | 80 GB        | Large embedding model
Whisper          | 1    | 80 GB          | 80 GB        | Hebrew transcription
-----------------|------|----------------|--------------|-------
Total            | 8    | -              | 640 GB       |
```

With H100's massive memory, we can:
- Run much larger, more capable models
- Distribute services across GPUs for better performance
- Handle higher concurrency and throughput
- Keep all production models fully loaded

## Production Model Requirements

### Required Models
1. **Embedding Model**
   - Option A: Qwen/Qwen3-Embedding-4B (needs 6-8GB)
   - Option B: Smaller Hebrew-optimized embedding model
   - Must support Hebrew text

2. **LLM Model**
   - Option A: Fix GPT-OSS-20B compatibility
   - Option B: Use Llama-2-13B or Mistral-7B
   - Option C: Use Hebrew-optimized model
   - Must fit in ~13GB GPU memory

3. **OCR Model**
   - Current: DotsOCR (working)
   - No changes needed

4. **Whisper Model**
   - Current: ivrit-ai/whisper-large-v3 (working)
   - No changes needed

## Deployment Steps

### Phase 1: Testing Environment (Current)
1. Use small test models to validate deployment
2. Ensure all services can communicate
3. Test GPU memory sharing
4. Validate offline operation flow

### Phase 2: Container Preparation
1. **Build Production Containers**
   ```bash
   # For each service that needs models:
   docker build --build-arg MODEL_NAME=<model> \
                --build-arg CACHE_MODEL=true \
                -t rag-<service>:offline .
   ```

2. **Pre-cache Models**
   - Download all models during container build
   - Store in `/root/.cache/huggingface/hub/`
   - Verify offline mode with HF_HUB_OFFLINE=1

3. **Test Offline Operation**
   ```bash
   # Test each container in offline mode
   docker run --env HF_HUB_OFFLINE=1 \
              --env TRANSFORMERS_OFFLINE=1 \
              rag-<service>:offline
   ```

### Phase 3: Package for Transfer
1. **Export Docker Images**
   ```bash
   # Save all images
   docker save -o rag-embedding-offline.tar rag-embedding-server:offline
   docker save -o rag-llm-offline.tar rag-llm-server:offline
   docker save -o rag-dotsocr-offline.tar rag-dots-ocr:offline
   docker save -o rag-whisper-offline.tar rag-whisper:offline
   docker save -o rag-api-offline.tar rag-api:offline
   docker save -o rag-frontend-offline.tar rag-frontend:offline
   ```

2. **Create Installation Package**
   ```
   offline-rag-package/
   ├── images/
   │   ├── rag-embedding-offline.tar
   │   ├── rag-llm-offline.tar
   │   ├── rag-dotsocr-offline.tar
   │   ├── rag-whisper-offline.tar
   │   ├── rag-api-offline.tar
   │   └── rag-frontend-offline.tar
   ├── scripts/
   │   ├── load_images.sh
   │   ├── deploy_a100_offline.sh
   │   └── validate_deployment.sh
   ├── config/
   │   └── config.yaml
   └── README.md
   ```

### Phase 4: Deployment on Airgapped H100 System
1. Transfer package to airgapped H100 cluster
2. Load Docker images on all nodes
3. Run H100-specific deployment script
   ```bash
   ./deploy_h100_8gpu_offline.sh
   ```
4. Configure GPU assignments per service
5. Validate all services
6. Run performance benchmarks

## TODO List

### Immediate Tasks
- [ ] Find LLM model compatible with current vLLM version
- [ ] Test with smaller models (Qwen2-0.5B, Llama-2-7B)
- [ ] Document exact model versions needed

### Container Preparation
- [ ] Create Dockerfile for embedding server with cached model
- [ ] Create Dockerfile for LLM server with cached model
- [ ] Build and test offline containers
- [ ] Verify models work with HF_HUB_OFFLINE=1

### Packaging Tasks
- [ ] Create image export script
- [ ] Create offline installation script
- [ ] Write deployment documentation
- [ ] Create validation test suite

### Testing Tasks
- [ ] Test complete system with small models
- [ ] Test offline mode with all services
- [ ] Benchmark performance on A100
- [ ] Test Hebrew language processing

## Scripts Created

### Testing Scripts (A100)
- `deploy/deploy_a100_single_gpu.sh` - A100 test deployment
- `deploy/monitor_a100_single_gpu.sh` - A100 monitoring
- `deploy/validate_a100_deployment.sh` - A100 validation

### Production Scripts (H100) - To Be Created
- `deploy/deploy_h100_8gpu_offline.sh` - H100 production deployment
- `deploy/monitor_h100_cluster.sh` - H100 cluster monitoring
- `deploy/validate_h100_deployment.sh` - H100 validation

### Key Configuration Changes
1. **GPU Memory Utilization**
   - Embedding: 0.15 (6GB)
   - LLM: 0.35 (14GB)
   - DotsOCR: 0.30 (12GB)
   - Whisper: 0.15 (6GB)

2. **Environment Variables for Offline**
   ```bash
   HF_HUB_OFFLINE=1
   TRANSFORMERS_OFFLINE=1
   HF_DATASETS_OFFLINE=1
   ```

## Known Issues & Solutions

### Issue 1: FlashAttention 3 Requirement
**Problem**: GPT-OSS-20B requires FlashAttention 3
**Solution**: 
- Use --enforce-eager flag (partial fix)
- Or use different model
- Or upgrade vLLM container

### Issue 2: Model Download in Offline Mode
**Problem**: Models try to download in offline environment
**Solution**: Pre-cache all models in Docker containers during build

### Issue 3: Memory Allocation
**Problem**: Services competing for GPU memory
**Solution**: Careful memory allocation with GPU_MEMORY_UTILIZATION parameter

## Success Criteria
1. All 6 services running and healthy
2. System operates completely offline
3. Hebrew text, audio, and document processing working
4. Response times acceptable for production use
5. System stable under load

## Migration Path: A100 Testing → H100 Production

### Why Test on A100?
1. **Resource Constraints**: A100 forces us to optimize and find minimum viable configurations
2. **Compatibility Testing**: Issues found on A100 will also affect H100
3. **Cost Efficiency**: A100 testing is cheaper than H100 development
4. **Portability**: Solutions that work on constrained A100 will scale to H100

### Key Differences for H100 Production
1. **Scale Up Models**: Use full-size production models (70B+ LLMs)
2. **Distributed Services**: Spread across 8 GPUs instead of sharing 1
3. **Higher Throughput**: Support 10-15 concurrent users (vs 3-5 on A100)
4. **Better Performance**: 2-10x faster inference times

## Contact & Resources
- H100 deployment guide: `TESTING_GUIDE.md`
- A100 testing guide: `A100_TESTING_GUIDE.md`
- Configuration: `config/config.yaml`
- HiRAG documentation: `HiRAG/README.md`

## Next Developer Steps
1. Review this document and current status
2. Check `docker ps` to see running services
3. Check `docker logs <service-name>` for any errors
4. Focus on finding compatible LLM model
5. Begin container preparation with model caching

---
*Last Updated: 2025-09-07*
*Status: Testing phase on A100 - 5/6 services operational*
*Target: Production deployment on H100 8-GPU cluster (offline)*