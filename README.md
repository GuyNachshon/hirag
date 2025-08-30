# Offline RAG System v2

A comprehensive offline Retrieval-Augmented Generation system combining HiRAG's hierarchical knowledge processing with conversational AI capabilities. Designed for secure, air-gapped environments with complete offline operation using local vLLM models.

## 🌟 Features

### 🔍 **File Retrieval & Search**
- **Semantic File Search**: Advanced vector similarity search across indexed documents
- **Multi-format Support**: PDF, images, text files via DotsOCR integration  
- **Hierarchical Knowledge**: Multi-layer knowledge graphs with local, global, and bridge connections
- **Intelligent Filtering**: Search by file type, date, relevance score

### 💬 **Conversational AI (Agentic RAG)**
- **RAG-Enhanced Chat**: Context-aware responses using retrieved document content
- **Multi-session Support**: Independent conversation threads with persistent history
- **File Upload Chat**: Upload documents for immediate analysis and discussion
- **Context Management**: Automatic context merging from multiple sources

### 🏗️ **System Architecture**
- **Offline-First Design**: No internet connectivity required during operation
- **Local Model Serving**: Uses vLLM for both LLM and embedding models
- **Containerized Deployment**: Pre-baked Docker images with all dependencies
- **Scalable Storage**: NetworkX, Neo4j, and NanoVectorDB backends

### 📊 **Enterprise Features**
- **Comprehensive Logging**: Structured logging with performance metrics and error tracking
- **Health Monitoring**: System status and service health endpoints
- **Session Management**: User session isolation and persistence
- **RESTful API**: Complete API for frontend integration

## 📋 Prerequisites

### Required Services
- **vLLM Server**: Running with both LLM and embedding models
- **Python 3.9+**
- **Docker** (for containerized deployment)

### Models Required
- **LLM Model**: For response generation (e.g., `openai/gpt-oss-20b`)
- **Embedding Model**: For vector search (e.g., `Qwen/Qwen3-Embedding-4B`)
- **Vision Model**: For document OCR (integrated via DotsOCR)

## 🚀 Quick Start

### 1. Installation
```bash
# Clone the repository
git clone <repository-url>
cd rag-v2

# Install Python dependencies
pip install -r requirements.txt

# Install HiRAG
cd HiRAG
pip install -e .
cd ..
```

### 2. Configuration
Configure your vLLM settings in `HiRAG/config.yaml`:
```yaml
VLLM:
    api_key: 0
    llm:
        model: "openai/gpt-oss-20b"
        base_url: "http://localhost:8000/v1"
    embedding:
        model: "Qwen/Qwen3-Embedding-4B"  
        base_url: "http://localhost:8001/v1"

hirag:
    working_dir: "your_work_dir"
    enable_llm_cache: false
    enable_hierarchical_mode: true
    embedding_batch_num: 6
    embedding_func_max_async: 8
    enable_naive_rag: true

model_params:
    vllm_embedding_dim: 2560
    max_token_size: 8192
```

### 3. Start the API Server
```bash
uvicorn api.main:app --host 0.0.0.0 --port 8080 --reload
```

### 4. Access the System
- **API Documentation**: http://localhost:8080/docs
- **Health Check**: http://localhost:8080/health
- **API Base URL**: http://localhost:8080/api

## 🔧 API Endpoints

### Health & System
```bash
GET  /health              # System health check
GET  /api/search/health   # File search service health
GET  /api/chat/health     # Chat service health
```

### File Search
```bash
GET  /api/search/files?q={query}&limit=10&file_types=.pdf,.txt
# Search for files using semantic similarity
```

### Chat Sessions
```bash
POST   /api/chat/sessions                    # Create new session
GET    /api/chat/sessions/{session_id}       # Get session info  
DELETE /api/chat/sessions/{session_id}       # Delete session
GET    /api/chat/sessions/{session_id}/history # Get conversation history
```

### Chat Messaging  
```bash
POST /api/chat/{session_id}/message         # Send message, get RAG response
POST /api/chat/{session_id}/upload          # Upload file to session
```

## 💡 Usage Examples

### File Search
```bash
curl "http://localhost:8080/api/search/files?q=contract+payment+terms&limit=5&file_types=.pdf"
```

### Create Chat Session
```bash
curl -X POST "http://localhost:8080/api/chat/sessions" \
  -H "Content-Type: application/json" \
  -d '{"name": "Contract Analysis", "description": "Analyzing legal documents"}'
```

### RAG-Enhanced Chat
```bash
curl -X POST "http://localhost:8080/api/chat/{session_id}/message" \
  -H "Content-Type: application/json" \
  -d '{"content": "What are the key payment terms in the uploaded contract?", "include_context": true}'
```

### Upload File to Chat
```bash
curl -X POST "http://localhost:8080/api/chat/{session_id}/upload" \
  -F "file=@contract.pdf"
```

## 📁 Project Structure

```
rag-v2/
├── api/                          # FastAPI application
│   ├── main.py                   # Application entry point
│   ├── models.py                 # Pydantic models
│   ├── services.py               # Business logic services  
│   ├── logger.py                 # Comprehensive logging system
│   ├── routers/                  # API route handlers
│   │   ├── file_search.py        # File search endpoints
│   │   └── chat.py               # Chat endpoints
│   └── README.md                 # API documentation
├── HiRAG/                        # HiRAG system
│   ├── hirag/                    # Core HiRAG library
│   ├── config.yaml               # System configuration
│   ├── hi_Search_vllm.py         # vLLM integration example
│   └── requirements.txt          # HiRAG dependencies
├── file_parser/                  # DotsOCR file parser
│   └── dots_ocr/                 # OCR processing
├── Whisper/                      # Audio transcription (future)
├── logs/                         # Application logs (auto-created)
├── requirements.txt              # Python dependencies
└── README.md                     # This file
```

## 📝 Logging System

The system includes comprehensive logging with five specialized log files:

### Log Files
- **`api_main.log`**: Application lifecycle and general operations
- **`api_access.log`**: All HTTP requests and responses (JSON format)  
- **`api_errors.log`**: Detailed error logs with stack traces
- **`api_performance.log`**: Performance metrics and timing data (JSON format)
- **`rag_operations.log`**: RAG-specific operations and context retrieval (JSON format)

### Log Configuration
```python
# Customize logging in api/main.py
logger = setup_logging(log_dir="logs", log_level="INFO")
```

### Sample Log Entries
```json
// Performance Log
{"timestamp": "2024-01-15T10:30:45", "operation": "file_search", "duration_seconds": 1.234, "metadata": {"query": "contract", "results_count": 5}}

// RAG Operations Log  
{"timestamp": "2024-01-15T10:30:45", "operation": "rag_request", "data": {"session_id": "uuid", "message_preview": "What does...", "context_sources_count": 3}}
```

## 🐳 Deployment

### Docker Deployment
```bash
# Build container with all dependencies
docker build -t offline-rag-api .

# Run with volume mounts for logs and data
docker run -d \
  -p 8080:8080 \
  -v $(pwd)/logs:/app/logs \
  -v $(pwd)/data:/app/data \
  --name rag-api offline-rag-api
```

### Production Considerations
- **Model Storage**: Ensure all models are pre-downloaded and cached
- **Resource Allocation**: Sufficient RAM for model loading and vector operations
- **Log Management**: Implement log rotation and archival policies
- **Health Monitoring**: Set up alerts on health check endpoints
- **Session Persistence**: Consider adding database backend for session storage

## 🔒 Security & Offline Operation

### Offline Design Principles
- **No External Dependencies**: All models and processing local
- **Pre-baked Containers**: Self-contained deployment packages
- **Local Model Serving**: vLLM servers with cached models
- **Secure by Design**: No data leaves the local environment

### Security Features
- **Input Validation**: Comprehensive request validation
- **Error Handling**: Secure error responses without information disclosure
- **Session Isolation**: Each chat session is independently managed
- **File Upload Security**: Controlled file processing and validation

## 🛠️ Development

### Running in Development
```bash
# Start API with hot reload
uvicorn api.main:app --reload --log-level debug

# Run with custom log level
LOG_LEVEL=DEBUG uvicorn api.main:app --reload
```

### Adding New Features
1. **Models**: Add Pydantic models in `api/models.py`
2. **Services**: Implement business logic in `api/services.py`  
3. **Endpoints**: Create routes in `api/routers/`
4. **Logging**: Use the logging system for monitoring

### Testing
```bash
# Install test dependencies
pip install pytest httpx

# Run tests (when test suite is added)
pytest tests/
```

## 🔧 Configuration Options

### HiRAG Configuration
- **`working_dir`**: Directory for HiRAG storage
- **`enable_hierarchical_mode`**: Enable multi-layer knowledge processing
- **`embedding_batch_num`**: Batch size for embedding processing
- **`enable_naive_rag`**: Enable simple RAG mode

### vLLM Configuration  
- **`base_url`**: vLLM server endpoints
- **`model`**: Model names for LLM and embeddings
- **`api_key`**: Authentication (usually 0 for local)

### API Configuration
- **`log_dir`**: Logging directory location
- **`log_level`**: Logging verbosity (DEBUG, INFO, WARNING, ERROR)

## 📚 Integration Guide

### Frontend Integration
The API provides OpenAPI/Swagger documentation at `/docs` for easy frontend development.

### Custom UI Development
```javascript
// Example: File search
const searchFiles = async (query) => {
  const response = await fetch(`/api/search/files?q=${query}`);
  return response.json();
};

// Example: Chat with RAG
const sendMessage = async (sessionId, message) => {
  const response = await fetch(`/api/chat/${sessionId}/message`, {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({content: message, include_context: true})
  });
  return response.json();
};
```

## 🤝 Contributing

1. Follow the existing code structure and patterns
2. Add comprehensive logging for new features
3. Update API documentation for new endpoints  
4. Test offline functionality thoroughly
5. Ensure security best practices

## 📄 License

[License information to be added]

---

**Note**: This system is designed for offline, secure environments. All processing occurs locally without external API calls during runtime. Ensure proper model licensing and compliance for your use case.