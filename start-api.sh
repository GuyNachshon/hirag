#!/bin/bash
# Start the RAG Transcription API server

echo "Starting RAG Transcription API..."
echo "================================="
echo ""

# Activate virtual environment
source .venv/bin/activate

# Start uvicorn server
uvicorn api.main:app --host 0.0.0.0 --port 8080 --reload
