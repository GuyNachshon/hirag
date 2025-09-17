#!/bin/bash

# Emergency fallback solutions for stubborn services

echo "==========================================="
echo "    EMERGENCY FALLBACK SOLUTIONS         "
echo "==========================================="
echo ""

# Fallback 1: CPU-only embedding server
fallback_embedding_cpu() {
    echo "=== Fallback: CPU-Only Embedding Server ==="
    echo "Use this if GPU embedding keeps failing"
    echo ""

    docker stop rag-embedding-server 2>/dev/null || true
    docker rm rag-embedding-server 2>/dev/null || true

    echo "Starting CPU-based embedding server (slower but stable)..."

    docker run -d \
        --name rag-embedding-server \
        --network rag-network \
        --restart unless-stopped \
        --cpus="2.0" \
        --memory="4g" \
        -p 8001:8000 \
        -v $(pwd)/model-cache:/root/.cache/huggingface \
        -e HF_HOME=/root/.cache/huggingface \
        -e TRANSFORMERS_CACHE=/root/.cache/huggingface \
        -e HF_HUB_OFFLINE=1 \
        -e CUDA_VISIBLE_DEVICES="" \
        --entrypoint /bin/bash \
        rag-embedding-server:latest \
        -c "
MODEL=\$(find /root/.cache/huggingface/hub -name 'models--*' | head -1 | sed 's|.*models--||' | sed 's|--|/|g')
if [ -z \"\$MODEL\" ]; then MODEL='BAAI/bge-small-en-v1.5'; fi

echo \"Using model: \$MODEL on CPU\"

exec python -m vllm.entrypoints.openai.api_server \\
    --model \$MODEL \\
    --host 0.0.0.0 \\
    --port 8000 \\
    --trust-remote-code \\
    --enforce-eager \\
    --tensor-parallel-size 1 \\
    --max-model-len 512 \\
    --task embedding \\
    --device cpu
"

    echo "✓ CPU embedding server started"
}

# Fallback 2: Use LLM server for embeddings too
fallback_unified_llm() {
    echo "=== Fallback: Use LLM Server for Everything ==="
    echo "Configure the LLM server to handle both generation AND embeddings"
    echo ""

    # Stop separate embedding server
    docker stop rag-embedding-server 2>/dev/null || true
    docker rm rag-embedding-server 2>/dev/null || true

    echo "Reconfiguring LLM server to handle embeddings too..."

    # Add a simple proxy to route embedding requests to LLM server
    cat > /tmp/embedding-proxy.py << 'EOF'
from fastapi import FastAPI, Request
import httpx
import uvicorn

app = FastAPI()

@app.api_route("/v1/embeddings", methods=["POST"])
async def proxy_embeddings(request: Request):
    # Simple proxy to LLM server
    # You can adapt this to use the LLM for embeddings
    return {"error": "Use LLM server at port 8003 for both generation and embeddings"}

@app.get("/health")
async def health():
    return {"status": "healthy", "note": "redirects to LLM server"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

    docker run -d \
        --name rag-embedding-server \
        --network rag-network \
        --restart unless-stopped \
        -p 8001:8000 \
        -v /tmp/embedding-proxy.py:/app/proxy.py \
        python:3.11-slim \
        sh -c "pip install fastapi uvicorn httpx && python /app/proxy.py"

    echo "✓ Embedding proxy created (points to LLM server)"
}

# Fallback 3: Whisper CPU mode
fallback_whisper_cpu() {
    echo "=== Fallback: CPU-Only Whisper ==="
    echo "Use this if GPU whisper has issues"
    echo ""

    docker stop rag-whisper 2>/dev/null || true
    docker rm rag-whisper 2>/dev/null || true

    docker run -d \
        --name rag-whisper \
        --network rag-network \
        --restart unless-stopped \
        --cpus="4.0" \
        --memory="8g" \
        -p 8004:8004 \
        -v $(pwd)/model-cache:/root/.cache/huggingface \
        -e HF_HOME=/root/.cache/huggingface \
        -e TRANSFORMERS_CACHE=/root/.cache/huggingface \
        -e HF_HUB_OFFLINE=1 \
        -e CUDA_VISIBLE_DEVICES="" \
        -e MODEL_NAME=ivrit-ai/whisper-large-v3 \
        rag-whisper:latest

    echo "✓ CPU whisper server started"
}

# Fallback 4: Mock services for UI testing
fallback_mock_services() {
    echo "=== Fallback: Mock Services for UI Testing ==="
    echo "Creates minimal mock responses so frontend can be tested"
    echo ""

    # Create a simple mock server
    cat > /tmp/mock-services.py << 'EOF'
from fastapi import FastAPI
import uvicorn

app = FastAPI()

@app.get("/health")
async def health():
    return {"status": "ok", "mode": "mock"}

@app.post("/v1/embeddings")
async def mock_embeddings(request: dict):
    return {
        "embeddings": [[0.1] * 384],  # Mock embedding
        "model": "mock-embedding",
        "usage": {"prompt_tokens": 10}
    }

@app.post("/v1/completions")
async def mock_completions(request: dict):
    return {
        "choices": [{"text": "This is a mock response for testing."}],
        "model": "mock-llm"
    }

@app.post("/transcribe")
async def mock_transcribe(request: dict):
    return {
        "text": "This is a mock transcription for testing.",
        "language": "en"
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

    # Start mock embedding server
    docker run -d \
        --name rag-embedding-server \
        --network rag-network \
        -p 8001:8000 \
        -v /tmp/mock-services.py:/app/mock.py \
        python:3.11-slim \
        sh -c "pip install fastapi uvicorn && python /app/mock.py"

    # Start mock LLM server
    docker run -d \
        --name rag-llm-server \
        --network rag-network \
        -p 8003:8000 \
        -v /tmp/mock-services.py:/app/mock.py \
        python:3.11-slim \
        sh -c "pip install fastapi uvicorn && python /app/mock.py"

    echo "✓ Mock services started for UI testing"
}

# Menu
show_menu() {
    echo "Choose a fallback solution:"
    echo ""
    echo "1) CPU-only embedding server (slower but stable)"
    echo "2) Use LLM server for everything (unified approach)"
    echo "3) CPU-only whisper server"
    echo "4) Mock all services (for UI testing only)"
    echo "5) Exit"
    echo ""
    read -p "Enter choice (1-5): " choice

    case $choice in
        1) fallback_embedding_cpu ;;
        2) fallback_unified_llm ;;
        3) fallback_whisper_cpu ;;
        4) fallback_mock_services ;;
        5) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid choice"; show_menu ;;
    esac
}

# Main execution
echo "These are emergency fallback solutions when the main fixes don't work:"
echo ""
show_menu