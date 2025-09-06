#!/bin/bash

set -e

echo "=========================================="
echo "Runtime Override Generator"
echo "Apply fixes without rebuilding Docker images"
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
    echo -e "${BLUE}[OVERRIDE]${NC} $1"
}

print_status "Creating runtime override scripts..."
echo ""

# 1. Create DotsOCR Memory Override
print_header "1. Creating DotsOCR Memory Override"
cat > deploy/override_dots_ocr_memory.sh << 'EOF'
#!/bin/bash
echo "🔧 Applying DotsOCR Memory Override..."

# Stop existing DotsOCR if running
docker stop rag-dots-ocr 2>/dev/null || true
docker rm rag-dots-ocr 2>/dev/null || true

# Start DotsOCR with memory override
docker run -d \
    --name rag-dots-ocr \
    --network rag-network \
    --gpus all \
    --shm-size=8g \
    --restart unless-stopped \
    -p 8002:8000 \
    -e CUDA_VISIBLE_DEVICES=0 \
    --entrypoint /bin/bash \
    rag-dots-ocr:latest \
    -c "
        echo '--- DotsOCR Memory Override Active ---'
        echo 'Original GPU utilization: 0.95 → Override: 0.4'
        sed -i 's/from vllm\.entrypoints\.cli\.main import main/from vllm.entrypoints.cli.main import main\nfrom DotsOCR import modeling_dots_ocr_vllm/' \$(which vllm)
        exec vllm serve /workspace/weights/DotsOCR \
            --tensor-parallel-size 1 \
            --gpu-memory-utilization 0.4 \
            --max-model-len 8192 \
            --chat-template-content-format string \
            --served-model-name model \
            --trust-remote-code \
            --host 0.0.0.0 \
            --port 8000
    "

echo "✓ DotsOCR restarted with 40% GPU memory utilization"
EOF

chmod +x deploy/override_dots_ocr_memory.sh
print_status "✓ Created: deploy/override_dots_ocr_memory.sh"

# 2. Create Whisper FastAPI Override
print_header "2. Creating Whisper FastAPI Override"
cat > deploy/override_whisper_fastapi.sh << 'EOF'
#!/bin/bash
echo "🔧 Applying Whisper FastAPI Override..."

# Create fixed whisper service with lifespan
cat > /tmp/whisper_service_fixed.py << 'PYTHON_EOF'
import os
import tempfile
import logging
import torch
from pathlib import Path
from contextlib import asynccontextmanager
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse
from transformers import AutoProcessor, AutoModelForSpeechSeq2Seq
import librosa
import uvicorn

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global model variables
model = None
processor = None
MODEL_NAME = os.environ.get('MODEL_NAME', 'ivrit-ai/whisper-large-v3')

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global model, processor
    logger.info(f"Loading Whisper model: {MODEL_NAME}")
    try:
        device = "cuda" if torch.cuda.is_available() else "cpu"
        processor = AutoProcessor.from_pretrained(MODEL_NAME)
        model = AutoModelForSpeechSeq2Seq.from_pretrained(
            MODEL_NAME,
            torch_dtype=torch.float16 if device == "cuda" else torch.float32,
            low_cpu_mem_usage=True,
            use_safetensors=True,
            device_map="auto" if device == "cuda" else None
        )
        if device == "cuda" and not hasattr(model, 'hf_device_map'):
            model = model.to(device)
        logger.info(f"Whisper model loaded successfully on {device}")
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        raise e
    yield
    logger.info("Shutting down Whisper service")

app = FastAPI(title="Whisper Transcription Service", version="1.0.0", lifespan=lifespan)

@app.get("/health")
async def health_check():
    return {
        "status": "healthy" if model is not None and processor is not None else "unhealthy",
        "service": "whisper-transcription",
        "model": MODEL_NAME,
        "version": "1.0.0-fixed"
    }

@app.post("/transcribe")
async def transcribe_audio(file: UploadFile = File(...)):
    if model is None or processor is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=Path(file.filename).suffix) as tmp_file:
            content = await file.read()
            tmp_file.write(content)
            tmp_file_path = tmp_file.name
        
        try:
            audio_array, sampling_rate = librosa.load(tmp_file_path, sr=16000)
            inputs = processor(audio_array, sampling_rate=16000, return_tensors="pt")
            device = next(model.parameters()).device
            inputs = {k: v.to(device) for k, v in inputs.items()}
            
            with torch.no_grad():
                forced_decoder_ids = processor.get_decoder_prompt_ids(language="hebrew", task="transcribe")
                predicted_ids = model.generate(**inputs, forced_decoder_ids=forced_decoder_ids, max_new_tokens=448)
            
            transcription = processor.batch_decode(predicted_ids, skip_special_tokens=True)
            transcribed_text = transcription[0] if transcription else ""
            duration = len(audio_array) / sampling_rate
            
            return JSONResponse(content={
                "success": True,
                "text": transcribed_text.strip(),
                "language": "he",
                "duration": duration,
                "fixed_version": True
            })
        finally:
            os.unlink(tmp_file_path)
    except Exception as e:
        logger.error(f"Transcription failed: {e}")
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8004)
PYTHON_EOF

# Stop existing whisper if running
docker stop rag-whisper 2>/dev/null || true
docker rm rag-whisper 2>/dev/null || true

# Copy fixed service into container and restart
docker run -d \
    --name rag-whisper \
    --network rag-network \
    --gpus all \
    --restart unless-stopped \
    -p 8004:8004 \
    -e CUDA_VISIBLE_DEVICES=0 \
    -e MODEL_NAME=ivrit-ai/whisper-large-v3 \
    -v /tmp/whisper_service_fixed.py:/app/whisper_service.py \
    --entrypoint python3 \
    rag-whisper:latest \
    /app/whisper_service.py

echo "✓ Whisper restarted with fixed FastAPI lifespan"
rm /tmp/whisper_service_fixed.py
EOF

chmod +x deploy/override_whisper_fastapi.sh
print_status "✓ Created: deploy/override_whisper_fastapi.sh"

# 3. Create GPT-OSS Offline Override
print_header "3. Creating GPT-OSS Offline Override"
cat > deploy/override_gptoss_offline.sh << 'EOF'
#!/bin/bash
echo "🔧 Applying GPT-OSS Offline Override..."

# Stop existing LLM if running
docker stop rag-llm-server 2>/dev/null || true
docker rm rag-llm-server 2>/dev/null || true

# Start GPT-OSS with offline environment variables
docker run -d \
    --name rag-llm-server \
    --network rag-network \
    --gpus all \
    --shm-size=16g \
    --restart unless-stopped \
    -p 8003:8000 \
    -e CUDA_VISIBLE_DEVICES=0 \
    -e HF_HUB_OFFLINE=1 \
    -e TRANSFORMERS_OFFLINE=1 \
    -e HF_DATASETS_OFFLINE=1 \
    -e TENSOR_PARALLEL=1 \
    -e GPU_MEMORY=0.5 \
    rag-llm-gptoss:latest

echo "✓ GPT-OSS restarted with offline environment variables"
EOF

chmod +x deploy/override_gptoss_offline.sh
print_status "✓ Created: deploy/override_gptoss_offline.sh"

# 4. Create TGI Embedding Override
print_header "4. Creating TGI Embedding Override"
cat > deploy/override_embedding_tgi.sh << 'EOF'
#!/bin/bash
echo "🔧 Applying TGI Embedding Override..."

# Stop existing embedding if running
docker stop rag-embedding-server 2>/dev/null || true
docker rm rag-embedding-server 2>/dev/null || true

# Start with TGI proper syntax
docker run -d \
    --name rag-embedding-server \
    --network rag-network \
    --gpus all \
    --restart unless-stopped \
    -p 8001:8000 \
    -e MODEL_ID=Qwen/Qwen2-0.5B-Instruct \
    --entrypoint text-generation-launcher \
    ghcr.io/huggingface/text-generation-inference:latest \
    --model-id Qwen/Qwen2-0.5B-Instruct \
    --hostname 0.0.0.0 \
    --port 8000

echo "✓ Embedding restarted with proper TGI syntax"
EOF

chmod +x deploy/override_embedding_tgi.sh
print_status "✓ Created: deploy/override_embedding_tgi.sh"

# 5. Create Master Override Script
print_header "5. Creating Master Override Script"
cat > deploy/apply_all_overrides.sh << 'EOF'
#!/bin/bash

echo "=========================================="
echo "Applying All Runtime Overrides"
echo "=========================================="

set -e

echo "🔧 Applying runtime fixes to existing Docker images..."
echo ""

# Apply overrides in dependency order
echo "1. Applying TGI Embedding override..."
./deploy/override_embedding_tgi.sh
echo ""

echo "2. Applying Whisper FastAPI override..."
./deploy/override_whisper_fastapi.sh
echo ""

echo "3. Applying DotsOCR memory override..."
./deploy/override_dots_ocr_memory.sh  
echo ""

echo "4. Applying GPT-OSS offline override..."
./deploy/override_gptoss_offline.sh
echo ""

echo "=========================================="
echo "🎉 All Runtime Overrides Applied!"
echo "=========================================="
echo ""
echo "✅ Fixed Issues:"
echo "• TGI Embedding: Proper command syntax"
echo "• Whisper: FastAPI lifespan + accelerate compatibility"  
echo "• DotsOCR: GPU memory reduced to 40%"
echo "• GPT-OSS: Offline environment variables"
echo ""
echo "🔍 Validate deployment:"
echo "./deploy/validate_h100_deployment.sh"
EOF

chmod +x deploy/apply_all_overrides.sh
print_status "✓ Created: deploy/apply_all_overrides.sh"

# 6. Create Rollback Script
print_header "6. Creating Rollback Script"
cat > deploy/rollback_overrides.sh << 'EOF'
#!/bin/bash

echo "🔄 Rolling back runtime overrides..."

# Stop all override containers
docker stop rag-embedding-server rag-whisper rag-dots-ocr rag-llm-server 2>/dev/null || true
docker rm rag-embedding-server rag-whisper rag-dots-ocr rag-llm-server 2>/dev/null || true

echo "✓ Override containers removed. You can now use original images or rebuild."
echo ""
echo "Options:"
echo "• Use original deployment: ./deploy/deploy_complete.sh"
echo "• Use selective rebuild: ./deploy/rebuild_modified_services.sh"
EOF

chmod +x deploy/rollback_overrides.sh
print_status "✓ Created: deploy/rollback_overrides.sh"

echo ""
echo "=========================================="
echo "🎉 Runtime Override Scripts Created!"
echo "=========================================="
echo ""
print_status "Available override options:"
echo ""
echo "🚀 Quick Fix (No Rebuild Required):"
echo "   ./deploy/apply_all_overrides.sh"
echo ""
echo "🔧 Individual Overrides:"
echo "   ./deploy/override_embedding_tgi.sh"
echo "   ./deploy/override_whisper_fastapi.sh"
echo "   ./deploy/override_dots_ocr_memory.sh"
echo "   ./deploy/override_gptoss_offline.sh"
echo ""
echo "🔄 Rollback:"
echo "   ./deploy/rollback_overrides.sh"
echo ""
echo "🔍 Validation:"
echo "   ./deploy/validate_h100_deployment.sh"
echo ""
print_warning "Note: Runtime overrides are temporary. For permanent fixes, use:"
print_warning "./deploy/rebuild_modified_services.sh"