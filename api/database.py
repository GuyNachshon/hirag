"""
Database models and configuration for the transcription system.
Uses SQLAlchemy with SQLite for offline/air-gapped deployment.
"""

from typing import Optional
from sqlalchemy import create_engine, Column, String, Integer, Float, DateTime, ForeignKey, Text, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship
from datetime import datetime, timedelta
import uuid
import os
from pathlib import Path

# Database configuration
DATABASE_DIR = Path(os.getenv("DATABASE_DIR", "./data"))
DATABASE_DIR.mkdir(parents=True, exist_ok=True)
DATABASE_URL = os.getenv("DATABASE_URL", f"sqlite:///{DATABASE_DIR}/transcriptions.db")

# Create engine and session
engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False} if "sqlite" in DATABASE_URL else {},
    echo=False  # Set to True for SQL debugging
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


# Dependency to get DB session
def get_db():
    """Get database session for dependency injection"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# Models

class User(Base):
    """User accounts for authentication"""
    __tablename__ = "users"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    username = Column(String, unique=True, nullable=False, index=True)
    hashed_password = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    last_login = Column(DateTime, nullable=True)

    # Relationships
    folders = relationship("Folder", back_populates="user", cascade="all, delete-orphan")
    transcripts = relationship("Transcript", back_populates="user", cascade="all, delete-orphan")
    sessions = relationship("Session", back_populates="user", cascade="all, delete-orphan")


class Session(Base):
    """User session tokens for authentication"""
    __tablename__ = "sessions"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    token = Column(String, unique=True, nullable=False, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    expires_at = Column(DateTime, nullable=False)

    # Relationships
    user = relationship("User", back_populates="sessions")

    @property
    def is_expired(self):
        """Check if session is expired"""
        return datetime.utcnow() > self.expires_at


class Folder(Base):
    """Folders for organizing transcripts"""
    __tablename__ = "folders"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    name = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    user = relationship("User", back_populates="folders")
    transcripts = relationship("Transcript", back_populates="folder")


class Transcript(Base):
    """Transcription metadata and status"""
    __tablename__ = "transcripts"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    folder_id = Column(String, ForeignKey("folders.id", ondelete="SET NULL"), nullable=True)

    # Metadata
    title = Column(String, nullable=False)
    audio_filename = Column(String, nullable=False)
    duration = Column(Float, nullable=True)  # in seconds
    language = Column(String, default="he")  # ISO language code
    tags = Column(Text, nullable=True)  # JSON array stored as text

    # Transcription status
    status = Column(String, default="processing")  # processing, completed, failed
    progress_percent = Column(Integer, default=0)
    error_message = Column(Text, nullable=True)

    # Transcription results
    full_text = Column(Text, nullable=True)
    language_probability = Column(Float, nullable=True)
    diarization_enabled = Column(Boolean, default=True)
    num_speakers = Column(Integer, nullable=True)
    speaker_names_json = Column(Text, nullable=True)  # JSON mapping SPEAKER_XX -> name
    embeddings_generated = Column(Boolean, default=False)  # Track if segment embeddings exist

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    completed_at = Column(DateTime, nullable=True)

    # Relationships
    user = relationship("User", back_populates="transcripts")
    folder = relationship("Folder", back_populates="transcripts")
    segments = relationship("TranscriptSegment", back_populates="transcript", cascade="all, delete-orphan")


class TranscriptSegment(Base):
    """Individual timestamped segments of a transcript"""
    __tablename__ = "transcript_segments"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    transcript_id = Column(String, ForeignKey("transcripts.id", ondelete="CASCADE"), nullable=False)

    # Segment data
    start_time = Column(Float, nullable=False)  # seconds
    end_time = Column(Float, nullable=False)  # seconds
    text = Column(Text, nullable=False)
    speaker = Column(String, nullable=True)  # SPEAKER_00, SPEAKER_01, or identified name
    embedding = Column(Text, nullable=True)  # Serialized numpy array for semantic search

    # Relationships
    transcript = relationship("Transcript", back_populates="segments")


# Database initialization

def init_db():
    """Initialize database tables"""
    Base.metadata.create_all(bind=engine)
    print(f"Database initialized at: {DATABASE_URL}")


def drop_all_tables():
    """Drop all tables - use with caution!"""
    Base.metadata.drop_all(bind=engine)
    print("All tables dropped")


# Utility functions

def create_session_token(user_id: str, db) -> tuple[str, datetime]:
    """
    Create a new session token for a user

    Returns:
        tuple: (token, expires_at)
    """
    token = str(uuid.uuid4())
    expiry_days = int(os.getenv("SESSION_TOKEN_EXPIRY_DAYS", "30"))
    expires_at = datetime.utcnow() + timedelta(days=expiry_days)

    session = Session(
        user_id=user_id,
        token=token,
        expires_at=expires_at
    )
    db.add(session)
    db.commit()

    return token, expires_at


def validate_session_token(token: str, db) -> Optional[User]:
    """
    Validate a session token and return the user if valid

    Returns:
        User object if valid, None if invalid/expired
    """
    session = db.query(Session).filter(Session.token == token).first()

    if not session:
        return None

    if session.is_expired:
        # Clean up expired session
        db.delete(session)
        db.commit()
        return None

    return session.user


def invalidate_session_token(token: str, db):
    """Invalidate a session token (logout)"""
    session = db.query(Session).filter(Session.token == token).first()
    if session:
        db.delete(session)
        db.commit()


if __name__ == "__main__":
    # Initialize database when run directly
    init_db()
    print("Database tables created successfully!")
