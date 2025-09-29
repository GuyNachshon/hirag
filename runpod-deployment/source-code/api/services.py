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
    
    async def transcribe_audio(self, audio_file_path: str, filename: str) -> TranscriptionResponse:
        """Transcribe audio file using Whisper service"""
        import aiofiles
        import aiohttp
        
        start_time = time.time()
        
        self.logger.main_logger.info(f"Starting transcription of {filename}")
        
        try:
            # Read audio file
            async with aiofiles.open(audio_file_path, 'rb') as f:
                audio_content = await f.read()

            # Prepare multipart form data
            data = aiohttp.FormData()
            data.add_field('file', audio_content, filename=filename, content_type='audio/*')

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
                                text=seg['text']
                            )
                            for seg in result.get('segments', [])
                        ]
                        
                        transcription_response = TranscriptionResponse(
                            success=True,
                            text=result.get('text', ''),
                            language=result.get('language', 'he'),
                            language_probability=result.get('language_probability', 0.0),
                            duration=result.get('duration', 0.0),
                            segments=segments,
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