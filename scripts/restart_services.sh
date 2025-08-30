#!/bin/bash

# Restart all RAG services

echo "🔄 Restarting offline RAG services..."

# Stop services
./scripts/stop_services.sh

# Wait a moment
sleep 5

# Start services  
./scripts/start_services.sh

echo "✅ Services restarted!"