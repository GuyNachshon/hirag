#!/bin/bash

# Simulate offline/airgapped environment for testing
# This script blocks external network access to test offline functionality

set -e

echo "============================================"
echo "       OFFLINE MODE SIMULATION TOOL        "
echo "============================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_header() { echo -e "\n=== $1 ==="; }

# Configuration
IPTABLES_BACKUP="/tmp/iptables-backup-$(date +%s)"
OFFLINE_MODE_ACTIVE=false

# Check if we're root or can use sudo
check_privileges() {
    if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        print_error "This script requires root privileges or passwordless sudo"
        echo "Run with: sudo $0"
        exit 1
    fi
}

# Backup current iptables rules
backup_iptables() {
    print_header "Backing Up Current Network Rules"

    if command -v iptables-save &> /dev/null; then
        iptables-save > $IPTABLES_BACKUP
        print_status "Network rules backed up to $IPTABLES_BACKUP"
    else
        print_warning "iptables-save not available, cannot backup rules"
    fi
}

# Enable offline mode
enable_offline_mode() {
    print_header "Enabling Offline Mode"

    print_info "This will block external network access while allowing:"
    echo "  • Local network communication (192.168.x.x, 10.x.x.x, 172.16-31.x.x)"
    echo "  • Localhost communication (127.x.x.x)"
    echo "  • Docker container networking"
    echo ""

    read -p "Continue? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 0
    fi

    # Set offline environment variables for all containers
    print_info "Setting offline environment variables..."

    # Get list of running containers
    containers=$(docker ps -q)
    if [ -n "$containers" ]; then
        for container in $containers; do
            container_name=$(docker inspect --format='{{.Name}}' $container | sed 's/\///')
            echo "  Setting offline vars for: $container_name"

            # We can't set env vars in running containers, but we can note them for restart
            echo "    (Will require container restart to take effect)"
        done
    fi

    # Configure iptables to simulate offline environment
    print_info "Configuring network isolation..."

    # Allow loopback
    iptables -I OUTPUT 1 -o lo -j ACCEPT
    iptables -I INPUT 1 -i lo -j ACCEPT

    # Allow local network ranges
    iptables -I OUTPUT 2 -d 10.0.0.0/8 -j ACCEPT
    iptables -I OUTPUT 3 -d 172.16.0.0/12 -j ACCEPT
    iptables -I OUTPUT 4 -d 192.168.0.0/16 -j ACCEPT

    # Allow Docker networks (typically 172.17.0.0/16 and custom networks)
    docker network ls --format "table {{.Name}}" | grep -v NETWORK | while read network; do
        if [ "$network" != "host" ] && [ "$network" != "none" ]; then
            subnet=$(docker network inspect $network --format='{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null)
            if [ -n "$subnet" ]; then
                iptables -I OUTPUT 5 -d $subnet -j ACCEPT
                echo "    Allowed Docker network: $network ($subnet)"
            fi
        fi
    done

    # Allow established connections
    iptables -I OUTPUT 6 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -I INPUT 6 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    # Block everything else outbound
    iptables -A OUTPUT -j DROP

    OFFLINE_MODE_ACTIVE=true
    print_status "Offline mode enabled"

    # Test connectivity
    print_info "Testing network isolation..."
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        print_warning "External connectivity still available (ping 8.8.8.8 succeeded)"
    else
        print_status "External connectivity blocked"
    fi

    if ping -c 1 127.0.0.1 >/dev/null 2>&1; then
        print_status "Localhost connectivity working"
    else
        print_error "Localhost connectivity broken!"
    fi
}

# Disable offline mode
disable_offline_mode() {
    print_header "Disabling Offline Mode"

    # Restore iptables rules
    if [ -f "$IPTABLES_BACKUP" ]; then
        print_info "Restoring network rules..."
        iptables-restore < $IPTABLES_BACKUP
        rm -f $IPTABLES_BACKUP
        print_status "Network rules restored"
    else
        print_warning "No backup found, flushing all rules..."
        iptables -F OUTPUT
        iptables -F INPUT
        iptables -P OUTPUT ACCEPT
        iptables -P INPUT ACCEPT
        print_status "Network rules cleared"
    fi

    OFFLINE_MODE_ACTIVE=false
    print_status "Offline mode disabled"

    # Test connectivity
    print_info "Testing network restoration..."
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        print_status "External connectivity restored"
    else
        print_warning "External connectivity still blocked"
    fi
}

# Test offline functionality
test_offline_functionality() {
    print_header "Testing Offline RAG System"

    if [ "$OFFLINE_MODE_ACTIVE" != "true" ]; then
        print_warning "Offline mode not active, testing anyway..."
    fi

    # Test Docker containers
    print_info "Testing Docker containers..."
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep rag || print_warning "No RAG containers running"

    # Test services
    print_info "Testing service endpoints..."

    services=(
        "8087:Frontend"
        "7860:Langflow"
        "8080:API"
        "8001:Embedding"
        "8003:LLM"
        "8004:Whisper"
        "8002:OCR"
    )

    healthy_count=0
    total_count=${#services[@]}

    for service in "${services[@]}"; do
        IFS=':' read -r port name <<< "$service"
        if curl -s --max-time 5 http://localhost:$port/health >/dev/null 2>&1; then
            print_status "$name (port $port) - healthy"
            ((healthy_count++))
        else
            # Try without /health endpoint
            if curl -s --max-time 5 http://localhost:$port >/dev/null 2>&1; then
                print_status "$name (port $port) - responding"
                ((healthy_count++))
            else
                print_error "$name (port $port) - not responding"
            fi
        fi
    done

    echo ""
    echo "Service Health Summary: $healthy_count/$total_count services responding"

    # Test model loading (check logs for download attempts)
    print_info "Checking for model download attempts..."
    download_attempts=false

    containers=$(docker ps --format "{{.Names}}" | grep rag)
    for container in $containers; do
        if docker logs $container --tail 50 2>&1 | grep -i "download\|fetch\|pull\|http" | grep -v "127.0.0.1\|localhost" >/dev/null; then
            print_warning "Container $container may be attempting downloads"
            download_attempts=true
        fi
    done

    if [ "$download_attempts" = false ]; then
        print_status "No external download attempts detected"
    fi

    # Test functional workflow
    print_info "Testing end-to-end workflow..."

    # Test embedding
    if curl -s --max-time 10 -X POST http://localhost:8001/v1/embeddings \
        -H "Content-Type: application/json" \
        -d '{"input": "test", "model": "embedding"}' >/dev/null 2>&1; then
        print_status "Embedding service functional"
    else
        print_error "Embedding service test failed"
    fi

    # Test LLM
    if curl -s --max-time 10 -X POST http://localhost:8003/v1/completions \
        -H "Content-Type: application/json" \
        -d '{"prompt": "Hello", "max_tokens": 5}' >/dev/null 2>&1; then
        print_status "LLM service functional"
    else
        print_error "LLM service test failed"
    fi

    # GPU utilization
    if command -v nvidia-smi >/dev/null 2>&1; then
        print_info "GPU Status:"
        nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used --format=csv,noheader | \
            while IFS=',' read -r gpu name util memory; do
                echo "    GPU $gpu ($name): ${util}% utilization, ${memory} memory"
            done
    fi
}

# Restart containers with offline settings
restart_containers_offline() {
    print_header "Restarting Containers with Offline Configuration"

    containers=$(docker ps --format "{{.Names}}" | grep rag)

    if [ -z "$containers" ]; then
        print_warning "No RAG containers found running"
        return
    fi

    print_info "Restarting containers with offline environment variables..."

    for container in $containers; do
        echo "Processing container: $container"

        # Get current container info
        image=$(docker inspect --format='{{.Config.Image}}' $container)
        ports=$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{$p}} {{end}}{{end}}' $container)

        print_info "  Stopping $container..."
        docker stop $container >/dev/null

        print_info "  Starting $container with offline settings..."

        # Restart with offline environment (this is a simplified example)
        # In practice, you'd need to preserve all the original docker run parameters
        case $container in
            *whisper*)
                docker run -d \
                    --name $container \
                    --network rag-network \
                    --gpus all \
                    --restart unless-stopped \
                    -p 8004:8004 \
                    -v $(pwd)/model-cache:/root/.cache/huggingface \
                    -e HF_HUB_OFFLINE=1 \
                    -e TRANSFORMERS_OFFLINE=1 \
                    -e DEVICE=cuda \
                    $image >/dev/null
                ;;
            *embedding*|*llm*)
                docker run -d \
                    --name $container \
                    --network rag-network \
                    --gpus all \
                    --restart unless-stopped \
                    -e HF_HUB_OFFLINE=1 \
                    -e TRANSFORMERS_OFFLINE=1 \
                    $image >/dev/null
                ;;
            *)
                docker start $container >/dev/null
                ;;
        esac

        print_status "  $container restarted"
    done

    print_info "Waiting for services to stabilize..."
    sleep 30
}

# Show current status
show_status() {
    print_header "Current Status"

    # Network status
    echo "Network Status:"
    if iptables -L OUTPUT | grep -q "policy DROP\|DROP.*all"; then
        print_warning "  Offline mode appears to be active"
    else
        print_info "  Normal network mode (online)"
    fi

    # Test external connectivity
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        print_info "  External connectivity: Available"
    else
        print_warning "  External connectivity: Blocked"
    fi

    # Docker containers
    echo ""
    echo "RAG Containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(NAMES|rag)" || echo "  No RAG containers running"

    # Environment variables check
    echo ""
    echo "Offline Environment Variables:"
    containers=$(docker ps -q --filter name=rag)
    for container in $containers; do
        name=$(docker inspect --format='{{.Name}}' $container | sed 's/\///')
        offline_vars=$(docker exec $container env | grep -E "HF_HUB_OFFLINE|TRANSFORMERS_OFFLINE" || echo "none")
        echo "  $name: $offline_vars"
    done
}

# Cleanup function
cleanup() {
    if [ "$OFFLINE_MODE_ACTIVE" = "true" ]; then
        print_warning "Offline mode is still active!"
        read -p "Disable offline mode before exit? (Y/n): " confirm
        if [[ ! $confirm =~ ^[Nn]$ ]]; then
            disable_offline_mode
        fi
    fi
}

# Main menu
main_menu() {
    while true; do
        print_header "Offline Mode Simulation Menu"
        echo ""
        echo "1) Show current status"
        echo "2) Enable offline mode (block external network)"
        echo "3) Test offline functionality"
        echo "4) Restart containers with offline config"
        echo "5) Disable offline mode (restore network)"
        echo "6) Exit"
        echo ""
        read -p "Choose option (1-6): " choice

        case $choice in
            1) show_status ;;
            2) backup_iptables; enable_offline_mode ;;
            3) test_offline_functionality ;;
            4) restart_containers_offline ;;
            5) disable_offline_mode ;;
            6) cleanup; exit 0 ;;
            *) print_error "Invalid option" ;;
        esac

        echo ""
        read -p "Press Enter to continue..."
    done
}

# Handle signals
trap cleanup EXIT INT TERM

# Main execution
echo "This tool simulates an offline/airgapped environment for testing"
echo "the RAG system without external network access."
echo ""

check_privileges

# If arguments provided, run non-interactively
if [ $# -gt 0 ]; then
    case $1 in
        "enable") backup_iptables; enable_offline_mode ;;
        "disable") disable_offline_mode ;;
        "test") test_offline_functionality ;;
        "status") show_status ;;
        *) echo "Usage: $0 [enable|disable|test|status]"; exit 1 ;;
    esac
else
    main_menu
fi