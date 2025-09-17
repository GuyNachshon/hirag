# Langflow Docker container for offline deployment

FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Langflow
RUN pip install --no-cache-dir langflow

# Create data directory for flows and components
RUN mkdir -p /app/flows /app/components

# Copy any pre-built flows (optional)
# COPY flows/ /app/flows/

# Expose Langflow port
EXPOSE 7860

# Set environment variables
ENV LANGFLOW_HOST=0.0.0.0
ENV LANGFLOW_PORT=7860
ENV LANGFLOW_BACKEND_ONLY=false
ENV LANGFLOW_CACHE_TYPE=memory

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:7860/health || exit 1

# Start Langflow
CMD ["langflow", "run", "--host", "0.0.0.0", "--port", "7860", "--backend-only", "false"]