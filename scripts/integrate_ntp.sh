#!/bin/bash

# SyHub NTP Server Integration Script
# This script integrates NTP server installation into the main SyHub setup

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_message() {
    echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check if NTP should be installed
should_install_ntp() {
    local choice=""
    
    echo ""
    echo "=========================================="
    echo "  NTP Server Installation"
    echo "=========================================="
    echo ""
    echo "An NTP (Network Time Protocol) server allows connected devices"
    echo "to synchronize their system clocks with your Raspberry Pi."
    echo ""
    echo "Benefits:"
    echo "  • Accurate timestamps for data logging"
    echo "  • Coordinated IoT device operations"
    echo "  • Reliable MQTT message ordering"
    echo "  • Consistent system behavior"
    echo ""
    echo "Requirements:"
    echo "  • ~5MB RAM usage"
    echo "  • UDP port 123"
    echo "  • Internet connectivity for initial sync"
    echo ""
    
    read -p "Install NTP server for time synchronization? [Y/n]: " choice
    choice=${choice:-Y}
    
    case "$choice" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# Install NTP server
install_ntp_server() {
    log_message "Installing NTP server..."
    
    # Check if setup script exists
    if [ ! -f "scripts/setup_ntp.sh" ]; then
        log_warning "NTP setup script not found. Skipping NTP installation."
        return 1
    fi
    
    # Make script executable
    chmod +x scripts/setup_ntp.sh
    
    # Run NTP installation
    if scripts/setup_ntp.sh install; then
        log_success "NTP server installed successfully"
        return 0
    else
        log_warning "NTP server installation failed"
        return 1
    fi
}

# Test NTP server
test_ntp_server() {
    log_message "Testing NTP server functionality..."
    
    # Check if test script exists
    if [ ! -f "scripts/test_ntp.sh" ]; then
        log_warning "NTP test script not found. Skipping NTP testing."
        return 1
    fi
    
    # Make script executable
    chmod +x scripts/test_ntp.sh
    
    # Run NTP tests
    if scripts/test_ntp.sh test; then
        log_success "NTP server tests completed"
        return 0
    else
        log_warning "Some NTP server tests failed"
        return 1
    fi
}

# Show NTP information
show_ntp_info() {
    echo ""
    echo "=========================================="
    echo "  NTP Server Information"
    echo "=========================================="
    echo ""
    echo "NTP Server Status:"
    if systemctl is-active --quiet ntp; then
        echo "  ✓ Service is running"
    else
        echo "  ✗ Service is not running"
    fi
    
    # Get IP addresses
    local ipv4_addresses=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -3)
    
    if [ -n "$ipv4_addresses" ]; then
        echo ""
        echo "Client Configuration:"
        echo "  Use one of these IP addresses as your NTP server:"
        echo "$ipv4_addresses" | while read -r ip; do
            echo "    $ip"
        done
    fi
    
    echo ""
    echo "Management Commands:"
    echo "  Check status: sudo systemctl status ntp"
    echo "  View peers: sudo ntpq -p"
    echo "  Test sync: sudo ./scripts/test_ntp.sh test"
    echo "  View logs: sudo journalctl -u ntp -f"
    echo ""
    echo "=========================================="
}

# Main integration function
main() {
    log_message "Starting NTP server integration..."
    
    # Check if user wants to install NTP
    if should_install_ntp; then
        # Install NTP server
        if install_ntp_server; then
            # Test NTP server
            test_ntp_server
            
            # Show information
            show_ntp_info
            
            log_success "NTP server integration completed"
        else
            log_warning "NTP server installation failed, but continuing with setup"
        fi
    else
        log_message "NTP server installation skipped"
    fi
}

# Help function
show_help() {
    echo "SyHub NTP Server Integration"
    echo "============================"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  install    : Install NTP server (interactive)"
    echo "  test       : Test NTP server functionality"
    echo "  info       : Show NTP server information"
    echo "  help       : Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 install : Install NTP server"
    echo "  $0 test    : Test NTP server"
    echo "  $0 info    : Show NTP information"
    echo ""
}

# Parse command line arguments
case "${1:-install}" in
    install)
        main
        ;;
    test)
        test_ntp_server
        ;;
    info)
        show_ntp_info
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac 