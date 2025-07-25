#!/bin/bash

# Simple FRP Setup Script
# Automatically downloads, configures, and runs FRP in server or client mode

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect system architecture
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "arm"
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "darwin"
    else
        print_error "Unsupported OS: $OSTYPE"
        exit 1
    fi
}

# Download and install FRP
install_frp() {
    local os=$(detect_os)
    local arch=$(detect_arch)
    local version="0.61.0"
    local filename="frp_${version}_${os}_${arch}.tar.gz"
    local url="https://github.com/fatedier/frp/releases/download/v${version}/${filename}"
    
    print_info "Downloading FRP v${version} for ${os}_${arch}..."
    
    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        print_error "Neither wget nor curl is available. Please install one of them."
        exit 1
    fi
    
    # Download
    if command -v wget &> /dev/null; then
        wget -q "$url" -O "$filename"
    else
        curl -L -s "$url" -o "$filename"
    fi
    
    # Extract
    print_info "Extracting FRP..."
    tar -xzf "$filename"
    
    # Move binaries
    local extract_dir="frp_${version}_${os}_${arch}"
    mv "${extract_dir}/frps" ./ 2>/dev/null || true
    mv "${extract_dir}/frpc" ./ 2>/dev/null || true
    
    # Make executable
    chmod +x frps frpc 2>/dev/null || true
    
    # Cleanup
    rm -rf "$filename" "$extract_dir"
    
    print_info "FRP installation completed!"
}

# Create server configuration
create_server_config() {
    local bind_port=$1
    local dashboard_port=${2:-7500}
    local vhost_port=${3:-8080}
    
    cat > frps.toml << EOF
bindPort = $bind_port
vhostHTTPPort = $vhost_port

[webServer]
addr = "0.0.0.0" 
port = $dashboard_port
user = "admin"
password = "admin"
EOF
    
    print_info "Server config created: frps.toml"
    print_info "Dashboard will be available at: http://YOUR_SERVER_IP:$dashboard_port"
    print_info "HTTP vhost port: $vhost_port"
    print_info "Dashboard credentials - user: admin, password: admin"
}

# Create client configuration
create_client_config() {
    local server_addr=$1
    local server_port=$2
    local proxy_name=$3
    local proxy_type=$4
    local local_port=$5
    local remote_port=$6
    
    if [[ "$proxy_type" == "http" ]]; then
        cat > frpc.toml << EOF
serverAddr = "$server_addr"
serverPort = $server_port

[[proxies]]
name = "$proxy_name"
type = "$proxy_type"
localPort = $local_port
customDomains = ["localhost"]
EOF
    else
        cat > frpc.toml << EOF
serverAddr = "$server_addr"
serverPort = $server_port

[[proxies]]
name = "$proxy_name"
type = "$proxy_type"
localPort = $local_port
remotePort = $remote_port
EOF
    fi
    
    print_info "Client config created: frpc.toml"
}

# Stop running FRP processes
stop_frp() {
    local stopped=false
    
    # Stop server if running
    if [[ -f "frps.pid" ]]; then
        local server_pid=$(cat frps.pid)
        if kill -0 "$server_pid" 2>/dev/null; then
            kill "$server_pid"
            print_info "Stopped FRP Server (PID: $server_pid)"
            stopped=true
        fi
        rm -f frps.pid
    fi
    
    # Stop client if running
    if [[ -f "frpc.pid" ]]; then
        local client_pid=$(cat frpc.pid)
        if kill -0 "$client_pid" 2>/dev/null; then
            kill "$client_pid"
            print_info "Stopped FRP Client (PID: $client_pid)"
            stopped=true
        fi
        rm -f frpc.pid
    fi
    
    # Find and stop any other frps/frpc processes using multiple methods
    # Method 1: pgrep
    local other_pids=$(pgrep -f "frps\|frpc" 2>/dev/null || true)
    
    # Method 2: ps + grep (more reliable)
    if [[ -z "$other_pids" ]]; then
        other_pids=$(ps aux | grep -E "[f]rps|[f]rpc" | awk '{print $2}' 2>/dev/null || true)
    fi
    
    # Method 3: direct process name search
    if [[ -z "$other_pids" ]]; then
        other_pids=$(pgrep "frps\|frpc" 2>/dev/null || true)
    fi
    
    if [[ -n "$other_pids" ]]; then
        for pid in $other_pids; do
            if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
                if kill "$pid" 2>/dev/null; then
                    print_info "Stopped FRP process (PID: $pid)"
                    stopped=true
                fi
            fi
        done
    fi
    
    if [[ "$stopped" == false ]]; then
        print_warn "No running FRP processes found"
    fi
}

# Check running status
check_status() {
    local running=false
    
    # Check server
    if [[ -f "frps.pid" ]]; then
        local server_pid=$(cat frps.pid)
        if kill -0 "$server_pid" 2>/dev/null; then
            print_info "FRP Server is running (PID: $server_pid)"
            running=true
        else
            print_warn "FRP Server PID file exists but process is not running"
            rm -f frps.pid
        fi
    fi
    
    # Check client
    if [[ -f "frpc.pid" ]]; then
        local client_pid=$(cat frpc.pid)
        if kill -0 "$client_pid" 2>/dev/null; then
            print_info "FRP Client is running (PID: $client_pid)"
            running=true
        else
            print_warn "FRP Client PID file exists but process is not running"
            rm -f frpc.pid
        fi
    fi
    
    if [[ "$running" == false ]]; then
        print_info "No FRP processes are currently running"
    fi
}

# Apply Ubuntu optimizations for FRP
optimize_ubuntu() {
    print_info "Applying Ubuntu optimizations for FRP..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_warn "Some optimizations require root privileges. Run as root for full optimization."
    fi
    
    local applied=0
    
    # 1. Increase file descriptor limits
    print_info "Setting file descriptor limits..."
    if [[ $EUID -eq 0 ]]; then
        # System-wide limits
        if ! grep -q "* soft nofile" /etc/security/limits.conf; then
            echo "* soft nofile 65535" >> /etc/security/limits.conf
            echo "* hard nofile 65535" >> /etc/security/limits.conf
            applied=$((applied + 1))
            print_info "✓ File descriptor limits set to 65535"
        else
            print_info "✓ File descriptor limits already configured"
        fi
    fi
    
    # Current session limits
    ulimit -n 65535 2>/dev/null && print_info "✓ Session file descriptor limit set"
    
    # 2. TCP optimizations
    if [[ $EUID -eq 0 ]]; then
        print_info "Applying TCP optimizations..."
        
        cat > /etc/sysctl.d/99-frp-optimization.conf << 'EOF'
# FRP TCP optimizations
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 65535
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_timestamps = 0
EOF
        
        sysctl -p /etc/sysctl.d/99-frp-optimization.conf >/dev/null 2>&1
        applied=$((applied + 1))
        print_info "✓ TCP optimizations applied"
    fi
    
    # 3. Create FRP systemd service
    if [[ $EUID -eq 0 ]]; then
        print_info "Creating systemd services..."
        
        # FRP Server service
        cat > /etc/systemd/system/frps.service << EOF
[Unit]
Description=FRP Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=5
ExecStart=$(pwd)/frps -c $(pwd)/frps.toml
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Delegate=yes
LimitNOFILE=65535
LimitNPROC=65535

[Install]
WantedBy=multi-user.target
EOF
        
        # FRP Client service
        cat > /etc/systemd/system/frpc.service << EOF
[Unit]
Description=FRP Client
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=5
ExecStart=$(pwd)/frpc -c $(pwd)/frpc.toml
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Delegate=yes
LimitNOFILE=65535
LimitNPROC=65535

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        applied=$((applied + 1))
        print_info "✓ Systemd services created (frps.service, frpc.service)"
        print_info "  Use: systemctl enable frps && systemctl start frps"
        print_info "  Use: systemctl enable frpc && systemctl start frpc"
    fi
    
    # 4. Install useful network tools
    if [[ $EUID -eq 0 ]] && command -v apt-get >/dev/null; then
        print_info "Installing network monitoring tools..."
        apt-get update >/dev/null 2>&1
        apt-get install -y htop iftop nethogs ss curl wget >/dev/null 2>&1
        applied=$((applied + 1))
        print_info "✓ Network tools installed (htop, iftop, nethogs, ss)"
    fi
    
    # 5. Configure log rotation
    if [[ $EUID -eq 0 ]]; then
        print_info "Setting up log rotation..."
        
        cat > /etc/logrotate.d/frp << 'EOF'
/root/frp/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
    maxsize 100M
}
EOF
        applied=$((applied + 1))
        print_info "✓ Log rotation configured"
    fi
    
    # 6. Set timezone and NTP
    if [[ $EUID -eq 0 ]]; then
        print_info "Configuring time synchronization..."
        timedatectl set-ntp true >/dev/null 2>&1
        applied=$((applied + 1))
        print_info "✓ NTP synchronization enabled"
    fi
    
    # 7. Firewall recommendations
    print_info "Firewall recommendations:"
    print_info "  Server: ufw allow 7000,7500,8080/tcp"
    print_info "  Client: No firewall changes needed"
    
    echo
    print_info "Applied $applied optimizations"
    print_warn "Reboot recommended for all optimizations to take effect"
    
    if [[ $applied -eq 0 ]]; then
        print_warn "Run as root (sudo) to apply system-level optimizations"
    fi
}

# Main menu
main() {
    print_info "=== FRP Simple Setup Script ==="
    echo
    
    # Check if binaries exist
    if [[ ! -f "frps" ]] || [[ ! -f "frpc" ]]; then
        print_info "FRP binaries not found. Installing..."
        install_frp
        echo
    fi
    
    # Ask for mode
    echo "Select mode:"
    echo "1) Server mode"
    echo "2) Client mode"
    echo "3) Stop running FRP processes"
    echo "4) Check FRP status"
    echo "5) Optimize Ubuntu for FRP"
    read -p "Enter choice (1-5): " mode_choice
    
    case $mode_choice in
        1)
            print_info "Setting up FRP Server..."
            
            # Server configuration
            read -p "Enter bind port (default: 7000): " bind_port
            bind_port=${bind_port:-7000}
            
            read -p "Enter dashboard port (default: 7500): " dashboard_port
            dashboard_port=${dashboard_port:-7500}
            
            read -p "Enter HTTP vhost port (default: 8080): " vhost_port
            vhost_port=${vhost_port:-8080}
            
            create_server_config "$bind_port" "$dashboard_port" "$vhost_port"
            
            print_info "Starting FRP Server in background..."
            print_info "Server will listen on port: $bind_port"
            print_info "Dashboard available at: http://$(hostname -I | awk '{print $1}'):$dashboard_port"
            echo
            
            nohup ./frps -c frps.toml > frps.log 2>&1 &
            local server_pid=$!
            echo $server_pid > frps.pid
            
            print_info "FRP Server started with PID: $server_pid"
            print_info "Logs: tail -f frps.log"
            print_info "Stop server: kill $server_pid"
            ;;
            
        2)
            print_info "Setting up FRP Client..."
            
            # Client configuration
            read -p "Enter server address (IP): " server_addr
            if [[ -z "$server_addr" ]]; then
                print_error "Server address is required!"
                exit 1
            fi
            
            read -p "Enter server port (default: 7000): " server_port
            server_port=${server_port:-7000}
            
            read -p "Enter proxy name (default: ssh): " proxy_name
            proxy_name=${proxy_name:-ssh}
            
            echo "Select proxy type:"
            echo "1) TCP (for SSH, databases, etc.)"
            echo "2) HTTP (for web services)"
            read -p "Enter choice (1 or 2, default: 1): " proxy_type_choice
            proxy_type_choice=${proxy_type_choice:-1}
            
            case $proxy_type_choice in
                1)
                    proxy_type="tcp"
                    read -p "Enter port to forward (default: 22 for SSH): " local_port
                    local_port=${local_port:-22}
                    remote_port=$local_port  # Use same port for remote
                    ;;
                2)
                    proxy_type="http"
                    read -p "Enter local port (default: 80): " local_port
                    local_port=${local_port:-80}
                    remote_port=""  # HTTP doesn't use remotePort
                    ;;
                *)
                    print_error "Invalid choice!"
                    exit 1
                    ;;
            esac
            
            create_client_config "$server_addr" "$server_port" "$proxy_name" "$proxy_type" "$local_port" "$remote_port"
            
            print_info "Starting FRP Client in background..."
            if [[ "$proxy_type" == "tcp" ]]; then
                print_info "Local service (port $local_port) will be accessible via: $server_addr:$local_port"
            else
                print_info "Local web service (port $local_port) will be accessible via server's vhost HTTP port"
            fi
            echo
            
            nohup ./frpc -c frpc.toml > frpc.log 2>&1 &
            local client_pid=$!
            echo $client_pid > frpc.pid
            
            print_info "FRP Client started with PID: $client_pid"
            print_info "Logs: tail -f frpc.log"
            print_info "Stop client: kill $client_pid"
            ;;
            
        3)
            print_info "Stopping FRP processes..."
            stop_frp
            ;;
            
        4)
            print_info "Checking FRP status..."
            check_status
            ;;
            
        5)
            print_info "Optimizing Ubuntu for FRP..."
            optimize_ubuntu
            ;;
            
        *)
            print_error "Invalid choice!"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"