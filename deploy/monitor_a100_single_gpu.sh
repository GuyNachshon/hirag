#!/bin/bash

echo "=========================================="
echo "A100 Single GPU RAG System Monitor"
echo "Real-time monitoring for a2-highgpu-1g"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

show_service_status() {
    echo -e "${BLUE}Service Status:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(rag-|hebrew-rag)" | head -6
    echo ""
}

show_gpu_usage() {
    echo -e "${BLUE}A100 GPU Usage:${NC}"
    if command -v nvidia-smi > /dev/null; then
        # Header
        printf "%-15s %-12s %-12s %-10s %-8s %-20s\n" "Memory Used" "Memory Total" "Utilization" "Temp" "Power" "Service Load"
        echo "--------------------------------------------------------------------------------"
        
        # Get GPU info
        local gpu_data=$(nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null)
        
        if [[ -n "$gpu_data" ]]; then
            IFS=',' read -r mem_used mem_total util temp power <<< "$gpu_data"
            # Trim whitespace
            mem_used=$(echo $mem_used | xargs)
            mem_total=$(echo $mem_total | xargs)
            util=$(echo $util | xargs)
            temp=$(echo $temp | xargs)
            power=$(echo $power | xargs)
            
            # Convert to GB
            local mem_used_gb=$(echo "scale=1; $mem_used / 1024" | bc 2>/dev/null || echo "0")
            local mem_total_gb=$(echo "scale=1; $mem_total / 1024" | bc 2>/dev/null || echo "40")
            
            # Determine service load based on memory usage
            local service_load="Shared across all services"
            if (( $(echo "$mem_used > 30000" | bc -l 2>/dev/null || echo 0) )); then
                service_load="High load (all services)"
            elif (( $(echo "$mem_used > 20000" | bc -l 2>/dev/null || echo 0) )); then
                service_load="Medium load (multiple services)"
            elif (( $(echo "$mem_used > 5000" | bc -l 2>/dev/null || echo 0) )); then
                service_load="Light load (few services)"
            fi
            
            # Color coding based on utilization
            if [ "$util" -gt 80 ]; then
                color=$RED
            elif [ "$util" -gt 50 ]; then
                color=$YELLOW
            else
                color=$GREEN
            fi
            
            printf "${color}%-12s${NC} %-12s %-8s%% %-6s°C %-6sW %-20s\n" \
                "${mem_used_gb}GB" "${mem_total_gb}GB" "$util" "$temp" "$power" "$service_load"
        else
            echo "GPU data not available"
        fi
        echo ""
    else
        echo -e "${RED}nvidia-smi not available${NC}"
        echo ""
    fi
}

show_service_health() {
    echo -e "${BLUE}Service Health Checks:${NC}"
    
    # Define services with their expected memory usage
    declare -A SERVICES=(
        ["API"]="8080:CPU:CPU only"
        ["Embedding"]="8001:4GB:Lightweight embedding"
        ["DotsOCR"]="8002:12GB:Vision processing"
        ["LLM"]="8003:13GB:Language model"  
        ["Whisper"]="8004:6GB:Audio transcription"
        ["Frontend"]="3000:CPU:Web interface"
    )
    
    for service_name in "${!SERVICES[@]}"; do
        IFS=':' read -r port memory description <<< "${SERVICES[$service_name]}"
        
        if [[ "$service_name" == "Frontend" ]]; then
            url="http://localhost:$port/"
        else
            url="http://localhost:$port/health"
        fi
        
        if curl -s -f "$url" >/dev/null 2>&1; then
            status="${GREEN}✓ HEALTHY${NC}"
        else
            status="${RED}✗ UNHEALTHY${NC}"
        fi
        
        printf "%-12s %s %-15s %s\n" "$service_name:" "$status" "($memory)" "$description"
    done
    echo ""
}

show_memory_breakdown() {
    echo -e "${BLUE}A100 Memory Allocation:${NC}"
    if command -v nvidia-smi > /dev/null; then
        local gpu_data=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)
        
        if [[ -n "$gpu_data" ]]; then
            IFS=',' read -r mem_used mem_total <<< "$gpu_data"
            mem_used=$(echo $mem_used | xargs)
            mem_total=$(echo $mem_total | xargs)
            
            # Convert to GB
            local mem_used_gb=$(echo "scale=1; $mem_used / 1024" | bc 2>/dev/null || echo "0")
            local mem_total_gb=$(echo "scale=1; $mem_total / 1024" | bc 2>/dev/null || echo "40")
            local mem_free_gb=$(echo "scale=1; $mem_total_gb - $mem_used_gb" | bc 2>/dev/null || echo "0")
            
            # Calculate percentage
            local mem_percent=$(echo "scale=1; $mem_used * 100 / $mem_total" | bc 2>/dev/null || echo "0")
            
            # Progress bar
            local bar_length=30
            local filled_length=$(echo "($mem_percent * $bar_length) / 100" | bc 2>/dev/null || echo "0")
            local bar=$(printf "%*s" $filled_length | tr ' ' '█')
            local empty=$(printf "%*s" $((bar_length - filled_length)) | tr ' ' '░')
            
            if (( $(echo "$mem_percent > 85" | bc -l 2>/dev/null || echo 0) )); then
                color=$RED
                status="HIGH"
            elif (( $(echo "$mem_percent > 70" | bc -l 2>/dev/null || echo 0) )); then
                color=$YELLOW
                status="MODERATE"
            else
                color=$GREEN
                status="GOOD"
            fi
            
            echo "Total GPU Memory Usage:"
            printf "A100: ${color}[%s%s]${NC} %s%% (%sGB/%sGB used, %sGB free)\n" \
                "$bar" "$empty" "$mem_percent" "$mem_used_gb" "$mem_total_gb" "$mem_free_gb"
            printf "Status: ${color}%s${NC}\n" "$status"
            echo ""
            
            # Expected allocation breakdown
            echo "Expected Service Allocation:"
            echo "├─ Embedding Server:  4GB  (10%)"
            echo "├─ Whisper Service:   6GB  (15%)"
            echo "├─ DotsOCR Service:   12GB (30%)"
            echo "├─ LLM Service:       13GB (32.5%)"
            echo "└─ System Buffer:     5GB  (12.5%)"
            echo ""
        fi
    fi
}

show_system_resources() {
    echo -e "${BLUE}System Resources (a2-highgpu-1g):${NC}"
    
    # CPU usage
    if command -v top > /dev/null 2>&1; then
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' 2>/dev/null || echo "N/A")
        echo "CPU Usage: $cpu_usage (12 vCPUs available)"
    fi
    
    # Memory usage
    if command -v free > /dev/null 2>&1; then
        local mem_info=$(free -h | grep "^Mem:")
        local mem_used=$(echo "$mem_info" | awk '{print $3}')
        local mem_total=$(echo "$mem_info" | awk '{print $2}')
        local mem_available=$(echo "$mem_info" | awk '{print $7}')
        echo "System RAM: $mem_used used / $mem_total total ($mem_available available)"
    fi
    
    # Disk usage
    if command -v df > /dev/null 2>&1; then
        local disk_usage=$(df -h / | tail -1 | awk '{print $3 "/" $2 " (" $5 " used)"}')
        echo "Disk Usage: $disk_usage"
    fi
    
    echo ""
}

show_container_logs() {
    echo -e "${BLUE}Recent Container Logs (last 2 lines each):${NC}"
    
    local containers=("rag-api" "rag-embedding-server" "rag-dots-ocr" "rag-llm-server" "rag-whisper" "rag-frontend")
    
    for container in "${containers[@]}"; do
        if docker ps | grep -q "$container"; then
            echo -e "${CYAN}$container:${NC}"
            docker logs "$container" --tail 2 2>/dev/null | sed 's/^/  /' || echo "  No logs available"
            echo ""
        fi
    done
}

# Main monitoring function
main() {
    # Check if this is a one-time run or continuous monitoring
    if [[ "$1" == "--once" ]]; then
        clear
        show_service_status
        show_gpu_usage
        show_service_health
        show_memory_breakdown
        show_system_resources
        exit 0
    fi
    
    if [[ "$1" == "--logs" ]]; then
        show_container_logs
        exit 0
    fi
    
    if [[ "$1" == "--help" ]]; then
        echo "Usage: $0 [OPTIONS]"
        echo "Monitor A100 single GPU RAG system deployment"
        echo ""
        echo "Options:"
        echo "  --once       Show status once and exit"
        echo "  --logs       Show recent container logs"
        echo "  --help       Show this help"
        echo ""
        echo "Default: Continuous monitoring (updates every 3 seconds)"
        echo "Press Ctrl+C to exit continuous monitoring"
        exit 0
    fi
    
    # Continuous monitoring
    echo "Starting continuous monitoring (press Ctrl+C to exit)..."
    echo ""
    
    while true; do
        clear
        echo "A100 RAG System Monitor - Last updated: $(date)"
        echo ""
        show_service_status
        show_gpu_usage
        show_service_health
        show_memory_breakdown
        show_system_resources
        
        echo -e "${CYAN}Refreshing in 3 seconds... (Ctrl+C to exit, --once for single check)${NC}"
        sleep 3
    done
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${GREEN}Monitoring stopped.${NC}"; exit 0' INT

main "$@"