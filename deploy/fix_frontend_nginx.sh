#!/bin/bash

# Fix Frontend Nginx Configuration
# This script fixes the frontend nginx configuration to properly proxy to rag-api

set -e

echo "=== Fixing Frontend Nginx Configuration ==="

# Stop and remove the current frontend container
echo "Stopping current frontend container..."
docker stop rag-frontend 2>/dev/null || true
docker rm rag-frontend 2>/dev/null || true

# Create the nginx configuration if it doesn't exist
if [[ ! -f "frontend/nginx-frontend.conf" ]]; then
    echo "Creating nginx configuration..."
    mkdir -p frontend
    cat > frontend/nginx-frontend.conf << 'EOF'
server {
    listen 3000;
    server_name localhost;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;

    # Static file root
    root /usr/share/nginx/html;
    index index.html;

    # App routes
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Access-Control-Allow-Origin "*";
        try_files $uri =404;
    }

    # API proxy to backend (use Docker network service name)
    location /api/ {
        proxy_pass http://rag-api:8080/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # CORS headers
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
        add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;

        # Handle preflight requests
        if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Health check endpoint (proxy to backend health)
    location /health {
        proxy_pass http://rag-api:8080/health;
        proxy_set_header Host $host;
        access_log off;
    }
    
    # Frontend health check
    location /frontend-health {
        access_log off;
        add_header Content-Type text/plain;
        return 200 "frontend healthy\n";
    }

    # Error pages
    error_page 404 /index.html;
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
EOF
fi

# Redeploy frontend with proper nginx config
echo "Deploying frontend with fixed nginx configuration..."
docker run -d \
    --name rag-frontend \
    --network rag-network \
    --restart unless-stopped \
    -p 3000:3000 \
    -v $(pwd)/frontend/nginx-frontend.conf:/etc/nginx/conf.d/default.conf:ro \
    rag-frontend:latest

# Wait for container to start
echo "Waiting for frontend to start..."
sleep 5

# Check status
if docker ps | grep -q rag-frontend; then
    echo "✓ Frontend deployed with fixed nginx configuration"
    
    # Test the proxy
    echo "Testing API proxy..."
    if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
        echo "✓ API proxy is working"
    else
        echo "⚠ API proxy test failed - check logs with: docker logs rag-frontend"
    fi
    
    # Test frontend health
    if curl -s http://localhost:3000/frontend-health | grep -q "healthy"; then
        echo "✓ Frontend health check passed"
    else
        echo "⚠ Frontend health check failed"
    fi
else
    echo "✗ Frontend deployment failed"
    echo "Check logs with: docker logs rag-frontend"
fi

echo "=== Frontend fix complete ==="