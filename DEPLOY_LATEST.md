# Deployment Guide - Latest Updates

## Changes in this Deployment

### Backend
1. **Insights Generation Endpoint** - `POST /api/transcription/{transcript_id}/insights`
   - Generates structured insights: summary, key points, action items, topics
   - Uses comprehensive Hebrew system prompt
   - Caches results in database

2. **Streaming Chat** - `POST /api/transcription/chat/{session_id}/message/stream`
   - Server-Sent Events (SSE) for real-time token streaming
   - Ready for frontend implementation

3. **Improved Chat Responses**
   - Added `include_reasoning=false` to vLLM calls
   - Should get cleaner, more concise responses
   - All prompts now in Hebrew

### Frontend
1. **Real Chat Integration**
   - Creates chat session on page load
   - Sends messages to real API
   - Loading indicator while generating responses

2. **Markdown Rendering**
   - Chat responses now render markdown (bold, lists, code, etc.)
   - Custom styling for RTL support

3. **Button Hover Colors**
   - Icons now turn green/teal on hover
   - Better visual feedback

4. **InsightsView** - Partially ready (needs API integration completion)

## Deployment Steps on Remote Machine

### 1. Pull Latest Code

```bash
cd ~/hirag
git pull origin update-ui-gran
```

### 2. Rebuild Frontend

```bash
cd ~/hirag/frontend
npm run build

# Stop and remove old container
docker stop rag-frontend
docker rm rag-frontend

# Rebuild image
docker build -t rag-frontend:latest .

# Start new container (use your existing docker run command)
docker run -d \
  --name rag-frontend \
  --network rag-network \
  -p 8087:3000 \
  -e NEXT_PUBLIC_API_URL=http://rag-api:8080 \
  rag-frontend:latest
```

### 3. Update Backend Files (No rebuild needed - just restart)

```bash
# Restart API to pick up changes
docker restart rag-api

# Check logs
docker logs -f rag-api --tail 100
```

### 4. Verify Everything Works

```bash
# Test API health
curl http://localhost:8080/health

# Test chat health
curl http://localhost:8080/api/transcription/chat/health

# Check frontend
curl http://localhost:8087/frontend-health
```

### 5. Test in Browser

1. **Upload a new transcript** (to test with fresh data)
2. **Test chat** - Should show loading spinner, then response with markdown
3. **Test button hovers** - Icons should turn green
4. **Click insights button** - Should switch view (though insights won't generate yet without completing the frontend integration)

## Known Issues to Monitor

1. **InsightsView** - Currently references `mockInsights` which doesn't exist
   - View will switch but may show errors
   - Need to add API call: `apiClient.generateInsights(transcriptId)`
   - This can be fixed in next iteration

2. **Speaker Diarization** - Need to verify:
   - Check if Whisper is actually identifying speakers
   - Look at transcript segments to see if `speaker_label` is populated
   - May need to adjust Whisper service parameters

3. **LLM Response Quality**
   - With `include_reasoning=false`, responses should be cleaner
   - Monitor if answers are complete or too brief
   - Can adjust prompts if needed

## Rollback Plan

If something breaks:

```bash
# Rollback git
cd ~/hirag
git checkout HEAD~1

# Rebuild and restart
cd frontend && npm run build
docker build -t rag-frontend:latest .
docker stop rag-frontend && docker rm rag-frontend
# ... run docker run command ...
docker restart rag-api
```

## Quick Logs Check

```bash
# API logs
docker logs rag-api --tail 100 -f

# Frontend logs
docker logs rag-frontend --tail 100 -f

# LLM server logs
docker logs rag-llm-server --tail 100 -f
```
