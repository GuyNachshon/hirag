#!/bin/bash

echo "=========================================="
echo "H100 8-Core GPU Monitoring Dashboard"
echo "Real-time monitoring of RAG services"
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
    echo -e "${BLUE}GPU Core Usage:${NC}"
    if command -v nvidia-smi > /dev/null; then
        # Header
        printf "%-5s %-15s %-12s %-12s %-8s %-20s\n" "Core" "Memory Used" "Memory Total" "Utilization" "Temp" "Service Assignment"
        echo "------------------------------------------------------------------------------------"
        
        # Get GPU info
        nvidia-smi --query-gpu=index,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits | while IFS=',' read -r index mem_used mem_total util temp; do
            # Trim whitespace
            index=$(echo $index | xargs)
            mem_used=$(echo $mem_used | xargs)
            mem_total=$(echo $mem_total | xargs)
            util=$(echo $util | xargs)
            temp=$(echo $temp | xargs)
            
            # Determine service assignment
            case $index in
                0) service="DotsOCR (Primary)" ;;
                1) service="DotsOCR (Secondary)" ;;
                2) service="LLM (Primary)" ;;
                3) service="LLM (Secondary)" ;;
                4) service="LLM (Tertiary)" ;;
                5) service="LLM (Quaternary)" ;;
                6) service="Embedding Server" ;;
                7) service="Whisper Service" ;;
                *) service="Unassigned" ;;
            esac
            
            # Color coding based on utilization
            if [ "$util" -gt 80 ]; then
                color=$RED
            elif [ "$util" -gt 50 ]; then
                color=$YELLOW
            else
                color=$GREEN
            fi
            
            printf "${color}%-5s${NC} %-12s %-12s %-8s%% %-6s°C %-20s\n" \
                "$index" "${mem_used}MB" "${mem_total}MB" "$util" "$temp" "$service"
        done
        echo ""
    else
        echo -e "${RED}nvidia-smi not available${NC}"
        echo ""
    fi
}

show_service_health() {
    echo -e "${BLUE}Service Health Checks:${NC}"
    
    # Define services with their ports and expected GPU cores
    declare -A SERVICES=(
        ["API"]="8080:0:CPU only"
        ["Embedding"]="8001:6:Core 6"
        ["DotsOCR"]="8002:0,1:Cores 0-1"
        ["LLM"]="8003:2,3,4,5:Cores 2-5"  
        ["Whisper"]="8004:7:Core 7"
        ["Frontend"]="3000:0:CPU only"
    )
    
    for service_name in "${!SERVICES[@]}"; do
        IFS=':' read -r port gpu_cores description <<< "${SERVICES[$service_name]}"
        
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
        
        printf "%-12s %s %-15s %s\n" "$service_name:" "$status" "($description)" ""
    done
    echo ""
}

show_container_logs() {
    echo -e "${BLUE}Recent Container Logs (last 3 lines each):${NC}"
    
    local containers=("rag-api" "rag-embedding-server" "rag-dots-ocr" "rag-llm-server" "rag-whisper" "rag-frontend")
    
    for container in "${containers[@]}"; do
        if docker ps | grep -q "$container"; then
            echo -e "${CYAN}$container:${NC}"
            docker logs "$container" --tail 3 2>/dev/null || echo "  No logs available"
            echo ""
        fi
    done
}

show_memory_breakdown() {
    echo -e "${BLUE}GPU Memory Breakdown:${NC}"
    if command -v nvidia-smi > /dev/null; then
        echo "Total GPU Memory Usage:"
        nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader | while IFS=',' read -r index mem_used mem_total; do
            index=$(echo $index | xargs)
            mem_used=$(echo $mem_used | xargs)
            mem_total=$(echo $mem_total | xargs)
            
            # Calculate percentage
            mem_percent=$((mem_used * 100 / mem_total))
            
            # Progress bar
            bar_length=20
            filled_length=$((mem_percent * bar_length / 100))
            bar=$(printf "%*s" $filled_length | tr ' ' '█')
            empty=$(printf "%*s" $((bar_length - filled_length)) | tr ' ' '░')
            
            if [ "$mem_percent" -gt 80 ]; then
                color=$RED
            elif [ "$mem_percent" -gt 60 ]; then
                color=$YELLOW
            else
                color=$GREEN
            fi
            
            printf "Core %s: ${color}[%s%s]${NC} %s%% (%s/%s MB)\n" \
                "$index" "$bar" "$empty" "$mem_percent" "$mem_used" "$mem_total"
        done
        echo ""
    fi
}

# Main monitoring loop
main() {
    # Check if this is a one-time run or continuous monitoring
    if [[ "$1" == "--once" ]]; then
        clear
        show_service_status
        show_gpu_usage
        show_service_health
        show_memory_breakdown
        exit 0
    fi
    
    if [[ "$1" == "--logs" ]]; then
        show_container_logs
        exit 0
    fi
    
    if [[ "$1" == "--help" ]]; then
        echo "Usage: $0 [OPTIONS]"
        echo "Monitor H100 8-core RAG system deployment"
        echo ""
        echo "Options:"
        echo "  --once       Show status once and exit"
        echo "  --logs       Show recent container logs"
        echo "  --help       Show this help"
        echo ""
        echo "Default: Continuous monitoring (updates every 5 seconds)"
        echo "Press Ctrl+C to exit continuous monitoring"
        exit 0
    fi
    
    # Continuous monitoring
    echo "Starting continuous monitoring (press Ctrl+C to exit)..."
    echo ""
    
    while true; do
        clear
        echo "Last updated: $(date)"
        echo ""
        show_service_status
        show_gpu_usage
        show_service_health
        show_memory_breakdown
        
        echo -e "${CYAN}Refreshing in 5 seconds... (Ctrl+C to exit)${NC}"
        sleep 5
    done
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${GREEN}Monitoring stopped.${NC}"; exit 0' INT

main "$@"