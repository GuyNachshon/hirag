# GPU Allocation and Management Guide

This document provides detailed guidance for GPU allocation, optimization, and monitoring in the RAG system deployment on 8x A100 SXM cluster.

## Overview

The RAG system is designed to efficiently utilize an 8x NVIDIA A100 SXM cluster (640GB total VRAM) with strategic GPU allocation across different services.

### Cluster Specifications
- **GPU Count**: 8x NVIDIA A100 SXM
- **Total VRAM**: 640GB (80GB per GPU)
- **Interconnect**: NVLink for high-speed GPU-to-GPU communication
- **Memory Bandwidth**: 2TB/s per GPU
- **Compute Capability**: 8.0

---

## Service GPU Allocation Strategy

### GPU Distribution Map

| GPU ID | Service | VRAM Usage | Model | Purpose |
|--------|---------|------------|-------|---------|
| 0 | Whisper | ~15GB | ivrit-ai/whisper-large-v3-ct2 | Hebrew audio transcription |
| 1 | Embedding | ~20GB | sentence-transformers/all-MiniLM-L6-v2 | Vector embeddings |
| 2-3 | LLM | ~120GB | microsoft/DialoGPT-medium | Language generation (tensor parallel) |
| 4 | OCR | ~25GB | rednote-hilab/dots.ocr | Document text extraction |
| 5-7 | Reserved | ~240GB | - | Scaling and additional services |

### Detailed Service Allocation

#### 1. Whisper Service (GPU 0)
```yaml
GPU: 0
VRAM: ~15GB out of 80GB available
Model: ivrit-ai/whisper-v2_he
Precision: fp16
Optimization: TensorRT where applicable
```

**Rationale**:
- Audio processing requires moderate GPU memory
- Isolated workload prevents interference with text processing
- Hebrew-optimized model for better transcription accuracy
- Dedicated GPU ensures consistent audio processing performance

**Configuration**:
```bash
docker run -d \
  --gpus '"device=0"' \
  -e CUDA_VISIBLE_DEVICES=0 \
  -e HF_HUB_OFFLINE=1 \
  rag-whisper:latest
```

#### 2. Embedding Service (GPU 1)
```yaml
GPU: 1
VRAM: ~20GB out of 80GB available
Model: sentence-transformers/all-MiniLM-L6-v2
Precision: fp16
Batch Size: 32
```

**Rationale**:
- Consistent GPU access for vector generation
- Sentence transformers model fits comfortably on single A100
- Dedicated GPU ensures stable embedding performance
- Supports multilingual text processing

**Configuration**:
```bash
docker run -d \
  --gpus '"device=1"' \
  -e CUDA_VISIBLE_DEVICES=1 \
  -e MODEL_NAME=sentence-transformers/all-MiniLM-L6-v2 \
  rag-embedding-server:latest
```

#### 3. LLM Service (GPU 2-3)
```yaml
GPUs: 2, 3
VRAM: ~120GB out of 160GB available
Model: microsoft/DialoGPT-medium
Precision: fp16
Tensor Parallel: 2
Max Tokens: 2048
```

**Rationale**:
- Large language model requires substantial memory
- Tensor parallelism across 2 GPUs for better throughput
- Handles both completion and chat functionality
- NVLink enables efficient multi-GPU communication

**Configuration**:
```bash
docker run -d \
  --gpus '"device=2,3"' \
  -e CUDA_VISIBLE_DEVICES=2,3 \
  -e TENSOR_PARALLEL_SIZE=2 \
  -e MODEL_NAME=microsoft/DialoGPT-medium \
  --shm-size=32g \
  rag-llm-server:latest
```

#### 4. OCR Service (GPU 4)
```yaml
GPU: 4
VRAM: ~25GB out of 80GB available
Model: rednote-hilab/dots.ocr (1.7B vision-language model)
Precision: fp16
Optimization: ONNX where applicable
```

**Rationale**:
- DotsOCR with vision language model for document parsing
- Moderate memory requirements for layout analysis
- Isolated GPU prevents interference with other services
- Optimized for mixed text and image processing

**Configuration**:
```bash
docker run -d \
  --gpus '"device=4"' \
  -e CUDA_VISIBLE_DEVICES=4 \
  -e MODEL_NAME=rednote-hilab/dots.ocr \
  rag-dots-ocr:latest
```

---

## Memory Management

### Memory Allocation Strategy

#### Per-Service Memory Limits
```yaml
Service Limits:
  whisper: 72GB (90% of 80GB)
  embedding: 72GB (90% of 80GB)
  llm: 144GB (90% of 160GB across 2 GPUs)
  ocr: 72GB (90% of 80GB)
```

#### Memory Optimization Settings
```bash
# vLLM Memory Settings
GPU_MEMORY_UTILIZATION=0.9
VLLM_USE_TRITON=0  # Disabled for compatibility
MAX_MODEL_LEN=2048
MAX_NUM_BATCHED_TOKENS=2048
ENABLE_CHUNKED_PREFILL=true
```

#### Dynamic Memory Management
- **Allow Growth**: Enable dynamic memory allocation
- **Memory Pooling**: Efficient memory reuse across requests
- **Garbage Collection**: Automatic cleanup of unused tensors
- **Memory Fragmentation**: Minimized through careful allocation

---

## Performance Optimization

### Compute Optimization

#### A100-Specific Settings
```yaml
Compute Capability: 8.0
Mixed Precision: Enabled (fp16)
Tensor Cores: Utilized automatically
CUDA Graphs: Enabled for repetitive operations
```

#### vLLM Optimizations
```bash
# vLLM Performance Settings
export VLLM_USE_TRITON=0
export ENABLE_PREFIX_CACHING=true
export MAX_NUM_SEQS=256
export GPU_MEMORY_UTILIZATION=0.9
```

#### Multi-GPU Communication
```yaml
NVLink: Enabled for GPU 2-3 communication
TCP Store: Distributed tensor operations
NCCL Backend: Optimized collective communications
```

### Model Loading Optimization

#### Model Precision Settings
```yaml
whisper:
  precision: fp16
  optimization: TensorRT
  estimated_size: 3GB

embedding:
  precision: fp16
  batch_size: 32
  estimated_size: 400MB

llm:
  precision: fp16
  tensor_parallel: 2
  estimated_size: 1.4GB

ocr:
  precision: fp16
  optimization: ONNX
  estimated_size: 350MB
```

#### Preloading Strategy
```bash
# Preload all models at startup
PRELOAD_MODELS=true
LOCAL_FILES_ONLY=true
HF_HUB_OFFLINE=1
TRANSFORMERS_OFFLINE=1
```

---

## Monitoring and Health Checks

### GPU Utilization Monitoring

#### Target Metrics
```yaml
GPU Utilization Target: 80%
Memory Usage Alert: 85%
Temperature Limit: 83°C (A100 spec)
Power Consumption: Monitor for efficiency
```

#### Monitoring Commands
```bash
# Real-time GPU monitoring
watch -n 1 nvidia-smi

# Detailed GPU metrics
nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw --format=csv

# Service-specific monitoring
docker exec rag-llm-server nvidia-smi
```

### Health Check Configuration

#### Service Health Checks
```yaml
Health Check Interval: 30 seconds
Timeout: 10 seconds
Retries: 3 attempts
```

#### Health Check Endpoints
```bash
# Test all service health
curl http://localhost:8004/health  # Whisper
curl http://localhost:8001/health  # Embedding
curl http://localhost:8003/health  # LLM
curl http://localhost:8002/health  # OCR
```

---

## Scaling Strategies

### Horizontal Scaling

#### Load Balancing Options
```yaml
LLM Scaling:
  Primary: GPU 2-3
  Secondary: GPU 5 (additional instance)

Embedding Scaling:
  Primary: GPU 1
  Secondary: GPU 6 (specialized models)
```

#### Scaling Commands
```bash
# Scale LLM to additional GPU
docker run -d \
  --name rag-llm-server-2 \
  --gpus '"device=5"' \
  -e CUDA_VISIBLE_DEVICES=5 \
  rag-llm-gptoss:latest

# Load balancer configuration (nginx/haproxy)
upstream llm_backend {
    server rag-llm-server:8000;
    server rag-llm-server-2:8000;
}
```

### Vertical Scaling

#### Resource Expansion
```yaml
Whisper Expansion:
  Max GPUs: 2 (add GPU 5)
  Memory Expansion: 160GB

OCR Expansion:
  Max GPUs: 2 (add GPU 7)
  Memory Expansion: 160GB
```

---

## Troubleshooting GPU Issues

### Common GPU Problems

#### 1. Out of Memory (OOM) Errors
```bash
# Check memory usage
nvidia-smi

# Reduce batch size
export MAX_NUM_BATCHED_TOKENS=1024

# Reduce GPU memory utilization
export GPU_MEMORY_UTILIZATION=0.8
```

#### 2. GPU Not Detected
```bash
# Verify GPU availability
nvidia-smi

# Check Docker GPU support
docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi

# Restart NVIDIA services
sudo systemctl restart nvidia-docker
```

#### 3. Inter-GPU Communication Issues
```bash
# Test NVLink connectivity
nvidia-smi nvlink --status

# Verify NCCL
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=ALL
```

#### 4. Service Won't Start
```bash
# Check container logs
docker logs rag-llm-server

# Verify GPU allocation
docker inspect rag-llm-server | grep -A 10 "DeviceRequests"

# Test GPU access in container
docker exec rag-llm-server nvidia-smi
```

### Diagnostic Scripts

#### GPU Health Check Script
```bash
#!/bin/bash
# GPU Health Check
echo "=== GPU Health Check ==="

# Check all GPUs
nvidia-smi --query-gpu=index,name,driver_version,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv

# Check running containers with GPU access
echo -e "\n=== Containers with GPU Access ==="
docker ps --format "table {{.Names}}\t{{.Status}}" | grep rag

# Test each service
echo -e "\n=== Service Health ==="
services=("8004:Whisper" "8001:Embedding" "8003:LLM" "8002:OCR")
for service in "${services[@]}"; do
    IFS=':' read -r port name <<< "$service"
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/health" | grep -q "200"; then
        echo "✓ $name: Healthy"
    else
        echo "✗ $name: Unhealthy"
    fi
done
```

---

## Best Practices

### GPU Allocation Best Practices

1. **Isolate Workloads**: Assign dedicated GPUs to prevent resource contention
2. **Monitor Utilization**: Maintain 70-85% GPU utilization for optimal performance
3. **Temperature Management**: Keep GPU temperature below 80°C
4. **Memory Buffers**: Reserve 10% GPU memory for overhead
5. **Load Balancing**: Distribute workload evenly across available GPUs

### Optimization Guidelines

1. **Model Precision**: Use fp16 for memory efficiency
2. **Batch Sizing**: Optimize batch sizes for GPU memory
3. **Tensor Parallelism**: Use for large models across multiple GPUs
4. **Memory Pooling**: Enable for frequent allocations
5. **Preloading**: Load models at startup for faster inference

### Maintenance Procedures

1. **Regular Monitoring**: Check GPU health daily
2. **Log Rotation**: Manage container and GPU logs
3. **Performance Tuning**: Adjust parameters based on usage patterns
4. **Capacity Planning**: Monitor for scaling needs
5. **Backup Strategies**: Plan for GPU failure scenarios

---

## Emergency Procedures

### GPU Failure Recovery

#### Single GPU Failure
```bash
# Identify failed GPU
nvidia-smi

# Reassign service to backup GPU
docker stop rag-whisper
docker run -d --name rag-whisper-backup --gpus '"device=5"' rag-whisper:latest

# Update load balancer configuration
```

#### Multiple GPU Failure
```bash
# Enable CPU fallback mode
export CUDA_VISIBLE_DEVICES=""
export DEVICE=cpu

# Restart services in CPU mode
./scripts/emergency_fallbacks.sh
```

### Service Recovery Scripts

#### Emergency Fallback Script
```bash
#!/bin/bash
# Emergency fallback to CPU operation
echo "=== Emergency Fallback to CPU ==="

# Stop GPU services
docker stop rag-whisper rag-embedding-server rag-llm-server rag-dots-ocr

# Start CPU-only versions
docker run -d --name rag-whisper-cpu -e DEVICE=cpu rag-whisper:latest
docker run -d --name rag-llm-cpu -e CUDA_VISIBLE_DEVICES="" rag-llm-gptoss:latest

echo "✓ Emergency fallback complete"
echo "⚠ Performance will be significantly reduced"
```

This GPU allocation guide ensures optimal performance and reliability of the RAG system while providing clear procedures for monitoring, scaling, and troubleshooting GPU-related issues.