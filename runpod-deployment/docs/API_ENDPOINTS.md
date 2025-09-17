# API Endpoints Documentation

This document provides comprehensive details about all API endpoints available in the RAG system, organized by service and functionality.

## Base URLs

| Service | Base URL | Port | Health Check |
|---------|----------|------|--------------|
| API Gateway | `http://localhost:8080` | 8080 | `/health` |
| Frontend | `http://localhost:8087` | 8087 | `/frontend-health` |
| Langflow | `http://localhost:7860` | 7860 | `/health` |
| LLM Service | `http://localhost:8003` | 8003 | `/health` |
| Embedding Service | `http://localhost:8001` | 8001 | `/health` |
| Whisper Service | `http://localhost:8004` | 8004 | `/health` |
| OCR Service | `http://localhost:8002` | 8002 | `/health` |

---

## System Health & Status

### 1. System Health Check
- **Endpoint**: `GET /health`
- **Description**: Check overall system health
- **Response**: JSON with system status and service availability

```bash
curl http://localhost:8080/health
```

**Response Example**:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "services": {
    "llm": "healthy",
    "embedding": "healthy",
    "whisper": "healthy",
    "ocr": "healthy"
  },
  "gpu_status": {
    "total_gpus": 8,
    "available_gpus": 8,
    "memory_usage": "25%"
  }
}
```

### 2. Individual Service Health
- **File Search Service**: `GET /api/search/health`
- **Chat Service**: `GET /api/chat/health`
- **Frontend**: `GET /frontend-health`

---

## File Search & Retrieval

### 1. File Search
- **Endpoint**: `GET /api/search/files`
- **Description**: Search for files using natural language queries
- **Parameters**:
  - `q` (required): Search query
  - `limit` (optional): Maximum number of results (default: 10)
  - `file_types` (optional): Comma-separated file extensions
  - `include_content` (optional): Include file content in results

```bash
# Basic search
curl "http://localhost:8080/api/search/files?q=contract&limit=10"

# Search with file type filters
curl "http://localhost:8080/api/search/files?q=financial report&limit=5&file_types=.pdf,.xlsx"

# Search with content inclusion
curl "http://localhost:8080/api/search/files?q=budget analysis&include_content=true"
```

**Response Example**:
```json
{
  "results": [
    {
      "file_id": "doc_123",
      "filename": "Q3_Financial_Report.pdf",
      "path": "/uploads/reports/Q3_Financial_Report.pdf",
      "relevance_score": 0.95,
      "file_type": "pdf",
      "size": 2048576,
      "created_at": "2024-01-10T14:30:00Z",
      "summary": "Quarterly financial analysis...",
      "content_preview": "Executive Summary: Our Q3 results show..."
    }
  ],
  "total_results": 1,
  "query_time_ms": 150
}
```

### 2. File Upload
- **Endpoint**: `POST /api/search/upload`
- **Description**: Upload and index new files
- **Content-Type**: `multipart/form-data`

```bash
curl -X POST http://localhost:8080/api/search/upload \
  -F "file=@document.pdf" \
  -F "metadata={\"category\":\"financial\",\"tags\":[\"report\",\"Q3\"]}"
```

### 3. File Content Retrieval
- **Endpoint**: `GET /api/search/files/{file_id}/content`
- **Description**: Get full content of a specific file

```bash
curl http://localhost:8080/api/search/files/doc_123/content
```

---

## Chat & Conversation

### 1. Create Chat Session
- **Endpoint**: `POST /api/chat/sessions`
- **Description**: Create a new chat session
- **Content-Type**: `application/json`

```bash
curl -X POST http://localhost:8080/api/chat/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Project Discussion",
    "description": "Discussion about Q4 projects",
    "context_files": ["doc_123", "doc_456"]
  }'
```

**Response**:
```json
{
  "session_id": "sess_abc123",
  "name": "Project Discussion",
  "created_at": "2024-01-15T10:30:00Z",
  "status": "active"
}
```

### 2. Send Chat Message
- **Endpoint**: `POST /api/chat/{session_id}/message`
- **Description**: Send a message in a chat session
- **Content-Type**: `application/json`

```bash
curl -X POST http://localhost:8080/api/chat/sess_abc123/message \
  -H "Content-Type: application/json" \
  -d '{
    "content": "What are the key findings from the Q3 report?",
    "include_context": true,
    "max_context_chunks": 10
  }'
```

**Response**:
```json
{
  "message_id": "msg_xyz789",
  "response": "Based on the Q3 financial report, the key findings include...",
  "context_sources": [
    {
      "file_id": "doc_123",
      "relevance_score": 0.92,
      "content_snippet": "Q3 revenue increased by 15%..."
    }
  ],
  "timestamp": "2024-01-15T10:31:00Z"
}
```

### 3. Get Session Info
- **Endpoint**: `GET /api/chat/sessions/{session_id}`
- **Description**: Get session details and metadata

```bash
curl http://localhost:8080/api/chat/sessions/sess_abc123
```

### 4. Get Conversation History
- **Endpoint**: `GET /api/chat/sessions/{session_id}/history`
- **Description**: Retrieve chat history for a session
- **Parameters**:
  - `limit` (optional): Number of messages to retrieve
  - `offset` (optional): Pagination offset

```bash
curl "http://localhost:8080/api/chat/sessions/sess_abc123/history?limit=50"
```

### 5. Delete Session
- **Endpoint**: `DELETE /api/chat/sessions/{session_id}`
- **Description**: Delete a chat session and its history

```bash
curl -X DELETE http://localhost:8080/api/chat/sessions/sess_abc123
```

---

## Document Processing

### 1. OCR Processing
- **Endpoint**: `POST /api/ocr/process`
- **Description**: Extract text from images and scanned documents
- **Content-Type**: `multipart/form-data`

```bash
curl -X POST http://localhost:8080/api/ocr/process \
  -F "file=@scanned_document.pdf" \
  -F "options={\"language\":\"he\",\"preserve_layout\":true}"
```

**Response**:
```json
{
  "extracted_text": "טקסט מהמסמך הסרוק...",
  "confidence_score": 0.94,
  "processing_time_ms": 2500,
  "page_count": 3,
  "layout_preserved": true
}
```

### 2. Audio Transcription
- **Endpoint**: `POST /api/whisper/transcribe`
- **Description**: Transcribe audio files to text (Hebrew optimized)
- **Content-Type**: `multipart/form-data`

```bash
curl -X POST http://localhost:8080/api/whisper/transcribe \
  -F "audio=@meeting_recording.wav" \
  -F "options={\"language\":\"he\",\"include_timestamps\":true}"
```

**Response**:
```json
{
  "transcript": "זה תמליל של הקלטת הפגישה...",
  "language": "he",
  "duration_seconds": 1800,
  "timestamps": [
    {"start": 0.0, "end": 5.2, "text": "זה תמליל של הקלטת הפגישה"},
    {"start": 5.2, "end": 10.1, "text": "נושא הפגישה היה תכנון פרויקטים"}
  ],
  "confidence_score": 0.89
}
```

---

## Knowledge Graph Operations

### 1. Entity Extraction
- **Endpoint**: `POST /api/knowledge/extract-entities`
- **Description**: Extract entities and relationships from text
- **Content-Type**: `application/json`

```bash
curl -X POST http://localhost:8080/api/knowledge/extract-entities \
  -H "Content-Type: application/json" \
  -d '{
    "text": "חברת טכנולוגיה חדשה בתל אביב פיתחה מוצר AI מתקדם",
    "language": "he"
  }'
```

**Response**:
```json
{
  "entities": [
    {
      "text": "טכנולוגיה",
      "type": "ORGANIZATION",
      "confidence": 0.87
    },
    {
      "text": "תל אביב",
      "type": "LOCATION",
      "confidence": 0.95
    },
    {
      "text": "AI",
      "type": "CONCEPT",
      "confidence": 0.92
    }
  ],
  "relationships": [
    {
      "source": "טכנולוגיה",
      "relation": "LOCATED_IN",
      "target": "תל אביב",
      "confidence": 0.88
    }
  ]
}
```

### 2. Query Knowledge Graph
- **Endpoint**: `POST /api/knowledge/query`
- **Description**: Query the hierarchical knowledge graph
- **Content-Type**: `application/json`

```bash
curl -X POST http://localhost:8080/api/knowledge/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What companies are located in Tel Aviv?",
    "mode": "hierarchical",
    "max_results": 10
  }'
```

---

## Embedding & Similarity

### 1. Generate Embeddings
- **Endpoint**: `POST /api/embeddings/generate`
- **Description**: Generate vector embeddings for text
- **Content-Type**: `application/json`

```bash
curl -X POST http://localhost:8080/api/embeddings/generate \
  -H "Content-Type: application/json" \
  -d '{
    "texts": ["מסמך ראשון", "מסמך שני"],
    "model": "multilingual"
  }'
```

### 2. Similarity Search
- **Endpoint**: `POST /api/embeddings/similarity`
- **Description**: Find similar texts using embeddings
- **Content-Type**: `application/json`

```bash
curl -X POST http://localhost:8080/api/embeddings/similarity \
  -H "Content-Type: application/json" \
  -d '{
    "query_text": "תכנון פרויקטים",
    "top_k": 5,
    "threshold": 0.7
  }'
```

---

## Batch Operations

### 1. Batch File Processing
- **Endpoint**: `POST /api/batch/process-files`
- **Description**: Process multiple files in batch
- **Content-Type**: `application/json`

```bash
curl -X POST http://localhost:8080/api/batch/process-files \
  -H "Content-Type: application/json" \
  -d '{
    "file_ids": ["doc_123", "doc_456", "doc_789"],
    "operations": ["extract_entities", "generate_embeddings"],
    "priority": "high"
  }'
```

### 2. Batch Job Status
- **Endpoint**: `GET /api/batch/jobs/{job_id}/status`
- **Description**: Check status of batch processing job

```bash
curl http://localhost:8080/api/batch/jobs/job_abc123/status
```

---

## Administration & Monitoring

### 1. System Statistics
- **Endpoint**: `GET /api/admin/stats`
- **Description**: Get system performance statistics
- **Requires**: Admin authentication

```bash
curl -H "Authorization: Bearer admin_token" \
  http://localhost:8080/api/admin/stats
```

### 2. GPU Utilization
- **Endpoint**: `GET /api/admin/gpu-status`
- **Description**: Get real-time GPU usage information

```bash
curl http://localhost:8080/api/admin/gpu-status
```

**Response**:
```json
{
  "gpus": [
    {
      "id": 0,
      "name": "NVIDIA A100-SXM-80GB",
      "utilization": 75,
      "memory_used": "45GB",
      "memory_total": "80GB",
      "temperature": 68,
      "assigned_service": "whisper"
    }
  ],
  "total_utilization": 42
}
```

### 3. Service Logs
- **Endpoint**: `GET /api/admin/logs/{service}`
- **Description**: Retrieve recent logs for a specific service
- **Parameters**:
  - `lines` (optional): Number of log lines to retrieve
  - `level` (optional): Log level filter (ERROR, WARN, INFO, DEBUG)

```bash
curl "http://localhost:8080/api/admin/logs/llm?lines=100&level=ERROR"
```

---

## Error Handling

All endpoints return standard HTTP status codes and JSON error responses:

```json
{
  "error": {
    "code": "INVALID_REQUEST",
    "message": "Missing required parameter 'q'",
    "details": {
      "parameter": "q",
      "expected_type": "string"
    }
  },
  "timestamp": "2024-01-15T10:30:00Z",
  "request_id": "req_xyz123"
}
```

### Common Error Codes
- `400 Bad Request`: Invalid parameters or malformed request
- `401 Unauthorized`: Authentication required or invalid token
- `403 Forbidden`: Insufficient permissions
- `404 Not Found`: Resource not found
- `429 Too Many Requests`: Rate limit exceeded
- `500 Internal Server Error`: Server error
- `503 Service Unavailable`: Service temporarily unavailable

---

## Rate Limiting

API endpoints are rate-limited to ensure fair usage:

- **Search endpoints**: 100 requests/minute
- **Chat endpoints**: 50 requests/minute
- **Upload endpoints**: 20 requests/minute
- **Admin endpoints**: 200 requests/minute

Rate limit headers are included in responses:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1705315800
```

---

## Authentication

For endpoints requiring authentication, include the authorization header:

```bash
curl -H "Authorization: Bearer your_api_token" \
  http://localhost:8080/api/protected-endpoint
```

API tokens can be obtained through the admin interface or by contacting your system administrator.