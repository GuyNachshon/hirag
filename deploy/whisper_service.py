import os
import tempfile
import logging
from pathlib import Path
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse
from faster_whisper import WhisperModel
import uvicorn

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(title="Whisper Transcription Service", version="1.0.0")

# Global model variable
model = None
MODEL_NAME = os.environ.get('MODEL_NAME', 'ivrit-ai/whisper-large-v3-turbo')

@app.on_event("startup")
async def load_model():
    global model
    logger.info(f"Loading Whisper model: {MODEL_NAME}")
    try:
        # Use CPU with int8 for efficiency, can be changed to GPU if available
        device = "cuda" if os.environ.get("CUDA_VISIBLE_DEVICES", "") != "" else "cpu"
        compute_type = "int8" if device == "cpu" else "float16"
        
        model = WhisperModel(MODEL_NAME, device=device, compute_type=compute_type)
        logger.info(f"Whisper model loaded successfully on {device}")
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        raise e

@app.get("/health")
async def health_check():
    return {
        "status": "healthy" if model is not None else "unhealthy",
        "service": "whisper-transcription",
        "model": MODEL_NAME,
        "version": "1.0.0"
    }

@app.post("/transcribe")
async def transcribe_audio(file: UploadFile = File(...)):
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    # Validate file type
    allowed_types = [
        "audio/wav", "audio/mpeg", "audio/mp3", "audio/ogg",
        "audio/flac", "audio/aac", "audio/webm", "audio/m4a"
    ]
    
    if file.content_type not in allowed_types:
        raise HTTPException(
            status_code=400, 
            detail=f"Unsupported file type: {file.content_type}"
        )
    
    # Check file size (max 100MB)
    if file.size and file.size > 100 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="File too large. Max size is 100MB")
    
    try:
        logger.info(f"Transcribing audio file: {file.filename}")
        
        # Save uploaded file to temporary location
        with tempfile.NamedTemporaryFile(delete=False, suffix=Path(file.filename).suffix) as tmp_file:
            content = await file.read()
            tmp_file.write(content)
            tmp_file_path = tmp_file.name
        
        try:
            # Transcribe audio with Hebrew language explicitly set
            segments, info = model.transcribe(
                tmp_file_path, 
                language="he",  # Explicitly set to Hebrew for ivrit-ai model
                beam_size=5,
                word_timestamps=False
            )
            
            # Extract text from segments
            transcribed_text = ""
            segment_list = []
            
            for segment in segments:
                transcribed_text += segment.text + " "
                segment_list.append({
                    "start": segment.start,
                    "end": segment.end,
                    "text": segment.text.strip()
                })
            
            result = {
                "success": True,
                "text": transcribed_text.strip(),
                "language": info.language,
                "language_probability": info.language_probability,
                "duration": info.duration,
                "segments": segment_list
            }
            
            logger.info(f"Transcription completed. Duration: {info.duration:.2f}s, Language: {info.language}")
            return JSONResponse(content=result)
            
        finally:
            # Clean up temporary file
            os.unlink(tmp_file_path)
            
    except Exception as e:
        logger.error(f"Transcription failed: {e}")
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8004)