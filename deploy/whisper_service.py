import os
import tempfile
import logging
import torch
from pathlib import Path
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse
from transformers import AutoProcessor, AutoModelForSpeechSeq2Seq
import librosa
import uvicorn

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(title="Whisper Transcription Service", version="1.0.0")

# Global model variables
model = None
processor = None
MODEL_NAME = os.environ.get('MODEL_NAME', 'ivrit-ai/whisper-large-v3')

@app.on_event("startup")
async def load_model():
    global model, processor
    logger.info(f"Loading Whisper model: {MODEL_NAME}")
    try:
        # Determine device
        device = "cuda" if torch.cuda.is_available() and os.environ.get("CUDA_VISIBLE_DEVICES", "") != "" else "cpu"
        
        # Load processor and model
        logger.info(f"Loading processor from {MODEL_NAME}")
        processor = AutoProcessor.from_pretrained(MODEL_NAME)
        
        logger.info(f"Loading model from {MODEL_NAME} on {device}")
        model = AutoModelForSpeechSeq2Seq.from_pretrained(
            MODEL_NAME,
            torch_dtype=torch.float16 if device == "cuda" else torch.float32,
            low_cpu_mem_usage=True,
            use_safetensors=True
        ).to(device)
        
        logger.info(f"Whisper model loaded successfully on {device}")
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        raise e

@app.get("/health")
async def health_check():
    return {
        "status": "healthy" if model is not None and processor is not None else "unhealthy",
        "service": "whisper-transcription",
        "model": MODEL_NAME,
        "version": "1.0.0"
    }

@app.post("/transcribe")
async def transcribe_audio(file: UploadFile = File(...)):
    if model is None or processor is None:
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
            # Load audio using librosa
            audio_array, sampling_rate = librosa.load(tmp_file_path, sr=16000)
            
            # Process audio
            inputs = processor(audio_array, sampling_rate=16000, return_tensors="pt")
            
            # Move inputs to same device as model
            device = next(model.parameters()).device
            inputs = {k: v.to(device) for k, v in inputs.items()}
            
            # Generate transcription
            with torch.no_grad():
                # Force language to Hebrew
                forced_decoder_ids = processor.get_decoder_prompt_ids(language="hebrew", task="transcribe")
                predicted_ids = model.generate(
                    **inputs,
                    forced_decoder_ids=forced_decoder_ids,
                    max_new_tokens=448
                )
            
            # Decode the transcription
            transcription = processor.batch_decode(predicted_ids, skip_special_tokens=True)
            transcribed_text = transcription[0] if transcription else ""
            
            # Calculate duration
            duration = len(audio_array) / sampling_rate
            
            result = {
                "success": True,
                "text": transcribed_text.strip(),
                "language": "he",
                "language_probability": 1.0,  # Forced Hebrew
                "duration": duration,
                "segments": [{
                    "start": 0.0,
                    "end": duration,
                    "text": transcribed_text.strip()
                }]
            }
            
            logger.info(f"Transcription completed. Duration: {duration:.2f}s, Text: {transcribed_text[:100]}...")
            return JSONResponse(content=result)
            
        finally:
            # Clean up temporary file
            os.unlink(tmp_file_path)
            
    except Exception as e:
        logger.error(f"Transcription failed: {e}")
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8004)