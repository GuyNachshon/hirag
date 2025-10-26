"""
Search endpoints for finding transcripts across all user data.
"""

from fastapi import APIRouter, HTTPException, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import or_, and_, func
from typing import Optional, List
from datetime import datetime

from ..database import get_db, Transcript, Folder, TranscriptSegment
from ..dependencies import get_current_user
from ..models import TranscriptListItem, TranscriptListResponse
from ..logger import get_logger
import json

router = APIRouter(prefix="/api/search", tags=["Search"])
logger = get_logger()


@router.get("/transcripts", response_model=TranscriptListResponse)
async def search_transcripts(
    q: str = Query(..., min_length=1, description="Search query"),
    folder_id: Optional[str] = Query(None, description="Filter by folder ID"),
    tags: Optional[str] = Query(None, description="Filter by tags (comma-separated)"),
    date_from: Optional[datetime] = Query(None, description="Filter from date"),
    date_to: Optional[datetime] = Query(None, description="Filter to date"),
    limit: int = Query(20, ge=1, le=100, description="Max results"),
    offset: int = Query(0, ge=0, description="Offset for pagination"),
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Search transcripts by title, content, and speakers.

    Searches across:
    - Transcript titles
    - Full transcript text
    - Speaker names in segments

    Requires authentication.

    Args:
        q: Search query string
        folder_id: Optional folder filter
        tags: Optional comma-separated tag filter
        date_from: Optional start date filter
        date_to: Optional end date filter
        limit: Maximum number of results (1-100)
        offset: Pagination offset
        current_user: Authenticated user
        db: Database session

    Returns:
        TranscriptListResponse with matching transcripts
    """
    logger.main_logger.info(
        f"Search query '{q}' by user: {current_user.username} "
        f"(folder={folder_id}, tags={tags}, limit={limit}, offset={offset})"
    )

    # Build base query
    query = (
        db.query(Transcript, Folder.name.label('folder_name'))
        .outerjoin(Folder, Transcript.folder_id == Folder.id)
        .filter(Transcript.user_id == current_user.id)
    )

    # Search filter - search in title and full_text
    search_term = f"%{q}%"
    query = query.filter(
        or_(
            Transcript.title.ilike(search_term),
            Transcript.full_text.ilike(search_term)
        )
    )

    # Folder filter
    if folder_id:
        query = query.filter(Transcript.folder_id == folder_id)

    # Tags filter
    if tags:
        tag_list = [t.strip() for t in tags.split(',') if t.strip()]
        if tag_list:
            # Check if any of the provided tags exist in the transcript's tags JSON
            tag_conditions = []
            for tag in tag_list:
                tag_conditions.append(Transcript.tags.ilike(f'%"{tag}"%'))
            query = query.filter(or_(*tag_conditions))

    # Date range filters
    if date_from:
        query = query.filter(Transcript.created_at >= date_from)
    if date_to:
        query = query.filter(Transcript.created_at <= date_to)

    # Get total count before pagination
    total_count = query.count()

    # Apply pagination and ordering
    query = query.order_by(Transcript.created_at.desc())
    query = query.offset(offset).limit(limit)

    results = query.all()

    # Build response
    transcript_items = []
    for transcript, folder_name in results:
        # Parse tags from JSON string
        tags_list = []
        if transcript.tags:
            try:
                tags_list = json.loads(transcript.tags)
            except json.JSONDecodeError:
                tags_list = []

        # Get unique speakers from segments
        speakers = []
        if transcript.status == "completed":
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

    logger.main_logger.info(
        f"Search returned {len(transcript_items)}/{total_count} results for query '{q}'"
    )

    return TranscriptListResponse(
        transcripts=transcript_items,
        total_count=total_count
    )


@router.get("/speakers")
async def search_speakers(
    q: str = Query(..., min_length=1, description="Speaker name search query"),
    limit: int = Query(10, ge=1, le=50, description="Max results"),
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Search for unique speaker names across user's transcripts.

    Useful for autocomplete/suggestions when filtering by speaker.

    Requires authentication.

    Args:
        q: Search query for speaker name
        limit: Maximum number of results
        current_user: Authenticated user
        db: Database session

    Returns:
        List of matching speaker names
    """
    logger.main_logger.info(
        f"Speaker search query '{q}' by user: {current_user.username}"
    )

    # Get transcripts belonging to user
    user_transcript_ids = (
        db.query(Transcript.id)
        .filter(Transcript.user_id == current_user.id)
        .subquery()
    )

    # Search for speakers in those transcripts
    search_term = f"%{q}%"
    speakers = (
        db.query(TranscriptSegment.speaker)
        .filter(TranscriptSegment.transcript_id.in_(user_transcript_ids))
        .filter(TranscriptSegment.speaker.ilike(search_term))
        .filter(TranscriptSegment.speaker.isnot(None))
        .distinct()
        .limit(limit)
        .all()
    )

    speaker_names = [s[0] for s in speakers if s[0]]

    logger.main_logger.info(
        f"Found {len(speaker_names)} matching speakers for query '{q}'"
    )

    return {
        "speakers": speaker_names,
        "total_count": len(speaker_names)
    }
