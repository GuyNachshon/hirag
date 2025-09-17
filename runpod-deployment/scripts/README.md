# Scripts Directory

This directory contains all deployment, build, and testing scripts for the RAG system.

## 📁 Directory Structure

### 🔨 Build Scripts (`build/`)
- **`build_official_images.sh`** - Build Docker images using official repositories (Recommended)
- **`build_ivrit_whisper_offline.sh`** - Build offline Ivrit-AI Whisper image

### 🚀 Deployment Scripts (`deployment/`)
- **`deploy_h100_manual.sh`** - Manual deployment for H100 clusters (No docker-compose)
- **`deploy_h100_optimized.sh`** - H100-optimized deployment with performance tuning
- **`deploy_runpod_cluster.sh`** - Original RunPod cluster deployment
- **`start_services_sequential.sh`** - Sequential service startup with dependency management

### 🧪 Testing Scripts (`testing/`)
- **`test_official_images.sh`** - Test individual official-based services
- **`test_rag_integration.sh`** - End-to-end RAG system integration test
- **`test_all_services.sh`** - Comprehensive service testing

### 🛠 Utilities (`utilities/`)
- **`create_offline_package_runpod.sh`** - Create offline deployment package
- **`simulate_offline_mode.sh`** - Simulate offline environment for testing

## 🚀 Quick Start Commands

### For RunPod Deployment:
```bash
# 1. Build images with official repositories
./build/build_official_images.sh

# 2. Deploy all services
./deployment/deploy_h100_manual.sh

# 3. Test deployment
./testing/test_rag_integration.sh
```

### For H100 Cluster:
```bash
# 1. Build and package on RunPod
./build/build_official_images.sh
./utilities/create_offline_package_runpod.sh

# 2. Transfer package to H100 cluster

# 3. Deploy on H100
./deployment/deploy_h100_optimized.sh
```

### For Testing:
```bash
# Test individual services
./testing/test_official_images.sh

# Test full system integration
./testing/test_rag_integration.sh

# Test all services comprehensively
./testing/test_all_services.sh
```

## 📋 Script Categories

### 🎯 **Recommended Workflow**
1. **Build**: `./build/build_official_images.sh`
2. **Deploy**: `./deployment/deploy_h100_manual.sh`
3. **Test**: `./testing/test_rag_integration.sh`

### 🔧 **Advanced Options**
- **Performance Tuning**: Use `deploy_h100_optimized.sh`
- **Sequential Deploy**: Use `start_services_sequential.sh`
- **Offline Package**: Use `create_offline_package_runpod.sh`

### 🚨 **Troubleshooting**
- **Service Issues**: Check individual service logs
- **Integration Problems**: Run `test_rag_integration.sh`
- **Offline Mode**: Use `simulate_offline_mode.sh`

## 📝 Usage Notes

- All scripts are executable and include `--help` options
- Scripts assume they're run from the project root
- Most scripts include colored output and progress indicators
- Error handling and cleanup functions are included
- All scripts support offline/airgapped environments