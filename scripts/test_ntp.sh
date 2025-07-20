#!/bin/bash

# NTP Server Test Script
# Tests NTP server functionality and provides diagnostics

set -e

# Colors for output
RED='\033[0;31m'
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

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# Test NTP service status
test_service_status() {
    log_message "Testing NTP service status..."
    
    if systemctl is-active --quiet ntp; then
        log_success "NTP service is running"
        return 0
    else
        log_error "NTP service is not running"
        return 1
    fi
}

# Test NTP port availability
test_port_availability() {
    log_message "Testing NTP port availability..."
    
    if netstat -uln | grep -q ":123 "; then
        log_success "NTP port 123/UDP is listening"
        return 0
    else
        log_error "NTP port 123/UDP is not listening"
        return 1
    fi
}

# Test NTP peer synchronization
test_peer_sync() {
    log_message "Testing NTP peer synchronization..."
    
    if command -v ntpq >/dev/null 2>&1; then
        local peer_count=$(ntpq -p | grep -c "^\*\|^o\|^+\|^-" 2>/dev/null || echo "0")
        
        if [ "$peer_count" -gt 0 ]; then
            log_success "NTP has $peer_count active peers"
            return 0
        else
            log_warning "NTP has no active peers (may be normal during initial sync)"
            return 1
        fi
    else
        log_error "ntpq command not available"
        return 1
    fi
}

# Test local NTP query
test_local_query() {
    log_message "Testing local NTP query..."
    
    if command -v ntpdate >/dev/null 2>&1; then
        if ntpdate -q 127.0.0.1 >/dev/null 2>&1; then
            log_success "Local NTP query successful"
            return 0
        else
            log_warning "Local NTP query failed"
            return 1
        fi
    else
        log_warning "ntpdate command not available"
        return 1
    fi
}

# Test external NTP servers
test_external_servers() {
    log_message "Testing external NTP server connectivity..."
    
    local servers=("0.pool.ntp.org" "time.nist.gov" "time.google.com")
    local success_count=0
    
    for server in "${servers[@]}"; do
        if ntpdate -q "$server" >/dev/null 2>&1; then
            log_success "Can reach external server: $server"
            ((success_count++))
        else
            log_warning "Cannot reach external server: $server"
        fi
    done
    
    if [ "$success_count" -gt 0 ]; then
        log_success "External connectivity: $success_count/${#servers[@]} servers reachable"
        return 0
    else
        log_error "No external NTP servers reachable"
        return 1
    fi
}

# Test client connectivity
test_client_connectivity() {
    log_message "Testing client connectivity..."
    
    # Get local IP addresses
    local ipv4_addresses=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -3)
    
    if [ -n "$ipv4_addresses" ]; then
        log_message "Available IP addresses for clients:"
        echo "$ipv4_addresses" | while read -r ip; do
            echo "  $ip"
        done
        
        # Test if we can bind to the port
        if timeout 5 bash -c "</dev/udp/127.0.0.1/123" 2>/dev/null; then
            log_success "NTP server is responding on localhost"
        else
            log_warning "NTP server not responding on localhost"
        fi
    else
        log_error "No IPv4 addresses found"
    fi
}

# Show detailed NTP information
show_ntp_info() {
    log_message "Showing detailed NTP information..."
    
    echo ""
    echo "=== NTP Service Status ==="
    systemctl status ntp --no-pager -l | head -20
    
    echo ""
    echo "=== NTP Peers ==="
    if command -v ntpq >/dev/null 2>&1; then
        ntpq -p
    else
        echo "ntpq not available"
    fi
    
    echo ""
    echo "=== System Time ==="
    date
    timedatectl status --no-pager | head -10
    
    echo ""
    echo "=== NTP Configuration ==="
    if [ -f "/etc/ntp.conf" ]; then
        grep -v "^#" /etc/ntp.conf | grep -v "^$" | head -20
    else
        echo "NTP configuration file not found"
    fi
    
    echo ""
    echo "=== Recent NTP Logs ==="
    journalctl -u ntp --no-pager -n 10
}

# Main test function
main() {
    echo "=========================================="
    echo "  NTP Server Diagnostic Test"
    echo "=========================================="
    echo ""
    
    local tests_passed=0
    local tests_total=0
    
    # Run tests
    test_service_status && ((tests_passed++))
    ((tests_total++))
    
    test_port_availability && ((tests_passed++))
    ((tests_total++))
    
    test_peer_sync && ((tests_passed++))
    ((tests_total++))
    
    test_local_query && ((tests_passed++))
    ((tests_total++))
    
    test_external_servers && ((tests_passed++))
    ((tests_total++))
    
    test_client_connectivity && ((tests_passed++))
    ((tests_total++))
    
    echo ""
    echo "=========================================="
    echo "Test Results: $tests_passed/$tests_total tests passed"
    echo "=========================================="
    
    if [ "$tests_passed" -eq "$tests_total" ]; then
        log_success "All tests passed! NTP server is working correctly."
    elif [ "$tests_passed" -ge 3 ]; then
        log_warning "Most tests passed. NTP server is mostly functional."
    else
        log_error "Many tests failed. NTP server may have issues."
    fi
    
    # Show detailed information
    show_ntp_info
}

# Help function
show_help() {
    echo "NTP Server Test Script"
    echo "====================="
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  test       : Run all tests (default)"
    echo "  info       : Show detailed NTP information"
    echo "  help       : Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 test    : Run all diagnostic tests"
    echo "  $0 info    : Show detailed NTP information"
    echo ""
}

# Parse command line arguments
case "${1:-test}" in
    test)
        main
        ;;
    info)
        show_ntp_info
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