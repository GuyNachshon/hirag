"""
FastAPI adapter for DotsOCR vLLM service
Translates REST API calls to vLLM OpenAI-compatible format
"""
import os
import io
import base64
import json
import logging
import tempfile
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse
import uvicorn
from PIL import Image
import aiofiles
import httpx

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="DotsOCR FastAPI Adapter")

# vLLM service configuration
VLLM_URL = "http://localhost:8000/v1/chat/completions"
VLLM_MODEL_NAME = "dotsocr-model"

# DotsOCR prompt templates
PROMPT_TEMPLATES = {
    "layout_all": "Please parse this document image and extract the layout and content. Return the result in JSON format with bounding boxes and text content.",
    "layout_only": "Please detect the layout elements in this document image. Return bounding boxes for all elements.",
    "ocr_only": "Please extract all text content from this document image."
}

async def encode_image_to_base64(image_path: str) -> str:
    """Convert image file to base64 string for vLLM"""
    try:
        with open(image_path, "rb") as image_file:
            image_data = image_file.read()
            base64_string = base64.b64encode(image_data).decode('utf-8')
            return f"data:image/jpeg;base64,{base64_string}"
    except Exception as e:
        logger.error(f"Failed to encode image: {e}")
        raise

async def call_vllm_service(image_base64: str, prompt: str) -> dict:
    """Call vLLM OpenAI-compatible service"""
    try:
        payload = {
            "model": VLLM_MODEL_NAME,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {"url": image_base64}
                        }
                    ]
                }
            ],
            "max_tokens": 4096,
            "temperature": 0.1,
            "top_p": 0.9
        }

        async with httpx.AsyncClient(timeout=120) as client:
            response = await client.post(VLLM_URL, json=payload)
            response.raise_for_status()
            return response.json()

    except Exception as e:
        logger.error(f"vLLM service call failed: {e}")
        raise

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Test vLLM service connectivity
        async with httpx.AsyncClient(timeout=5) as client:
            response = await client.get("http://localhost:8000/health")
            vllm_healthy = response.status_code == 200
    except:
        vllm_healthy = False

    return {
        "status": "healthy" if vllm_healthy else "degraded",
        "service": "dotsocr-adapter",
        "vllm_service": vllm_healthy,
        "model": VLLM_MODEL_NAME
    }

@app.post("/parse")
async def parse_document(
    file: UploadFile = File(...),
    prompt_mode: Optional[str] = "layout_all"
):
    """
    Parse document using DotsOCR via vLLM service

    Args:
        file: Image or PDF file to parse
        prompt_mode: Type of parsing (layout_all, layout_only, ocr_only)

    Returns:
        JSON response with parsed content
    """
    if not file:
        raise HTTPException(status_code=400, detail="No file provided")

    # Validate file type
    allowed_extensions = {'.jpg', '.jpeg', '.png', '.pdf'}
    file_extension = Path(file.filename).suffix.lower()
    if file_extension not in allowed_extensions:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type: {file_extension}. Supported: {allowed_extensions}"
        )

    # Get appropriate prompt
    prompt = PROMPT_TEMPLATES.get(prompt_mode, PROMPT_TEMPLATES["layout_all"])

    try:
        # Save uploaded file temporarily
        with tempfile.NamedTemporaryFile(delete=False, suffix=file_extension) as temp_file:
            content = await file.read()
            temp_file.write(content)
            temp_file_path = temp_file.name

        try:
            # Convert image to base64
            image_base64 = await encode_image_to_base64(temp_file_path)

            # Call vLLM service
            vllm_response = await call_vllm_service(image_base64, prompt)

            # Extract content from vLLM response
            if "choices" in vllm_response and vllm_response["choices"]:
                content = vllm_response["choices"][0]["message"]["content"]

                # Try to parse as JSON if it looks like JSON
                result_content = content
                try:
                    if content.strip().startswith('{') or content.strip().startswith('['):
                        result_content = json.loads(content)
                except json.JSONDecodeError:
                    # Keep as string if not valid JSON
                    pass

                return JSONResponse({
                    "success": True,
                    "result": {
                        "content": result_content,
                        "prompt_mode": prompt_mode,
                        "filename": file.filename,
                        "model": VLLM_MODEL_NAME
                    },
                    "usage": vllm_response.get("usage", {})
                })
            else:
                raise HTTPException(status_code=500, detail="Invalid response from vLLM service")

        finally:
            # Clean up temp file
            Path(temp_file_path).unlink(missing_ok=True)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Document parsing failed: {e}")
        raise HTTPException(status_code=500, detail=f"Parsing failed: {str(e)}")

@app.get("/models")
async def list_models():
    """List available models"""
    return {
        "models": [
            {
                "id": VLLM_MODEL_NAME,
                "object": "model",
                "created": 1234567890,
                "owned_by": "rednote-hilab"
            }
        ]
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8002)