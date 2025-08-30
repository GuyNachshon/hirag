from fastapi import APIRouter, HTTPException, Depends, File, UploadFile
from typing import Union
import tempfile
import os
from pathlib import Path

from ..models import TranscriptionResponse, TranscriptionErrorResponse
from ..services import TranscriptionService

router = APIRouter()

def get_transcription_service() -> TranscriptionService:
    """Dependency to get transcription service"""
    from ..main import transcription_service
    if transcription_service is None:
        raise HTTPException(status_code=503, detail="Transcription service not available")
    return transcription_service

@router.post("/transcribe", response_model=Union[TranscriptionResponse, TranscriptionErrorResponse])
async def transcribe_audio(
    file: UploadFile = File(..., description="Audio file to transcribe"),
    service: TranscriptionService = Depends(get_transcription_service)
):
    """
    Transcribe audio file using Hebrew-optimized Whisper
    
    Supported formats: wav, mp3, m4a, flac, ogg, aac, webm
    Maximum file size: 100MB
    """
    
    # Validate file type
    if not file.content_type:
        return TranscriptionErrorResponse(
            error="invalid_file_type",
            message="File content type not specified"
        )
    
    allowed_types = [
        "audio/wav", "audio/mpeg", "audio/mp3", "audio/ogg",
        "audio/flac", "audio/aac", "audio/webm", "audio/m4a", 
        "audio/mp4", "audio/x-m4a"
    ]
    
    if file.content_type not in allowed_types:
        return TranscriptionErrorResponse(
            error="unsupported_file_type", 
            message=f"Unsupported file type: {file.content_type}. Supported types: {', '.join(allowed_types)}"
        )
    
    # Check file size (max 100MB)
    if file.size and file.size > 100 * 1024 * 1024:
        return TranscriptionErrorResponse(
            error="file_too_large",
            message="File too large. Maximum size is 100MB"
        )
    
    # Save uploaded file to temporary location
    temp_file = None
    try:
        # Create temporary file with proper extension
        file_extension = Path(file.filename or "audio").suffix or ".tmp"
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=file_extension)
        
        # Write file content
        content = await file.read()
        temp_file.write(content)
        temp_file.close()
        
        # Transcribe audio
        result = await service.transcribe_audio(temp_file.name, file.filename or "audio")
        
        return result
        
    except Exception as e:
        return TranscriptionErrorResponse(
            error="server_error",
            message=f"Server error during transcription: {str(e)}"
        )
    
    finally:
        # Clean up temporary file
        if temp_file:
            try:
                os.unlink(temp_file.name)
            except OSError:
                pass

@router.get("/transcribe/health")
async def transcription_health():
    """Check transcription service health"""
    try:
        service = get_transcription_service()
        return {
            "status": "healthy",
            "service": "transcription",
            "whisper_url": service.base_url
        }
    except HTTPException:
        return {
            "status": "unavailable",
            "service": "transcription"
        }