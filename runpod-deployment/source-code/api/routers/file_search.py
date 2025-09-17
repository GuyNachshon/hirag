from fastapi import APIRouter, HTTPException, Depends, Query
from typing import Optional, List
import time

from ..models import FileSearchRequest, FileSearchResponse
from ..services import FileSearchService

router = APIRouter()

def get_file_search_service() -> FileSearchService:
    """Dependency to get file search service"""
    from ..main import file_search_service
    if file_search_service is None:
        raise HTTPException(status_code=503, detail="File search service not available")
    return file_search_service

@router.get("/search/files", response_model=FileSearchResponse)
async def search_files(
    q: str = Query(..., description="Search query"),
    limit: int = Query(10, ge=1, le=50, description="Maximum number of results"),
    file_types: Optional[str] = Query(None, description="Comma-separated file extensions (e.g., .pdf,.txt)"),
    service: FileSearchService = Depends(get_file_search_service)
):
    """
    Search for files using semantic search
    
    - **q**: The search query
    - **limit**: Maximum number of results (1-50)
    - **file_types**: Optional comma-separated file extensions to filter by
    """
    try:
        # Parse file types if provided
        parsed_file_types = None
        if file_types:
            parsed_file_types = [ft.strip().lower() for ft in file_types.split(",")]
            # Ensure extensions start with dot
            parsed_file_types = [ft if ft.startswith('.') else f'.{ft}' for ft in parsed_file_types]
        
        # Perform search
        results = await service.search_files(
            query=q,
            limit=limit,
            file_types=parsed_file_types
        )
        
        return results
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Search failed: {str(e)}"
        )

@router.get("/search/health")
async def search_health_check():
    """Health check for file search functionality"""
    try:
        from ..main import file_search_service
        if file_search_service is None:
            raise HTTPException(status_code=503, detail="File search service not initialized")
        
        return {
            "status": "healthy",
            "service": "file_search",
            "message": "File search service is operational"
        }
    except Exception as e:
        raise HTTPException(
            status_code=503,
            detail=f"File search service unhealthy: {str(e)}"
        )