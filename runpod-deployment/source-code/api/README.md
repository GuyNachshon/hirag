# Offline RAG API

This is a FastAPI-based REST API for the offline RAG system that provides file search and conversational AI capabilities using local vLLM models.

## Features

- **File Search**: Semantic search across indexed documents
- **Conversational RAG**: Multi-session chat with RAG-enhanced responses
- **File Upload**: Upload files to chat sessions for immediate analysis
- **Offline Operation**: Runs completely offline using local vLLM models

## Setup

### Prerequisites

1. **vLLM Server**: You need a running vLLM server with both LLM and embedding models
2. **HiRAG**: The HiRAG system should be installed and configured
3. **Python 3.9+**

### Installation

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Install HiRAG:
```bash
cd HiRAG
pip install -e .
```

3. Configure your `HiRAG/config.yaml` with vLLM settings:
```yaml
VLLM:
    api_key: 0
    llm:
        model: "your-llm-model"
        base_url: "http://localhost:8000/v1"
    embedding:
        model: "your-embedding-model"
        base_url: "http://localhost:8001/v1"
```

### Running the API

```bash
# From the project root directory
uvicorn api.main:app --host 0.0.0.0 --port 8080 --reload
```

The API will be available at:
- API: `http://localhost:8080`
- Interactive docs: `http://localhost:8080/docs`
- Health check: `http://localhost:8080/health`

## API Endpoints

### Health
- `GET /` - Root endpoint with API info
- `GET /health` - Health check

### File Search
- `GET /api/search/files?q={query}&limit=10&file_types=.pdf,.txt` - Search files
- `GET /api/search/health` - File search health check

### Chat Sessions
- `POST /api/chat/sessions` - Create new session
- `GET /api/chat/sessions/{session_id}` - Get session info
- `DELETE /api/chat/sessions/{session_id}` - Delete session
- `GET /api/chat/sessions/{session_id}/history` - Get conversation history

### Chat Messaging
- `POST /api/chat/{session_id}/message` - Send message and get RAG response
- `POST /api/chat/{session_id}/upload` - Upload file to session

### Health Checks
- `GET /api/chat/health` - Chat service health check

## Usage Examples

### File Search
```bash
curl "http://localhost:8080/api/search/files?q=contract&limit=5"
```

### Create Chat Session
```bash
curl -X POST "http://localhost:8080/api/chat/sessions" \
  -H "Content-Type: application/json" \
  -d '{"name": "My Chat Session"}'
```

### Send Chat Message
```bash
curl -X POST "http://localhost:8080/api/chat/{session_id}/message" \
  -H "Content-Type: application/json" \
  -d '{"content": "What does the contract say about payment terms?", "include_context": true}'
```

### Upload File to Chat
```bash
curl -X POST "http://localhost:8080/api/chat/{session_id}/upload" \
  -F "file=@document.pdf"
```

## Configuration

The API reads configuration from `HiRAG/config.yaml`. Key sections:

- `VLLM`: vLLM server configuration
- `hirag`: HiRAG system settings
- `model_params`: Model dimensions and token limits

## Architecture

The API consists of three main services:

1. **FileSearchService**: Handles file search using HiRAG vector search
2. **ChatSessionService**: Manages conversation sessions and message history
3. **RAGService**: Provides RAG-enhanced response generation using vLLM

## Deployment

For offline deployment:

1. Pre-download all required models
2. Configure vLLM servers with local models
3. Build Docker containers with all dependencies
4. Deploy without internet access

## Development

Run in development mode:
```bash
uvicorn api.main:app --reload
```

The API includes automatic interactive documentation at `/docs` powered by Swagger UI.