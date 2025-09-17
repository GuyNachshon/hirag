# FastAPI Whisper service based on Ivrit-AI implementation
# Provides REST API endpoints for Hebrew audio transcription
import os
import io
import logging
import tempfile
import time
from pathlib import Path
from typing import Optional, List, Dict, Any

from fastapi import FastAPI, File, UploadFile, HTTPException, Form
from fastapi.responses import JSONResponse
import uvicorn
import ivrit

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Ivrit-AI Whisper FastAPI Service")

# Global model cache (similar to Ivrit-AI serverless logic)
current_model = None

class ModelManager:
    """Manages Whisper model loading and caching"""

    def __init__(self):
        self.current_model = None

    def load_model(self, engine: str = "faster-whisper", model_name: str = None):
        """Load or reuse Whisper model"""
        global current_model

        if not model_name:
            model_name = os.environ.get('MODEL_NAME', 'ivrit-ai/whisper-large-v3-ct2')

        # Check if we need to load a different model
        different_model = (
            not current_model or
            current_model.engine != engine or
            current_model.model != model_name
        )

        if different_model:
            logger.info(f'Loading new model: {engine} with {model_name}')
            current_model = ivrit.load_model(
                engine=engine,
                model=model_name,
                local_files_only=True
            )
        else:
            logger.info(f'Reusing existing model: {engine} with {model_name}')

        return current_model

model_manager = ModelManager()

@app.on_event("startup")
async def startup_event():
    """Initialize model on startup"""
    try:
        logger.info("Loading default Whisper model...")
        model_manager.load_model()
        logger.info("Model loaded successfully")
    except Exception as e:
        logger.error(f"Failed to load model on startup: {e}")

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "ivrit-whisper",
        "model": os.environ.get('MODEL_NAME', 'ivrit-ai/whisper-large-v3-ct2'),
        "device": os.environ.get('DEVICE', 'cuda'),
        "model_loaded": current_model is not None,
        "offline_mode": bool(os.environ.get('HF_HUB_OFFLINE'))
    }

@app.post("/transcribe")
async def transcribe_audio(
    file: UploadFile = File(...),
    engine: str = Form("faster-whisper"),
    model: Optional[str] = Form(None),
    language: str = Form("he"),
    diarize: bool = Form(False),
    word_timestamps: bool = Form(False)
):
    """
    Transcribe audio file using Ivrit-AI models

    Args:
        file: Audio file to transcribe
        engine: Transcription engine (faster-whisper, stable-whisper)
        model: Model name (defaults to environment MODEL_NAME)
        language: Language code (default: he for Hebrew)
        diarize: Enable speaker diarization
        word_timestamps: Include word-level timestamps

    Returns:
        JSON response with transcription results
    """
    if not file:
        raise HTTPException(status_code=400, detail="No file provided")

    # Validate engine
    if engine not in ['faster-whisper', 'stable-whisper']:
        raise HTTPException(
            status_code=400,
            detail=f"Engine must be 'faster-whisper' or 'stable-whisper', got: {engine}"
        )

    try:
        # Save uploaded file temporarily
        file_extension = Path(file.filename).suffix.lower()
        with tempfile.NamedTemporaryFile(delete=False, suffix=file_extension) as temp_file:
            content = await file.read()
            temp_file.write(content)
            temp_file_path = temp_file.name

        try:
            # Load appropriate model
            whisper_model = model_manager.load_model(engine=engine, model_name=model)

            start_time = time.time()

            # Prepare transcription arguments (based on Ivrit-AI logic)
            transcribe_args = {
                'blob': temp_file_path,
                'language': language,
                'diarize': diarize
            }

            # Add word timestamps if requested
            if word_timestamps and not diarize:
                transcribe_args['word_timestamps'] = True

            # Perform transcription
            if diarize:
                # For diarization, get complete result
                result = whisper_model.transcribe(**transcribe_args)
                segments = result.get('segments', [])
                # Convert segments to dict format
                transcription_segments = [
                    {
                        'text': seg.get('text', ''),
                        'start': seg.get('start', 0),
                        'end': seg.get('end', 0),
                        'speaker': seg.get('speaker', 'SPEAKER_00')
                    }
                    for seg in segments
                ]
                full_text = ' '.join([seg['text'] for seg in transcription_segments])
            else:
                # For regular transcription, use streaming
                transcribe_args['stream'] = True
                segments_stream = whisper_model.transcribe(**transcribe_args)

                transcription_segments = []
                for segment in segments_stream:
                    # Convert dataclass to dict if needed
                    if hasattr(segment, '__dict__'):
                        seg_dict = segment.__dict__
                    else:
                        seg_dict = segment
                    transcription_segments.append(seg_dict)

                full_text = ' '.join([seg.get('text', '') for seg in transcription_segments])

            processing_time = time.time() - start_time

            return JSONResponse({
                "text": full_text,
                "language": language,
                "segments": transcription_segments,
                "processing_time": processing_time,
                "model": model or os.environ.get('MODEL_NAME'),
                "engine": engine,
                "diarization_enabled": diarize,
                "word_timestamps": word_timestamps,
                "filename": file.filename
            })

        finally:
            # Clean up temp file
            Path(temp_file_path).unlink(missing_ok=True)

    except Exception as e:
        logger.error(f"Transcription failed: {e}")
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")

@app.post("/transcribe_batch")
async def transcribe_batch(
    files: List[UploadFile] = File(...),
    engine: str = Form("faster-whisper"),
    model: Optional[str] = Form(None),
    language: str = Form("he"),
    diarize: bool = Form(False)
):
    """
    Transcribe multiple audio files
    """
    if not files:
        raise HTTPException(status_code=400, detail="No files provided")

    results = []
    for file in files:
        try:
            # Call single transcription for each file
            # Note: This is a simplified batch implementation
            # In production, you might want to process in parallel
            result = await transcribe_audio(
                file=file,
                engine=engine,
                model=model,
                language=language,
                diarize=diarize
            )
            results.append({
                "filename": file.filename,
                "result": result,
                "success": True
            })
        except Exception as e:
            results.append({
                "filename": file.filename,
                "error": str(e),
                "success": False
            })

    return JSONResponse({
        "batch_results": results,
        "total_files": len(files),
        "successful": len([r for r in results if r["success"]]),
        "failed": len([r for r in results if not r["success"]])
    })

@app.get("/models")
async def list_models():
    """List available models"""
    return {
        "models": [
            {
                "id": "ivrit-ai/whisper-large-v3-ct2",
                "name": "Whisper Large V3 CT2",
                "language": "Hebrew",
                "engine": "faster-whisper"
            },
            {
                "id": "ivrit-ai/whisper-large-v3-turbo-ct2",
                "name": "Whisper Large V3 Turbo CT2",
                "language": "Hebrew",
                "engine": "faster-whisper"
            }
        ],
        "current_model": os.environ.get('MODEL_NAME')
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8004)