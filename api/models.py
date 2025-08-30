from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from datetime import datetime
from enum import Enum

# Health and system models
class HealthResponse(BaseModel):
    status: str
    message: str
    version: str

# File search models
class FileSearchRequest(BaseModel):
    query: str
    limit: Optional[int] = 10
    file_types: Optional[List[str]] = None

class FileResult(BaseModel):
    file_path: str
    filename: str
    relevance_score: float
    file_type: str
    file_size: Optional[int] = None
    last_modified: Optional[datetime] = None
    summary: Optional[str] = None

class FileSearchResponse(BaseModel):
    query: str
    results: List[FileResult]
    total_results: int
    processing_time: float

# Chat session models
class SessionCreateRequest(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None

class SessionCreateResponse(BaseModel):
    session_id: str
    name: Optional[str] = None
    description: Optional[str] = None
    created_at: datetime

class ChatSession(BaseModel):
    session_id: str
    name: Optional[str] = None
    description: Optional[str] = None
    created_at: datetime
    last_activity: datetime
    message_count: int

class MessageRole(str, Enum):
    USER = "user"
    ASSISTANT = "assistant"
    SYSTEM = "system"

class ChatMessage(BaseModel):
    message_id: str
    session_id: str
    role: MessageRole
    content: str
    timestamp: datetime
    context_used: Optional[List[str]] = None  # Files/sources used for RAG
    metadata: Optional[Dict[str, Any]] = None

class ChatMessageRequest(BaseModel):
    content: str
    include_context: bool = True  # Whether to use RAG for response

class ChatMessageResponse(BaseModel):
    message_id: str
    content: str
    timestamp: datetime
    context_sources: Optional[List[str]] = None  # Sources used for RAG response
    processing_time: float

class ChatHistory(BaseModel):
    session_id: str
    messages: List[ChatMessage]
    total_messages: int

# File upload models
class FileUploadResponse(BaseModel):
    file_id: str
    filename: str
    file_size: int
    upload_time: datetime
    processing_status: str
    message: str