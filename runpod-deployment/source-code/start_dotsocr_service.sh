#!/bin/bash
set -e

echo "Starting DotsOCR service with vLLM backend"

# Patch vLLM entrypoint to include DotsOCR modeling
echo "Patching vLLM entrypoint..."
sed -i '/^from vllm\.entrypoints\.cli\.main import main/a from DotsOCR import modeling_dots_ocr_vllm' $(which vllm)

echo "Starting vLLM server in background..."
python3 -m vllm.entrypoints.openai.api_server \
    --model /workspace/weights/DotsOCR \
    --tensor-parallel-size 1 \
    --gpu-memory-utilization 0.8 \
    --chat-template-content-format string \
    --served-model-name dotsocr-model \
    --trust-remote-code \
    --host 0.0.0.0 \
    --port 8000 &

VLLM_PID=$!

# Wait for vLLM to be ready
echo "Waiting for vLLM service to be ready..."
for i in {1..60}; do
    if curl -f http://localhost:8000/health >/dev/null 2>&1; then
        echo "vLLM service is ready!"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "vLLM service failed to start"
        exit 1
    fi
    sleep 2
done

echo "Starting FastAPI adapter..."
python3 ocr_fastapi_adapter.py &
FASTAPI_PID=$!

# Wait for either process to exit
wait -n $VLLM_PID $FASTAPI_PID

# If we get here, one process exited, so kill the other
kill $VLLM_PID 2>/dev/null || true
kill $FASTAPI_PID 2>/dev/null || true

exit 1