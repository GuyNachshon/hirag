"""
Transcription endpoints with database storage and authentication.
Manages the full lifecycle: upload → transcribe → store → retrieve.
"""

from fastapi import APIRouter, HTTPException, Depends, File, UploadFile, Form, Response
from fastapi.responses import StreamingResponse, JSONResponse
from typing import Union, Optional
from sqlalchemy.orm import Session
from pathlib import Path
import tempfile
import os
import json
import asyncio
import time
from datetime import datetime
import io

from ..database import get_db, Transcript, TranscriptSegment, Folder
from ..dependencies import get_current_user
from ..models import (
    TranscriptionResponse,
    TranscriptionErrorResponse,
    TranscriptUploadResponse,
    TranscriptStatusResponse,
    TranscriptListResponse,
    TranscriptListItem,
    TranscriptDetailResponse,
    TranscriptUpdateRequest,
    TranscriptionSegment as TranscriptionSegmentModel,
    TranscriptStatus,
    ExportFormat
)
from ..services import TranscriptionService
from ..logger import get_logger

router = APIRouter(prefix="/api/transcription", tags=["Transcription"])
logger = get_logger()


def get_transcription_service() -> TranscriptionService:
    """Dependency to get transcription service"""
    from ..main import transcription_service
    if transcription_service is None:
        raise HTTPException(status_code=503, detail="Transcription service not available")
    return transcription_service


@router.post("/upload", response_model=TranscriptUploadResponse)
async def upload_and_transcribe(
    file: UploadFile = File(..., description="Audio file to transcribe"),
    title: str = Form(..., description="Transcript title"),
    folder_id: Optional[str] = Form(None, description="Optional folder ID"),
    tags: Optional[str] = Form(None, description="Optional comma-separated tags"),
    enable_diarization: bool = Form(True, description="Enable speaker diarization"),
    identify_speakers: bool = Form(False, description="Use LLM to identify speaker names"),
    num_speakers: Optional[int] = Form(None, description="Expected number of speakers (for diarization hint)"),
    language: str = Form("he", description="Language code (e.g., 'he', 'en')"),
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db),
    service: TranscriptionService = Depends(get_transcription_service)
):
    """
    Upload audio file and start transcription process.

    Creates a transcript record in database with "processing" status,
    then asynchronously processes the audio file.

    Requires authentication.

    Args:
        file: Audio file (wav, mp3, m4a, etc.)
        title: Transcript title
        folder_id: Optional folder to organize transcript
        tags: Optional comma-separated tags
        enable_diarization: Enable speaker detection
        identify_speakers: Use LLM to identify speaker names
        language: Audio language code
        current_user: Authenticated user
        db: Database session
        service: Transcription service

    Returns:
        TranscriptUploadResponse with transcript ID and status

    Raises:
        HTTPException: 400 for invalid file/folder, 503 if service unavailable
    """
    logger.main_logger.info(
        f"Upload request from user {current_user.username}: "
        f"title='{title}', folder={folder_id}, file={file.filename}"
    )

    # Validate file type
    if not file.content_type:
        raise HTTPException(status_code=400, detail="File content type not specified")

    allowed_types = [
        "audio/wav", "audio/mpeg", "audio/mp3", "audio/ogg",
        "audio/flac", "audio/aac", "audio/webm", "audio/m4a",
        "audio/mp4", "audio/x-m4a"
    ]

    if file.content_type not in allowed_types:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type: {file.content_type}"
        )

    # Check file size (max 100MB)
    if file.size and file.size > 100 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="File too large. Maximum size is 100MB")

    # Validate folder belongs to user if specified
    if folder_id:
        folder = (
            db.query(Folder)
            .filter(Folder.id == folder_id)
            .filter(Folder.user_id == current_user.id)
            .first()
        )
        if not folder:
            raise HTTPException(status_code=400, detail="Folder not found")

    # Parse tags
    tags_list = []
    if tags:
        tags_list = [t.strip() for t in tags.split(',') if t.strip()]

    # Create transcript record with "processing" status
    transcript = Transcript(
        user_id=current_user.id,
        folder_id=folder_id,
        title=title,
        audio_filename=file.filename or "audio",
        language=language,
        tags=json.dumps(tags_list) if tags_list else None,
        status=TranscriptStatus.PROCESSING,
        progress_percent=0,
        diarization_enabled=enable_diarization
    )

    db.add(transcript)
    db.commit()
    db.refresh(transcript)

    logger.main_logger.info(f"Created transcript record: {transcript.id}")

    # Save file and process asynchronously
    temp_file = None
    try:
        # Save uploaded file
        file_extension = Path(file.filename or "audio").suffix or ".tmp"
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=file_extension)
        content = await file.read()
        temp_file.write(content)
        temp_file.close()

        # Start background transcription
        asyncio.create_task(
            process_transcription_async(
                transcript_id=transcript.id,
                audio_path=temp_file.name,
                enable_diarization=enable_diarization,
                identify_speakers=identify_speakers,
                num_speakers=num_speakers,
                language=language,
                service=service
            )
        )

        return TranscriptUploadResponse(
            transcript_id=transcript.id,
            status=TranscriptStatus.PROCESSING,
            message="Transcription started successfully"
        )

    except Exception as e:
        # Update transcript status to failed
        transcript.status = TranscriptStatus.FAILED
        transcript.error_message = str(e)
        db.commit()

        logger.log_error(e, {"transcript_id": transcript.id})

        raise HTTPException(status_code=500, detail=f"Failed to start transcription: {str(e)}")


async def generate_embeddings_background(transcript_id: str):
    """
    Background task to generate embeddings for a transcript.
    Runs independently and doesn't block transcription completion.
    """
    from ..main import transcription_chat_service

    # Wait a bit to let the main transaction complete
    await asyncio.sleep(2)

    # Get a new database session for this background task
    db = next(get_db())

    try:
        if transcription_chat_service and transcription_chat_service.embedding_func:
            logger.main_logger.info(
                f"[Background] Starting embedding generation for transcript {transcript_id}"
            )

            start_time = time.time()

            await transcription_chat_service._generate_embeddings_for_transcript(
                transcript_id, db
            )

            duration = time.time() - start_time

            logger.main_logger.info(
                f"[Background] Embeddings generated for {transcript_id} in {duration:.2f}s"
            )
        else:
            logger.main_logger.warning(
                f"[Background] Transcription chat service or embedding function not available "
                f"for transcript {transcript_id}"
            )
    except Exception as e:
        logger.main_logger.error(
            f"[Background] Failed to generate embeddings for {transcript_id}: {e}"
        )
        # Don't raise - this is a background task, failure shouldn't affect the transcript
    finally:
        db.close()


async def process_transcription_async(
    transcript_id: str,
    audio_path: str,
    enable_diarization: bool,
    identify_speakers: bool,
    num_speakers: Optional[int],
    language: str,
    service: TranscriptionService
):
    """
    Background task to process transcription and save to database.

    Args:
        transcript_id: Transcript database ID
        audio_path: Path to temporary audio file
        enable_diarization: Enable speaker detection
        identify_speakers: Use LLM for speaker identification
        num_speakers: Expected number of speakers (hint for diarization)
        language: Language code
        service: Transcription service
    """
    db = next(get_db())

    try:
        logger.main_logger.info(f"Starting transcription processing for: {transcript_id}")

        # Get transcript record
        transcript = db.query(Transcript).filter(Transcript.id == transcript_id).first()
        if not transcript:
            logger.main_logger.error(f"Transcript {transcript_id} not found")
            return

        # Update progress
        transcript.progress_percent = 10
        db.commit()

        # Call transcription service
        result = await service.transcribe_audio(
            audio_file_path=audio_path,
            filename=transcript.audio_filename,
            enable_diarization=enable_diarization,
            identify_speakers=identify_speakers,
            num_speakers=num_speakers,
            language=language
        )

        transcript.progress_percent = 90
        db.commit()

        if isinstance(result, TranscriptionErrorResponse):
            # Transcription failed
            transcript.status = TranscriptStatus.FAILED
            transcript.error_message = result.message
            transcript.progress_percent = 0
            db.commit()
            logger.main_logger.error(
                f"Transcription failed for {transcript_id}: {result.message}"
            )
            return

        # Save transcription results
        transcript.status = TranscriptStatus.COMPLETED
        transcript.progress_percent = 100
        transcript.full_text = result.text
        transcript.duration = result.duration
        transcript.language_probability = result.language_probability
        transcript.num_speakers = result.num_speakers
        transcript.speaker_names_json = json.dumps(result.speaker_names) if result.speaker_names else None
        transcript.completed_at = datetime.utcnow()
        db.commit()

        # Save segments
        for seg in result.segments:
            segment = TranscriptSegment(
                transcript_id=transcript.id,
                start_time=seg.start,
                end_time=seg.end,
                text=seg.text,
                speaker=seg.speaker
            )
            db.add(segment)

        db.commit()

        logger.main_logger.info(
            f"Transcription completed for {transcript_id}: "
            f"{len(result.segments)} segments, duration={result.duration}s"
        )

        # Trigger background embedding generation (don't wait for it)
        asyncio.create_task(
            generate_embeddings_background(transcript_id)
        )

    except Exception as e:
        # Update to failed status
        transcript = db.query(Transcript).filter(Transcript.id == transcript_id).first()
        if transcript:
            transcript.status = TranscriptStatus.FAILED
            transcript.error_message = str(e)
            transcript.progress_percent = 0
            db.commit()

        logger.log_error(e, {"transcript_id": transcript_id})

    finally:
        # Clean up temporary file
        try:
            os.unlink(audio_path)
        except OSError:
            pass
        db.close()


@router.get("/status/{transcript_id}", response_model=TranscriptStatusResponse)
async def get_transcription_status(
    transcript_id: str,
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get transcription processing status (for polling).

    Requires authentication.

    Args:
        transcript_id: Transcript ID
        current_user: Authenticated user
        db: Database session

    Returns:
        TranscriptStatusResponse with current status and progress

    Raises:
        HTTPException: 404 if transcript not found
    """
    transcript = (
        db.query(Transcript)
        .filter(Transcript.id == transcript_id)
        .filter(Transcript.user_id == current_user.id)
        .first()
    )

    if not transcript:
        raise HTTPException(status_code=404, detail="Transcript not found")

    return TranscriptStatusResponse(
        transcript_id=transcript.id,
        status=transcript.status,
        progress_percent=transcript.progress_percent,
        error_message=transcript.error_message
    )


@router.get("/list", response_model=TranscriptListResponse)
async def list_transcripts(
    folder_id: Optional[str] = None,
    status: Optional[TranscriptStatus] = None,
    limit: int = 20,
    offset: int = 0,
    sort_by: str = "created_at",
    order: str = "desc",
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    List user's transcripts with optional filters.

    Requires authentication.

    Args:
        folder_id: Filter by folder
        status: Filter by status
        limit: Max results (1-100)
        offset: Pagination offset
        sort_by: Sort field (created_at, updated_at, title, duration)
        order: Sort order (asc, desc)
        current_user: Authenticated user
        db: Database session

    Returns:
        TranscriptListResponse with transcripts
    """
    # Build query
    query = (
        db.query(Transcript, Folder.name.label('folder_name'))
        .outerjoin(Folder, Transcript.folder_id == Folder.id)
        .filter(Transcript.user_id == current_user.id)
    )

    # Apply filters
    if folder_id:
        query = query.filter(Transcript.folder_id == folder_id)
    if status:
        query = query.filter(Transcript.status == status)

    # Get total count
    total_count = query.count()

    # Apply sorting
    sort_field = getattr(Transcript, sort_by, Transcript.created_at)
    if order == "desc":
        query = query.order_by(sort_field.desc())
    else:
        query = query.order_by(sort_field.asc())

    # Apply pagination
    query = query.offset(offset).limit(min(limit, 100))

    results = query.all()

    # Build response
    transcript_items = []
    for transcript, folder_name in results:
        # Parse tags
        tags_list = []
        if transcript.tags:
            try:
                tags_list = json.loads(transcript.tags)
            except json.JSONDecodeError:
                pass

        # Get unique speakers
        speakers = []
        if transcript.status == TranscriptStatus.COMPLETED:
            unique_speakers = (
                db.query(TranscriptSegment.speaker)
                .filter(TranscriptSegment.transcript_id == transcript.id)
                .filter(TranscriptSegment.speaker.isnot(None))
                .distinct()
                .all()
            )
            speakers = [s[0] for s in unique_speakers if s[0]]

        transcript_items.append(
            TranscriptListItem(
                id=transcript.id,
                title=transcript.title,
                duration=transcript.duration,
                status=transcript.status,
                folder_id=transcript.folder_id,
                folder_name=folder_name,
                tags=tags_list,
                speakers=speakers,
                language=transcript.language,
                created_at=transcript.created_at,
                updated_at=transcript.updated_at,
                completed_at=transcript.completed_at
            )
        )

    return TranscriptListResponse(
        transcripts=transcript_items,
        total_count=total_count
    )


@router.get("/{transcript_id}", response_model=TranscriptDetailResponse)
async def get_transcript(
    transcript_id: str,
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get full transcript details with all segments.

    Requires authentication.

    Args:
        transcript_id: Transcript ID
        current_user: Authenticated user
        db: Database session

    Returns:
        TranscriptDetailResponse with all data

    Raises:
        HTTPException: 404 if not found
    """
    # Get transcript with folder name
    result = (
        db.query(Transcript, Folder.name.label('folder_name'))
        .outerjoin(Folder, Transcript.folder_id == Folder.id)
        .filter(Transcript.id == transcript_id)
        .filter(Transcript.user_id == current_user.id)
        .first()
    )

    if not result:
        raise HTTPException(status_code=404, detail="Transcript not found")

    transcript, folder_name = result

    # Get segments
    segments_db = (
        db.query(TranscriptSegment)
        .filter(TranscriptSegment.transcript_id == transcript_id)
        .order_by(TranscriptSegment.start_time)
        .all()
    )

    segments = [
        TranscriptionSegmentModel(
            start=seg.start_time,
            end=seg.end_time,
            text=seg.text,
            speaker=seg.speaker
        )
        for seg in segments_db
    ]

    # Parse tags
    tags_list = []
    if transcript.tags:
        try:
            tags_list = json.loads(transcript.tags)
        except json.JSONDecodeError:
            pass

    # Parse speaker names
    speaker_names = None
    if transcript.speaker_names_json:
        try:
            speaker_names = json.loads(transcript.speaker_names_json)
        except json.JSONDecodeError:
            pass

    return TranscriptDetailResponse(
        id=transcript.id,
        title=transcript.title,
        duration=transcript.duration,
        status=transcript.status,
        folder_id=transcript.folder_id,
        folder_name=folder_name,
        tags=tags_list,
        language=transcript.language,
        full_text=transcript.full_text,
        language_probability=transcript.language_probability,
        diarization_enabled=transcript.diarization_enabled,
        num_speakers=transcript.num_speakers,
        speaker_names=speaker_names,
        segments=segments,
        created_at=transcript.created_at,
        updated_at=transcript.updated_at,
        completed_at=transcript.completed_at
    )


@router.patch("/{transcript_id}", response_model=TranscriptDetailResponse)
async def update_transcript(
    transcript_id: str,
    request: TranscriptUpdateRequest,
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Update transcript metadata (title, folder, tags).

    Requires authentication.

    Args:
        transcript_id: Transcript ID
        request: Update fields
        current_user: Authenticated user
        db: Database session

    Returns:
        Updated transcript details

    Raises:
        HTTPException: 404 if not found, 400 if folder invalid
    """
    transcript = (
        db.query(Transcript)
        .filter(Transcript.id == transcript_id)
        .filter(Transcript.user_id == current_user.id)
        .first()
    )

    if not transcript:
        raise HTTPException(status_code=404, detail="Transcript not found")

    # Update fields
    if request.title is not None:
        transcript.title = request.title

    if request.folder_id is not None:
        # Validate folder belongs to user
        folder = (
            db.query(Folder)
            .filter(Folder.id == request.folder_id)
            .filter(Folder.user_id == current_user.id)
            .first()
        )
        if not folder:
            raise HTTPException(status_code=400, detail="Folder not found")
        transcript.folder_id = request.folder_id

    if request.tags is not None:
        transcript.tags = json.dumps(request.tags)

    db.commit()
    db.refresh(transcript)

    logger.main_logger.info(f"Updated transcript {transcript_id}")

    # Return full details
    return await get_transcript(transcript_id, current_user, db)


@router.delete("/{transcript_id}")
async def delete_transcript(
    transcript_id: str,
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Delete a transcript and all its segments.

    Requires authentication.

    Args:
        transcript_id: Transcript ID
        current_user: Authenticated user
        db: Database session

    Returns:
        Success message

    Raises:
        HTTPException: 404 if not found
    """
    transcript = (
        db.query(Transcript)
        .filter(Transcript.id == transcript_id)
        .filter(Transcript.user_id == current_user.id)
        .first()
    )

    if not transcript:
        raise HTTPException(status_code=404, detail="Transcript not found")

    title = transcript.title
    db.delete(transcript)
    db.commit()

    logger.main_logger.info(f"Deleted transcript {transcript_id}: {title}")

    return {"message": f"Transcript '{title}' deleted successfully"}


@router.get("/{transcript_id}/export")
async def export_transcript(
    transcript_id: str,
    format: ExportFormat = ExportFormat.TXT,
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Export transcript in various formats (TXT, PDF, JSON).

    Requires authentication.

    Args:
        transcript_id: Transcript ID
        format: Export format (txt, pdf, json)
        current_user: Authenticated user
        db: Database session

    Returns:
        File download

    Raises:
        HTTPException: 404 if not found, 400 if not completed
    """
    # Get transcript
    transcript = (
        db.query(Transcript)
        .filter(Transcript.id == transcript_id)
        .filter(Transcript.user_id == current_user.id)
        .first()
    )

    if not transcript:
        raise HTTPException(status_code=404, detail="Transcript not found")

    if transcript.status != TranscriptStatus.COMPLETED:
        raise HTTPException(
            status_code=400,
            detail="Transcript not yet completed. Cannot export."
        )

    # Get segments
    segments = (
        db.query(TranscriptSegment)
        .filter(TranscriptSegment.transcript_id == transcript_id)
        .order_by(TranscriptSegment.start_time)
        .all()
    )

    filename = f"{transcript.title.replace(' ', '_')}.{format.value}"

    if format == ExportFormat.TXT:
        # Plain text format
        content = f"{transcript.title}\n"
        content += f"{'=' * len(transcript.title)}\n\n"

        for seg in segments:
            speaker_label = f"[{seg.speaker}] " if seg.speaker else ""
            time_label = f"[{format_timestamp(seg.start_time)}] "
            content += f"{time_label}{speaker_label}{seg.text}\n\n"

        return Response(
            content=content.encode('utf-8'),
            media_type="text/plain",
            headers={"Content-Disposition": f"attachment; filename={filename}"}
        )

    elif format == ExportFormat.JSON:
        # JSON format
        export_data = {
            "id": transcript.id,
            "title": transcript.title,
            "duration": transcript.duration,
            "language": transcript.language,
            "created_at": transcript.created_at.isoformat(),
            "completed_at": transcript.completed_at.isoformat() if transcript.completed_at else None,
            "full_text": transcript.full_text,
            "segments": [
                {
                    "start": seg.start_time,
                    "end": seg.end_time,
                    "speaker": seg.speaker,
                    "text": seg.text
                }
                for seg in segments
            ]
        }

        return JSONResponse(
            content=export_data,
            headers={"Content-Disposition": f"attachment; filename={filename}"}
        )

    elif format == ExportFormat.PDF:
        # PDF format (simplified - would need reportlab for production)
        raise HTTPException(
            status_code=501,
            detail="PDF export not yet implemented. Use TXT or JSON format."
        )


def format_timestamp(seconds: float) -> str:
    """Format seconds to MM:SS or HH:MM:SS"""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)

    if hours > 0:
        return f"{hours:02d}:{minutes:02d}:{secs:02d}"
    else:
        return f"{minutes:02d}:{secs:02d}"


@router.post("/{transcript_id}/insights")
async def generate_insights(
    transcript_id: str,
    current_user=Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Generate AI insights for a transcript including:
    - Summary
    - Key points
    - Action items
    - Topics discussed
    """
    # Get transcript from database
    transcript = db.query(Transcript).filter(
        Transcript.id == transcript_id,
        Transcript.user_id == current_user.id
    ).first()

    if not transcript:
        raise HTTPException(status_code=404, detail="Transcript not found")

    if transcript.status != "completed":
        raise HTTPException(status_code=400, detail="Transcript not completed yet")

    # Check if insights already generated and cached
    if transcript.insights:
        logger.main_logger.info(f"Returning cached insights for transcript {transcript_id}")
        return transcript.insights

    # Get transcription chat service for LLM access
    from ..main import transcription_chat_service
    if not transcription_chat_service:
        raise HTTPException(status_code=503, detail="Chat service not available")

    try:
        logger.main_logger.info(f"Generating insights for transcript {transcript_id}")
        start_time = time.time()

        # Generate insights using LLM
        insights = await transcription_chat_service.generate_response(
            user_message="",  # Not needed for insights
            context=transcript.full_text,
            conversation_history=[],
            quick_action_id="generate_insights"  # Special ID for insights generation
        )

        # Parse the insights (assuming structured markdown response)
        insights_data = {
            "summary": "",
            "keyPoints": [],
            "actionItems": [],
            "topics": [],
            "participants": transcript.speaker_labels or []
        }

        # Try to parse structured response
        try:
            import json
            insights_data = json.loads(insights)
        except:
            # If not JSON, use the text as summary
            insights_data["summary"] = insights

        # Cache the insights
        transcript.insights = insights_data
        db.commit()

        processing_time = time.time() - start_time
        logger.log_performance(
            operation="generate_insights",
            duration=processing_time,
            metadata={
                "transcript_id": transcript_id,
                "transcript_length": len(transcript.full_text)
            }
        )

        return insights_data

    except Exception as e:
        logger.log_error(e, {
            "operation": "generate_insights",
            "transcript_id": transcript_id
        })
        raise HTTPException(status_code=500, detail=f"Failed to generate insights: {str(e)}")


@router.get("/{transcript_id}/export")
async def export_transcript(
    transcript_id: str,
    format: str = "pdf",
    current_user=Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Export transcript to PDF format with full transcript, insights, and metadata.
    Supports RTL (Hebrew) text formatting.
    """
    from fastapi.responses import StreamingResponse
    from reportlab.lib.pagesizes import letter, A4
    from reportlab.lib import colors
    from reportlab.lib.units import inch
    from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, PageBreak
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.enums import TA_RIGHT, TA_CENTER
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from io import BytesIO
    from datetime import datetime
    import arabic_reshaper
    from bidi.algorithm import get_display

    if format != "pdf":
        raise HTTPException(status_code=400, detail="Only PDF format is currently supported")

    # Get transcript
    transcript = db.query(Transcript).filter(
        Transcript.id == transcript_id,
        Transcript.user_id == current_user.id
    ).first()

    if not transcript:
        raise HTTPException(status_code=404, detail="Transcript not found")

    # Helper function for RTL text
    def format_rtl(text):
        """Format text for RTL display (Hebrew/Arabic)"""
        if not text:
            return ""
        reshaped_text = arabic_reshaper.reshape(str(text))
        return get_display(reshaped_text)

    # Create PDF buffer
    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, rightMargin=72, leftMargin=72, topMargin=72, bottomMargin=18)

    # Container for PDF elements
    elements = []

    # Try to register Hebrew font (DejaVu Sans has good Hebrew support)
    # If font not available, will fall back to default
    try:
        # Note: In production, you'll need to include DejaVuSans.ttf in your deployment
        pdfmetrics.registerFont(TTFont('Hebrew', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'))
        hebrew_font = 'Hebrew'
    except:
        # Fallback to Helvetica (limited Hebrew support)
        hebrew_font = 'Helvetica'
        logger.main_logger.warning("Hebrew font not found, using Helvetica (limited RTL support)")

    # Define styles with RTL support
    styles = getSampleStyleSheet()

    title_style = ParagraphStyle(
        'HebrewTitle',
        parent=styles['Heading1'],
        fontName=hebrew_font,
        fontSize=24,
        alignment=TA_RIGHT,
        textColor=colors.HexColor('#0D9588'),
        spaceAfter=12
    )

    heading_style = ParagraphStyle(
        'HebrewHeading',
        parent=styles['Heading2'],
        fontName=hebrew_font,
        fontSize=16,
        alignment=TA_RIGHT,
        textColor=colors.HexColor('#0D9588'),
        spaceAfter=10
    )

    body_style = ParagraphStyle(
        'HebrewBody',
        parent=styles['BodyText'],
        fontName=hebrew_font,
        fontSize=11,
        alignment=TA_RIGHT,
        leading=16,
        rightIndent=0,
        leftIndent=0
    )

    # Title
    title_text = format_rtl(transcript.title or "תמליל")
    elements.append(Paragraph(title_text, title_style))
    elements.append(Spacer(1, 0.2*inch))

    # Metadata table
    metadata = [
        [format_rtl("תאריך:"), format_rtl(transcript.created_at.strftime("%d/%m/%Y %H:%M"))],
        [format_rtl("משך:"), format_rtl(f"{transcript.duration or 0:.0f} שניות")],
        [format_rtl("מספר דוברים:"), str(len(set([s.get('speaker_label', 'Unknown') for s in (transcript.segments or [])])))]
    ]

    metadata_table = Table(metadata, colWidths=[2*inch, 4*inch])
    metadata_table.setStyle(TableStyle([
        ('FONT', (0, 0), (-1, -1), hebrew_font, 10),
        ('ALIGN', (0, 0), (-1, -1), 'RIGHT'),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('TEXTCOLOR', (0, 0), (0, -1), colors.HexColor('#666666')),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#E5E5E6')),
        ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#F6F6F7')),
        ('PADDING', (0, 0), (-1, -1), 8),
    ]))
    elements.append(metadata_table)
    elements.append(Spacer(1, 0.4*inch))

    # Insights section (if available)
    if transcript.insights:
        elements.append(Paragraph(format_rtl("תובנות"), heading_style))
        elements.append(Spacer(1, 0.1*inch))

        # Summary
        if transcript.insights.get('summary'):
            elements.append(Paragraph(format_rtl("סיכום:"), body_style))
            elements.append(Paragraph(format_rtl(transcript.insights['summary']), body_style))
            elements.append(Spacer(1, 0.15*inch))

        # Key points
        if transcript.insights.get('keyPoints'):
            elements.append(Paragraph(format_rtl("נקודות מפתח:"), body_style))
            for point in transcript.insights['keyPoints']:
                elements.append(Paragraph(f"• {format_rtl(point)}", body_style))
            elements.append(Spacer(1, 0.15*inch))

        # Action items
        if transcript.insights.get('actionItems'):
            elements.append(Paragraph(format_rtl("פעולות מעקב:"), body_style))
            for item in transcript.insights['actionItems']:
                task_text = format_rtl(item.get('task', ''))
                assignee = format_rtl(item.get('assignee', ''))
                priority = format_rtl(item.get('priority', ''))
                elements.append(Paragraph(f"• {task_text} ({assignee} - {priority})", body_style))
            elements.append(Spacer(1, 0.15*inch))

        elements.append(PageBreak())

    # Full transcript
    elements.append(Paragraph(format_rtl("תמליל מלא"), heading_style))
    elements.append(Spacer(1, 0.2*inch))

    # Add transcript segments
    for segment in (transcript.segments or []):
        speaker = format_rtl(segment.get('speaker_label', 'Unknown'))
        start_time = segment.get('start', 0)
        text = format_rtl(segment.get('text', ''))

        # Format timestamp
        mins = int(start_time // 60)
        secs = int(start_time % 60)
        timestamp = f"[{mins:02d}:{secs:02d}]"

        # Create segment paragraph
        segment_text = f"<b>{speaker}</b> {timestamp}<br/>{text}"
        elements.append(Paragraph(segment_text, body_style))
        elements.append(Spacer(1, 0.1*inch))

    # Build PDF
    try:
        doc.build(elements)
        buffer.seek(0)

        # Return as downloadable file
        filename = f"transcript_{transcript_id}_{datetime.now().strftime('%Y%m%d')}.pdf"
        return StreamingResponse(
            buffer,
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename={filename}"}
        )
    except Exception as e:
        logger.log_error(e, {
            "operation": "export_pdf",
            "transcript_id": transcript_id
        })
        raise HTTPException(status_code=500, detail=f"Failed to generate PDF: {str(e)}")


@router.get("/health")
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
