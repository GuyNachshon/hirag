#!/bin/bash

# Master script to fix all RAG services offline

set -e

echo "=========================================="
echo "    RAG SERVICES OFFLINE FIX MASTER     "
echo "=========================================="
echo ""

# Function to print colored output
print_status() {
    echo -e "\033[32m✓ $1\033[0m"
}

print_error() {
    echo -e "\033[31m✗ $1\033[0m"
}

print_warning() {
    echo -e "\033[33m⚠ $1\033[0m"
}

print_header() {
    echo ""
    echo "=== $1 ==="
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    if ! docker --version > /dev/null 2>&1; then
        print_error "Docker not installed or not running"
        exit 1
    fi

    if ! docker network ls | grep -q rag-network; then
        print_warning "rag-network not found, creating it..."
        docker network create rag-network
    fi

    if [ ! -d "model-cache" ]; then
        print_warning "model-cache directory not found, creating it..."
        mkdir -p model-cache
    fi

    print_status "Prerequisites checked"
}

# Fix Frontend (nginx MIME types for Edge browser)
fix_frontend() {
    print_header "Fixing Frontend (Edge MIME Types)"

    # Create proper nginx config
    cat > /tmp/nginx-frontend.conf << 'EOF'
server {
    listen 8087;
    server_name localhost;

    root /usr/share/nginx/html;
    index index.html;

    # CRITICAL: JS/CSS handlers BEFORE catch-all with 'always' flag
    location ~* \.(js|mjs)$ {
        add_header Content-Type application/javascript always;
        add_header Cache-Control "public, max-age=31536000, immutable";
        try_files $uri =404;
    }

    location ~* \.css$ {
        add_header Content-Type text/css always;
        add_header Cache-Control "public, max-age=31536000, immutable";
        try_files $uri =404;
    }

    # SPA routing AFTER specific handlers
    location / {
        try_files $uri $uri/ /index.html;
    }

    # API proxy
    location /api/ {
        proxy_pass http://rag-api:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;

        if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /health {
        proxy_pass http://rag-api:8080/health;
        proxy_set_header Host $host;
        access_log off;
    }

    location /frontend-health {
        access_log off;
        add_header Content-Type text/plain;
        return 200 "frontend healthy\n";
    }

    error_page 404 /index.html;
}
EOF

    # Apply to running container
    if docker ps | grep -q rag-frontend; then
        docker cp /tmp/nginx-frontend.conf rag-frontend:/etc/nginx/conf.d/default.conf
        docker exec rag-frontend nginx -s reload
        print_status "Frontend nginx config updated"
    else
        print_warning "Frontend container not running"
    fi

    rm /tmp/nginx-frontend.conf
}

# Fix Embedding Service (Triton/CUDA errors)
fix_embedding() {
    print_header "Fixing Embedding Service (Triton/CUDA Issues)"

    print_warning "Stopping current embedding server..."
    docker stop rag-embedding-server 2>/dev/null || true
    docker rm rag-embedding-server 2>/dev/null || true

    print_status "Starting embedding server with Triton disabled..."

    docker run -d \
        --name rag-embedding-server \
        --network rag-network \
        --gpus all \
        --restart unless-stopped \
        -p 8001:8000 \
        -v $(pwd)/model-cache:/root/.cache/huggingface \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e HF_HOME=/root/.cache/huggingface \
        -e TRANSFORMERS_CACHE=/root/.cache/huggingface \
        -e HF_HUB_OFFLINE=1 \
        -e VLLM_USE_TRITON=0 \
        -e DISABLE_CUSTOM_ALL_REDUCE=1 \
        --entrypoint /bin/bash \
        rag-embedding-server:latest \
        -c "
export VLLM_USE_TRITON=0
export DISABLE_CUSTOM_ALL_REDUCE=1

# Find available embedding model
if [ -d '/root/.cache/huggingface/hub/models--BAAI--bge-small-en-v1.5' ]; then
    MODEL='BAAI/bge-small-en-v1.5'
elif [ -d '/root/.cache/huggingface/hub/models--Qwen--Qwen2-0.5B-Instruct' ]; then
    MODEL='Qwen/Qwen2-0.5B-Instruct'
else
    MODEL='BAAI/bge-small-en-v1.5'
fi

echo \"Using embedding model: \$MODEL\"

exec python -m vllm.entrypoints.openai.api_server \\
    --model \$MODEL \\
    --host 0.0.0.0 \\
    --port 8000 \\
    --trust-remote-code \\
    --enforce-eager \\
    --disable-custom-all-reduce \\
    --gpu-memory-utilization 0.1 \\
    --max-model-len 512 \\
    --tensor-parallel-size 1 \\
    --task embedding
"

    print_status "Embedding server restarted"
}

# Fix LLM Service (cache and FlashAttention issues)
fix_llm() {
    print_header "Fixing LLM Service (Cache & FlashAttention)"

    print_warning "Stopping current LLM server..."
    docker stop rag-llm-server 2>/dev/null || true
    docker rm rag-llm-server 2>/dev/null || true

    print_status "Starting LLM server with proper cache mounting..."

    docker run -d \
        --name rag-llm-server \
        --network rag-network \
        --gpus all \
        --shm-size=16g \
        --restart unless-stopped \
        -p 8003:8000 \
        -v $(pwd)/model-cache:/root/.cache/huggingface \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e TENSOR_PARALLEL_SIZE=1 \
        -e GPU_MEMORY_UTILIZATION=0.35 \
        -e HF_HOME=/root/.cache/huggingface \
        -e TRANSFORMERS_CACHE=/root/.cache/huggingface \
        -e HF_HUB_OFFLINE=1 \
        -e TRANSFORMERS_OFFLINE=1 \
        --entrypoint /bin/bash \
        rag-llm-gptoss:latest \
        -c "
echo 'Cache contents:'
ls -la /root/.cache/huggingface/hub/ | head -5

# Find available LLM model
if [ -d '/root/.cache/huggingface/hub/models--openai--gpt-oss-20b' ]; then
    MODEL='openai/gpt-oss-20b'
    echo 'Using GPT-OSS-20B from cache'
elif [ -d '/root/.cache/huggingface/hub/models--Qwen--Qwen2-0.5B-Instruct' ]; then
    MODEL='Qwen/Qwen2-0.5B-Instruct'
    echo 'Using Qwen2-0.5B-Instruct from cache'
else
    echo 'No suitable model found, trying GPT-OSS-20B...'
    MODEL='openai/gpt-oss-20b'
fi

echo \"Starting vLLM with model: \$MODEL\"

exec vllm serve \$MODEL \\
    --tensor-parallel-size 1 \\
    --gpu-memory-utilization 0.35 \\
    --max-model-len 2048 \\
    --served-model-name llm \\
    --trust-remote-code \\
    --enforce-eager \\
    --host 0.0.0.0 \\
    --port 8000
"

    print_status "LLM server restarted"
}

# Fix Whisper Service (offline model loading)
fix_whisper() {
    print_header "Fixing Whisper Service (Offline Model Loading)"

    print_warning "Stopping current whisper server..."
    docker stop rag-whisper 2>/dev/null || true
    docker rm rag-whisper 2>/dev/null || true

    print_status "Starting whisper server with proper cache..."

    docker run -d \
        --name rag-whisper \
        --network rag-network \
        --gpus all \
        --restart unless-stopped \
        -p 8004:8004 \
        -v $(pwd)/model-cache:/root/.cache/huggingface \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e HF_HOME=/root/.cache/huggingface \
        -e TRANSFORMERS_CACHE=/root/.cache/huggingface \
        -e HF_HUB_OFFLINE=1 \
        -e TRANSFORMERS_OFFLINE=1 \
        -e MODEL_NAME=ivrit-ai/whisper-large-v3 \
        rag-whisper:latest

    print_status "Whisper server restarted"
}

# Test all services
test_services() {
    print_header "Testing All Services"

    echo "Waiting 30 seconds for services to start..."
    sleep 30

    # Test each service
    echo ""
    echo "Service Status:"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep rag

    echo ""
    echo "Health Checks:"

    # Frontend
    if curl -s http://localhost:8087/frontend-health > /dev/null; then
        print_status "Frontend: Healthy"
    else
        print_error "Frontend: Unhealthy"
    fi

    # API
    if curl -s http://localhost:8080/health > /dev/null; then
        print_status "API: Healthy"
    else
        print_error "API: Unhealthy"
    fi

    # Embedding
    if curl -s http://localhost:8001/health > /dev/null; then
        print_status "Embedding: Healthy"
    else
        print_error "Embedding: Unhealthy"
    fi

    # LLM
    if curl -s http://localhost:8003/health > /dev/null; then
        print_status "LLM: Healthy"
    else
        print_error "LLM: Unhealthy"
    fi

    # Whisper
    if curl -s http://localhost:8004/health > /dev/null; then
        print_status "Whisper: Healthy"
    else
        print_error "Whisper: Unhealthy"
    fi
}

# Main execution
main() {
    echo "This script will fix common issues with RAG services:"
    echo "  • Frontend: Edge browser MIME type errors (script5022)"
    echo "  • Embedding: Triton/CUDA compilation errors"
    echo "  • LLM: Model cache and FlashAttention issues"
    echo "  • Whisper: Offline model loading problems"
    echo ""

    read -p "Continue with fixes? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    check_prerequisites

    # Execute fixes
    fix_frontend
    fix_embedding
    fix_llm
    fix_whisper

    # Test everything
    test_services

    print_header "Fix Complete!"
    echo ""
    print_status "All services have been restarted with offline-compatible configurations"
    echo ""
    echo "Access points:"
    echo "  Frontend:  http://localhost:8087"
    echo "  API:       http://localhost:8080"
    echo "  Embedding: http://localhost:8001"
    echo "  LLM:       http://localhost:8003"
    echo "  Whisper:   http://localhost:8004"
    echo ""
    echo "If any service is still unhealthy, check logs:"
    echo "  docker logs <service-name> --tail 50"
}

# Run main function
main "$@"