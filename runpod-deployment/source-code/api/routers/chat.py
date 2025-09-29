from fastapi import APIRouter, HTTPException, Depends, UploadFile, File
from typing import List, Optional
import uuid
from datetime import datetime

from ..models import (
    SessionCreateRequest, SessionCreateResponse, ChatSession,
    ChatMessageRequest, ChatMessageResponse, ChatHistory,
    FileUploadResponse, MessageRole
)
from ..services import ChatSessionService, RAGService

router = APIRouter()

def get_chat_service() -> ChatSessionService:
    """Dependency to get chat session service"""
    from ..main import chat_service
    if chat_service is None:
        raise HTTPException(status_code=503, detail="Chat service not available")
    return chat_service

def get_rag_service() -> RAGService:
    """Dependency to get RAG service"""
    from ..main import rag_service
    if rag_service is None:
        raise HTTPException(status_code=503, detail="RAG service not available")
    return rag_service

# Session management endpoints
@router.post("/chat/sessions", response_model=SessionCreateResponse)
async def create_session(
    request: SessionCreateRequest,
    service: ChatSessionService = Depends(get_chat_service)
):
    """Create a new chat session"""
    try:
        session = service.create_session(
            name=request.name,
            description=request.description
        )
        
        return SessionCreateResponse(
            session_id=session.session_id,
            name=session.name,
            description=session.description,
            created_at=session.created_at
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to create session: {str(e)}"
        )

@router.get("/chat/sessions/{session_id}", response_model=ChatSession)
async def get_session(
    session_id: str,
    service: ChatSessionService = Depends(get_chat_service)
):
    """Get session information"""
    session = service.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    return session

@router.delete("/chat/sessions/{session_id}")
async def delete_session(
    session_id: str,
    service: ChatSessionService = Depends(get_chat_service)
):
    """Delete a chat session"""
    if not service.delete_session(session_id):
        raise HTTPException(status_code=404, detail="Session not found")
    
    return {"message": "Session deleted successfully"}

@router.get("/chat/sessions/{session_id}/history", response_model=ChatHistory)
async def get_session_history(
    session_id: str,
    service: ChatSessionService = Depends(get_chat_service)
):
    """Get conversation history for a session"""
    session = service.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    messages = service.get_messages(session_id)
    
    return ChatHistory(
        session_id=session_id,
        messages=messages,
        total_messages=len(messages)
    )

# Messaging endpoints
@router.post("/chat/{session_id}/message", response_model=ChatMessageResponse)
async def send_message(
    session_id: str,
    request: ChatMessageRequest,
    chat_service: ChatSessionService = Depends(get_chat_service),
    rag_service: RAGService = Depends(get_rag_service)
):
    """Send a message and get RAG-enhanced response"""
    try:
        # Check if session exists
        session = chat_service.get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        # Add user message to session
        user_message = chat_service.add_message(
            session_id=session_id,
            role=MessageRole.USER,
            content=request.content
        )
        
        if not user_message:
            raise HTTPException(status_code=500, detail="Failed to save user message")
        
        # Get conversation history
        conversation_history = chat_service.get_messages(session_id)[:-1]  # Exclude the message we just added

        # Generate response based on include_context flag
        if request.include_context:
            # Generate response using RAG
            response = await rag_service.generate_response(
                session_id=session_id,
                user_message=request.content,
                conversation_history=conversation_history
            )

            # Save assistant response to session
            assistant_message = chat_service.add_message(
                session_id=session_id,
                role=MessageRole.ASSISTANT,
                content=response.content,
                context_used=response.context_sources
            )

            return response
        else:
            # Call LLM directly without RAG context
            import time
            start_time = time.time()

            # Construct simple prompt with conversation history
            prompt = rag_service._construct_prompt(request.content, "", conversation_history)
            llm_response = await rag_service._call_vllm(prompt)

            processing_time = time.time() - start_time

            response = ChatMessageResponse(
                message_id=str(uuid.uuid4()),
                content=llm_response,
                timestamp=datetime.now(),
                context_sources=None,
                processing_time=processing_time
            )

            # Save assistant response to session
            assistant_message = chat_service.add_message(
                session_id=session_id,
                role=MessageRole.ASSISTANT,
                content=response.content,
                context_used=None
            )

            return response
            
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to process message: {str(e)}"
        )

# File upload endpoint
@router.post("/chat/{session_id}/upload", response_model=FileUploadResponse)
async def upload_file(
    session_id: str,
    file: UploadFile = File(...),
    chat_service: ChatSessionService = Depends(get_chat_service)
):
    """Upload a file to a chat session for analysis"""
    try:
        # Check if session exists
        session = chat_service.get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        # Validate file
        if not file.filename:
            raise HTTPException(status_code=400, detail="No filename provided")
        
        # Read file content
        content = await file.read()
        file_size = len(content)
        
        # TODO: Process file with DotsOCR and add to session context
        # For now, return a placeholder response
        
        file_id = str(uuid.uuid4())
        
        return FileUploadResponse(
            file_id=file_id,
            filename=file.filename,
            file_size=file_size,
            upload_time=session.last_activity,
            processing_status="uploaded",
            message="File uploaded successfully. Processing integration with RAG system is pending implementation."
        )
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"File upload failed: {str(e)}"
        )

@router.get("/chat/health")
async def chat_health_check():
    """Health check for chat functionality"""
    try:
        from ..main import chat_service, rag_service
        
        services_status = {
            "chat_service": chat_service is not None,
            "rag_service": rag_service is not None
        }
        
        if not all(services_status.values()):
            raise HTTPException(
                status_code=503, 
                detail=f"Some chat services not initialized: {services_status}"
            )
        
        return {
            "status": "healthy",
            "service": "chat",
            "message": "Chat services are operational",
            "services": services_status
        }
    except Exception as e:
        raise HTTPException(
            status_code=503,
            detail=f"Chat service unhealthy: {str(e)}"
        )