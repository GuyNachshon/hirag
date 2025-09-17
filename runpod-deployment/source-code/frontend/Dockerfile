# Frontend Dockerfile - Standalone service with nginx
# Simple approach: build locally, package built files

# Production stage with nginx
FROM nginx:alpine

# Copy built frontend files (built locally)
COPY dist /usr/share/nginx/html

# Copy nginx configuration
COPY nginx-frontend.conf /etc/nginx/conf.d/default.conf

# Create startup script
RUN echo '#!/bin/sh\n\
echo "Starting Hebrew RAG Frontend with Nginx..."\n\
echo "Frontend will be available at: http://localhost:3000"\n\
echo "Backend API should be running at: http://localhost:8000"\n\
echo "Make sure the backend container is running before accessing the frontend"\n\
nginx -g "daemon off;"\n\
' > /app/start.sh && chmod +x /app/start.sh

# Expose port
EXPOSE 3000

# Start nginx
CMD ["/app/start.sh"] 