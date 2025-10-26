"""
Transcription Chat endpoints with adaptive context strategy.
Provides chat functionality specifically for transcriptions using direct DB queries
and optional embedding-based search.
"""

from fastapi import APIRouter, HTTPException, Depends
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
import time
import uuid
import json
from datetime import datetime

from ..database import get_db
from ..dependencies import get_current_user
from ..models import (
    TranscriptionChatSessionRequest,
    TranscriptionChatSessionResponse,
    TranscriptionChatMessageRequest,
    TranscriptionChatMessageResponse,
    TranscriptionChatHistory,
    TranscriptionChatMessage,
    SegmentReference
)
from ..services import TranscriptionChatService
from ..logger import get_logger

router = APIRouter(prefix="/api/transcription/chat", tags=["Transcription Chat"])
logger = get_logger()


def get_transcription_chat_service() -> TranscriptionChatService:
    """Dependency to get transcription chat service"""
    from ..main import transcription_chat_service
    if transcription_chat_service is None:
        raise HTTPException(
            status_code=503,
            detail="Transcription chat service not available"
        )
    return transcription_chat_service


@router.post("/sessions", response_model=TranscriptionChatSessionResponse)
async def create_session(
    request: TranscriptionChatSessionRequest,
    current_user=Depends(get_current_user),
    service: TranscriptionChatService = Depends(get_transcription_chat_service)
):
    """
    Create a new transcription chat session.

    The session is associated with a specific context (folder or transcript)
    and all messages in this session will use that context.
    """
    try:
        session = service.create_session(
            context_type=request.context_type,
            context_id=request.context_id,
            name=request.name
        )

        return TranscriptionChatSessionResponse(
            session_id=session["session_id"],
            context_type=session["context_type"],
            context_id=session["context_id"],
            created_at=session["created_at"]
        )
    except Exception as e:
        logger.log_error(e, {
            "operation": "create_transcription_chat_session",
            "user_id": current_user.id,
            "context_type": request.context_type,
            "context_id": request.context_id
        })
        raise HTTPException(
            status_code=500,
            detail=f"Failed to create chat session: {str(e)}"
        )


@router.post("/{session_id}/message", response_model=TranscriptionChatMessageResponse)
async def send_message(
    session_id: str,
    request: TranscriptionChatMessageRequest,
    current_user=Depends(get_current_user),
    db: Session = Depends(get_db),
    service: TranscriptionChatService = Depends(get_transcription_chat_service)
):
    """
    Send a message and get an AI response with transcription context.

    The system automatically chooses the best context strategy:
    - Small transcripts/folders: Full context (most accurate)
    - Large transcripts/folders: Embedding search (efficient)
    """
    start_time = time.time()

    try:
        # Verify session exists
        session = service.get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")

        logger.main_logger.info(
            f"Processing chat message for session {session_id}: "
            f"{request.content[:50]}..."
        )

        # Add user message to history
        service.add_message(session_id, "user", request.content)

        # Get adaptive context
        context_result = await service.get_adaptive_context(
            context_type=request.context_type,
            context_id=request.context_id,
            user_message=request.content,
            user_id=current_user.id,
            db=db
        )

        # Get conversation history
        conversation_history = service.get_messages(session_id)[:-1]  # Exclude the message we just added

        # Generate response
        response_content = await service.generate_response(
            user_message=request.content,
            context=context_result["context"],
            conversation_history=conversation_history,
            quick_action_id=request.quick_action_id
        )

        # Add assistant message to history
        service.add_message(
            session_id,
            "assistant",
            response_content,
            strategy_used=context_result["strategy"],
            sources=context_result["sources"]
        )

        processing_time = time.time() - start_time

        # Log performance
        logger.log_performance(
            operation="transcription_chat_message",
            duration=processing_time,
            metadata={
                "session_id": session_id,
                "strategy_used": context_result["strategy"],
                "sources_count": len(context_result["sources"]),
                "message_length": len(request.content),
                "response_length": len(response_content)
            }
        )

        # Build segment references if available
        segment_references = None
        if context_result.get("segment_references"):
            segment_references = [
                SegmentReference(**ref)
                for ref in context_result["segment_references"]
            ]

        return TranscriptionChatMessageResponse(
            message_id=str(uuid.uuid4()),
            content=response_content,
            timestamp=datetime.now(),
            strategy_used=context_result["strategy"],
            sources=context_result["sources"],
            segment_references=segment_references,
            processing_time=processing_time
        )

    except ValueError as e:
        # User error (transcript not found, etc.)
        raise HTTPException(status_code=400, detail=str(e))

    except Exception as e:
        import traceback
        processing_time = time.time() - start_time
        tb = traceback.format_exc()
        logger.main_logger.error(f"Chat message error: {e}")
        logger.main_logger.error(f"Traceback: {tb}")
        logger.log_error(e, {
            "operation": "transcription_chat_message",
            "session_id": session_id,
            "user_id": current_user.id,
            "processing_time": processing_time,
            "traceback": tb
        })
        raise HTTPException(
            status_code=500,
            detail=f"Failed to process message: {str(e)}"
        )


@router.post("/{session_id}/message/stream")
async def send_message_stream(
    session_id: str,
    request: TranscriptionChatMessageRequest,
    current_user=Depends(get_current_user),
    db: Session = Depends(get_db),
    service: TranscriptionChatService = Depends(get_transcription_chat_service)
):
    """
    Send a message and stream the AI response in real-time.
    Returns Server-Sent Events (SSE) stream.
    """

    async def generate_stream():
        start_time = time.time()
        full_response = ""

        try:
            # Verify session exists
            session = service.get_session(session_id)
            if not session:
                yield f"data: {json.dumps({'error': 'Session not found'})}\n\n"
                return

            logger.main_logger.info(
                f"Processing streaming chat message for session {session_id}: "
                f"{request.content[:50]}..."
            )

            # Add user message to history
            service.add_message(session_id, "user", request.content)

            # Send initial status
            yield f"data: {json.dumps({'type': 'status', 'status': 'processing'})}\n\n"

            # Get adaptive context
            context_result = await service.get_adaptive_context(
                context_type=request.context_type,
                context_id=request.context_id,
                user_message=request.content,
                user_id=current_user.id,
                db=db
            )

            # Send context info
            yield f"data: {json.dumps({'type': 'context', 'strategy': context_result['strategy']})}\n\n"

            # Get conversation history
            conversation_history = service.get_messages(session_id)[:-1]

            # Generate streaming response
            async for chunk in service.generate_response_stream(
                user_message=request.content,
                context=context_result["context"],
                conversation_history=conversation_history,
                quick_action_id=request.quick_action_id
            ):
                full_response += chunk
                yield f"data: {json.dumps({'type': 'content', 'content': chunk})}\n\n"

            # Add assistant message to history
            service.add_message(
                session_id,
                "assistant",
                full_response,
                strategy_used=context_result["strategy"],
                sources=context_result["sources"]
            )

            processing_time = time.time() - start_time

            # Send completion
            yield f"data: {json.dumps({'type': 'done', 'processing_time': processing_time, 'sources': context_result['sources']})}\n\n"

            # Log performance
            logger.log_performance(
                operation="transcription_chat_message_stream",
                duration=processing_time,
                metadata={
                    "session_id": session_id,
                    "strategy_used": context_result["strategy"],
                    "sources_count": len(context_result["sources"]),
                    "message_length": len(request.content),
                    "response_length": len(full_response)
                }
            )

        except Exception as e:
            import traceback
            tb = traceback.format_exc()
            logger.main_logger.error(f"Streaming chat error: {e}")
            logger.main_logger.error(f"Traceback: {tb}")
            yield f"data: {json.dumps({'type': 'error', 'error': str(e)})}\n\n"

    return StreamingResponse(
        generate_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"  # Disable nginx buffering
        }
    )


@router.get("/{session_id}/history", response_model=TranscriptionChatHistory)
async def get_history(
    session_id: str,
    current_user=Depends(get_current_user),
    service: TranscriptionChatService = Depends(get_transcription_chat_service)
):
    """
    Get conversation history for a session.
    """
    try:
        session = service.get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")

        messages = service.get_messages(session_id)

        chat_messages = [
            TranscriptionChatMessage(
                message_id=msg["message_id"],
                role=msg["role"],
                content=msg["content"],
                timestamp=msg["timestamp"],
                strategy_used=msg.get("strategy_used"),
                sources=msg.get("sources")
            )
            for msg in messages
        ]

        return TranscriptionChatHistory(
            session_id=session_id,
            messages=chat_messages,
            total_messages=len(chat_messages)
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.log_error(e, {
            "operation": "get_transcription_chat_history",
            "session_id": session_id
        })
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get history: {str(e)}"
        )


@router.delete("/{session_id}")
async def delete_session(
    session_id: str,
    current_user=Depends(get_current_user),
    service: TranscriptionChatService = Depends(get_transcription_chat_service)
):
    """
    Delete a chat session and its history.
    """
    try:
        if not service.delete_session(session_id):
            raise HTTPException(status_code=404, detail="Session not found")

        logger.main_logger.info(f"Deleted chat session: {session_id}")

        return {"message": "Session deleted successfully"}

    except HTTPException:
        raise
    except Exception as e:
        logger.log_error(e, {
            "operation": "delete_transcription_chat_session",
            "session_id": session_id
        })
        raise HTTPException(
            status_code=500,
            detail=f"Failed to delete session: {str(e)}"
        )


@router.get("/health")
async def chat_health_check():
    """Health check for transcription chat functionality"""
    try:
        from ..main import transcription_chat_service

        if transcription_chat_service is None:
            raise HTTPException(
                status_code=503,
                detail="Transcription chat service not initialized"
            )

        return {
            "status": "healthy",
            "service": "transcription_chat",
            "message": "Transcription chat service is operational"
        }
    except Exception as e:
        raise HTTPException(
            status_code=503,
            detail=f"Transcription chat service unhealthy: {str(e)}"
        )
