# Testing Transcription Chat Locally (Without Docker)

Quick guide for testing the chat system locally without rebuilding Docker images.

## Option 1: Local Development (Fastest for Testing)

### Prerequisites

Assumes you have the following services already running (in Docker or elsewhere):
- Embedding server: `http://localhost:8001` (Qwen3-Embedding-4B)
- LLM server: `http://localhost:8003` (GPT-OSS-20b)
- Whisper: `http://localhost:8004` (optional, only needed for new transcriptions)

### Setup

1. **Run database migration** (one-time):
```bash
cd /Users/guynachshon/Documents/baddon-ai/rag-v2
python migrate_add_embeddings.py
```

2. **Start API server**:
```bash
cd /Users/guynachshon/Documents/baddon-ai/rag-v2

# Make sure you're in the right Python environment
# If using virtual env:
source .venv/bin/activate  # or wherever your venv is

# Start API with hot reload
uvicorn api.main:app --host 0.0.0.0 --port 8080 --reload
```

3. **Start Frontend** (in another terminal):
```bash
cd /Users/guynachshon/Documents/baddon-ai/rag-v2/frontend

# Install dependencies (if not already done)
npm install

# Start development server
npm run dev
```

4. **Open browser**:
```
http://localhost:3000
```

### Testing Chat

1. Navigate to a transcript or folder in the UI
2. Open right sidebar (chat panel)
3. Type a message in Hebrew: "מה הנושא המרכזי?"
4. Press Enter or click send
5. Watch for AI response

### Check Logs

**API logs** (in terminal where uvicorn is running):
- Watch for `[Background] Starting embedding generation` after transcription
- Check `strategy_used: full_context` or `strategy_used: embedding_search`

**Frontend logs** (browser console - F12):
- Check for API request/response
- Look for any errors

---

## Option 2: Docker API + Local Frontend (Good for API Testing)

### Setup

1. **Build and run API in Docker**:
```bash
cd /Users/guynachshon/Documents/baddon-ai/rag-v2/runpod-deployment

# Build API image
./scripts/build/build_api_with_chat.sh

# Run just the API (assuming ML services are already running)
docker run -d \
  --name rag-api-dev \
  --network rag-network \
  -p 8080:8080 \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/logs:/app/logs \
  -e LOG_LEVEL=DEBUG \
  rag-api:latest
```

2. **Start Frontend locally**:
```bash
cd /Users/guynachshon/Documents/baddon-ai/rag-v2/frontend

# Set API URL
export NEXT_PUBLIC_API_URL=http://localhost:8080

# Start dev server
npm run dev
```

3. **Test**: Open `http://localhost:3000`

---

## Option 3: Use docker-compose.dev.yaml (API + Frontend Only)

If all ML services are already running:

```bash
cd /Users/guynachshon/Documents/baddon-ai/rag-v2/runpod-deployment

# Build API (if not already built)
./scripts/build/build_api_with_chat.sh

# Build frontend (if not already built)
cd ..
docker build -f runpod-deployment/dockerfiles/Dockerfile.frontend -t rag-frontend-complete:latest .

# Start API + Frontend only
cd runpod-deployment/configs
docker-compose -f docker-compose.dev.yaml up -d

# Check logs
docker-compose -f docker-compose.dev.yaml logs -f
```

---

## Quick API Testing (Without UI)

Test the chat API directly with curl:

### 1. Create a chat session
```bash
curl -X POST http://localhost:8080/api/transcription/chat/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "context_type": "folder",
    "context_id": "all",
    "name": "Test Session"
  }'

# Save the session_id from response
```

### 2. Send a message
```bash
curl -X POST http://localhost:8080/api/transcription/chat/{session_id}/message \
  -H "Content-Type: application/json" \
  -d '{
    "content": "מה יש לך?",
    "context_type": "folder",
    "context_id": "all"
  }'
```

### 3. Check response
Look for:
- `strategy_used`: Should be "full_context" or "embedding_search"
- `content`: AI response in Hebrew
- `segment_references`: List of relevant transcript segments (if any)
- `processing_time`: Time taken to generate response

---

## Troubleshooting

### Issue: "Connection refused" when API tries to reach LLM/Embedding services

**If running API locally** (not in Docker):
- LLM service should be at `http://localhost:8003`
- Embedding service should be at `http://localhost:8001`
- Check `HiRAG/config.yaml` has correct URLs:
```yaml
VLLM:
  llm:
    base_url: "http://localhost:8003/v1"
  embedding:
    base_url: "http://localhost:8001/v1"
```

**If running API in Docker**:
- LLM service should be at `http://rag-llm-server:8000/v1`
- Embedding service should be at `http://rag-embedding-server:8000/v1`
- Make sure API container is on `rag-network`
- Check with: `docker network inspect rag-network`

### Issue: Frontend can't reach API

**Check CORS settings** in `api/main.py`:
```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:8087"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

### Issue: Database migration fails

**Check database location**:
```bash
# Default location
ls -la /Users/guynachshon/Documents/baddon-ai/rag-v2/data/transcriptions.db

# Or set custom location
export DATABASE_DIR=/path/to/data
python migrate_add_embeddings.py
```

### Issue: No embeddings being generated

**Check embedding service**:
```bash
# Test embedding service directly
curl http://localhost:8001/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-Embedding-4B",
    "input": "test"
  }'
```

**Check API logs** for background task:
```bash
# Should see these messages after transcription
tail -f logs/api_main.log | grep Background

# Expected output:
# [Background] Starting embedding generation for transcript_id=...
# [Background] Successfully generated N embeddings in X seconds
```

---

## What to Test

### 1. Small Transcript (Full Context Mode)
- Upload a short audio file (<5 minutes)
- Wait for transcription to complete
- Open chat, ask: "סכם את השיחה הזו"
- Check logs: `strategy_used` should be "full_context"
- Verify response is accurate

### 2. Large Transcript (Embedding Search Mode)
- Upload a long audio file (>30 minutes)
- Wait for transcription + embedding generation
- Open chat, ask: "מה נאמר על [specific topic]?"
- Check logs: `strategy_used` should be "embedding_search"
- Verify segment references are relevant

### 3. Folder Context
- Create/select a folder with multiple transcripts
- Open chat, ask: "מה הנושאים המרכזיים בכל הפגישות?"
- Verify response references multiple transcripts

### 4. Conversation History
- Send multiple messages in same session
- Verify AI remembers previous context
- Check: GET `/api/transcription/chat/{session_id}/history`

### 5. Quick Actions
- Click a quick action button (if UI implemented)
- Verify pre-filled prompt is sent
- Check response is tailored to action type

---

## Performance Benchmarks

**Expected Response Times:**

| Scenario | Context Size | Strategy | Response Time |
|----------|-------------|----------|---------------|
| Small transcript | <40k words | Full context | 2-4 seconds |
| Large transcript | >40k words | Embedding search | 2-5 seconds |
| Folder (3 transcripts) | <100k total | Full context | 3-5 seconds |
| Folder (10+ transcripts) | >100k total | Embedding search | 3-6 seconds |

**Embedding Generation (Background):**
- 100 segments: ~5-10 seconds
- 500 segments: ~30-60 seconds
- 1000 segments: ~60-120 seconds

---

## Next Steps After Local Testing

Once you've verified everything works locally:

1. **Commit changes**:
```bash
git add .
git commit -m "feat: Add transcription chat with adaptive context"
```

2. **Build for production**:
```bash
cd runpod-deployment
./scripts/build/build_api_with_chat.sh
```

3. **Deploy to production**:
```bash
cd configs
docker-compose down
docker-compose up -d
```

4. **Monitor production**:
```bash
tail -f logs/api_main.log
tail -f logs/api_performance.log
```
