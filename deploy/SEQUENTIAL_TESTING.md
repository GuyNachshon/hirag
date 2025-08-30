# Sequential Service Testing Guide

This guide explains how to test the RAG system services individually to manage GPU memory constraints effectively.

## Overview

The RAG system includes multiple GPU-intensive services that require significant VRAM:

| Service | Memory Required | Description |
|---------|----------------|-------------|
| DotsOCR | ~7GB | Vision-language model for document processing |
| Embedding | ~3GB | Text embedding generation (Qwen2-0.5B) |
| LLM Small | ~8GB | Small language model (Qwen3-4B) |
| LLM GPT-OSS | ~16GB | Large language model (gpt-oss-20b) |
| Whisper | ~4GB | Hebrew audio transcription |

**Total if running simultaneously: ~38GB VRAM** (impossible on most single GPUs)

## Sequential Testing Solution

The `test_services_sequential.sh` script tests each GPU service individually:

1. **Starts one service** at a time
2. **Runs comprehensive tests** for that service
3. **Stops the service** and cleans up GPU memory
4. **Moves to the next service**
5. **Runs integration tests** with CPU services

## Usage

### Basic Usage

```bash
# Test all services sequentially
./test_services_sequential.sh

# Test with custom memory limit
./test_services_sequential.sh --memory-limit 12

# Test specific service only
./test_services_sequential.sh --service whisper

# Skip GPU services, test integration only
./test_services_sequential.sh --skip-gpu

# Verbose output with detailed information
./test_services_sequential.sh --verbose
```

### Command Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `--service <name>` | Test specific service only | `--service dotsocr` |
| `--skip-gpu` | Run only CPU services and integration | `--skip-gpu` |
| `--integration-only` | Skip individual tests, run integration only | `--integration-only` |
| `--memory-limit <gb>` | GPU memory limit in GB (default: 8) | `--memory-limit 12` |
| `--verbose` | Show detailed output and benchmarks | `--verbose` |
| `--help` | Show help message | `--help` |

### Service Names

Available services for `--service` option:

- `dotsocr` - DotsOCR vision service
- `embedding` - Embedding generation service  
- `llm-small` - Small LLM service (Qwen3-4B)
- `llm-gptoss` - GPT-OSS LLM service (20B parameters)
- `whisper` - Hebrew transcription service

## Test Types

### 1. Individual Service Tests

Each service undergoes:

**Health Checks:**
- Container startup verification
- Health endpoint testing
- Service readiness confirmation

**Functionality Tests:**
- **DotsOCR**: Image processing and OCR capability
- **Embedding**: Text embedding generation via vLLM API
- **LLM Services**: Text generation via chat completions API
- **Whisper**: Audio transcription with Hebrew audio files

**Performance Tests** (with `--verbose`):
- Response time benchmarking
- GPU memory usage monitoring
- Stress testing with concurrent requests

### 2. Integration Tests

**API Testing:**
- REST endpoint functionality
- File search capabilities
- Chat session management
- Cross-service communication

**Frontend Testing:**
- Web interface accessibility
- Static asset serving
- API proxy functionality

### 3. Resource Management

**GPU Memory Monitoring:**
- Pre-service memory check
- Usage monitoring during tests
- Post-service cleanup verification
- Memory leak detection

**Cleanup Procedures:**
- Container shutdown and removal
- GPU memory release
- Network cleanup
- Temporary file removal

## Test Scenarios

### Scenario 1: Full System Validation

```bash
# Test all services with 8GB GPU
./test_services_sequential.sh --memory-limit 8 --verbose
```

**What happens:**
1. Tests DotsOCR (7GB) - ✓
2. Tests Embedding (3GB) - ✓ 
3. Tests LLM Small (8GB) - ✓
4. Tests Whisper (4GB) - ✓
5. Skips GPT-OSS (16GB > 8GB limit)
6. Tests API and Frontend integration
7. Reports comprehensive results

### Scenario 2: High-Memory GPU Testing

```bash
# Test all services including GPT-OSS with 20GB GPU
./test_services_sequential.sh --memory-limit 20 --verbose
```

**What happens:**
1. Tests all services including GPT-OSS
2. Runs comprehensive functionality tests
3. Performs stress testing and benchmarking
4. Validates complete system capabilities

### Scenario 3: Quick Integration Check

```bash
# Skip GPU services, test integration only
./test_services_sequential.sh --integration-only
```

**What happens:**
1. Skips all GPU services
2. Tests API service startup and endpoints
3. Tests frontend accessibility
4. Validates basic system integration

### Scenario 4: Specific Service Debugging

```bash
# Debug specific service with detailed output
./test_services_sequential.sh --service whisper --verbose
```

**What happens:**
1. Tests only Whisper service
2. Shows detailed startup logs
3. Runs comprehensive transcription tests
4. Monitors GPU memory usage
5. Provides detailed debugging information

## Creating Test Data

The script automatically creates test data:

**Audio Files:**
- Generates test audio using `espeak` and `ffmpeg` if available
- Creates Hebrew speech samples for Whisper testing
- Falls back to simple audio files if tools unavailable

**Image Files:**
- Creates test images with text using ImageMagick if available
- Provides OCR test samples for DotsOCR validation

**Text Data:**
- Creates sample documents for indexing
- Provides test queries for search functionality

## Interpreting Results

### Success Indicators

```
========================================
Sequential Service Testing Results
========================================
Services Tested: 5
Tests Passed: 23
Tests Failed: 0
Total Tests: 23

🎉 All tests passed!
Your RAG system is ready for deployment!
```

### Failure Analysis

```
❌ Some tests failed
Please check the failed services and try again.

Troubleshooting tips:
1. Check Docker logs: docker logs <container-name>
2. Verify GPU memory: nvidia-smi
3. Check available disk space: df -h
4. Run with --verbose for detailed output
```

## Troubleshooting Common Issues

### GPU Memory Issues

**Problem**: Service fails to start due to insufficient GPU memory

**Solutions:**
- Lower memory limit: `--memory-limit 6`
- Test specific services: `--service embedding`
- Use CPU mode for testing: `--skip-gpu`

### Model Loading Failures

**Problem**: Service starts but model fails to load

**Solutions:**
- Check container logs: `docker logs rag-service-name`
- Verify model images are properly built
- Ensure sufficient disk space for model files

### Network Connectivity Issues

**Problem**: Services can't communicate

**Solutions:**
- Verify Docker network: `docker network ls`
- Check firewall settings
- Ensure ports aren't already in use: `netstat -tulpn`

### Container Startup Failures

**Problem**: Containers fail to start

**Solutions:**
- Check Docker daemon: `docker info`
- Verify image availability: `docker images`
- Check system resources: `df -h` and `free -h`

## Advanced Usage

### Custom Test Scenarios

You can modify `test_service_functions.sh` to add custom test cases:

```bash
# Add custom DotsOCR test
test_dotsocr_custom() {
    local service_name="$1"
    local base_url="$2"
    
    # Your custom test logic here
    print_test "Running custom DotsOCR test..."
    # ... test implementation
}
```

### CI/CD Integration

For automated testing in CI/CD pipelines:

```yaml
# GitHub Actions example
- name: Test RAG Services
  run: |
    ./deploy/test_services_sequential.sh --memory-limit 8 --integration-only
```

### Resource Monitoring

For detailed resource monitoring:

```bash
# Monitor system resources during tests
watch -n 1 'nvidia-smi; echo "---"; docker ps --format "table {{.Names}}\t{{.Status}}"' &
./test_services_sequential.sh --verbose
```

## Best Practices

1. **Start with integration tests** to validate basic functionality
2. **Use specific service testing** for debugging issues
3. **Run full sequential tests** before production deployment
4. **Monitor resource usage** during testing
5. **Keep test data minimal** but representative
6. **Document test failures** with verbose output
7. **Validate cleanup** between service tests

## Comparison with Other Testing Methods

| Method | GPU Memory | Test Coverage | Time | Use Case |
|--------|------------|---------------|------|----------|
| **Sequential** | Low (max 8GB) | Complete | Medium | Resource-constrained environments |
| **Simultaneous** | High (38GB+) | Complete | Fast | High-end GPU systems |
| **Mock Services** | None | Integration only | Fast | Development and basic validation |
| **Partial Testing** | Variable | Selective | Fast | Debugging specific issues |

## Conclusion

Sequential testing provides a comprehensive validation approach for GPU-constrained environments while maintaining thorough test coverage. It enables complete system validation on standard development hardware without requiring expensive high-memory GPU setups.

The approach ensures each service is properly validated individually while still testing system integration, making it ideal for:

- Development environments with limited GPU memory
- CI/CD pipelines with resource constraints  
- Production deployment validation
- Service-specific debugging and optimization