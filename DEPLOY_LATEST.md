# Deployment Guide - Latest Updates

## Changes in this Deployment

### Backend

1. **CRITICAL FIX: Empty LLM Response Issue**
   - **Problem**: GPT-OSS reasoning model returns answers in `reasoning_content` field, not `content` field
   - **Root Cause**: GPT-OSS models use Chain-of-Thought reasoning. With `include_reasoning=false`, they put ALL tokens into internal reasoning and return empty `content`
   - **Solution**: Multi-layered approach:
     1. **Set include_reasoning=True**: Include reasoning in content field instead of separate reasoning_content
     2. **Use reasoning_effort parameter**: Control reasoning depth ("low" for chat, "medium" for insights)
     3. **Generous token allocation**: Start with 12000 tokens to accommodate reasoning chains
     4. **Retry with more tokens**: If still empty, retry with doubled tokens (12000 → 24000 → 40000)
     5. **Fallback extraction**: Extract from reasoning_content if content is still empty
   - **Key Insight**: With `include_reasoning=True` and `reasoning_effort=low`, responses are faster and appear in `content` field
   - **Model Specs**: GPT-OSS-20b supports 128k context length, so we can be generous with tokens
   - **Token Strategy**:
     - Chat: 12000 initial, 40000 max, reasoning_effort="low"
     - Insights: 20000 initial, 40000 max, reasoning_effort="medium"
   - **Real-world Results**: 12000 tokens with reasoning_effort="low" should work on first attempt
   - **Reference**: https://huggingface.co/openai/gpt-oss-120b/discussions/67
   - This completely fixes the "LLM returned empty content" error

2. **PDF Export Endpoint** - `GET /api/transcription/{transcript_id}/export?format=pdf`
   - Professional PDF generation with full RTL (Hebrew) support
   - Includes: title, metadata, insights section, full transcript with timestamps
   - Styled with teal theme (#0D9588)
   - Uses DejaVu Sans font for Hebrew (needs font installed on server)
   - **New Dependencies**: reportlab, arabic-reshaper, python-bidi

3. **Insights Generation Endpoint** - `POST /api/transcription/{transcript_id}/insights`
   - Generates structured insights: summary, key points, action items, topics
   - Uses comprehensive Hebrew system prompt
   - Caches results in database `insights` column (NEW)
   - Now uses higher token limits (20000-40000) for structured JSON output
   - **Database migration required**: Run `migrate_add_insights.py` to add column

4. **Improved Chat Responses**
   - Hybrid retry logic ensures responses are never empty
   - All prompts in Hebrew
   - Better handling of reasoning model output

### Frontend

1. **InsightsView - FULLY INTEGRATED**
   - ✅ Fixed mockInsights undefined error
   - ✅ Fixed 401 Unauthorized error - now uses apiClient with auth headers
   - Real API integration with POST /api/transcription/{id}/insights
   - Loading state with spinner and "מייצר תובנות..." text
   - Error handling with retry button
   - Conditional rendering for all sections
   - Auto-fetches insights when switching to insights view

2. **PDF Export Button**
   - New FileDown icon button in action buttons row
   - Opens PDF in new tab
   - Tooltip: "ייצא לPDF"
   - Green hover effect matching design system

3. **Chat Loading Indicator**
   - Already implemented and working
   - Shows Loader2 spinner with "מייצר תשובה..." while generating response

4. **Button Hover Colors**
   - Icons turn green/teal on hover
   - Consistent across all action buttons

5. **Markdown Rendering** ✅ ALREADY IMPLEMENTED
   - Chat responses render markdown using react-markdown + remark-gfm
   - Supports: bold, italic, lists, code blocks, links, tables (full GFM)
   - Custom prose styling for RTL Hebrew support
   - **Note:** Frontend must be rebuilt to get this feature on remote machine

## Deployment Steps on Remote Machine

### Quick Update (API Only - No Frontend Rebuild Needed)

If you only changed backend code (like the LLM fixes), you don't need to rebuild the frontend:

```bash
cd ~/hirag
git pull origin update-ui-gran

# Copy updated API code to the container's mounted volume
# (The API container mounts ~/hirag/api or source-code/api)
cp -r ~/hirag/api/* ~/hirag/runpod-deployment/source-code/api/

# Rebuild the API image (--no-cache forces fresh build, avoiding cached layers)
docker build --no-cache -f dockerfiles/Dockerfile.api -t rag-api:latest .

# Stop and remove old container, then start new one
docker stop rag-api && docker rm rag-api

docker run -d \
  --name rag-api \
  --network rag-network \
  -p 8080:8080 \
  -e HIRAG_CONFIG_PATH=/app/configs/hirag-config.yaml \
  -e LOG_LEVEL=INFO \
  -e PYTHONPATH=/app \
  -e CORS_ORIGINS=http://localhost:3000,http://localhost:8087,http://34.72.116.231:8087 \
  -v $(pwd)/configs:/app/configs \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/logs:/app/logs \
  -v model-cache:/root/.cache/huggingface \
  --restart unless-stopped \
  rag-api:latest

# Watch logs to verify new code is running
docker logs -f rag-api --tail 100
```

**What to look for in logs:**
- Token strategy should show `initial=12000, max=40000, reasoning_effort=low`
- For chat: Should get response on **first attempt** (no retries)
- Response should have content immediately (not empty on first try)
- Much faster responses due to reasoning_effort=low

### Full Deployment (When Frontend Also Changed)

### 1. Pull Latest Code and Update API

```bash
cd ~/hirag
git pull origin update-ui-gran

# IMPORTANT: Copy updated API code to source-code directory
cp -r ~/hirag/api/* ~/hirag/runpod-deployment/source-code/api/
```

### 2. Rebuild Frontend (If Frontend Code Changed)

**WHEN TO DO THIS:** Only if you changed frontend code (React components, UI, etc.). Skip if you only changed API/backend code.

**IMPORTANT:** The frontend must be rebuilt with the correct API URL as a build argument, and the source code must be copied to `source-code/` directory first!

**CRITICAL:** The API URL MUST be the **external IP address** (not `rag-api:8080`) because the browser needs to connect from outside!

```bash
# Step 0: Get your external IP address
curl -s ifconfig.me
# OR check your cloud provider dashboard for the instance's public IP
# Example: 34.72.116.231

# Step 1: Copy updated frontend to source-code
rm -rf ~/hirag/runpod-deployment/source-code/frontend
cp -r ~/hirag/frontend ~/hirag/runpod-deployment/source-code/

# Step 2: Copy updated API files
cp -r ~/hirag/api/* ~/hirag/runpod-deployment/source-code/api/

# Step 3: Rebuild frontend image with EXTERNAL API URL
cd ~/hirag/runpod-deployment

# ⚠️ REPLACE 34.72.116.231 WITH YOUR ACTUAL EXTERNAL IP ⚠️
docker build \
  -f dockerfiles/Dockerfile.frontend-nextjs \
  --build-arg NEXT_PUBLIC_API_URL=http://34.72.116.231:8080 \
  -t rag-frontend:latest .

# Step 4: Stop and remove old container
docker stop rag-frontend
docker rm rag-frontend

# Step 5: Start new container with correct port mapping
# CRITICAL: Map port 3000 (internal) to 8087 (external)
docker run -d \
  --name rag-frontend \
  --network rag-network \
  -p 8087:3000 \
  -e PORT=3000 \
  rag-frontend:latest

# Step 6: Verify the build worked correctly
# Check that the API URL was baked into the image
docker inspect rag-frontend:latest | grep NEXT_PUBLIC_API_URL
# Should show: "NEXT_PUBLIC_API_URL=http://YOUR_EXTERNAL_IP:8080"

# Check container logs
docker logs -f rag-frontend --tail 50
```

**TROUBLESHOOTING**: If you see `GET http://34.72.116.231:8087/34.72.116.231:8080/api/...` errors in browser:
- This means the API URL was NOT set during build
- Solution: Make sure you used `--build-arg NEXT_PUBLIC_API_URL=http://YOUR_EXTERNAL_IP:8080`
- Rebuild the image with the correct build arg (see Step 3 above)
```

**Why these specific settings?**
- `--build-arg NEXT_PUBLIC_API_URL=http://YOUR_EXTERNAL_IP:8080` - **MUST be external IP!** The browser needs to reach the API from outside the Docker network
- `-p 8087:3000` - Maps internal port 3000 to external port 8087
- `-e PORT=3000` - Tells Next.js to listen on port 3000 internally
- Source code MUST be in `source-code/` because that's what the Dockerfile expects

**Common mistake:** Using `http://rag-api:8080` won't work! That's only accessible inside Docker network. The browser needs the public IP.

### 3. Install New Python Dependencies

```bash
# Enter the API container
docker exec -it rag-api bash

# Install new dependencies
pip install reportlab>=4.0.0 arabic-reshaper>=3.0.0 python-bidi>=0.4.2

# Exit container
exit
```

**Note**: These are needed for PDF export with RTL (Hebrew) support.

### 4. Run Database Migration and Restart API

```bash
# Enter API container
docker exec -it rag-api bash

# Run migration to add insights column
python api/migrate_add_insights.py

# Exit container
exit

# Restart API to pick up all code changes
docker restart rag-api

# Check logs for any errors
docker logs -f rag-api --tail 100
```

**Important**: Watch for any import errors related to the new dependencies. The migration should show "✓ Successfully added insights column" or "✓ Insights column already exists".

### 5. Verify Everything Works

```bash
# Test API health
curl http://localhost:8080/health

# Test chat health
curl http://localhost:8080/api/transcription/chat/health

# Check frontend
curl http://localhost:8087/frontend-health
```

### 6. Test in Browser

1. **Upload a new transcript** (to test with fresh data)
2. **Test chat** - Should show loading spinner "מייצר תשובה...", then response with markdown
   - **IMPORTANT**: Responses should no longer be empty! The retry logic will automatically handle token limits
   - Check API logs to see retry attempts if query is complex
3. **Test button hovers** - Icons should turn green/teal
4. **Click insights button** - Should switch view and automatically generate insights
   - Shows loading spinner "מייצר תובנות..."
   - Displays summary, key points, action items, topics
   - Cached in database for subsequent views
5. **Test PDF export** - Click FileDown button
   - Should download PDF with Hebrew text (RTL)
   - Includes metadata, insights, and full transcript

## Known Issues to Monitor

1. **Speaker Diarization** - Need to verify:
   - Check if Whisper is actually identifying speakers
   - Look at transcript segments to see if `speaker_label` is populated
   - May need to adjust Whisper service parameters

2. **PDF Font on Server**
   - PDF export uses DejaVu Sans for Hebrew support
   - Path: `/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf`
   - If font not found, falls back to Helvetica (limited Hebrew support)
   - To install DejaVu fonts: `apt-get install fonts-dejavu`

3. **Token Usage Monitoring**
   - Check API logs for retry attempts and debug messages
   - Debug logs now show actual `reasoning_content` for troubleshooting
   - Current settings: Chat 12000→40000, Insights 12000→24000
   - Testing showed: 4000 tokens = empty, 8000 tokens = success, so 12000 should eliminate retries
   - Logs show: "LLM call attempt N/3 with max_tokens=X"
   - Look for: "DEBUG reasoning_content - length: X" to see extraction process

## What's Fixed

1. ✅ **Empty LLM responses** - include_reasoning=True + reasoning_effort parameter
2. ✅ **mockInsights error** - Full API integration in InsightsView
3. ✅ **Insights 401 error** - Now uses apiClient with proper auth headers
4. ✅ **Insights AttributeError** - Added insights column to Transcript model
5. ✅ **Insights negative max_tokens** - Truncate long transcripts to 60k chars
6. ✅ **Markdown rendering** - Chat responses render bold, lists, code blocks
7. ✅ **Loading indicators** - Spinner + "מייצר תשובה..." during chat
8. ✅ **Button hover colors** - Green/teal hover effects
9. ✅ **PDF export** - Complete with RTL Hebrew support

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
