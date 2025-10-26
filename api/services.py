import asyncio
import uuid
import time
import numpy as np
from datetime import datetime
from typing import List, Dict, Optional, Any
from pathlib import Path
import os

from openai import AsyncOpenAI
from hirag import HiRAG, QueryParam
from hirag.base import BaseKVStorage
from hirag._utils import compute_args_hash
from .models import (
    FileResult, FileSearchResponse, 
    ChatSession, ChatMessage, MessageRole, ChatMessageResponse,
    TranscriptionResponse, TranscriptionSegment, TranscriptionErrorResponse
)
from .logger import get_logger

class FileSearchService:
    """Service for file search functionality"""
    
    def __init__(self, hirag_instance: HiRAG):
        self.hirag = hirag_instance
    
    async def search_files(self, query: str, limit: int = 10, file_types: Optional[List[str]] = None) -> FileSearchResponse:
        """Search for files using HiRAG vector search"""
        start_time = time.time()
        logger = get_logger()
        
        logger.main_logger.info(f"Starting file search: query='{query}', limit={limit}, file_types={file_types}")
        
        try:
            # Use HiRAG to find relevant documents
            logger.main_logger.info("Querying HiRAG for file search")
            results = await self.hirag.aquery(
                query, 
                param=QueryParam(mode="naive", top_k=limit * 2)  # Get more results to filter
            )
            logger.main_logger.info(f"HiRAG returned {len(results.get('chunks', []))} results")
            
            # Process results into file list
            file_results = []
            seen_files = set()
            
            # Extract file information from HiRAG results
            # This would need to be adapted based on how HiRAG stores file metadata
            for result in results.get('chunks', [])[:limit]:
                file_path = result.get('full_doc_id', '')
                if file_path and file_path not in seen_files:
                    seen_files.add(file_path)
                    
                    # Get file info
                    path_obj = Path(file_path)
                    if path_obj.exists():
                        stat = path_obj.stat()
                        
                        # Filter by file type if specified
                        if file_types and path_obj.suffix.lower() not in file_types:
                            continue
                        
                        file_result = FileResult(
                            file_path=str(path_obj),
                            filename=path_obj.name,
                            relevance_score=result.get('score', 0.0),
                            file_type=path_obj.suffix.lower(),
                            file_size=stat.st_size,
                            last_modified=datetime.fromtimestamp(stat.st_mtime),
                            summary=result.get('content', '')[:200] + "..." if len(result.get('content', '')) > 200 else result.get('content', '')
                        )
                        file_results.append(file_result)
            
            processing_time = time.time() - start_time
            
            logger.log_performance(
                operation="file_search",
                duration=processing_time,
                metadata={
                    "query": query,
                    "results_count": len(file_results),
                    "limit": limit,
                    "file_types": file_types
                }
            )
            
            logger.main_logger.info(f"File search completed: {len(file_results)} results in {processing_time:.3f}s")
            
            return FileSearchResponse(
                query=query,
                results=file_results,
                total_results=len(file_results),
                processing_time=processing_time
            )
            
        except Exception as e:
            processing_time = time.time() - start_time
            logger.log_error(e, {
                "operation": "file_search",
                "query": query,
                "limit": limit,
                "file_types": file_types,
                "processing_time": processing_time
            })
            logger.main_logger.error(f"File search failed: {str(e)}")
            
            return FileSearchResponse(
                query=query,
                results=[],
                total_results=0,
                processing_time=processing_time
            )


class ChatSessionService:
    """Service for managing chat sessions"""
    
    def __init__(self):
        self.sessions: Dict[str, ChatSession] = {}
        self.session_messages: Dict[str, List[ChatMessage]] = {}
    
    def create_session(self, name: Optional[str] = None, description: Optional[str] = None) -> ChatSession:
        """Create a new chat session"""
        logger = get_logger()
        session_id = str(uuid.uuid4())
        now = datetime.now()
        
        session = ChatSession(
            session_id=session_id,
            name=name or f"Chat Session {len(self.sessions) + 1}",
            description=description,
            created_at=now,
            last_activity=now,
            message_count=0
        )
        
        self.sessions[session_id] = session
        self.session_messages[session_id] = []
        
        logger.main_logger.info(f"Created new chat session: {session_id} - '{session.name}'")
        
        return session
    
    def get_session(self, session_id: str) -> Optional[ChatSession]:
        """Get a session by ID"""
        return self.sessions.get(session_id)
    
    def delete_session(self, session_id: str) -> bool:
        """Delete a session"""
        if session_id in self.sessions:
            del self.sessions[session_id]
            del self.session_messages[session_id]
            return True
        return False
    
    def add_message(self, session_id: str, role: MessageRole, content: str, 
                   context_used: Optional[List[str]] = None) -> Optional[ChatMessage]:
        """Add a message to a session"""
        if session_id not in self.sessions:
            return None
        
        message_id = str(uuid.uuid4())
        now = datetime.now()
        
        message = ChatMessage(
            message_id=message_id,
            session_id=session_id,
            role=role,
            content=content,
            timestamp=now,
            context_used=context_used
        )
        
        self.session_messages[session_id].append(message)
        
        # Update session
        self.sessions[session_id].last_activity = now
        self.sessions[session_id].message_count += 1
        
        return message
    
    def get_messages(self, session_id: str) -> List[ChatMessage]:
        """Get all messages for a session"""
        return self.session_messages.get(session_id, [])


class RAGService:
    """Service for RAG-enhanced chat responses"""
    
    def __init__(self, hirag_instance: HiRAG, config: Dict[str, Any]):
        self.hirag = hirag_instance
        self.config = config
    
    async def generate_response(self, session_id: str, user_message: str, 
                              conversation_history: List[ChatMessage]) -> ChatMessageResponse:
        """Generate a RAG-enhanced response to a user message"""
        start_time = time.time()
        logger = get_logger()
        
        logger.main_logger.info(f"Starting RAG response generation for session {session_id}")
        logger.log_rag_operation("rag_request", {
            "session_id": session_id,
            "message_preview": user_message[:100] + "..." if len(user_message) > 100 else user_message,
            "history_length": len(conversation_history)
        })
        
        try:
            # Step 1: Use HiRAG to retrieve relevant context
            logger.main_logger.info("Retrieving context from HiRAG")
            context_start = time.time()
            context_results = await self.hirag.aquery(
                user_message,
                param=QueryParam(mode="hi", top_k=5)  # Use hierarchical mode for better context
            )
            context_time = time.time() - context_start
            logger.main_logger.info(f"Context retrieval completed in {context_time:.3f}s")
            
            # Step 2: Extract context and sources
            context_text = ""
            context_sources = []
            
            if 'chunks' in context_results:
                for chunk in context_results['chunks']:
                    context_text += chunk.get('content', '') + "\n\n"
                    source = chunk.get('full_doc_id', '')
                    if source and source not in context_sources:
                        context_sources.append(source)
            
            # Step 3: Construct prompt with context and conversation history
            prompt = self._construct_prompt(user_message, context_text, conversation_history)
            
            # Step 4: Generate response using vLLM
            response = await self._call_vllm(prompt)
            
            processing_time = time.time() - start_time
            
            logger.log_rag_operation("rag_response", {
                "session_id": session_id,
                "context_sources_count": len(context_sources),
                "context_sources": context_sources,
                "processing_time": processing_time,
                "response_preview": response[:100] + "..." if len(response) > 100 else response
            })
            
            logger.log_performance(
                operation="rag_generation",
                duration=processing_time,
                metadata={
                    "session_id": session_id,
                    "context_sources_count": len(context_sources),
                    "message_length": len(user_message),
                    "response_length": len(response)
                }
            )
            
            logger.main_logger.info(f"RAG response generated successfully in {processing_time:.3f}s")
            
            return ChatMessageResponse(
                message_id=str(uuid.uuid4()),
                content=response,
                timestamp=datetime.now(),
                context_sources=context_sources,
                processing_time=processing_time
            )
            
        except Exception as e:
            processing_time = time.time() - start_time
            logger.log_error(e, {
                "operation": "rag_generation",
                "session_id": session_id,
                "message": user_message[:100] + "..." if len(user_message) > 100 else user_message,
                "processing_time": processing_time
            })
            logger.main_logger.error(f"RAG response generation failed: {str(e)}")
            
            return ChatMessageResponse(
                message_id=str(uuid.uuid4()),
                content=f"I apologize, but I encountered an error processing your request: {str(e)}",
                timestamp=datetime.now(),
                context_sources=[],
                processing_time=processing_time
            )
    
    def _construct_prompt(self, user_message: str, context: str, history: List[ChatMessage]) -> str:
        """Construct the prompt for the LLM with context and conversation history"""
        prompt_parts = []
        
        # System prompt
        prompt_parts.append(
            "You are a helpful AI assistant with access to relevant documents and information. "
            "Use the provided context to answer questions accurately and helpfully. "
            "If the context doesn't contain relevant information, say so clearly."
        )
        
        # Add context if available
        if context.strip():
            prompt_parts.append(f"\n\nRelevant Context:\n{context}")
        
        # Add conversation history (last few messages)
        if history:
            prompt_parts.append("\n\nConversation History:")
            for msg in history[-5:]:  # Only include last 5 messages
                role = "Human" if msg.role == MessageRole.USER else "Assistant"
                prompt_parts.append(f"{role}: {msg.content}")
        
        # Add current user message
        prompt_parts.append(f"\n\nHuman: {user_message}")
        prompt_parts.append("\n\nAssistant:")
        
        return "\n".join(prompt_parts)
    
    async def _call_vllm(self, prompt: str) -> str:
        """Call vLLM API for response generation"""
        try:
            # Extract vLLM configuration
            vllm_config = self.config.get('VLLM', {})
            vllm_api_key = vllm_config.get('api_key', 0)
            vllm_url = vllm_config.get('llm', {}).get('base_url', 'http://localhost:8000/v1')
            model = vllm_config.get('llm', {}).get('model', 'model')
            
            # Create vLLM client
            client = AsyncOpenAI(
                api_key=str(vllm_api_key),
                base_url=vllm_url
            )
            
            # Create messages for chat completion
            messages = [{"role": "user", "content": prompt}]
            
            # Call vLLM
            response = await client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=0.7,
                max_tokens=2048
            )
            
            return response.choices[0].message.content
            
        except Exception as e:
            # Return error message if vLLM call fails
            return f"I apologize, but I'm having trouble generating a response. Error: {str(e)}"


class TranscriptionService:
    """Service for audio transcription using Whisper"""

    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.whisper_config = config.get('whisper', {})
        self.base_url = self.whisper_config.get('base_url', 'http://rag-whisper:8004')
        self.logger = get_logger()

    async def _identify_speakers_with_llm(self, segments: List[TranscriptionSegment]) -> Optional[Dict[str, str]]:
        """
        Use LLM to identify speaker names from conversation content

        Args:
            segments: List of transcription segments with speaker labels

        Returns:
            Dictionary mapping speaker labels to names (e.g., {"SPEAKER_00": "Sarah"})
            or None if identification fails or no names found
        """
        try:
            # Check if vLLM is configured
            vllm_config = self.config.get('VLLM', {})
            if not vllm_config:
                self.logger.main_logger.warning("vLLM not configured, skipping speaker identification")
                return None

            vllm_api_key = vllm_config.get('api_key', 0)
            vllm_url = vllm_config.get('llm', {}).get('base_url', 'http://localhost:8000/v1')
            model = vllm_config.get('llm', {}).get('model', 'model')

            # Format conversation for LLM
            conversation = []
            for seg in segments:
                speaker = seg.speaker or "UNKNOWN"
                conversation.append(f"[{speaker}] ({seg.start:.1f}s-{seg.end:.1f}s): {seg.text}")

            conversation_text = "\n".join(conversation)

            # Create prompt for speaker identification
            prompt = f"""Analyze the following conversation transcript and identify if any speakers introduce themselves by name.

Conversation:
{conversation_text}

Task: Extract the real names of speakers if they introduce themselves (e.g., "Hi, I'm Sarah", "This is David speaking", "My name is...").

Respond ONLY with a JSON object mapping speaker IDs to names. If a speaker doesn't introduce themselves, don't include them.
Format: {{"SPEAKER_00": "Name1", "SPEAKER_01": "Name2"}}

If no speakers introduce themselves, respond with: {{}}

JSON Response:"""

            # Call vLLM
            client = AsyncOpenAI(
                api_key=str(vllm_api_key),
                base_url=vllm_url
            )

            response = await client.chat.completions.create(
                model=model,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.1,  # Low temperature for more deterministic output
                max_tokens=500
            )

            llm_response = response.choices[0].message.content.strip()
            self.logger.main_logger.info(f"LLM speaker identification response: {llm_response}")

            # Parse JSON response
            import json
            import re

            # Try to extract JSON from response (handle cases where LLM adds explanation)
            json_match = re.search(r'\{[^}]*\}', llm_response)
            if json_match:
                speaker_names = json.loads(json_match.group())
                if speaker_names:
                    self.logger.main_logger.info(f"Identified speakers: {speaker_names}")
                    return speaker_names
                else:
                    self.logger.main_logger.info("No speaker names identified from conversation")
                    return None
            else:
                self.logger.main_logger.warning(f"Could not parse JSON from LLM response: {llm_response}")
                return None

        except Exception as e:
            self.logger.main_logger.error(f"Speaker identification failed: {e}")
            return None
    
    async def transcribe_audio(
        self,
        audio_file_path: str,
        filename: str,
        enable_diarization: bool = True,
        identify_speakers: bool = False,
        num_speakers: Optional[int] = None,
        language: str = "he"
    ) -> TranscriptionResponse:
        """
        Transcribe audio file using Whisper service with diarization and speaker identification

        Args:
            audio_file_path: Path to audio file
            filename: Original filename
            enable_diarization: Enable speaker diarization (enabled by default)
            identify_speakers: Use LLM to identify speaker names from conversation (requires diarization)
            num_speakers: Expected number of speakers (hint for diarization)
            language: Language code (default: "he" for Hebrew)
        """
        import aiofiles
        import aiohttp

        start_time = time.time()

        self.logger.main_logger.info(
            f"Starting transcription of {filename} (diarization: {enable_diarization})"
        )

        try:
            # Read audio file
            async with aiofiles.open(audio_file_path, 'rb') as f:
                audio_content = await f.read()

            # Prepare multipart form data
            data = aiohttp.FormData()
            data.add_field('file', audio_content, filename=filename, content_type='audio/*')
            data.add_field('language', language)
            data.add_field('diarize', str(enable_diarization).lower())

            # Add num_speakers hint if provided and diarization is enabled
            if num_speakers is not None and enable_diarization:
                data.add_field('num_speakers', str(num_speakers))

            # Call Whisper service
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{self.base_url}/transcribe",
                    data=data,
                    timeout=aiohttp.ClientTimeout(total=300)  # 5 minutes timeout
                ) as response:
                    if response.status == 200:
                        result = await response.json()

                        processing_time = time.time() - start_time

                        # Convert segments to our model
                        segments = [
                            TranscriptionSegment(
                                start=seg['start'],
                                end=seg['end'],
                                text=seg['text'],
                                speaker=seg.get('speaker')  # Include speaker if present
                            )
                            for seg in result.get('segments', [])
                        ]

                        # Extract speaker information if diarization was enabled
                        speakers = None
                        num_speakers = None
                        if enable_diarization and segments:
                            unique_speakers = list(set(
                                seg.speaker for seg in segments if seg.speaker is not None
                            ))
                            if unique_speakers:
                                speakers = sorted(unique_speakers)
                                num_speakers = len(speakers)

                        # Identify speaker names using LLM if requested
                        speaker_names = None
                        speaker_identification_attempted = False
                        if identify_speakers and enable_diarization and segments:
                            self.logger.main_logger.info("Attempting speaker identification with LLM...")
                            speaker_identification_attempted = True
                            speaker_names = await self._identify_speakers_with_llm(segments)

                            # Update segment speaker labels with identified names
                            if speaker_names:
                                for seg in segments:
                                    if seg.speaker and seg.speaker in speaker_names:
                                        # Keep original speaker ID but we'll provide mapping
                                        pass  # Don't modify speaker field, just provide mapping

                        transcription_response = TranscriptionResponse(
                            success=True,
                            text=result.get('text', ''),
                            language=result.get('language', 'he'),
                            language_probability=result.get('language_probability', 0.0),
                            duration=result.get('duration', 0.0),
                            segments=segments,
                            diarization_enabled=enable_diarization,
                            speakers=speakers,
                            num_speakers=num_speakers,
                            speaker_names=speaker_names,
                            speaker_identification_attempted=speaker_identification_attempted,
                            message=f"Transcription completed in {processing_time:.2f}s"
                        )
                        
                        self.logger.log_performance(
                            operation="audio_transcription",
                            duration=processing_time,
                            metadata={
                                "filename": filename,
                                "duration": result.get('duration', 0.0),
                                "language": result.get('language', 'he'),
                                "text_length": len(result.get('text', ''))
                            }
                        )
                        
                        self.logger.main_logger.info(
                            f"Transcription completed for {filename} in {processing_time:.2f}s"
                        )
                        
                        return transcription_response
                    
                    else:
                        error_text = await response.text()
                        self.logger.main_logger.error(
                            f"Whisper service error {response.status}: {error_text}"
                        )
                        return TranscriptionErrorResponse(
                            error=f"Whisper service error: {response.status}",
                            message=error_text
                        )
        
        except asyncio.TimeoutError:
            error_msg = "Transcription timeout - audio file may be too long"
            self.logger.main_logger.error(error_msg)
            return TranscriptionErrorResponse(
                error="timeout",
                message=error_msg
            )
        
        except Exception as e:
            processing_time = time.time() - start_time
            self.logger.log_error(e, {
                "operation": "audio_transcription",
                "filename": filename,
                "processing_time": processing_time
            })
            return TranscriptionErrorResponse(
                error=str(e),
                message=f"Transcription failed: {str(e)}"
            )


class TranscriptionChatService:
    """Service for chat functionality specific to transcriptions"""

    # Thresholds for adaptive context strategy
    TOKEN_THRESHOLD_SINGLE = 50000  # ~40k words for single transcript
    TOKEN_THRESHOLD_FOLDER = 100000  # ~80k words for folder
    WORD_TO_TOKEN_RATIO = 1.3  # Conservative estimate

    def __init__(self, config: Dict[str, Any], embedding_func=None):
        self.config = config
        self.embedding_func = embedding_func
        self.logger = get_logger()

        # In-memory session storage
        self.sessions: Dict[str, Dict] = {}
        self.session_messages: Dict[str, List] = {}

    def create_session(self, context_type: str, context_id: str, name: Optional[str] = None) -> Dict:
        """Create a new chat session"""
        session_id = str(uuid.uuid4())
        now = datetime.now()

        session = {
            "session_id": session_id,
            "context_type": context_type,
            "context_id": context_id,
            "name": name or f"Chat {len(self.sessions) + 1}",
            "created_at": now
        }

        self.sessions[session_id] = session
        self.session_messages[session_id] = []

        self.logger.main_logger.info(
            f"Created transcription chat session: {session_id} "
            f"(type={context_type}, id={context_id})"
        )

        return session

    def get_session(self, session_id: str) -> Optional[Dict]:
        """Get session by ID"""
        return self.sessions.get(session_id)

    def delete_session(self, session_id: str) -> bool:
        """Delete a session"""
        if session_id in self.sessions:
            del self.sessions[session_id]
            del self.session_messages[session_id]
            return True
        return False

    def add_message(self, session_id: str, role: str, content: str,
                   strategy_used: Optional[str] = None, sources: Optional[List[str]] = None):
        """Add a message to session history"""
        if session_id not in self.sessions:
            return None

        message = {
            "message_id": str(uuid.uuid4()),
            "role": role,
            "content": content,
            "timestamp": datetime.now(),
            "strategy_used": strategy_used,
            "sources": sources
        }

        self.session_messages[session_id].append(message)
        return message

    def get_messages(self, session_id: str) -> List:
        """Get all messages for a session"""
        return self.session_messages.get(session_id, [])

    async def get_adaptive_context(
        self,
        context_type: str,
        context_id: str,
        user_message: str,
        user_id: str,
        db
    ) -> Dict:
        """
        Adaptively choose context strategy based on content size.
        Returns dict with: strategy, context, sources, segment_references
        """
        from .database import Transcript, TranscriptSegment, Folder

        self.logger.main_logger.info(
            f"Getting adaptive context: type={context_type}, id={context_id}"
        )

        if context_type == "transcript":
            # Single transcript
            transcript = (
                db.query(Transcript)
                .filter(Transcript.id == context_id)
                .filter(Transcript.user_id == user_id)
                .first()
            )

            if not transcript:
                raise ValueError("Transcript not found")

            if not transcript.full_text:
                raise ValueError("Transcript has no text")

            word_count = len(transcript.full_text.split())
            token_estimate = int(word_count * self.WORD_TO_TOKEN_RATIO)

            self.logger.main_logger.info(
                f"Transcript word count: {word_count}, estimated tokens: {token_estimate}"
            )

            if token_estimate < self.TOKEN_THRESHOLD_SINGLE:
                # Use full context
                self.logger.main_logger.info("Using full context strategy")
                return {
                    "strategy": "full_context",
                    "context": f"[Transcript: {transcript.title}]\n\n{transcript.full_text}",
                    "sources": [transcript.id],
                    "segment_references": None
                }
            else:
                # Use embedding search
                self.logger.main_logger.info("Using embedding search strategy")
                return await self._embedding_search(
                    user_message,
                    transcript_id=context_id,
                    user_id=user_id,
                    db=db
                )

        elif context_type == "folder":
            # Multiple transcripts
            transcripts = (
                db.query(Transcript)
                .filter(Transcript.folder_id == context_id)
                .filter(Transcript.user_id == user_id)
                .filter(Transcript.status == "completed")
                .all()
            )

            if not transcripts:
                raise ValueError("No transcripts found in folder")

            total_words = sum(
                len(t.full_text.split()) if t.full_text else 0
                for t in transcripts
            )
            token_estimate = int(total_words * self.WORD_TO_TOKEN_RATIO)

            self.logger.main_logger.info(
                f"Folder has {len(transcripts)} transcripts, "
                f"total words: {total_words}, estimated tokens: {token_estimate}"
            )

            if token_estimate < self.TOKEN_THRESHOLD_FOLDER:
                # Use all transcripts
                self.logger.main_logger.info("Using full context strategy for folder")
                context_parts = []
                for t in transcripts:
                    if t.full_text:
                        context_parts.append(f"[Transcript: {t.title}]\n{t.full_text}")

                return {
                    "strategy": "full_context",
                    "context": "\n\n---\n\n".join(context_parts),
                    "sources": [t.id for t in transcripts],
                    "segment_references": None
                }
            else:
                # Use embedding search with keyword filter
                self.logger.main_logger.info("Using embedding search strategy for folder")
                return await self._embedding_search_with_filter(
                    user_message,
                    folder_id=context_id,
                    user_id=user_id,
                    db=db
                )
        else:
            raise ValueError(f"Invalid context_type: {context_type}")

    async def _embedding_search(
        self,
        query: str,
        transcript_id: Optional[str] = None,
        folder_id: Optional[str] = None,
        user_id: str = None,
        db = None
    ) -> Dict:
        """
        Perform embedding-based semantic search on segments.
        Returns top K most relevant segments as context.
        """
        from .database import Transcript, TranscriptSegment
        import json
        import base64

        if not self.embedding_func:
            raise ValueError("Embedding function not available")

        # Get segments
        if transcript_id:
            transcript = (
                db.query(Transcript)
                .filter(Transcript.id == transcript_id)
                .filter(Transcript.user_id == user_id)
                .first()
            )

            if not transcript:
                raise ValueError("Transcript not found")

            # Check if embeddings exist
            if not transcript.embeddings_generated:
                self.logger.main_logger.info(
                    f"Generating embeddings for transcript {transcript_id}"
                )
                await self._generate_embeddings_for_transcript(transcript_id, db)

            segments = (
                db.query(TranscriptSegment)
                .filter(TranscriptSegment.transcript_id == transcript_id)
                .all()
            )

            transcript_map = {transcript.id: transcript}

        else:  # folder_id
            transcripts = (
                db.query(Transcript)
                .filter(Transcript.folder_id == folder_id)
                .filter(Transcript.user_id == user_id)
                .filter(Transcript.status == "completed")
                .all()
            )

            transcript_map = {t.id: t for t in transcripts}

            # Generate embeddings for any transcripts that don't have them
            for t in transcripts:
                if not t.embeddings_generated:
                    self.logger.main_logger.info(
                        f"Generating embeddings for transcript {t.id}"
                    )
                    await self._generate_embeddings_for_transcript(t.id, db)

            # Get all segments from these transcripts
            segments = (
                db.query(TranscriptSegment)
                .join(Transcript)
                .filter(Transcript.folder_id == folder_id)
                .filter(Transcript.user_id == user_id)
                .all()
            )

        # Embed the query
        query_embedding = await self.embedding_func([query])
        query_vec = query_embedding[0]  # First (and only) embedding

        # Compute similarities
        similarities = []
        for seg in segments:
            if seg.embedding:
                try:
                    # Deserialize embedding
                    seg_vec = np.array(json.loads(seg.embedding))

                    # Cosine similarity
                    similarity = np.dot(query_vec, seg_vec) / (
                        np.linalg.norm(query_vec) * np.linalg.norm(seg_vec)
                    )

                    similarities.append((similarity, seg))
                except Exception as e:
                    self.logger.main_logger.warning(
                        f"Error computing similarity for segment {seg.id}: {e}"
                    )

        # Get top K segments
        top_k = 5
        top_segments = sorted(similarities, key=lambda x: x[0], reverse=True)[:top_k]

        self.logger.main_logger.info(
            f"Found {len(top_segments)} relevant segments from {len(segments)} total"
        )

        # Build context
        context_parts = []
        segment_references = []

        for similarity, seg in top_segments:
            transcript = transcript_map[seg.transcript_id]

            # Format timestamp
            minutes = int(seg.start_time // 60)
            seconds = int(seg.start_time % 60)
            timestamp = f"{minutes:02d}:{seconds:02d}"

            speaker_label = f"[{seg.speaker}]" if seg.speaker else ""
            context_parts.append(
                f"[{transcript.title} - {timestamp}] {speaker_label} {seg.text}"
            )

            segment_references.append({
                "transcript_id": transcript.id,
                "transcript_title": transcript.title,
                "segment_id": seg.id,
                "speaker": seg.speaker,
                "start_time": seg.start_time,
                "end_time": seg.end_time,
                "text": seg.text
            })

        return {
            "strategy": "embedding_search",
            "context": "Relevant segments:\n\n" + "\n\n".join(context_parts),
            "sources": list(set(seg.transcript_id for _, seg in top_segments)),
            "segment_references": segment_references
        }

    async def _embedding_search_with_filter(
        self,
        query: str,
        folder_id: str,
        user_id: str,
        db
    ) -> Dict:
        """
        Embedding search with keyword pre-filtering for large folders.
        First filters transcripts by keywords, then does embedding search.
        """
        from .database import Transcript
        from sqlalchemy import or_

        # Extract keywords (simple: top 3 words)
        keywords = [w.lower() for w in query.split() if len(w) > 3][:3]

        if keywords:
            # Filter transcripts that contain any of the keywords
            filters = [Transcript.full_text.ilike(f"%{kw}%") for kw in keywords]

            relevant_transcripts = (
                db.query(Transcript)
                .filter(Transcript.folder_id == folder_id)
                .filter(Transcript.user_id == user_id)
                .filter(Transcript.status == "completed")
                .filter(or_(*filters))
                .limit(10)  # Limit to top 10 matching transcripts
                .all()
            )

            self.logger.main_logger.info(
                f"Keyword filter narrowed to {len(relevant_transcripts)} transcripts"
            )

            if not relevant_transcripts:
                # Fallback to all transcripts if no keyword matches
                return await self._embedding_search(
                    query, folder_id=folder_id, user_id=user_id, db=db
                )

            # Now do embedding search only on these transcripts' segments
            # We'll temporarily modify the folder to only include these transcripts
            # by searching each transcript individually and combining results
            all_segment_refs = []
            all_sources = set()

            for transcript in relevant_transcripts:
                result = await self._embedding_search(
                    query, transcript_id=transcript.id, user_id=user_id, db=db
                )
                if result["segment_references"]:
                    all_segment_refs.extend(result["segment_references"])
                all_sources.update(result["sources"])

            # Sort by relevance and take top 5
            # (In this simple version, we just take first 5 - could improve with re-ranking)
            top_refs = all_segment_refs[:5]

            # Build context
            context_parts = []
            for ref in top_refs:
                minutes = int(ref["start_time"] // 60)
                seconds = int(ref["start_time"] % 60)
                timestamp = f"{minutes:02d}:{seconds:02d}"
                speaker_label = f"[{ref['speaker']}]" if ref['speaker'] else ""

                context_parts.append(
                    f"[{ref['transcript_title']} - {timestamp}] {speaker_label} {ref['text']}"
                )

            return {
                "strategy": "embedding_search",
                "context": "Relevant segments:\n\n" + "\n\n".join(context_parts),
                "sources": list(all_sources),
                "segment_references": top_refs
            }
        else:
            # No keywords, fall back to regular embedding search
            return await self._embedding_search(
                query, folder_id=folder_id, user_id=user_id, db=db
            )

    async def _generate_embeddings_for_transcript(self, transcript_id: str, db):
        """Generate and store embeddings for all segments in a transcript"""
        from .database import Transcript, TranscriptSegment
        import json

        if not self.embedding_func:
            raise ValueError("Embedding function not available")

        segments = (
            db.query(TranscriptSegment)
            .filter(TranscriptSegment.transcript_id == transcript_id)
            .all()
        )

        if not segments:
            return

        # Batch embed all segment texts
        texts = [seg.text for seg in segments]

        try:
            embeddings = await self.embedding_func(texts)

            # Store embeddings
            for seg, emb in zip(segments, embeddings):
                # Serialize as JSON list
                seg.embedding = json.dumps(emb.tolist())

            # Mark transcript as having embeddings
            transcript = db.query(Transcript).filter(
                Transcript.id == transcript_id
            ).first()

            if transcript:
                transcript.embeddings_generated = True

            db.commit()

            self.logger.main_logger.info(
                f"Generated embeddings for {len(segments)} segments "
                f"in transcript {transcript_id}"
            )

        except Exception as e:
            self.logger.main_logger.error(
                f"Failed to generate embeddings for transcript {transcript_id}: {e}"
            )
            raise

    async def generate_response(
        self,
        user_message: str,
        context: str,
        conversation_history: List,
        quick_action_id: Optional[str] = None
    ) -> str:
        """
        Generate LLM response with context and conversation history.
        """
        from openai import AsyncOpenAI

        # Get vLLM configuration
        self.logger.main_logger.info(f"Config keys: {self.config.keys() if self.config else 'None'}")
        vllm_config = self.config.get('VLLM', {})
        self.logger.main_logger.info(f"VLLM config: {vllm_config}")
        llm_config = vllm_config.get('llm', {})
        self.logger.main_logger.info(f"LLM config: {llm_config}")
        api_key = vllm_config.get('api_key', 0)
        base_url = llm_config.get('base_url', 'http://localhost:8000/v1')
        model = llm_config.get('model', 'model')
        self.logger.main_logger.info(f"Resolved - base_url: {base_url}, model: {model}")

        # Create client
        client = AsyncOpenAI(api_key=str(api_key), base_url=base_url)

        # Construct system prompt
        system_prompt = """אתה עוזר AI המסייע למשתמשים לנתח תמלולי פגישות.

היכולות שלך:
- סיכום פגישות וחילוץ נקודות מפתח
- זיהוי משימות והחלטות
- מענה על שאלות לגבי מה שנדון
- מציאת מידע ספציפי בשיחות
- זיהוי דפוסים במספר פגישות

הנחיות:
- היה תמציתי ומדויק
- צטט ישירות מהתמלולים כשרלוונטי
- כלול חותמות זמן כשמתייחס לרגעים ספציפיים
- אם המידע לא נמצא בהקשר המסופק, אמור זאת בבירור
- תמוך בעברית ובאנגלית באופן שווה
"""

        # Build messages
        messages = [{"role": "system", "content": system_prompt}]

        # Add context
        if context:
            messages.append({
                "role": "system",
                "content": f"הקשר רלוונטי:\n\n{context}"
            })

        # Add conversation history (last 5 messages)
        for msg in conversation_history[-5:]:
            messages.append({
                "role": msg["role"],
                "content": msg["content"]
            })

        # Add current user message
        messages.append({"role": "user", "content": user_message})

        # Call vLLM
        try:
            response = await client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=0.7,
                max_tokens=2048
            )

            return response.choices[0].message.content

        except Exception as e:
            import traceback
            self.logger.main_logger.error(f"Error calling vLLM: {e}")
            self.logger.main_logger.error(f"Full traceback: {traceback.format_exc()}")
            self.logger.main_logger.error(f"Base URL: {base_url}, Model: {model}")
            return f"מצטער, נתקלתי בשגיאה ביצירת התשובה: {str(e)}"