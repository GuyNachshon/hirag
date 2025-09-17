"""
Audio Processing Router for RAG API
Handles audio file upload, conversion, and transcription via Whisper service
"""

import os
import tempfile
from pathlib import Path
from typing import Optional, List
import aiofiles
from fastapi import APIRouter, File, UploadFile, HTTPException, Form, BackgroundTasks
from fastapi.responses import JSONResponse
import httpx
import logging

from ..audio_processor import AudioProcessor
from ..logger import get_logger

logger = get_logger()

router = APIRouter(prefix="/api/audio", tags=["audio"])

# Initialize audio processor
audio_processor = AudioProcessor()

# Whisper service configuration
WHISPER_SERVICE_URL = os.getenv("WHISPER_SERVICE_URL", "http://rag-whisper:8004")
WHISPER_TIMEOUT = int(os.getenv("WHISPER_TIMEOUT", "300"))  # 5 minutes

@router.post("/upload")
async def upload_audio(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    language: Optional[str] = Form("he"),  # Default to Hebrew
    normalize: bool = Form(True),
    remove_silence: bool = Form(True),
    chunk_large_files: bool = Form(True)
):
    """
    Upload and process audio file for transcription

    Args:
        file: Audio file (supports MP3, WAV, M4A, OGG, FLAC, etc.)
        language: Language code (default: 'he' for Hebrew)
        normalize: Whether to normalize audio levels
        remove_silence: Whether to remove leading/trailing silence
        chunk_large_files: Whether to split large files into chunks

    Returns:
        JSON response with upload status and processing info
    """
    try:
        # Validate file
        if not file.filename:
            raise HTTPException(status_code=400, detail="No file provided")

        file_extension = Path(file.filename).suffix.lower()
        if file_extension not in audio_processor.SUPPORTED_FORMATS:
            supported = ", ".join(audio_processor.get_supported_formats())
            raise HTTPException(
                status_code=400,
                detail=f"Unsupported file format: {file_extension}. Supported: {supported}"
            )

        # Create temporary file for upload
        with tempfile.NamedTemporaryFile(delete=False, suffix=file_extension) as temp_file:
            # Read and save uploaded file
            content = await file.read()
            temp_file.write(content)
            temp_file_path = temp_file.name

        try:
            # Validate audio file
            is_valid = await audio_processor.validate_audio_file(temp_file_path)
            if not is_valid:
                raise HTTPException(status_code=400, detail="Invalid or corrupted audio file")

            # Process audio file
            processed_path, metadata = await audio_processor.process_audio_file(
                temp_file_path,
                normalize=normalize,
                remove_silence=remove_silence
            )

            # Check if file needs chunking (>30 seconds)
            chunks = []
            if chunk_large_files and metadata.get('processed_duration', 0) > 30:
                logger.info(f"Large file detected ({metadata['processed_duration']:.1f}s), chunking...")
                chunks = await audio_processor.chunk_audio(processed_path)
                logger.info(f"Created {len(chunks)} chunks")

            # Schedule cleanup
            cleanup_files = [temp_file_path, processed_path] + chunks
            background_tasks.add_task(audio_processor.cleanup_temp_files, cleanup_files)

            return JSONResponse({
                "status": "success",
                "message": "Audio file processed successfully",
                "data": {
                    "original_filename": file.filename,
                    "processed_file": processed_path,
                    "chunks": chunks,
                    "metadata": metadata,
                    "processing_options": {
                        "language": language,
                        "normalize": normalize,
                        "remove_silence": remove_silence,
                        "chunked": len(chunks) > 0
                    }
                }
            })

        finally:
            # Clean up original temp file
            Path(temp_file_path).unlink(missing_ok=True)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Audio upload failed: {e}")
        raise HTTPException(status_code=500, detail=f"Audio processing failed: {str(e)}")

@router.post("/transcribe")
async def transcribe_audio(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    language: Optional[str] = Form("he"),
    include_timestamps: bool = Form(True),
    word_timestamps: bool = Form(False),
    normalize: bool = Form(True),
    remove_silence: bool = Form(True)
):
    """
    Upload and transcribe audio file using Whisper service

    Args:
        file: Audio file
        language: Language code (default: 'he' for Hebrew)
        include_timestamps: Include segment timestamps
        word_timestamps: Include word-level timestamps
        normalize: Whether to normalize audio levels
        remove_silence: Whether to remove silence

    Returns:
        JSON response with transcription results
    """
    try:
        # Process audio file first
        upload_response = await upload_audio(
            background_tasks=background_tasks,
            file=file,
            language=language,
            normalize=normalize,
            remove_silence=remove_silence,
            chunk_large_files=True
        )

        upload_data = upload_response.body.decode() if hasattr(upload_response, 'body') else upload_response
        if isinstance(upload_data, str):
            import json
            upload_data = json.loads(upload_data)

        processed_file = upload_data["data"]["processed_file"]
        chunks = upload_data["data"]["chunks"]
        metadata = upload_data["data"]["metadata"]

        # Transcribe using Whisper service
        if chunks:
            # Process chunks separately
            transcriptions = []
            total_duration = 0

            for i, chunk_path in enumerate(chunks):
                chunk_transcription = await _transcribe_file(
                    chunk_path,
                    language=language,
                    include_timestamps=include_timestamps,
                    word_timestamps=word_timestamps
                )

                # Adjust timestamps for chunk offset
                if chunk_transcription and "segments" in chunk_transcription:
                    for segment in chunk_transcription["segments"]:
                        segment["start"] += total_duration
                        segment["end"] += total_duration

                transcriptions.append({
                    "chunk_index": i,
                    "chunk_file": chunk_path,
                    "transcription": chunk_transcription
                })

                # Estimate duration for next chunk offset
                total_duration += 28  # 30s chunk - 2s overlap

            # Combine all transcriptions
            combined_text = " ".join([
                t["transcription"].get("text", "") for t in transcriptions
                if t["transcription"]
            ])

            combined_segments = []
            for t in transcriptions:
                if t["transcription"] and "segments" in t["transcription"]:
                    combined_segments.extend(t["transcription"]["segments"])

            result = {
                "text": combined_text,
                "language": language,
                "segments": combined_segments if include_timestamps else None,
                "chunked": True,
                "chunk_count": len(chunks),
                "chunk_transcriptions": transcriptions
            }

        else:
            # Single file transcription
            result = await _transcribe_file(
                processed_file,
                language=language,
                include_timestamps=include_timestamps,
                word_timestamps=word_timestamps
            )

        # Add metadata
        if result:
            result.update({
                "original_filename": file.filename,
                "processing_metadata": metadata,
                "transcription_service": "whisper",
                "language_detected": result.get("language", language)
            })

        return JSONResponse({
            "status": "success",
            "message": "Audio transcribed successfully",
            "data": result
        })

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Audio transcription failed: {e}")
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")

async def _transcribe_file(
    file_path: str,
    language: str = "he",
    include_timestamps: bool = True,
    word_timestamps: bool = False
) -> dict:
    """
    Send file to Whisper service for transcription

    Args:
        file_path: Path to audio file
        language: Language code
        include_timestamps: Include timestamps
        word_timestamps: Include word-level timestamps

    Returns:
        Transcription result from Whisper service
    """
    try:
        async with httpx.AsyncClient(timeout=WHISPER_TIMEOUT) as client:
            # Prepare file for upload
            with open(file_path, 'rb') as audio_file:
                files = {
                    'file': (Path(file_path).name, audio_file, 'audio/wav')
                }

                data = {
                    'language': language,
                    'response_format': 'json',
                    'timestamp_granularities[]': ['segment']
                }

                if word_timestamps:
                    data['timestamp_granularities[]'] = ['word', 'segment']

                # Send to Whisper service
                response = await client.post(
                    f"{WHISPER_SERVICE_URL}/transcribe",
                    files=files,
                    data=data
                )

                response.raise_for_status()
                return response.json()

    except httpx.TimeoutException:
        logger.error(f"Whisper service timeout for file: {file_path}")
        raise HTTPException(status_code=504, detail="Transcription service timeout")
    except httpx.HTTPStatusError as e:
        logger.error(f"Whisper service error: {e.response.status_code} - {e.response.text}")
        raise HTTPException(
            status_code=e.response.status_code,
            detail=f"Transcription service error: {e.response.text}"
        )
    except Exception as e:
        logger.error(f"Transcription request failed: {e}")
        raise HTTPException(status_code=500, detail=f"Transcription request failed: {str(e)}")

@router.get("/formats")
async def get_supported_formats():
    """Get list of supported audio formats"""
    return JSONResponse({
        "status": "success",
        "data": {
            "supported_formats": audio_processor.get_supported_formats(),
            "target_format": audio_processor.TARGET_FORMAT,
            "target_sample_rate": audio_processor.TARGET_SAMPLE_RATE,
            "target_channels": audio_processor.TARGET_CHANNELS
        }
    })

@router.get("/health")
async def audio_health():
    """Health check for audio processing service"""
    try:
        # Test Whisper service connectivity
        async with httpx.AsyncClient(timeout=5) as client:
            response = await client.get(f"{WHISPER_SERVICE_URL}/health")
            whisper_healthy = response.status_code == 200

        return JSONResponse({
            "status": "healthy",
            "services": {
                "audio_processor": True,
                "whisper_service": whisper_healthy,
                "whisper_url": WHISPER_SERVICE_URL
            },
            "supported_formats": len(audio_processor.SUPPORTED_FORMATS)
        })

    except Exception as e:
        logger.error(f"Audio health check failed: {e}")
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "error": str(e),
                "services": {
                    "audio_processor": True,
                    "whisper_service": False
                }
            }
        )

# Example usage endpoints for testing
@router.post("/test/convert")
async def test_convert_audio(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    target_format: str = Form("wav")
):
    """Test endpoint for audio conversion only (no transcription)"""
    try:
        # Save uploaded file
        with tempfile.NamedTemporaryFile(delete=False, suffix=Path(file.filename).suffix) as temp_file:
            content = await file.read()
            temp_file.write(content)
            temp_file_path = temp_file.name

        # Process audio
        processed_path, metadata = await audio_processor.process_audio_file(
            temp_file_path,
            target_format=target_format
        )

        # Schedule cleanup
        background_tasks.add_task(audio_processor.cleanup_temp_files, [temp_file_path, processed_path])

        return JSONResponse({
            "status": "success",
            "message": "Audio converted successfully",
            "data": {
                "original_filename": file.filename,
                "processed_file": processed_path,
                "metadata": metadata
            }
        })

    except Exception as e:
        logger.error(f"Audio conversion test failed: {e}")
        raise HTTPException(status_code=500, detail=f"Conversion failed: {str(e)}")

@router.get("/test/whisper")
async def test_whisper_connection():
    """Test endpoint to check Whisper service connectivity"""
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(f"{WHISPER_SERVICE_URL}/health")

            return JSONResponse({
                "status": "success",
                "whisper_service": {
                    "url": WHISPER_SERVICE_URL,
                    "status_code": response.status_code,
                    "response": response.json() if response.status_code == 200 else response.text,
                    "healthy": response.status_code == 200
                }
            })

    except Exception as e:
        return JSONResponse(
            status_code=503,
            content={
                "status": "failed",
                "error": str(e),
                "whisper_service": {
                    "url": WHISPER_SERVICE_URL,
                    "healthy": False
                }
            }
        )