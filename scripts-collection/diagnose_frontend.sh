#!/bin/bash

# Diagnose frontend connection issues

echo "=== Frontend Diagnostics ==="
echo ""

# 1. Check if container is running
echo "1. Container Status:"
docker ps -a | grep -E "frontend|NAMES" | head -5
echo ""

# 2. Check port mapping
echo "2. Port Mapping:"
docker port rag-frontend 2>/dev/null || echo "Container 'rag-frontend' not found"
echo ""

# 3. Check container logs for errors
echo "3. Recent Logs:"
docker logs rag-frontend --tail 20 2>&1 | head -30 || echo "Cannot get logs"
echo ""

# 4. Check nginx process inside container
echo "4. Nginx Process Inside Container:"
docker exec rag-frontend ps aux | grep nginx 2>/dev/null || echo "Cannot check processes"
echo ""

# 5. Check what's listening inside the container
echo "5. Ports Inside Container:"
docker exec rag-frontend netstat -tlpn 2>/dev/null || \
docker exec rag-frontend ss -tlpn 2>/dev/null || \
echo "Cannot check ports (netstat/ss not available)"
echo ""

# 6. Test connection from inside the container
echo "6. Test Internal Connection:"
docker exec rag-frontend curl -I http://localhost:3000 2>/dev/null || \
docker exec rag-frontend wget -O- http://localhost:3000 --spider 2>&1 | head -5 || \
echo "Cannot test internal connection"
echo ""

# 7. Check nginx config
echo "7. Nginx Configuration Test:"
docker exec rag-frontend nginx -t 2>&1 || echo "Cannot test nginx config"
echo ""

# 8. Check if custom nginx config is mounted
echo "8. Mounted Nginx Config:"
docker exec rag-frontend ls -la /etc/nginx/conf.d/ 2>/dev/null || echo "Cannot list nginx conf.d"
echo ""

# 9. Show the actual nginx config being used
echo "9. Active Nginx Config:"
docker exec rag-frontend cat /etc/nginx/conf.d/default.conf 2>/dev/null | head -20 || \
docker exec rag-frontend cat /etc/nginx/nginx.conf 2>/dev/null | head -20 || \
echo "Cannot read nginx config"
echo ""

# 10. Network connectivity test
echo "10. Network Test from Host:"
echo "Testing port 8087 (your mapped port):"
curl -I http://localhost:8087 2>&1 | head -5 || echo "Connection failed"
echo ""
echo "Testing port 3000 (if directly exposed):"
curl -I http://localhost:3000 2>&1 | head -5 || echo "Connection failed"
echo ""

# 11. Quick fix suggestions
echo "=== Quick Fix Suggestions ==="
echo ""
echo "If nginx is not running or config is wrong:"
echo "  docker exec rag-frontend nginx -s reload"
echo ""
echo "If port mapping is wrong (you want 8087->3000):"
echo "  docker stop rag-frontend"
echo "  docker rm rag-frontend"
echo "  docker run -d --name rag-frontend --network rag-network -p 8087:3000 rag-frontend:latest"
echo ""
echo "If nginx config is missing/wrong:"
echo "  # Create proper config and mount it:"
echo "  docker run -d --name rag-frontend \\"
echo "    --network rag-network \\"
echo "    -p 8087:3000 \\"
echo "    -v \$(pwd)/frontend/nginx-frontend.conf:/etc/nginx/conf.d/default.conf:ro \\"
echo "    rag-frontend:latest"
echo ""
echo "To test from inside the machine:"
echo "  curl http://localhost:8087"
echo "  curl http://localhost:8087/frontend-health"
echo "  curl http://localhost:8087/api/health"