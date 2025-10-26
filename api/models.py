from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
from datetime import datetime
from enum import Enum

# Health and system models
class HealthResponse(BaseModel):
    status: str
    message: str
    version: str

# ===================================
# Authentication Models
# ===================================

class RegisterRequest(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=6, max_length=128)

class LoginRequest(BaseModel):
    username: str
    password: str

class AuthResponse(BaseModel):
    user_id: str
    username: str
    token: str
    expires_at: datetime

class UserResponse(BaseModel):
    user_id: str
    username: str
    created_at: datetime

class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(..., min_length=6, max_length=128)

# ===================================
# Folder Models
# ===================================

class FolderCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)

class FolderUpdate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)

class FolderResponse(BaseModel):
    id: str
    name: str
    transcript_count: int
    created_at: datetime
    updated_at: datetime

class FolderListResponse(BaseModel):
    folders: List[FolderResponse]
    total_count: int

# ===================================
# Transcript Models (Enhanced)
# ===================================

class TranscriptStatus(str, Enum):
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"

class TranscriptUploadResponse(BaseModel):
    transcript_id: str
    status: TranscriptStatus
    message: str

# Audio transcription segment model (needed by TranscriptDetailResponse)
class TranscriptionSegment(BaseModel):
    start: float
    end: float
    text: str
    speaker: Optional[str] = None  # Speaker label when diarization is enabled

class TranscriptStatusResponse(BaseModel):
    transcript_id: str
    status: TranscriptStatus
    progress_percent: int
    error_message: Optional[str] = None

class TranscriptListItem(BaseModel):
    id: str
    title: str
    duration: Optional[float] = None
    status: TranscriptStatus
    folder_id: Optional[str] = None
    folder_name: Optional[str] = None
    tags: List[str] = []
    speakers: List[str] = []
    language: str
    created_at: datetime
    updated_at: datetime
    completed_at: Optional[datetime] = None

class TranscriptListResponse(BaseModel):
    transcripts: List[TranscriptListItem]
    total_count: int

class TranscriptUpdateRequest(BaseModel):
    title: Optional[str] = None
    folder_id: Optional[str] = None
    tags: Optional[List[str]] = None

class TranscriptDetailResponse(BaseModel):
    id: str
    title: str
    duration: Optional[float] = None
    status: TranscriptStatus
    folder_id: Optional[str] = None
    folder_name: Optional[str] = None
    tags: List[str] = []
    language: str
    full_text: Optional[str] = None
    language_probability: Optional[float] = None
    diarization_enabled: bool
    num_speakers: Optional[int] = None
    speaker_names: Optional[Dict[str, str]] = None
    segments: List[TranscriptionSegment]
    created_at: datetime
    updated_at: datetime
    completed_at: Optional[datetime] = None

class ExportFormat(str, Enum):
    TXT = "txt"
    PDF = "pdf"
    JSON = "json"

# ===================================
# Search Models
# ===================================

class TranscriptSearchRequest(BaseModel):
    q: str = Field(..., min_length=1)
    folder_id: Optional[str] = None
    tags: Optional[List[str]] = None
    date_from: Optional[datetime] = None
    date_to: Optional[datetime] = None
    limit: int = Field(default=20, ge=1, le=100)
    offset: int = Field(default=0, ge=0)

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

# Audio transcription models
class TranscriptionResponse(BaseModel):
    success: bool
    text: str
    language: str
    language_probability: float
    duration: float
    segments: List[TranscriptionSegment]
    diarization_enabled: Optional[bool] = True  # Whether diarization was used (enabled by default)
    speakers: Optional[List[str]] = None  # List of unique speakers when diarization is enabled
    num_speakers: Optional[int] = None  # Number of speakers detected
    speaker_names: Optional[Dict[str, str]] = None  # Mapping of SPEAKER_XX to identified names (e.g., {"SPEAKER_00": "Sarah", "SPEAKER_01": "David"})
    speaker_identification_attempted: Optional[bool] = False  # Whether LLM-based speaker identification was attempted
    message: Optional[str] = None

class TranscriptionErrorResponse(BaseModel):
    success: bool = False
    error: str
    message: str

# ===================================
# Quick Actions Models
# ===================================

class QuickAction(BaseModel):
    id: str
    label: str
    icon: str
    prompt_template: str
    description: Optional[str] = None

class QuickActionsResponse(BaseModel):
    context: str  # 'folder' or 'transcript'
    actions: List[QuickAction]

# ===================================
# Transcription Chat Models
# ===================================

class TranscriptionChatSessionRequest(BaseModel):
    context_type: str  # 'folder' or 'transcript'
    context_id: str  # folder_id or transcript_id
    name: Optional[str] = None

class TranscriptionChatSessionResponse(BaseModel):
    session_id: str
    context_type: str
    context_id: str
    created_at: datetime

class SegmentReference(BaseModel):
    """Reference to a specific segment used in response"""
    transcript_id: str
    transcript_title: str
    segment_id: str
    speaker: Optional[str]
    start_time: float
    end_time: float
    text: str

class TranscriptionChatMessageRequest(BaseModel):
    content: str
    context_type: str  # 'folder' or 'transcript'
    context_id: str  # folder_id or transcript_id
    quick_action_id: Optional[str] = None
    include_sources: bool = True

class TranscriptionChatMessageResponse(BaseModel):
    message_id: str
    content: str
    timestamp: datetime
    strategy_used: str  # 'full_context' or 'embedding_search'
    sources: List[str]  # transcript IDs used
    segment_references: Optional[List[SegmentReference]] = None  # If embedding search used
    processing_time: float

class TranscriptionChatMessage(BaseModel):
    message_id: str
    role: str  # 'user' or 'assistant'
    content: str
    timestamp: datetime
    strategy_used: Optional[str] = None
    sources: Optional[List[str]] = None

class TranscriptionChatHistory(BaseModel):
    session_id: str
    messages: List[TranscriptionChatMessage]
    total_messages: int