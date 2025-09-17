# RAG Scripts Collection

Complete collection of all diagnostic and fix scripts for the RAG system.

## Core Fix Scripts
- `fix_all_services.sh` - Master script to fix all common issues
- `unified_llm_embedding.sh` - Create dedicated embedding server using LLM image
- `emergency_fallbacks.sh` - Last resort fixes when others fail

## Embedding Service Fixes
- `fix_embedding_with_existing_vllm.sh` - Use existing vLLM container for embeddings
- `fix_embedding_simple.sh` - Simple embedding server fix
- `fix_embedding_offline.sh` - Offline embedding configuration
- `fallback_cpu_embeddings.sh` - CPU-only embedding fallback

## Frontend and Model Fixes
- `fix_frontend_nginx.sh` - Fix nginx configuration issues
- `fix_model_paths.sh` - Fix model path and cache issues
- `fix_llm_cache.sh` - Fix LLM cache mounting (prevents downloading)
- `fix_whisper_gpu.sh` - Fix Whisper to use GPU instead of CPU
- `quick_frontend_fix.sh` - Quick frontend fixes

## Diagnostic Tools
- `diagnose_frontend.sh` - Frontend troubleshooting
- `diagnose_gpu_issues.sh` - GPU access diagnostics
- `mount_model_cache.sh` - Model cache setup

## Deployment Scripts
- `deploy_a100_single_gpu.sh` - A100 deployment script
- `build_all_offline.sh` - Build all images offline
- `build_essential_offline.sh` - Build essential images
- `build_smart_offline.sh` - Smart build script

## Testing and Validation
- `validate_a100_deployment.sh` - A100 deployment testing
- `validate_h100_deployment.sh` - H100 cluster validation
- `test_e2e_rag_workflow.sh` - End-to-end testing
- `test_offline_complete.sh` - Complete offline testing

## Monitoring
- `monitor_a100_single_gpu.sh` - A100 monitoring
- `monitor_h100_8core.sh` - H100 monitoring

## Usage Priority

1. **Start here**: `fix_all_services.sh` - Fixes most common issues
2. **If embedding issues**: `unified_llm_embedding.sh` - Creates dedicated embedding server
3. **If cache issues**: `fix_llm_cache.sh` - Fixes model downloading problems
4. **If Whisper on CPU**: `fix_whisper_gpu.sh` - Forces GPU usage
5. **Last resort**: `emergency_fallbacks.sh` - Emergency solutions

## Quick Health Check
```bash
curl http://localhost:8087/frontend-health
curl http://localhost:8080/health
curl http://localhost:8001/health
curl http://localhost:8003/health
curl http://localhost:8004/health
```