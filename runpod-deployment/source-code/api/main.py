from fastapi import FastAPI, HTTPException, UploadFile, File, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import asyncio
import yaml
import os
import sys
import time
import numpy as np
from pathlib import Path
from dataclasses import dataclass
from openai import AsyncOpenAI

from .logger import setup_logging, get_logger

# Add HiRAG to path
hirag_path = Path(__file__).parent.parent / "HiRAG"
sys.path.insert(0, str(hirag_path))

from hirag import HiRAG, QueryParam
from hirag.base import BaseKVStorage
from hirag._utils import compute_args_hash
from .models import (
    FileSearchRequest, FileSearchResponse, FileResult,
    ChatSession, ChatMessage, ChatMessageRequest, ChatMessageResponse,
    SessionCreateRequest, SessionCreateResponse, HealthResponse
)
from .services import ChatSessionService, FileSearchService, RAGService, TranscriptionService

# Load configuration
config_path = Path(__file__).parent.parent / "HiRAG" / "config.yaml"
with open(config_path, 'r') as file:
    config = yaml.safe_load(file)

# Global variables
hirag_instance = None
chat_service = None
file_search_service = None
rag_service = None
transcription_service = None

@dataclass
class EmbeddingFunc:
    embedding_dim: int
    max_token_size: int
    func: callable

    async def __call__(self, *args, **kwargs) -> np.ndarray:
        return await self.func(*args, **kwargs)

def wrap_embedding_func_with_attrs(**kwargs):
    """Wrap a function with attributes"""
    def final_decro(func) -> EmbeddingFunc:
        new_func = EmbeddingFunc(**kwargs, func=func)
        return new_func
    return final_decro

@wrap_embedding_func_with_attrs(
    embedding_dim=config['model_params']['vllm_embedding_dim'], 
    max_token_size=config['model_params']['max_token_size']
)
async def vllm_embedding(texts: list[str]) -> np.ndarray:
    """vLLM embedding function"""
    vllm_config = config.get('VLLM', {})
    embedding_config = vllm_config.get('embedding', {})
    api_key = vllm_config.get('api_key', 0)
    base_url = embedding_config.get('base_url', 'http://localhost:8000/v1')
    model = embedding_config.get('model', 'embedding-model')
    
    client = AsyncOpenAI(api_key=str(api_key), base_url=base_url)
    
    response = await client.embeddings.create(input=texts, model=model)
    final_embedding = [d.embedding for d in response.data]
    return np.array(final_embedding)

async def vllm_model_if_cache(prompt, system_prompt=None, history_messages=[], **kwargs) -> str:
    """vLLM model function with caching"""
    vllm_config = config.get('VLLM', {})
    llm_config = vllm_config.get('llm', {})
    api_key = vllm_config.get('api_key', 0)
    base_url = llm_config.get('base_url', 'http://localhost:8000/v1')
    model = llm_config.get('model', 'model')
    
    client = AsyncOpenAI(api_key=str(api_key), base_url=base_url)
    
    messages = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})
    
    # Get the cached response if having
    hashing_kv: BaseKVStorage = kwargs.pop("hashing_kv", None)
    messages.extend(history_messages)
    messages.append({"role": "user", "content": prompt})
    
    if hashing_kv is not None:
        args_hash = compute_args_hash(model, messages)
        if_cache_return = await hashing_kv.get_by_id(args_hash)
        if if_cache_return is not None:
            return if_cache_return["return"]
    
    response = await client.chat.completions.create(
        model=model, messages=messages, **kwargs
    )
    
    # Cache the response if having
    if hashing_kv is not None:
        await hashing_kv.upsert({
            args_hash: {"return": response.choices[0].message.content, "model": model}
        })
    
    return response.choices[0].message.content

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize services on startup"""
    global hirag_instance, chat_service, file_search_service, rag_service, transcription_service
    
    # Setup logging
    logger = setup_logging()
    logger.main_logger.info("Starting Offline RAG API...")
    
    try:
        # Initialize HiRAG with vLLM configuration
        logger.main_logger.info("Initializing HiRAG system...")
        hirag_instance = HiRAG(
            working_dir=config['hirag']['working_dir'],
            enable_llm_cache=config['hirag']['enable_llm_cache'],
            embedding_func=vllm_embedding,
            best_model_func=vllm_model_if_cache,
            cheap_model_func=vllm_model_if_cache,
            enable_hierachical_mode=config['hirag']['enable_hierarchical_mode'],
            embedding_batch_num=config['hirag']['embedding_batch_num'],
            embedding_func_max_async=config['hirag']['embedding_func_max_async'],
            enable_naive_rag=config['hirag']['enable_naive_rag']
        )
        logger.main_logger.info("HiRAG system initialized successfully")
        
        # Initialize services
        logger.main_logger.info("Initializing API services...")
        chat_service = ChatSessionService()
        file_search_service = FileSearchService(hirag_instance)
        rag_service = RAGService(hirag_instance, config)
        transcription_service = TranscriptionService(config)
        logger.main_logger.info("All services initialized successfully")
        
        logger.main_logger.info("Offline RAG API startup complete")
        
    except Exception as e:
        logger.error_logger.error(f"Failed to initialize services: {str(e)}")
        logger.log_error(e, {"phase": "startup"})
        raise
    
    yield
    
    # Cleanup
    logger.main_logger.info("Shutting down Offline RAG API...")
    if hirag_instance:
        # Add any cleanup logic here
        pass
    logger.main_logger.info("Shutdown complete")


# Create FastAPI app
app = FastAPI(
    title="Offline RAG API",
    description="API for file search and conversational RAG using local models",
    version="1.0.0",
    lifespan=lifespan
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure based on your UI domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Add logging middleware
@app.middleware("http")
async def log_requests(request: Request, call_next):
    """Log all API requests and responses"""
    logger = get_logger()
    start_time = time.time()
    
    # Log request
    request_data = {
        "method": request.method,
        "url": str(request.url),
        "client_ip": request.client.host if request.client else "unknown",
        "user_agent": request.headers.get("user-agent", "unknown"),
        "request_id": f"req_{int(start_time * 1000000)}"
    }
    
    logger.log_api_access(request_data)
    
    # Process request
    try:
        response = await call_next(request)
        duration = time.time() - start_time
        
        # Log response
        response_data = {
            **request_data,
            "status_code": response.status_code,
            "duration_seconds": round(duration, 4)
        }
        
        logger.log_performance(
            operation=f"{request.method} {request.url.path}",
            duration=duration,
            metadata={"status_code": response.status_code}
        )
        
        return response
        
    except Exception as e:
        duration = time.time() - start_time
        logger.log_error(e, {
            **request_data,
            "duration_seconds": round(duration, 4)
        })
        raise

@app.get("/", response_model=HealthResponse)
async def root():
    """Root endpoint with API information"""
    return HealthResponse(
        status="healthy",
        message="Offline RAG API is running",
        version="1.0.0"
    )

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    # Check if HiRAG instance is ready
    if hirag_instance is None:
        raise HTTPException(status_code=503, detail="RAG system not initialized")
    
    return HealthResponse(
        status="healthy",
        message="All systems operational",
        version="1.0.0"
    )

# Include routers
from .routers import file_search, chat, transcription, audio

app.include_router(file_search.router, prefix="/api", tags=["file-search"])
app.include_router(chat.router, prefix="/api", tags=["chat"])
app.include_router(transcription.router, prefix="/api", tags=["transcription"])
app.include_router(audio.router, tags=["audio"])