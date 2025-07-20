#!/bin/bash

# SyHub NTP Server Setup Script
# This script installs and configures an NTP server on Raspberry Pi
# for connected IoT devices to sync their time

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NTP_PACKAGE="ntp"
NTP_CONFIG="/etc/ntp.conf"
NTP_KEYS="/etc/ntp.keys"
NTP_DRIFT="/var/lib/ntp/drift"
NTP_STATS="/var/log/ntpstats"
NTP_SERVICE="ntp"
NTP_PORT="123"

# Logging function
log_message() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "${BLUE}[$timestamp]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root: sudo $0"
        exit 1
    fi
}

# Check system requirements
check_system() {
    log_message "Checking system requirements..."
    
    # Check if running on Raspberry Pi
    if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        log_warning "This script is optimized for Raspberry Pi, but will continue on other systems"
    fi
    
    # Check available memory
    local mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    if [ "$mem_total" -lt 512000 ]; then
        log_warning "System has less than 512MB RAM. NTP server may be resource-intensive."
    fi
    
    # Check available disk space
    local disk_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$disk_space" -lt 100000 ]; then
        log_warning "Low disk space available. Consider freeing up space."
    fi
    
    log_success "System requirements check completed"
}

# Install NTP server
install_ntp() {
    log_message "Installing NTP server..."
    
    # Update package lists
    apt update || {
        log_error "Failed to update package lists"
        return 1
    }
    
    # Install NTP package
    if apt install -y "$NTP_PACKAGE"; then
        log_success "NTP server installed successfully"
    else
        log_error "Failed to install NTP server"
        return 1
    fi
    
    # Create necessary directories
    mkdir -p "$NTP_STATS"
    mkdir -p "$(dirname "$NTP_DRIFT")"
    
    # Set proper permissions
    chown ntp:ntp "$NTP_STATS" 2>/dev/null || true
    chown ntp:ntp "$(dirname "$NTP_DRIFT")" 2>/dev/null || true
}

# Configure NTP server
configure_ntp() {
    log_message "Configuring NTP server..."
    
    # Backup existing configuration
    if [ -f "$NTP_CONFIG" ]; then
        cp "$NTP_CONFIG" "${NTP_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        log_message "Backed up existing NTP configuration"
    fi
    
    # Get system timezone
    local timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
    
    # Create optimized NTP configuration for Raspberry Pi
    cat > "$NTP_CONFIG" << EOF
# SyHub NTP Server Configuration
# Optimized for Raspberry Pi and IoT devices

# Drift file
driftfile $NTP_DRIFT

# Statistics directory
statsdir $NTP_STATS/

# Log file
logfile /var/log/ntp.log

# Logging configuration
logconfig =syncall +clockall +peerall +sysall +authall

# Access control configuration
# Allow localhost and local network clients
restrict default kod nomodify notrap nopeer noquery
restrict -6 default kod nomodify notrap nopeer noquery

# Allow localhost
restrict 127.0.0.1
restrict -6 ::1

# Allow local network (adjust subnet as needed)
restrict 192.168.0.0 mask 255.255.0.0 nomodify notrap
restrict 10.0.0.0 mask 255.0.0.0 nomodify notrap
restrict 172.16.0.0 mask 255.240.0.0 nomodify notrap

# Allow specific clients (uncomment and modify as needed)
# restrict 192.168.1.100 nomodify notrap

# Server configuration
# Primary time servers (pool.ntp.org)
server 0.pool.ntp.org iburst
server 1.pool.ntp.org iburst
server 2.pool.ntp.org iburst
server 3.pool.ntp.org iburst

# Fallback servers
server time.nist.gov iburst
server time.google.com iburst

# Local clock as fallback (if no internet)
server 127.127.1.0
fudge 127.127.1.0 stratum 10

# Broadcast configuration (for local network)
broadcast 192.168.1.255
broadcast 10.3.141.255

# Multicast configuration
multicastclient

# Authentication (optional - for security)
# keys $NTP_KEYS
# trustedkey 1
# requestkey 1
# controlkey 1

# Performance tuning for Raspberry Pi
tinker panic 0
tinker dispersion 1000000
tinker stepout 900
tinker step 0.128

# Monitoring
enable monitor
EOF
    
    log_success "NTP configuration created"
    
    # Set proper permissions
    chown root:ntp "$NTP_CONFIG"
    chmod 644 "$NTP_CONFIG"
}

# Configure firewall for NTP
configure_firewall() {
    log_message "Configuring firewall for NTP..."
    
    # Check if ufw is available and enabled
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        log_message "UFW firewall detected, adding NTP rule..."
        ufw allow 123/udp comment "NTP server"
        log_success "Firewall rule added for NTP (port 123/UDP)"
    elif command -v iptables >/dev/null 2>&1; then
        log_message "Adding iptables rule for NTP..."
        iptables -A INPUT -p udp --dport 123 -j ACCEPT
        log_success "iptables rule added for NTP"
    else
        log_warning "No firewall detected or firewall not configured"
    fi
}

# Configure system time synchronization
configure_system_time() {
    log_message "Configuring system time synchronization..."
    
    # Disable systemd-timesyncd if it conflicts with NTP
    if systemctl is-active --quiet systemd-timesyncd; then
        log_message "Disabling systemd-timesyncd to avoid conflicts with NTP server"
        systemctl stop systemd-timesyncd
        systemctl disable systemd-timesyncd
    fi
    
    # Set timezone if not already set
    local current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "")
    if [ -z "$current_tz" ]; then
        log_message "Setting timezone to UTC"
        timedatectl set-timezone UTC
    fi
    
    # Enable NTP service
    systemctl enable "$NTP_SERVICE"
    
    log_success "System time configuration completed"
}

# Start and test NTP service
start_ntp_service() {
    log_message "Starting NTP service..."
    
    # Start the service
    if systemctl start "$NTP_SERVICE"; then
        log_success "NTP service started successfully"
    else
        log_error "Failed to start NTP service"
        return 1
    fi
    
    # Wait for service to stabilize
    log_message "Waiting for NTP service to stabilize..."
    sleep 10
    
    # Check service status
    if systemctl is-active --quiet "$NTP_SERVICE"; then
        log_success "NTP service is running"
    else
        log_error "NTP service is not running"
        return 1
    fi
}

# Test NTP server functionality
test_ntp_server() {
    log_message "Testing NTP server functionality..."
    
    # Wait a bit more for initial sync
    sleep 5
    
    # Check NTP status
    if command -v ntpq >/dev/null 2>&1; then
        log_message "NTP server status:"
        ntpq -p | head -20
        
        # Check if we have peers
        local peer_count=$(ntpq -p | grep -c "^\*\|^o\|^+\|^-" || echo "0")
        if [ "$peer_count" -gt 0 ]; then
            log_success "NTP server has $peer_count active peers"
        else
            log_warning "NTP server has no active peers yet (this is normal during initial sync)"
        fi
    fi
    
    # Test local NTP query
    if command -v ntpdate >/dev/null 2>&1; then
        log_message "Testing local NTP query..."
        if ntpdate -q 127.0.0.1 >/dev/null 2>&1; then
            log_success "Local NTP query successful"
        else
            log_warning "Local NTP query failed (may be normal during initial sync)"
        fi
    fi
}

# Get network information
get_network_info() {
    log_message "Getting network information..."
    
    # Get IP addresses
    local ipv4_addresses=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -5)
    local ipv6_addresses=$(ip -6 addr show | grep -oP '(?<=inet6\s)[0-9a-f:]+' | grep -v '::1' | head -3)
    
    echo ""
    echo "=========================================="
    echo "  NTP Server Configuration Complete!"
    echo "=========================================="
    echo ""
    echo "NTP Server Information:"
    echo "  Service: $NTP_SERVICE"
    echo "  Port: $NTP_PORT/UDP"
    echo "  Status: $(systemctl is-active $NTP_SERVICE)"
    echo ""
    
    if [ -n "$ipv4_addresses" ]; then
        echo "IPv4 Addresses for client configuration:"
        echo "$ipv4_addresses" | while read -r ip; do
            echo "  $ip"
        done
        echo ""
    fi
    
    if [ -n "$ipv6_addresses" ]; then
        echo "IPv6 Addresses for client configuration:"
        echo "$ipv6_addresses" | while read -r ip; do
            echo "  $ip"
        done
        echo ""
    fi
    
    echo "Client Configuration Examples:"
    echo "  Linux/Unix: ntpdate <ip_address>"
    echo "  Windows: w32tm /config /syncfromflags:manual /manualpeerlist:<ip_address>"
    echo "  IoT Devices: Set NTP server to <ip_address>"
    echo ""
    echo "Monitoring Commands:"
    echo "  Check status: sudo systemctl status ntp"
    echo "  View peers: sudo ntpq -p"
    echo "  View logs: sudo journalctl -u ntp -f"
    echo "  Test sync: sudo ntpdate -q 127.0.0.1"
    echo ""
    echo "=========================================="
}

# Create monitoring script
create_monitoring_script() {
    local monitor_script="/usr/local/bin/ntp-monitor.sh"
    
    cat > "$monitor_script" << 'EOF'
#!/bin/bash

# NTP Server Monitoring Script

echo "=== NTP Server Status ==="
systemctl status ntp --no-pager -l

echo ""
echo "=== NTP Peers ==="
ntpq -p

echo ""
echo "=== NTP Statistics ==="
ntpstat 2>/dev/null || echo "ntpstat not available"

echo ""
echo "=== System Time ==="
date
timedatectl status --no-pager

echo ""
echo "=== NTP Logs (last 10 lines) ==="
journalctl -u ntp --no-pager -n 10
EOF
    
    chmod +x "$monitor_script"
    log_success "Monitoring script created at $monitor_script"
}

# Main installation function
main() {
    log_message "Starting NTP server installation..."
    
    check_root
    check_system
    install_ntp
    configure_ntp
    configure_firewall
    configure_system_time
    start_ntp_service
    test_ntp_server
    create_monitoring_script
    get_network_info
    
    log_success "NTP server installation completed successfully!"
    log_message "Your Raspberry Pi is now serving as an NTP server for connected devices."
}

# Uninstall function
uninstall_ntp() {
    log_message "Uninstalling NTP server..."
    
    # Stop and disable service
    systemctl stop "$NTP_SERVICE" 2>/dev/null || true
    systemctl disable "$NTP_SERVICE" 2>/dev/null || true
    
    # Remove firewall rules
    if command -v ufw >/dev/null 2>&1; then
        ufw delete allow 123/udp 2>/dev/null || true
    fi
    
    # Uninstall package
    apt remove -y "$NTP_PACKAGE" 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    
    # Remove configuration files
    rm -f "$NTP_CONFIG" 2>/dev/null || true
    rm -f "$NTP_KEYS" 2>/dev/null || true
    
    # Remove monitoring script
    rm -f "/usr/local/bin/ntp-monitor.sh" 2>/dev/null || true
    
    # Re-enable systemd-timesyncd
    systemctl enable systemd-timesyncd 2>/dev/null || true
    systemctl start systemd-timesyncd 2>/dev/null || true
    
    log_success "NTP server uninstalled"
}

# Help function
show_help() {
    echo "SyHub NTP Server Setup Script"
    echo "============================="
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  install    : Install and configure NTP server (default)"
    echo "  uninstall  : Remove NTP server and restore system defaults"
    echo "  status     : Show NTP server status"
    echo "  test       : Test NTP server functionality"
    echo "  help       : Show this help message"
    echo ""
    echo "Examples:"
    echo "  sudo $0 install    : Install NTP server"
    echo "  sudo $0 uninstall  : Remove NTP server"
    echo "  sudo $0 status     : Check NTP server status"
    echo ""
}

# Parse command line arguments
case "${1:-install}" in
    install)
        main
        ;;
    uninstall)
        check_root
        uninstall_ntp
        ;;
    status)
        echo "=== NTP Server Status ==="
        systemctl status ntp --no-pager -l
        echo ""
        echo "=== NTP Peers ==="
        ntpq -p 2>/dev/null || echo "NTP server not running or ntpq not available"
        ;;
    test)
        test_ntp_server
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac 