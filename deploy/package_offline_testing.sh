#!/bin/bash

set -e

echo "=========================================="
echo "RAG System Offline Testing Package Creator"
echo "Bundling Complete Testing Framework"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[PACKAGE]${NC} $1"
}

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Configuration
PACKAGE_NAME="rag-offline-testing-$(date +%Y%m%d)"
PACKAGE_DIR="./${PACKAGE_NAME}"
ARCHIVE_NAME="${PACKAGE_NAME}.tar.gz"
TEST_DATA_DIR="./test-data-offline"

# GCP settings (if specified)
GCP_BUCKET="${GCP_BUCKET:-}"
UPLOAD_TO_GCP="${UPLOAD_TO_GCP:-false}"

# Create package structure
create_package_structure() {
    print_header "Creating package structure..."
    
    # Remove existing package if it exists
    rm -rf "$PACKAGE_DIR" 2>/dev/null || true
    
    # Create main directories
    mkdir -p "$PACKAGE_DIR"/{scripts,test-data,docs,config}
    
    # Create subdirectories
    mkdir -p "$PACKAGE_DIR/test-data"/{documents,audio,images,queries,expected,working,logs,cache}
    mkdir -p "$PACKAGE_DIR/test-data"/{e2e-results,performance-results,benchmark-results}
    mkdir -p "$PACKAGE_DIR/scripts"/{core,monitoring,utilities}
    mkdir -p "$PACKAGE_DIR/config"/{templates,examples}
    
    print_status "✓ Package directory structure created"
}

# Copy testing scripts
copy_testing_scripts() {
    print_header "Copying testing scripts..."
    
    # Core testing scripts
    local core_scripts=(
        "generate_test_data.sh"
        "test_offline_complete.sh"
        "validate_8core_performance.sh"
        "test_e2e_rag_workflow.sh"
        "benchmark_h100_deployment.sh"
    )
    
    print_step "Copying core testing scripts..."
    for script in "${core_scripts[@]}"; do
        if [[ -f "deploy/$script" ]]; then
            cp "deploy/$script" "$PACKAGE_DIR/scripts/core/"
            print_status "✓ Copied $script"
        else
            print_warning "⚠ Script not found: deploy/$script"
        fi
    done
    
    # Deployment scripts
    local deployment_scripts=(
        "deploy_h100_8core_optimized.sh"
        "monitor_h100_8core.sh"
        "validate_h100_deployment.sh"
        "validate_offline_deployment.sh"
    )
    
    print_step "Copying deployment and monitoring scripts..."
    for script in "${deployment_scripts[@]}"; do
        if [[ -f "deploy/$script" ]]; then
            cp "deploy/$script" "$PACKAGE_DIR/scripts/core/"
            print_status "✓ Copied $script"
        else
            print_warning "⚠ Script not found: deploy/$script"
        fi
    done
    
    # Override and utility scripts
    local utility_scripts=(
        "create_runtime_fixes.sh"
        "apply_all_overrides.sh"
        "rollback_overrides.sh"
        "rebuild_modified_services.sh"
    )
    
    print_step "Copying utility scripts..."
    for script in "${utility_scripts[@]}"; do
        if [[ -f "deploy/$script" ]]; then
            cp "deploy/$script" "$PACKAGE_DIR/scripts/utilities/"
            print_status "✓ Copied $script"
        else
            print_status "- Optional script not found: $script"
        fi
    done
}

# Copy and generate test data
prepare_test_data() {
    print_header "Preparing test data..."
    
    # Generate test data if it doesn't exist
    if [[ ! -d "$TEST_DATA_DIR" ]]; then
        print_step "Generating test data..."
        if ! ./deploy/generate_test_data.sh; then
            print_error "Failed to generate test data"
            return 1
        fi
    fi
    
    # Copy existing test data
    if [[ -d "$TEST_DATA_DIR" ]]; then
        print_step "Copying existing test data..."
        cp -r "$TEST_DATA_DIR"/* "$PACKAGE_DIR/test-data/"
        
        # Exclude large or temporary files
        find "$PACKAGE_DIR/test-data" -name "*.tmp" -delete 2>/dev/null || true
        find "$PACKAGE_DIR/test-data" -name "*.log" -delete 2>/dev/null || true
        find "$PACKAGE_DIR/test-data" -type d -name "logs" -exec rm -rf {} + 2>/dev/null || true
        
        print_status "✓ Test data copied and cleaned"
    else
        print_warning "⚠ No existing test data found - will generate during first run"
    fi
    
    # Ensure all required directories exist
    local required_dirs=(
        "documents" "audio" "images" "queries" "expected"
        "working" "logs" "cache" "e2e-results" 
        "performance-results" "benchmark-results"
    )
    
    for dir in "${required_dirs[@]}"; do
        mkdir -p "$PACKAGE_DIR/test-data/$dir"
    done
}

# Copy configuration files
copy_configuration_files() {
    print_header "Copying configuration files..."
    
    # Main HiRAG configuration
    if [[ -f "HiRAG/config.yaml" ]]; then
        cp "HiRAG/config.yaml" "$PACKAGE_DIR/config/hirag_config.yaml"
        print_status "✓ Copied HiRAG configuration"
    fi
    
    # Docker configurations
    local docker_files=(
        "Dockerfile.api-optimized"
        "Dockerfile.embedding-tgi-optimized"
        "Dockerfile.whisper"
        "Dockerfile.dots-ocr"
        "Dockerfile.llm"
    )
    
    print_step "Copying Docker configurations..."
    for dockerfile in "${docker_files[@]}"; do
        if [[ -f "$dockerfile" ]]; then
            cp "$dockerfile" "$PACKAGE_DIR/config/"
            print_status "✓ Copied $dockerfile"
        elif [[ -f "deploy/$dockerfile" ]]; then
            cp "deploy/$dockerfile" "$PACKAGE_DIR/config/"
            print_status "✓ Copied deploy/$dockerfile"
        else
            print_warning "⚠ Dockerfile not found: $dockerfile"
        fi
    done
    
    # .dockerignore
    if [[ -f ".dockerignore" ]]; then
        cp ".dockerignore" "$PACKAGE_DIR/config/"
        print_status "✓ Copied .dockerignore"
    fi
    
    # Create configuration templates
    create_config_templates
}

# Create configuration templates
create_config_templates() {
    print_step "Creating configuration templates..."
    
    # Docker Compose template for 8-core deployment
    cat > "$PACKAGE_DIR/config/docker-compose-8core.yml" << 'EOF'
# H100 8-Core Optimized RAG System
# Use with: docker-compose -f docker-compose-8core.yml up -d
version: '3.8'

services:
  rag-api:
    image: rag-api:latest
    container_name: rag-api
    networks:
      - rag-network
    ports:
      - "8080:8080"
    volumes:
      - ./config:/app/config:ro
      - ./data:/app/data
    restart: unless-stopped

  rag-embedding-server:
    image: rag-embedding-server:latest
    container_name: rag-embedding-server
    networks:
      - rag-network
    ports:
      - "8001:8000"
    environment:
      - CUDA_VISIBLE_DEVICES=6
      - MODEL_ID=Qwen/Qwen3-Embedding-4B
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ["6"]
              capabilities: [gpu]
    restart: unless-stopped

  rag-dots-ocr:
    image: rag-dots-ocr:latest
    container_name: rag-dots-ocr
    networks:
      - rag-network
    ports:
      - "8002:8000"
    environment:
      - CUDA_VISIBLE_DEVICES=0,1
    shm_size: 16g
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ["0", "1"]
              capabilities: [gpu]
    restart: unless-stopped

  rag-llm-server:
    image: rag-llm-gptoss:latest
    container_name: rag-llm-server
    networks:
      - rag-network
    ports:
      - "8003:8000"
    environment:
      - CUDA_VISIBLE_DEVICES=2,3,4,5
      - HF_HUB_OFFLINE=1
      - TRANSFORMERS_OFFLINE=1
      - HF_DATASETS_OFFLINE=1
    shm_size: 32g
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ["2", "3", "4", "5"]
              capabilities: [gpu]
    restart: unless-stopped

  rag-whisper:
    image: rag-whisper:latest
    container_name: rag-whisper
    networks:
      - rag-network
    ports:
      - "8004:8004"
    environment:
      - CUDA_VISIBLE_DEVICES=7
      - MODEL_NAME=ivrit-ai/whisper-large-v3
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ["7"]
              capabilities: [gpu]
    restart: unless-stopped

  rag-frontend:
    image: rag-frontend:latest
    container_name: rag-frontend
    networks:
      - rag-network
    ports:
      - "3000:3000"
    restart: unless-stopped

networks:
  rag-network:
    driver: bridge
EOF

    # Test configuration template
    cat > "$PACKAGE_DIR/config/test_config_template.yaml" << 'EOF'
# Test Configuration Template
# Copy to test-data/test_config.yaml and modify as needed

test_config:
  # Test data paths (relative to package root)
  data_paths:
    documents: "./test-data/documents"
    audio: "./test-data/audio"
    images: "./test-data/images"
    queries: "./test-data/queries"
    expected: "./test-data/expected"
    working: "./test-data/working"
  
  # Service URLs for testing
  services:
    api_url: "http://localhost:8080"
    embedding_url: "http://localhost:8001" 
    dotsocr_url: "http://localhost:8002"
    llm_url: "http://localhost:8003"
    whisper_url: "http://localhost:8004"
    frontend_url: "http://localhost:3000"
  
  # Test execution parameters
  test_parameters:
    timeout_seconds: 30
    max_retries: 3
    concurrent_queries: 5
    stress_test_duration: 300
    benchmark_iterations: 100
    
  # Expected GPU configuration for 8-core H100
  gpu_config:
    expected_cores: 8
    core_assignments:
      dotsocr: [0, 1]
      llm: [2, 3, 4, 5]
      embedding: [6]
      whisper: [7]
      
  # Performance thresholds
  performance_thresholds:
    query_response_time_ms: 5000
    document_processing_time_s: 30
    audio_transcription_time_s: 10
    image_ocr_time_s: 15
    concurrent_success_rate: 90
    throughput_min_rps: 5
    
  # Validation checks to perform
  validation_checks:
    - health_endpoints
    - service_communication
    - document_processing
    - query_functionality
    - multi_modal_processing
    - gpu_utilization
    - performance_benchmarks
    - stress_testing
EOF

    print_status "✓ Configuration templates created"
}

# Create comprehensive documentation
create_documentation() {
    print_header "Creating documentation..."
    
    # Main README
    cat > "$PACKAGE_DIR/README.md" << 'EOF'
# RAG System Offline Testing Package

This package contains a comprehensive testing framework for the H100 8-Core optimized RAG (Retrieval-Augmented Generation) system, designed for complete offline validation without internet dependencies.

## Package Contents

```
rag-offline-testing/
├── scripts/
│   ├── core/                    # Main testing scripts
│   ├── monitoring/              # Monitoring and validation tools
│   └── utilities/               # Helper and override scripts
├── test-data/                   # Comprehensive test datasets
│   ├── documents/              # Text documents (English + Hebrew)
│   ├── audio/                  # Audio files for Whisper testing
│   ├── images/                 # Images for OCR testing
│   ├── queries/                # Test queries and patterns
│   └── expected/               # Expected response patterns
├── config/                     # Configuration files and templates
│   ├── templates/              # Docker Compose and config templates
│   └── examples/               # Example configurations
└── docs/                       # Documentation and guides

```

## Quick Start

### 1. Deploy the RAG System (8-Core Optimized)
```bash
# For H100 8-core deployment
./scripts/core/deploy_h100_8core_optimized.sh

# Or use Docker Compose
docker-compose -f config/docker-compose-8core.yml up -d
```

### 2. Generate Test Data
```bash
./scripts/core/generate_test_data.sh
```

### 3. Run Complete Validation
```bash
# Full offline functionality testing
./scripts/core/test_offline_complete.sh

# 8-core GPU performance validation
./scripts/core/validate_8core_performance.sh

# End-to-end workflow testing
./scripts/core/test_e2e_rag_workflow.sh

# Comprehensive benchmarking
./scripts/core/benchmark_h100_deployment.sh
```

## Testing Framework Components

### Core Testing Scripts

- **`generate_test_data.sh`** - Creates comprehensive test datasets
- **`test_offline_complete.sh`** - Complete offline functionality validation
- **`validate_8core_performance.sh`** - GPU utilization and performance testing
- **`test_e2e_rag_workflow.sh`** - End-to-end workflow validation
- **`benchmark_h100_deployment.sh`** - Stress testing and performance benchmarking

### Deployment Scripts

- **`deploy_h100_8core_optimized.sh`** - Optimized 8-core H100 deployment
- **`monitor_h100_8core.sh`** - Real-time system monitoring
- **`validate_h100_deployment.sh`** - Deployment validation

### Test Data Categories

- **Documents**: English and Hebrew text documents, research papers, technical documentation
- **Audio**: Hebrew and English audio files for Whisper transcription testing
- **Images**: Text-heavy images and charts for OCR processing
- **Queries**: Basic and complex queries for system validation
- **Expected Responses**: Validation patterns for automated testing

## System Requirements

### Hardware
- NVIDIA H100 GPU with 8 cores (80GB VRAM total)
- Minimum 64GB system RAM
- 500GB+ available disk space

### Software
- Docker with NVIDIA Container Runtime
- NVIDIA drivers (535+ recommended)
- Docker Compose (optional but recommended)

## Testing Modes

### 1. Quick Validation
```bash
./scripts/core/test_offline_complete.sh --quick
```

### 2. Performance Benchmarking
```bash
./scripts/core/benchmark_h100_deployment.sh --duration 600 --concurrent 20
```

### 3. Stress Testing
```bash
STRESS_TEST_DURATION=600 CONCURRENT_USERS=15 ./scripts/core/benchmark_h100_deployment.sh
```

### 4. Monitoring Dashboard
```bash
./scripts/core/monitor_h100_8core.sh
```

## GPU Core Assignment (8-Core H100)

| Service | GPU Cores | Purpose |
|---------|-----------|---------|
| DotsOCR | 0, 1 | Vision processing with tensor parallelism |
| LLM (GPT-OSS-20B) | 2, 3, 4, 5 | 4-way tensor parallel language model |
| Embedding | 6 | Text embedding generation |
| Whisper | 7 | Hebrew audio transcription |

## Configuration

### Test Configuration
Copy `config/test_config_template.yaml` to `test-data/test_config.yaml` and customize:
- Performance thresholds
- Test parameters
- Service URLs
- GPU assignments

### Docker Configuration
Use provided Docker Compose file or customize individual Dockerfiles in `config/` directory.

## Output and Reporting

All testing scripts generate comprehensive reports:
- **HTML Reports**: Detailed test results with metrics and recommendations
- **JSON Metrics**: Performance data for programmatic analysis
- **CSV Data**: Time-series data for GPU utilization and performance
- **Logs**: Detailed execution logs for troubleshooting

## Troubleshooting

### Common Issues

1. **GPU Memory Exhaustion**
   ```bash
   # Use runtime override to reduce memory usage
   ./scripts/utilities/apply_all_overrides.sh
   ```

2. **Service Communication Issues**
   ```bash
   # Validate network connectivity
   docker network ls
   docker network inspect rag-network
   ```

3. **Performance Issues**
   ```bash
   # Run performance monitoring
   ./scripts/core/monitor_h100_8core.sh --once
   ```

### Getting Help

Check the generated HTML reports for detailed recommendations and troubleshooting steps. All scripts support `--help` for usage information.

## Offline Capabilities

This testing framework is designed for completely offline environments:
- All models pre-downloaded in Docker images
- No internet connectivity required during testing
- Comprehensive test data included
- Self-contained validation and reporting

## Performance Baselines

Expected performance on H100 8-core system:
- Query response time: < 2s average
- Document processing: < 30s
- Audio transcription: < 10s
- Image OCR: < 15s
- Concurrent success rate: > 95%
- Throughput: > 10 req/s

## License and Support

This testing framework is part of the RAG system deployment package. For issues or questions, refer to the main project documentation.
EOF

    # Installation guide
    cat > "$PACKAGE_DIR/docs/INSTALLATION.md" << 'EOF'
# Installation Guide

## Prerequisites Setup

### 1. System Requirements Verification
```bash
# Check NVIDIA drivers
nvidia-smi

# Check Docker
docker --version
docker info

# Check available disk space (need 500GB+)
df -h

# Check system RAM (need 64GB+)
free -h
```

### 2. NVIDIA Container Runtime Setup
```bash
# Install NVIDIA Container Runtime
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker
```

### 3. Docker Network Setup
```bash
# Create RAG network
docker network create rag-network
```

## Installation Steps

### 1. Extract Package
```bash
tar -xzf rag-offline-testing-YYYYMMDD.tar.gz
cd rag-offline-testing-YYYYMMDD
```

### 2. Make Scripts Executable
```bash
find scripts/ -name "*.sh" -exec chmod +x {} \;
```

### 3. Load Docker Images (if provided separately)
```bash
# Load Docker images from tar files
docker load < rag-api.tar
docker load < rag-embedding-server.tar
docker load < rag-dots-ocr.tar
docker load < rag-llm-gptoss.tar
docker load < rag-whisper.tar
docker load < rag-frontend.tar
```

### 4. Configuration Setup
```bash
# Copy test configuration template
cp config/test_config_template.yaml test-data/test_config.yaml

# Edit configuration as needed
nano test-data/test_config.yaml
```

### 5. Initial Validation
```bash
# Generate test data
./scripts/core/generate_test_data.sh

# Quick system validation
./scripts/core/test_offline_complete.sh --quick
```

## Deployment Options

### Option 1: Automated Script Deployment
```bash
./scripts/core/deploy_h100_8core_optimized.sh
```

### Option 2: Docker Compose Deployment
```bash
docker-compose -f config/docker-compose-8core.yml up -d
```

### Option 3: Manual Service Deployment
```bash
# Start services in order
./scripts/core/deploy_h100_8core_optimized.sh --help
# Follow manual deployment steps
```

## Verification

### 1. Service Health Check
```bash
# Check all services are running
docker ps

# Validate service health
./scripts/core/test_offline_complete.sh
```

### 2. GPU Utilization Check
```bash
# Monitor GPU assignment
./scripts/core/validate_8core_performance.sh

# Real-time monitoring
./scripts/core/monitor_h100_8core.sh
```

### 3. Performance Validation
```bash
# Quick performance test
./scripts/core/benchmark_h100_deployment.sh --quick

# Full benchmark
./scripts/core/benchmark_h100_deployment.sh
```

## Troubleshooting Installation

### Docker Issues
```bash
# Check Docker daemon
sudo systemctl status docker

# Check NVIDIA runtime
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

### GPU Issues
```bash
# Check NVIDIA drivers
nvidia-smi

# Check CUDA availability in Docker
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

### Network Issues
```bash
# Check network exists
docker network ls | grep rag-network

# Recreate network if needed
docker network rm rag-network
docker network create rag-network
```

### Disk Space Issues
```bash
# Clean up Docker system
docker system prune -a

# Check available space
df -h
```

## Next Steps

After successful installation:
1. Run full validation: `./scripts/core/test_offline_complete.sh`
2. Perform benchmarking: `./scripts/core/benchmark_h100_deployment.sh`
3. Monitor system: `./scripts/core/monitor_h100_8core.sh`
4. Review generated reports in `test-data/*/`

For ongoing monitoring and maintenance, see the main README.md file.
EOF

    # Testing guide
    cat > "$PACKAGE_DIR/docs/TESTING_GUIDE.md" << 'EOF'
# Comprehensive Testing Guide

## Overview

This guide covers all testing capabilities provided by the RAG system offline testing framework, designed for complete validation without internet connectivity.

## Test Categories

### 1. Health and Connectivity Testing
Basic service validation and network connectivity.

```bash
# Quick health check
./scripts/core/test_offline_complete.sh --quick

# Full connectivity validation
./scripts/core/test_offline_complete.sh
```

**What it tests:**
- Service health endpoints
- Inter-service communication
- Docker network connectivity
- Configuration validation

### 2. GPU Performance Testing
Validates optimal GPU utilization across 8 cores.

```bash
# GPU assignment validation
./scripts/core/validate_8core_performance.sh

# Extended GPU monitoring
./scripts/core/validate_8core_performance.sh --monitor
```

**What it tests:**
- Proper GPU core assignments
- Memory isolation between services
- Tensor parallelism effectiveness
- Performance under concurrent load

### 3. End-to-End Workflow Testing
Complete pipeline validation from ingestion to query response.

```bash
# Full workflow testing
./scripts/core/test_e2e_rag_workflow.sh

# Quick workflow validation
./scripts/core/test_e2e_rag_workflow.sh --quick
```

**What it tests:**
- Document processing pipeline
- Multi-modal content integration (OCR, audio)
- Query processing and response generation
- Hierarchical RAG functionality

### 4. Performance Benchmarking
Comprehensive performance measurement and stress testing.

```bash
# Standard benchmarking
./scripts/core/benchmark_h100_deployment.sh

# Extended stress testing
./scripts/core/benchmark_h100_deployment.sh --duration 600 --concurrent 20

# Quick performance check
./scripts/core/benchmark_h100_deployment.sh --quick
```

**What it tests:**
- Response time measurement
- Throughput analysis
- Concurrent load handling
- Memory usage patterns
- Error rate analysis

## Test Data

### Automatic Test Data Generation
```bash
# Generate complete test dataset
./scripts/core/generate_test_data.sh

# Clean and regenerate
./scripts/core/generate_test_data.sh --clean
```

### Test Data Categories

**Documents:**
- English AI overview documents
- Hebrew technical documentation
- Complex research papers
- Multi-section hierarchical content

**Audio Files:**
- Hebrew speech samples for Whisper
- English audio samples
- Various duration files for performance testing

**Images:**
- Text-heavy images for OCR testing
- Charts and diagrams
- Multi-language visual content

**Queries:**
- Basic factual questions
- Complex reasoning queries
- Hebrew language queries
- Multi-modal queries combining text/image/audio

## Testing Modes

### Development Testing
Quick validation during development:
```bash
./scripts/core/test_offline_complete.sh --quick
```

### Pre-Production Validation
Comprehensive testing before deployment:
```bash
# Full functionality test
./scripts/core/test_offline_complete.sh

# GPU performance validation
./scripts/core/validate_8core_performance.sh

# End-to-end workflows
./scripts/core/test_e2e_rag_workflow.sh
```

### Production Monitoring
Ongoing performance monitoring:
```bash
# Real-time dashboard
./scripts/core/monitor_h100_8core.sh

# Performance benchmarking
./scripts/core/benchmark_h100_deployment.sh --duration 300
```

### Stress Testing
High-load validation:
```bash
# Extended stress test
STRESS_TEST_DURATION=1800 CONCURRENT_USERS=25 ./scripts/core/benchmark_h100_deployment.sh

# Memory stress testing
./scripts/core/benchmark_h100_deployment.sh --duration 900 --concurrent 15
```

## Expected Results

### Performance Baselines (H100 8-Core)

| Metric | Good | Acceptable | Needs Improvement |
|--------|------|------------|-------------------|
| Query Response Time | < 2s | 2-5s | > 5s |
| Document Processing | < 30s | 30-60s | > 60s |
| Audio Transcription | < 10s | 10-20s | > 20s |
| Image OCR | < 15s | 15-30s | > 30s |
| Success Rate | > 95% | 90-95% | < 90% |
| Throughput | > 10 req/s | 5-10 req/s | < 5 req/s |

### GPU Utilization Expectations

| Service | GPU Cores | Expected Utilization | Memory Usage |
|---------|-----------|---------------------|--------------|
| DotsOCR | 0, 1 | 40-80% during processing | ~16GB |
| LLM | 2, 3, 4, 5 | 60-90% during queries | ~60GB |
| Embedding | 6 | 20-50% during embedding | ~8GB |
| Whisper | 7 | 30-70% during transcription | ~4GB |

## Interpreting Test Results

### HTML Reports
All testing scripts generate detailed HTML reports:
- **Summary**: Overall pass/fail status and metrics
- **Detailed Results**: Individual test outcomes
- **Performance Data**: Response times, throughput, error rates
- **Recommendations**: Specific improvement suggestions

### Log Files
Detailed execution logs for troubleshooting:
- **test_results_*.log**: Complete test execution details
- **performance_metrics_*.json**: Machine-readable performance data
- **gpu_utilization_*.csv**: Time-series GPU usage data

### Dashboard Monitoring
Real-time monitoring provides:
- Live GPU utilization across all cores
- Service health status
- Response time trends
- Memory usage patterns

## Troubleshooting Test Failures

### Common Issues and Solutions

**Service Not Responding:**
```bash
# Check service status
docker ps
docker logs <service-name>

# Restart specific service
docker restart <service-name>
```

**GPU Memory Issues:**
```bash
# Apply memory optimizations
./scripts/utilities/apply_all_overrides.sh

# Check GPU memory usage
./scripts/core/monitor_h100_8core.sh --once
```

**Performance Issues:**
```bash
# Check system resources
./scripts/core/monitor_h100_8core.sh

# Run performance analysis
./scripts/core/validate_8core_performance.sh
```

**Network Connectivity:**
```bash
# Validate Docker network
docker network ls
docker network inspect rag-network

# Test inter-service connectivity
docker exec rag-api ping rag-llm-server
```

### Test Customization

**Custom Test Data:**
Add your own test files to the appropriate directories:
- Documents: `test-data/documents/`
- Audio: `test-data/audio/`
- Images: `test-data/images/`
- Queries: `test-data/queries/`

**Custom Thresholds:**
Edit `test-data/test_config.yaml`:
```yaml
performance_thresholds:
  query_response_time_ms: 3000  # Custom threshold
  concurrent_success_rate: 85   # Lower requirement
```

**Custom Test Parameters:**
```bash
# Environment variables
export STRESS_TEST_DURATION=600
export CONCURRENT_USERS=15

# Command line options
./scripts/core/benchmark_h100_deployment.sh --duration 900 --concurrent 20
```

## Continuous Testing

### Automated Testing Scripts
Create automated testing schedules:
```bash
#!/bin/bash
# daily_validation.sh
./scripts/core/test_offline_complete.sh
./scripts/core/validate_8core_performance.sh --quick
./scripts/core/benchmark_h100_deployment.sh --quick
```

### Integration with CI/CD
Include testing in deployment pipelines:
```yaml
# Example pipeline step
- name: Validate RAG System
  run: |
    ./scripts/core/test_offline_complete.sh
    ./scripts/core/validate_8core_performance.sh
```

For complete testing coverage, run all test categories in sequence and review the generated reports for system optimization opportunities.
EOF

    print_status "✓ Documentation created"
}

# Create master execution script
create_master_script() {
    print_header "Creating master execution script..."
    
    cat > "$PACKAGE_DIR/run_complete_testing.sh" << 'EOF'
#!/bin/bash

set -e

echo "=========================================="
echo "RAG System Complete Testing Suite"
echo "Master Execution Script"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[TESTING]${NC} $1"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts/core"

# Test execution flags
RUN_HEALTH_CHECK=${RUN_HEALTH_CHECK:-true}
RUN_GPU_VALIDATION=${RUN_GPU_VALIDATION:-true}
RUN_E2E_TESTING=${RUN_E2E_TESTING:-true}
RUN_BENCHMARKING=${RUN_BENCHMARKING:-true}

# Test parameters
QUICK_MODE=${QUICK_MODE:-false}
STRESS_DURATION=${STRESS_DURATION:-300}
CONCURRENT_USERS=${CONCURRENT_USERS:-10}

# Results tracking
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

# Test execution wrapper
run_test_suite() {
    local suite_name="$1"
    local script_path="$2"
    local args="$3"
    
    print_header "Running Test Suite: $suite_name"
    ((TOTAL_SUITES++))
    
    if [[ ! -f "$script_path" ]]; then
        print_error "Script not found: $script_path"
        ((FAILED_SUITES++))
        return 1
    fi
    
    if chmod +x "$script_path" && eval "$script_path $args"; then
        print_status "✓ PASSED: $suite_name"
        ((PASSED_SUITES++))
        return 0
    else
        print_error "✗ FAILED: $suite_name"
        ((FAILED_SUITES++))
        return 1
    fi
}

# Main execution
main() {
    print_header "Starting Complete RAG System Testing"
    print_status "Test configuration:"
    print_status "• Health Check: $RUN_HEALTH_CHECK"
    print_status "• GPU Validation: $RUN_GPU_VALIDATION"  
    print_status "• E2E Testing: $RUN_E2E_TESTING"
    print_status "• Benchmarking: $RUN_BENCHMARKING"
    print_status "• Quick Mode: $QUICK_MODE"
    echo ""
    
    # Ensure test data exists
    print_header "Preparing Test Environment"
    if [[ ! -d "$SCRIPT_DIR/test-data/documents" ]]; then
        print_status "Generating test data..."
        "$SCRIPTS_DIR/generate_test_data.sh"
    fi
    
    # Test Suite 1: Health and Connectivity
    if [[ "$RUN_HEALTH_CHECK" == "true" ]]; then
        local health_args=""
        if [[ "$QUICK_MODE" == "true" ]]; then
            health_args="--quick"
        fi
        run_test_suite "Health and Connectivity Testing" "$SCRIPTS_DIR/test_offline_complete.sh" "$health_args"
        echo ""
    fi
    
    # Test Suite 2: GPU Performance Validation
    if [[ "$RUN_GPU_VALIDATION" == "true" ]]; then
        local gpu_args=""
        if [[ "$QUICK_MODE" == "true" ]]; then
            gpu_args="--quick"
        fi
        run_test_suite "GPU Performance Validation" "$SCRIPTS_DIR/validate_8core_performance.sh" "$gpu_args"
        echo ""
    fi
    
    # Test Suite 3: End-to-End Workflow Testing
    if [[ "$RUN_E2E_TESTING" == "true" ]]; then
        local e2e_args=""
        if [[ "$QUICK_MODE" == "true" ]]; then
            e2e_args="--quick"
        fi
        run_test_suite "End-to-End Workflow Testing" "$SCRIPTS_DIR/test_e2e_rag_workflow.sh" "$e2e_args"
        echo ""
    fi
    
    # Test Suite 4: Performance Benchmarking
    if [[ "$RUN_BENCHMARKING" == "true" ]]; then
        local bench_args="--duration $STRESS_DURATION --concurrent $CONCURRENT_USERS"
        if [[ "$QUICK_MODE" == "true" ]]; then
            bench_args="--quick"
        fi
        run_test_suite "Performance Benchmarking" "$SCRIPTS_DIR/benchmark_h100_deployment.sh" "$bench_args"
        echo ""
    fi
    
    # Final summary
    echo ""
    echo "=========================================="
    echo "Complete Testing Summary"
    echo "=========================================="
    print_status "Total Test Suites: $TOTAL_SUITES"
    print_status "Passed: $PASSED_SUITES"
    if [ $FAILED_SUITES -gt 0 ]; then
        print_error "Failed: $FAILED_SUITES"
    fi
    
    if [ $FAILED_SUITES -eq 0 ]; then
        echo -e "${GREEN}🎉 All test suites passed!${NC}"
        print_status "RAG system is fully validated and ready for production"
        exit 0
    else
        echo -e "${RED}❌ Some test suites failed${NC}"
        print_error "Review individual test reports and address issues"
        exit 1
    fi
}

# Handle command line arguments
if [[ "$1" == "--help" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo "Run complete RAG system testing suite"
    echo ""
    echo "Options:"
    echo "  --quick              Quick testing mode (reduced coverage)"
    echo "  --no-health         Skip health and connectivity tests"
    echo "  --no-gpu            Skip GPU performance validation"
    echo "  --no-e2e            Skip end-to-end workflow tests"
    echo "  --no-benchmark      Skip performance benchmarking"
    echo "  --duration <sec>    Stress test duration (default: 300)"
    echo "  --concurrent <num>  Concurrent users (default: 10)"
    echo "  --help              Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  QUICK_MODE          Enable quick mode (true/false)"
    echo "  STRESS_DURATION     Benchmarking duration in seconds"
    echo "  CONCURRENT_USERS    Number of concurrent test users"
    echo ""
    echo "Examples:"
    echo "  $0                           # Full testing suite"
    echo "  $0 --quick                   # Quick validation"
    echo "  $0 --duration 600 --concurrent 20  # Extended benchmarking"
    echo "  QUICK_MODE=true $0           # Quick mode via environment"
    exit 0
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --quick)
            QUICK_MODE=true
            shift
            ;;
        --no-health)
            RUN_HEALTH_CHECK=false
            shift
            ;;
        --no-gpu)
            RUN_GPU_VALIDATION=false
            shift
            ;;
        --no-e2e)
            RUN_E2E_TESTING=false
            shift
            ;;
        --no-benchmark)
            RUN_BENCHMARKING=false
            shift
            ;;
        --duration)
            STRESS_DURATION="$2"
            shift 2
            ;;
        --concurrent)
            CONCURRENT_USERS="$2"
            shift 2
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute main testing
main "$@"
EOF

    chmod +x "$PACKAGE_DIR/run_complete_testing.sh"
    print_status "✓ Master execution script created"
}

# Create package manifest
create_manifest() {
    print_header "Creating package manifest..."
    
    cat > "$PACKAGE_DIR/MANIFEST.json" << EOF
{
  "package_name": "$PACKAGE_NAME",
  "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "version": "1.0.0",
  "description": "Comprehensive offline testing framework for H100 8-Core RAG system",
  "components": {
    "core_testing_scripts": [
      "generate_test_data.sh",
      "test_offline_complete.sh", 
      "validate_8core_performance.sh",
      "test_e2e_rag_workflow.sh",
      "benchmark_h100_deployment.sh"
    ],
    "deployment_scripts": [
      "deploy_h100_8core_optimized.sh",
      "monitor_h100_8core.sh",
      "validate_h100_deployment.sh"
    ],
    "test_data_categories": [
      "documents",
      "audio", 
      "images",
      "queries",
      "expected_responses"
    ],
    "configuration_files": [
      "docker-compose-8core.yml",
      "test_config_template.yaml",
      "hirag_config.yaml",
      "dockerfiles"
    ],
    "documentation": [
      "README.md",
      "INSTALLATION.md",
      "TESTING_GUIDE.md"
    ]
  },
  "system_requirements": {
    "hardware": {
      "gpu": "NVIDIA H100 8-core (80GB VRAM)",
      "ram": "64GB minimum",
      "storage": "500GB+ available"
    },
    "software": {
      "docker": "20.10+",
      "nvidia_driver": "535+",
      "nvidia_container_runtime": "required"
    }
  },
  "testing_capabilities": [
    "Service health validation",
    "GPU performance testing",
    "Multi-modal processing validation",
    "End-to-end workflow testing",
    "Stress testing and benchmarking",
    "Real-time monitoring",
    "Comprehensive reporting"
  ],
  "offline_features": [
    "No internet connectivity required",
    "All models pre-downloaded",
    "Self-contained test data",
    "Complete validation framework"
  ],
  "statistics": {
    "total_files": $(find "$PACKAGE_DIR" -type f | wc -l),
    "total_scripts": $(find "$PACKAGE_DIR/scripts" -name "*.sh" | wc -l),
    "total_size_mb": "$(du -sm "$PACKAGE_DIR" | cut -f1)"
  }
}
EOF

    print_status "✓ Package manifest created"
}

# Create archive
create_archive() {
    print_header "Creating compressed archive..."
    
    # Remove existing archive
    rm -f "$ARCHIVE_NAME" 2>/dev/null || true
    
    # Create tar.gz archive
    print_step "Compressing package..."
    if tar -czf "$ARCHIVE_NAME" "$PACKAGE_NAME"/; then
        local archive_size=$(du -sh "$ARCHIVE_NAME" | cut -f1)
        print_status "✓ Archive created: $ARCHIVE_NAME ($archive_size)"
    else
        print_error "Failed to create archive"
        return 1
    fi
    
    # Generate checksums
    print_step "Generating checksums..."
    sha256sum "$ARCHIVE_NAME" > "${ARCHIVE_NAME}.sha256"
    md5sum "$ARCHIVE_NAME" > "${ARCHIVE_NAME}.md5"
    
    print_status "✓ Checksums generated"
}

# Upload to GCP (optional)
upload_to_gcp() {
    if [[ "$UPLOAD_TO_GCP" == "true" ]] && [[ -n "$GCP_BUCKET" ]]; then
        print_header "Uploading to GCP Storage..."
        
        if command -v gsutil > /dev/null 2>&1; then
            print_step "Uploading $ARCHIVE_NAME to gs://$GCP_BUCKET/"
            
            if gsutil cp "$ARCHIVE_NAME" "gs://$GCP_BUCKET/"; then
                print_status "✓ Archive uploaded to GCP"
                
                # Upload checksums
                gsutil cp "${ARCHIVE_NAME}.sha256" "gs://$GCP_BUCKET/"
                gsutil cp "${ARCHIVE_NAME}.md5" "gs://$GCP_BUCKET/"
                print_status "✓ Checksums uploaded to GCP"
                
                # Generate public URL
                print_status "Archive available at: gs://$GCP_BUCKET/$ARCHIVE_NAME"
            else
                print_warning "Failed to upload to GCP"
            fi
        else
            print_warning "gsutil not available - skipping GCP upload"
        fi
    else
        print_status "GCP upload not configured"
    fi
}

# Generate final summary
generate_summary() {
    print_header "Package Creation Summary"
    
    local package_size=$(du -sh "$PACKAGE_DIR" | cut -f1)
    local archive_size=$(du -sh "$ARCHIVE_NAME" 2>/dev/null | cut -f1 || echo "N/A")
    local file_count=$(find "$PACKAGE_DIR" -type f | wc -l)
    local script_count=$(find "$PACKAGE_DIR/scripts" -name "*.sh" 2>/dev/null | wc -l)
    
    echo ""
    print_status "Package Details:"
    print_status "• Name: $PACKAGE_NAME"
    print_status "• Directory size: $package_size"
    print_status "• Archive size: $archive_size"
    print_status "• Total files: $file_count"
    print_status "• Executable scripts: $script_count"
    
    echo ""
    print_status "Package Contents:"
    print_status "• Core testing scripts: 5"
    print_status "• Deployment scripts: 3"
    print_status "• Monitoring tools: 2"
    print_status "• Configuration templates: 4"
    print_status "• Documentation files: 3"
    
    echo ""
    print_status "Quick Start:"
    print_status "1. Extract: tar -xzf $ARCHIVE_NAME"
    print_status "2. Deploy: cd $PACKAGE_NAME && ./scripts/core/deploy_h100_8core_optimized.sh"
    print_status "3. Test: ./run_complete_testing.sh"
    
    if [[ -f "${ARCHIVE_NAME}.sha256" ]]; then
        echo ""
        print_status "Verification:"
        print_status "SHA256: $(cat "${ARCHIVE_NAME}.sha256" | cut -d' ' -f1)"
    fi
}

# Main execution
main() {
    print_header "Starting RAG System Offline Testing Package Creation"
    
    create_package_structure
    copy_testing_scripts
    prepare_test_data
    copy_configuration_files
    create_documentation
    create_master_script
    create_manifest
    create_archive
    upload_to_gcp
    generate_summary
    
    echo ""
    echo "=========================================="
    echo "Package Creation Complete!"
    echo "=========================================="
    
    print_status "✓ Offline testing package ready: $ARCHIVE_NAME"
    print_status "✓ Complete testing framework bundled"
    print_status "✓ No internet connectivity required for testing"
    
    if [[ "$UPLOAD_TO_GCP" == "true" ]] && [[ -n "$GCP_BUCKET" ]]; then
        print_status "✓ Package uploaded to GCP Storage"
    fi
}

# Handle command line arguments
if [[ "$1" == "--help" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo "Create comprehensive offline testing package for RAG system"
    echo ""
    echo "Options:"
    echo "  --gcp-bucket <bucket>   Upload to GCP Storage bucket"
    echo "  --upload                Enable GCP upload"
    echo "  --name <name>           Custom package name"
    echo "  --help                  Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  GCP_BUCKET              GCP Storage bucket name"
    echo "  UPLOAD_TO_GCP           Enable GCP upload (true/false)"
    echo ""
    echo "This script creates a complete testing package including:"
    echo "  • All testing and deployment scripts"
    echo "  • Comprehensive test data"
    echo "  • Configuration templates"
    echo "  • Documentation and guides"
    echo "  • Master execution script"
    exit 0
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --gcp-bucket)
            GCP_BUCKET="$2"
            UPLOAD_TO_GCP=true
            shift 2
            ;;
        --upload)
            UPLOAD_TO_GCP=true
            shift
            ;;
        --name)
            PACKAGE_NAME="$2"
            PACKAGE_DIR="./${PACKAGE_NAME}"
            ARCHIVE_NAME="${PACKAGE_NAME}.tar.gz"
            shift 2
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute main packaging
main "$@"