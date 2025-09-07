# A100 Testing Guide
## RAG System Testing on a2-highgpu-1g

### Machine Configuration
- **Machine Type**: a2-highgpu-1g
- **CPUs**: 12 vCPUs (Intel Cascade Lake)
- **Memory**: 85 GB RAM
- **GPU**: 1 x NVIDIA A100 40GB
- **Architecture**: x86/64

---

## 🚀 Quick Start for A100 Testing

### 1. Deploy RAG System (A100 Optimized)
```bash
# Deploy all services optimized for single A100 GPU
./deploy/deploy_a100_single_gpu.sh
```

**Memory Allocation Strategy:**
- Embedding Server: 4GB (10%)
- Whisper Service: 6GB (15%)  
- DotsOCR Service: 12GB (30%)
- LLM Service: 13GB (32.5%)
- System Buffer: 5GB (12.5%)
- **Total: 35GB of 40GB available**

### 2. Monitor System Status
```bash
# Real-time monitoring dashboard
./deploy/monitor_a100_single_gpu.sh

# One-time status check
./deploy/monitor_a100_single_gpu.sh --once

# Check container logs
./deploy/monitor_a100_single_gpu.sh --logs
```

### 3. Validate Deployment
```bash
# A100-specific validation
./deploy/validate_a100_deployment.sh

# Complete offline functionality testing
./deploy/test_offline_complete.sh

# Generate test data first (if needed)
./deploy/generate_test_data.sh
```

### 4. Run Performance Testing
```bash
# End-to-end workflow testing
./deploy/test_e2e_rag_workflow.sh

# Performance benchmarking (reduced load for single GPU)
./deploy/benchmark_h100_deployment.sh --duration 300 --concurrent 5
```

---

## 🔧 A100-Specific Optimizations

### Single GPU Memory Management
Unlike the H100 8-core setup, all services share the single A100 GPU:

```yaml
Services on GPU 0:
├─ rag-embedding-server (4GB)
├─ rag-whisper (6GB)  
├─ rag-dots-ocr (12GB)
└─ rag-llm-server (13GB)
Total: 35GB / 40GB used (5GB buffer)
```

### Performance Expectations (Single GPU)
| Metric | A100 Single GPU | H100 8-Core |
|--------|----------------|-------------|
| Query Response | 2-4s | 1-2s |
| Document Processing | 30-60s | 15-30s |
| Concurrent Users | 3-5 | 10-15 |
| GPU Memory Usage | 85-90% | 60-70% |

### Docker Service Configuration
```bash
# All services use same GPU with memory limits
--gpus all
-e CUDA_VISIBLE_DEVICES=0
-e GPU_MEMORY_UTILIZATION=0.1-0.35  # Varies by service
```

---

## 🧪 Testing Scenarios

### Scenario 1: Basic Functionality Test
```bash
# Quick health check and basic functionality
./deploy/test_offline_complete.sh --quick
```

### Scenario 2: Memory Stress Test
```bash
# Test memory allocation under load
./deploy/benchmark_h100_deployment.sh --concurrent 3 --duration 180
```

### Scenario 3: Multi-Modal Processing
```bash
# Test document + image + audio processing
./deploy/test_e2e_rag_workflow.sh
```

### Scenario 4: Hebrew Language Testing
```bash
# Generate test data with Hebrew content
./deploy/generate_test_data.sh

# Test Hebrew queries and transcription
./deploy/test_e2e_rag_workflow.sh --verbose
```

---

## 🔍 Monitoring and Troubleshooting

### Real-Time Monitoring
```bash
# Continuous monitoring (updates every 3 seconds)
./deploy/monitor_a100_single_gpu.sh

# Expected output:
# GPU Memory Usage: 32.5GB / 40GB (81%)
# All services: HEALTHY
# GPU utilization: 45-85% during processing
```

### Common Issues and Solutions

#### High GPU Memory Usage (>95%)
```bash
# Check which service is using too much memory
docker stats

# Restart services in sequence
docker restart rag-llm-server
docker restart rag-dots-ocr
```

#### Service Startup Failures
```bash
# Check logs
docker logs rag-dots-ocr --tail 50

# Clean restart
./deploy/deploy_a100_single_gpu.sh --cleanup
./deploy/deploy_a100_single_gpu.sh
```

#### Slow Response Times
```bash
# Check GPU utilization
./deploy/monitor_a100_single_gpu.sh --once

# May be normal for single GPU - services queue requests
```

---

## 📊 Expected Test Results

### Health Check Results
```
✅ Service Health Checks: 6/6 services healthy
✅ Inter-service Communication: All connections working
✅ Document Processing: Upload and indexing successful
✅ Query Processing: English and Hebrew queries working
✅ Multi-modal Processing: OCR and transcription working
```

### Performance Benchmarks
```
Response Times (Single GPU):
├─ API Health Check: 0.1-0.3s
├─ Query Processing: 2-5s  
├─ Document Processing: 30-90s
├─ OCR Processing: 10-30s
└─ Audio Transcription: 5-15s

GPU Metrics:
├─ Memory Usage: 85-90% (expected)
├─ Utilization: 40-80% during processing
├─ Temperature: 65-75°C (good)
└─ Power Draw: 200-350W (normal)
```

### Memory Allocation Validation
```
Expected Memory Usage:
✅ Embedding: ~4GB allocated
✅ Whisper: ~6GB allocated  
✅ DotsOCR: ~12GB allocated
✅ LLM: ~13GB allocated
✅ Total: ~35GB (87.5% of 40GB)
```

---

## 🎯 Success Criteria

### ✅ Deployment Success
- All 6 services running and healthy
- GPU memory usage 80-90%
- No service crashes or OOM errors
- Response times within acceptable ranges

### ✅ Testing Success
- Health checks: 100% pass rate
- End-to-end workflows: All complete successfully
- Multi-modal processing: OCR + transcription working
- Hebrew language support: Queries and responses working

### ✅ Performance Acceptable
- Query response time: < 5s average
- Document processing: < 2 minutes
- System stability: No crashes during 5-minute test
- Concurrent processing: 3+ users supported

---

## 🚨 Important Notes for A100

1. **Single GPU Limitation**: All services share one GPU, so expect:
   - Sequential processing (services queue requests)
   - Higher memory pressure
   - Slower response times than multi-GPU setup

2. **Memory Management**: 
   - Keep total usage < 90% to prevent OOM
   - Monitor memory during heavy operations
   - Services may fail if memory exceeds limits

3. **Performance Expectations**:
   - 50-70% of H100 8-core performance 
   - Good for testing and validation
   - Not suitable for high-concurrency production

4. **Test Coverage**:
   - Focus on functionality over performance
   - Validate all features work correctly
   - Test memory limits and stability

---

## 📋 Testing Checklist

- [ ] Deploy RAG system: `./deploy/deploy_a100_single_gpu.sh`
- [ ] Validate deployment: `./deploy/validate_a100_deployment.sh`  
- [ ] Generate test data: `./deploy/generate_test_data.sh`
- [ ] Run health checks: `./deploy/test_offline_complete.sh`
- [ ] Test workflows: `./deploy/test_e2e_rag_workflow.sh`
- [ ] Performance benchmark: `./deploy/benchmark_h100_deployment.sh --quick`
- [ ] Monitor system: `./deploy/monitor_a100_single_gpu.sh --once`
- [ ] Review reports: Check generated HTML files

**Ready to test your RAG system on A100! 🚀**