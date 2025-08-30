# RAG System Testing - Quick Reference

## Sequential Testing (Recommended for GPU-Constrained Environments)

### Basic Commands

```bash
# Test all services (requires 8GB+ GPU memory)
./test_services_sequential.sh

# Test with custom memory limit
./test_services_sequential.sh --memory-limit 12

# Test specific service only
./test_services_sequential.sh --service whisper

# Test without GPU (CPU services only)
./test_services_sequential.sh --skip-gpu

# Detailed output with benchmarks
./test_services_sequential.sh --verbose

# Integration tests only
./test_services_sequential.sh --integration-only
```

### Service Memory Requirements

| Service | Command | Memory | Description |
|---------|---------|--------|-------------|
| DotsOCR | `--service dotsocr` | ~7GB | Vision-language OCR |
| Embedding | `--service embedding` | ~3GB | Text embeddings |
| LLM Small | `--service llm-small` | ~8GB | Qwen3-4B model |
| GPT-OSS | `--service llm-gptoss` | ~16GB | Large 20B model |
| Whisper | `--service whisper` | ~4GB | Hebrew transcription |

## Traditional Testing Methods

### Mock Services (No GPU Required)

```bash
cd deploy/test
./deploy_test_environment.sh mock
./run_integration_tests.sh
./stop_test_environment.sh
```

### Full Deployment (Requires 20GB+ GPU)

```bash
./deploy_complete.sh
./validate_offline_deployment.sh
```

## Common Use Cases

### 1. Limited GPU Memory (8GB)
```bash
# Test services that fit in 8GB
./test_services_sequential.sh --memory-limit 8
```
**Tests**: DotsOCR, Embedding, LLM Small, Whisper (skips GPT-OSS)

### 2. Debug Specific Service
```bash
# Verbose testing for troubleshooting
./test_services_sequential.sh --service whisper --verbose
```

### 3. CI/CD Pipeline
```bash
# Quick integration check
./test_services_sequential.sh --integration-only
```

### 4. Production Validation
```bash
# Full testing with high-end GPU
./test_services_sequential.sh --memory-limit 20 --verbose
```

### 5. Development Testing
```bash
# Mock services for rapid iteration
cd deploy/test && ./deploy_test_environment.sh mock
```

## Test Outputs

### Success Example
```
🎉 All tests passed!
Services Tested: 5
Tests Passed: 23  
Tests Failed: 0
Your RAG system is ready for deployment!
```

### Failure Example
```
❌ Some tests failed
Services Tested: 3
Tests Passed: 15
Tests Failed: 3

Troubleshooting tips:
1. Check Docker logs: docker logs <container-name>
2. Verify GPU memory: nvidia-smi
3. Run with --verbose for detailed output
```

## Quick Troubleshooting

| Issue | Solution |
|-------|----------|
| Out of GPU memory | Use `--memory-limit <gb>` or `--skip-gpu` |
| Service won't start | Check `docker logs <service-name>` |
| Network errors | Verify `docker network ls \| grep rag` |
| Model loading fails | Ensure images are built: `docker images \| grep rag` |
| Tests timeout | Increase wait times, check system load |

## File Structure

```
deploy/
├── test_services_sequential.sh      # Main sequential testing script
├── test_service_functions.sh        # Detailed test functions  
├── SEQUENTIAL_TESTING.md            # Comprehensive guide
├── validate_offline_deployment.sh   # Traditional validation
└── test/
    ├── deploy_test_environment.sh    # Mock services
    ├── run_integration_tests.sh      # Integration tests
    └── stop_test_environment.sh      # Cleanup
```

## When to Use Each Method

| Method | GPU Memory | Use Case | Time |
|--------|------------|----------|------|
| **Sequential** | 8GB+ | Most scenarios | 15-30 min |
| **Mock** | None | Development | 2-5 min |
| **Full Deploy** | 20GB+ | Final validation | 5-10 min |
| **Specific Service** | Variable | Debugging | 3-8 min |

## Examples by Hardware

### RTX 4090 (24GB VRAM)
```bash
# Can run everything
./test_services_sequential.sh --verbose
```

### RTX 3080 (10GB VRAM) 
```bash
# Skip GPT-OSS
./test_services_sequential.sh --memory-limit 10
```

### RTX 3060 (8GB VRAM)
```bash
# Test smaller services
./test_services_sequential.sh --memory-limit 8
```

### No GPU
```bash
# CPU only + mock tests
./test_services_sequential.sh --skip-gpu
cd deploy/test && ./deploy_test_environment.sh mock
```

## Getting Help

```bash
./test_services_sequential.sh --help
```

For detailed information, see `SEQUENTIAL_TESTING.md`.