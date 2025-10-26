"""
Folder management endpoints for organizing transcripts.
"""

from typing import Optional
from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.orm import Session
from sqlalchemy import func

from ..database import get_db, Folder, Transcript
from ..dependencies import get_current_user
from ..models import (
    FolderCreate,
    FolderUpdate,
    FolderResponse,
    FolderListResponse
)
from ..logger import get_logger

router = APIRouter(prefix="/api/folders", tags=["Folders"])
logger = get_logger()


@router.get("", response_model=FolderListResponse)
async def list_folders(
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    List all folders for the current user with transcript counts.

    Requires authentication.

    Returns:
        FolderListResponse with list of folders and counts
    """
    logger.main_logger.info(f"Listing folders for user: {current_user.username}")

    # Query folders with transcript counts
    folders_with_counts = (
        db.query(
            Folder,
            func.count(Transcript.id).label('transcript_count')
        )
        .outerjoin(Transcript, Folder.id == Transcript.folder_id)
        .filter(Folder.user_id == current_user.id)
        .group_by(Folder.id)
        .order_by(Folder.created_at.desc())
        .all()
    )

    folder_responses = [
        FolderResponse(
            id=folder.id,
            name=folder.name,
            transcript_count=count,
            created_at=folder.created_at,
            updated_at=folder.updated_at
        )
        for folder, count in folders_with_counts
    ]

    logger.main_logger.info(f"Found {len(folder_responses)} folders for user: {current_user.username}")

    return FolderListResponse(
        folders=folder_responses,
        total_count=len(folder_responses)
    )


@router.post("", response_model=FolderResponse)
async def create_folder(
    request: FolderCreate,
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Create a new folder.

    Requires authentication.

    Args:
        request: Folder creation details (name)
        current_user: Authenticated user
        db: Database session

    Returns:
        FolderResponse with created folder details

    Raises:
        HTTPException: 400 if folder name already exists for this user
    """
    logger.main_logger.info(f"Creating folder '{request.name}' for user: {current_user.username}")

    # Check if folder with same name already exists for this user
    existing_folder = (
        db.query(Folder)
        .filter(Folder.user_id == current_user.id)
        .filter(Folder.name == request.name)
        .first()
    )

    if existing_folder:
        logger.main_logger.warning(
            f"Folder name '{request.name}' already exists for user: {current_user.username}"
        )
        raise HTTPException(
            status_code=400,
            detail=f"Folder with name '{request.name}' already exists"
        )

    # Create new folder
    folder = Folder(
        user_id=current_user.id,
        name=request.name
    )

    db.add(folder)
    db.commit()
    db.refresh(folder)

    logger.main_logger.info(f"Folder created: {folder.name} (ID: {folder.id})")

    return FolderResponse(
        id=folder.id,
        name=folder.name,
        transcript_count=0,
        created_at=folder.created_at,
        updated_at=folder.updated_at
    )


@router.get("/{folder_id}", response_model=FolderResponse)
async def get_folder(
    folder_id: str,
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get a specific folder with transcript count.

    Requires authentication.

    Args:
        folder_id: Folder ID
        current_user: Authenticated user
        db: Database session

    Returns:
        FolderResponse with folder details

    Raises:
        HTTPException: 404 if folder not found or doesn't belong to user
    """
    # Query folder with transcript count
    result = (
        db.query(
            Folder,
            func.count(Transcript.id).label('transcript_count')
        )
        .outerjoin(Transcript, Folder.id == Transcript.folder_id)
        .filter(Folder.id == folder_id)
        .filter(Folder.user_id == current_user.id)
        .group_by(Folder.id)
        .first()
    )

    if not result:
        logger.main_logger.warning(
            f"Folder {folder_id} not found for user: {current_user.username}"
        )
        raise HTTPException(status_code=404, detail="Folder not found")

    folder, count = result

    return FolderResponse(
        id=folder.id,
        name=folder.name,
        transcript_count=count,
        created_at=folder.created_at,
        updated_at=folder.updated_at
    )


@router.patch("/{folder_id}", response_model=FolderResponse)
async def update_folder(
    folder_id: str,
    request: FolderUpdate,
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Update folder name.

    Requires authentication.

    Args:
        folder_id: Folder ID
        request: Updated folder details (name)
        current_user: Authenticated user
        db: Database session

    Returns:
        FolderResponse with updated folder

    Raises:
        HTTPException: 404 if folder not found
        HTTPException: 400 if new name already exists
    """
    logger.main_logger.info(
        f"Updating folder {folder_id} to name '{request.name}' for user: {current_user.username}"
    )

    # Get folder
    folder = (
        db.query(Folder)
        .filter(Folder.id == folder_id)
        .filter(Folder.user_id == current_user.id)
        .first()
    )

    if not folder:
        logger.main_logger.warning(
            f"Folder {folder_id} not found for user: {current_user.username}"
        )
        raise HTTPException(status_code=404, detail="Folder not found")

    # Check if new name conflicts with existing folder
    existing_folder = (
        db.query(Folder)
        .filter(Folder.user_id == current_user.id)
        .filter(Folder.name == request.name)
        .filter(Folder.id != folder_id)
        .first()
    )

    if existing_folder:
        logger.main_logger.warning(
            f"Folder name '{request.name}' already exists for user: {current_user.username}"
        )
        raise HTTPException(
            status_code=400,
            detail=f"Folder with name '{request.name}' already exists"
        )

    # Update folder
    folder.name = request.name
    db.commit()
    db.refresh(folder)

    # Get transcript count
    count = db.query(Transcript).filter(Transcript.folder_id == folder_id).count()

    logger.main_logger.info(f"Folder updated: {folder.name} (ID: {folder.id})")

    return FolderResponse(
        id=folder.id,
        name=folder.name,
        transcript_count=count,
        created_at=folder.created_at,
        updated_at=folder.updated_at
    )


@router.delete("/{folder_id}")
async def delete_folder(
    folder_id: str,
    move_to: Optional[str] = None,
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Delete a folder.

    Requires authentication.

    Args:
        folder_id: Folder ID to delete
        move_to: Optional folder ID to move transcripts to (null = unassign)
        current_user: Authenticated user
        db: Database session

    Returns:
        Success message with count of affected transcripts

    Raises:
        HTTPException: 404 if folder not found
        HTTPException: 400 if move_to folder not found
    """
    logger.main_logger.info(
        f"Deleting folder {folder_id} for user: {current_user.username}"
    )

    # Get folder
    folder = (
        db.query(Folder)
        .filter(Folder.id == folder_id)
        .filter(Folder.user_id == current_user.id)
        .first()
    )

    if not folder:
        logger.main_logger.warning(
            f"Folder {folder_id} not found for user: {current_user.username}"
        )
        raise HTTPException(status_code=404, detail="Folder not found")

    # Count transcripts in folder
    transcript_count = db.query(Transcript).filter(Transcript.folder_id == folder_id).count()

    # If move_to specified, validate target folder
    if move_to is not None:
        target_folder = (
            db.query(Folder)
            .filter(Folder.id == move_to)
            .filter(Folder.user_id == current_user.id)
            .first()
        )

        if not target_folder:
            logger.main_logger.warning(
                f"Target folder {move_to} not found for user: {current_user.username}"
            )
            raise HTTPException(status_code=400, detail="Target folder not found")

        # Move transcripts to target folder
        db.query(Transcript).filter(Transcript.folder_id == folder_id).update(
            {Transcript.folder_id: move_to}
        )
        logger.main_logger.info(
            f"Moved {transcript_count} transcripts from folder {folder_id} to {move_to}"
        )
    else:
        # Unassign transcripts (set folder_id to None)
        db.query(Transcript).filter(Transcript.folder_id == folder_id).update(
            {Transcript.folder_id: None}
        )
        logger.main_logger.info(
            f"Unassigned {transcript_count} transcripts from folder {folder_id}"
        )

    # Delete folder
    db.delete(folder)
    db.commit()

    logger.main_logger.info(f"Folder deleted: {folder.name} (ID: {folder.id})")

    return {
        "message": f"Folder deleted successfully",
        "transcripts_affected": transcript_count,
        "moved_to": move_to
    }
