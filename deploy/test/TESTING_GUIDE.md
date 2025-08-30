# RAG System Testing Guide

This guide explains how to test the RAG system without requiring GPUs or expensive hardware resources.

## Testing Strategies

### 1. Mock Services Testing (No GPU Required)

The easiest way to test the system is using mock services that simulate the LLM, embedding, and OCR services without requiring actual models or GPUs.

#### Setup Mock Environment

```bash
cd deploy/test

# Make scripts executable
chmod +x *.sh

# Deploy test environment with mock services
./deploy_test_environment.sh mock

# Run integration tests
./run_integration_tests.sh

# Stop test environment when done
./stop_test_environment.sh
```

#### What Mock Services Provide

- **Mock LLM**: Returns predefined responses, simulates streaming
- **Mock Embedding**: Generates random embeddings for testing
- **Mock OCR**: Returns sample text without actual OCR processing
- **Real API & Frontend**: Uses actual API and frontend code with mock backends

### 2. CPU-Only Testing (Limited Models)

For more realistic testing without GPUs, you can use CPU-optimized models:

#### Option A: Tiny Models on CPU

```bash
# Modify Dockerfiles to remove GPU requirements
# Use tiny models like:
# - microsoft/phi-2 (2.7B parameters)
# - TinyLlama/TinyLlama-1.1B
# - all-MiniLM-L6-v2 (for embeddings)

# Set environment variable to disable CUDA
export CUDA_VISIBLE_DEVICES=""

# Run with CPU-only configuration
docker run --rm \
  -e CUDA_VISIBLE_DEVICES="" \
  -e OMP_NUM_THREADS=4 \
  rag-llm-small:latest
```

#### Option B: Quantized Models

Use quantized versions of models that run efficiently on CPU:

```bash
# Use GGML/GGUF quantized models
# These can run on CPU with reasonable performance
# Examples: Llama.cpp compatible models
```

### 3. Partial System Testing

Test individual components in isolation:

#### Test Frontend Only

```bash
# Start only frontend with mock API responses
cd frontend
npm run dev
# Frontend will use fallback responses when API is unavailable
```

#### Test API Only

```bash
# Run API with in-memory mock services
docker run -d \
  --name rag-api-test \
  -p 8080:8080 \
  -e MOCK_MODE=true \
  rag-api:latest

# Test API endpoints
curl http://localhost:8080/health
curl -X POST http://localhost:8080/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "test"}'
```

### 4. Integration Testing

Run automated integration tests against the mock environment:

```bash
# Deploy test environment
./deploy_test_environment.sh mock

# Run integration tests
./run_integration_tests.sh

# Check results
# Tests cover:
# - Service health checks
# - API endpoint functionality
# - Session management
# - File upload/search
# - Frontend-API communication
```

## Test Scenarios

### Scenario 1: Basic Functionality Test

```bash
# 1. Deploy mock environment
./deploy_test_environment.sh mock

# 2. Open browser to http://localhost:3000

# 3. Test chat functionality
# - Send a message
# - Verify mock response appears

# 4. Test file search
# - Navigate to search tab
# - Enter search query
# - Verify mock results appear

# 5. Check logs for errors
docker logs rag-test-api
docker logs rag-test-frontend
```

### Scenario 2: API Integration Test

```bash
# Test complete API flow
./run_integration_tests.sh

# Manual API testing
# Create session
curl -X POST http://localhost:8080/api/chat/sessions \
  -H "Content-Type: application/json" \
  -d '{"user_id": "test", "title": "Test"}'

# Send message (replace SESSION_ID)
curl -X POST http://localhost:8080/api/chat/sessions/SESSION_ID/messages \
  -H "Content-Type: application/json" \
  -d '{"content": "Hello", "use_rag": true}'
```

### Scenario 3: Load Testing

```bash
# Simple load test with mock services
for i in {1..10}; do
  curl -X POST http://localhost:8080/api/search \
    -H "Content-Type: application/json" \
    -d '{"query": "test query '$i'"}' &
done
wait

# Check response times and errors
```

## Validation Checklist

### Pre-Deployment Testing

- [ ] All Docker images build successfully
- [ ] Mock services start without errors
- [ ] Frontend loads in browser
- [ ] API health check passes
- [ ] Basic chat functionality works
- [ ] File search returns results
- [ ] Session management works
- [ ] File upload accepts files
- [ ] Logs show no critical errors

### Integration Testing

- [ ] All automated tests pass
- [ ] Services communicate correctly
- [ ] Frontend proxies API requests
- [ ] Error handling works properly
- [ ] Sessions persist correctly
- [ ] RAG toggle functions
- [ ] Mock responses appear

### Performance Testing

- [ ] Services start within 30 seconds
- [ ] API responds within 2 seconds
- [ ] Frontend loads within 5 seconds
- [ ] No memory leaks after 100 requests
- [ ] CPU usage remains reasonable

## Troubleshooting

### Common Issues

#### 1. Services Not Starting

```bash
# Check Docker logs
docker logs rag-test-api
docker logs rag-test-llm

# Verify network exists
docker network ls | grep rag-test-network

# Check port availability
netstat -tulpn | grep -E '3000|8080|8001|8002|8003'
```

#### 2. Connection Errors

```bash
# Test network connectivity
docker exec rag-test-api ping rag-test-llm

# Check service discovery
docker exec rag-test-api nslookup rag-test-llm

# Verify endpoints
curl http://localhost:8080/health
curl http://localhost:3000/
```

#### 3. Mock Services Not Responding

```bash
# Rebuild mock images
docker build -f Dockerfile.mock-llm -t rag-mock-llm:test .

# Run with debug output
docker run --rm rag-mock-llm:test

# Check mock service directly
curl http://localhost:8003/health
```

## Test in Production-Like Environment

### Minimal GPU Testing

If you have access to a small GPU (even 4GB VRAM):

```bash
# Use smallest possible models
# - Qwen2-0.5B for embeddings
# - Phi-2 or TinyLlama for LLM
# - Reduce batch sizes and memory usage

# Deploy with minimal resources
docker run -d \
  --gpus all \
  -e GPU_MEMORY=0.2 \
  -e TENSOR_PARALLEL=1 \
  rag-llm-small:latest
```

### Cloud Testing

Test on cloud providers with free tiers:

- **Google Colab**: Free GPU access for testing
- **Kaggle**: Free GPU kernels
- **AWS Free Tier**: t2.micro for CPU testing
- **Azure Free Account**: Limited compute credits

## Continuous Integration

### GitHub Actions Example

```yaml
name: Test RAG System

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Build mock services
      run: |
        cd deploy/test
        docker build -f Dockerfile.mock-llm -t rag-mock-llm:test .
        docker build -f Dockerfile.mock-ocr -t rag-mock-ocr:test .
    
    - name: Deploy test environment
      run: |
        cd deploy/test
        ./deploy_test_environment.sh mock
    
    - name: Run integration tests
      run: |
        cd deploy/test
        ./run_integration_tests.sh
    
    - name: Cleanup
      if: always()
      run: |
        cd deploy/test
        ./stop_test_environment.sh
```

## Summary

Testing without GPUs is completely feasible using:

1. **Mock Services**: Fastest, no resources required
2. **CPU Models**: More realistic, slower but functional
3. **Partial Testing**: Test components individually
4. **Cloud Resources**: Use free tiers for occasional testing

The mock environment provides sufficient testing coverage for:
- Integration testing
- API functionality
- Frontend-backend communication
- Error handling
- Basic performance validation

For production deployment, always test with actual models and GPUs when possible, but the mock environment ensures the system architecture and integration work correctly.