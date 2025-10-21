from fastapi import APIRouter, HTTPException, Depends, File, UploadFile, Form
from typing import Union, Optional
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
    enable_diarization: bool = Form(True, description="Enable speaker diarization (enabled by default)"),
    identify_speakers: bool = Form(False, description="Use LLM to identify speaker names from conversation"),
    language: str = Form("he", description="Language code (e.g., 'he' for Hebrew, 'en' for English)"),
    service: TranscriptionService = Depends(get_transcription_service)
):
    """
    Transcribe audio file using Hebrew-optimized Whisper with speaker diarization and identification

    Supported formats: wav, mp3, m4a, flac, ogg, aac, webm
    Maximum file size: 100MB

    Features:
    - Diarization: ENABLED BY DEFAULT - Identifies different speakers in the audio and labels segments
      accordingly (SPEAKER_00, SPEAKER_01, etc.). Set enable_diarization=false to disable.
    - Speaker Identification: Optional LLM-based feature that extracts speaker names if they introduce
      themselves in the conversation (e.g., "Hi, I'm Sarah" → maps SPEAKER_00 to "Sarah")
      Set identify_speakers=true to enable.
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

        # Transcribe audio with diarization and speaker identification if requested
        result = await service.transcribe_audio(
            temp_file.name,
            file.filename or "audio",
            enable_diarization=enable_diarization,
            identify_speakers=identify_speakers,
            language=language
        )

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