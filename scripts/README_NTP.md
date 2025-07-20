# NTP Server Scripts for SyHub

This directory contains scripts for setting up and managing an NTP (Network Time Protocol) server on your Raspberry Pi hub.

## Scripts Overview

### `setup_ntp.sh` - Main Installation Script
- Installs and configures NTP server
- Optimized for Raspberry Pi
- Configures firewall rules
- Sets up monitoring

**Usage:**
```bash
sudo ./setup_ntp.sh install    # Install NTP server
sudo ./setup_ntp.sh uninstall  # Remove NTP server
sudo ./setup_ntp.sh status     # Check status
sudo ./setup_ntp.sh test       # Test functionality
```

### `test_ntp.sh` - Diagnostic Script
- Comprehensive testing of NTP functionality
- Network connectivity tests
- Service status verification
- Performance monitoring

**Usage:**
```bash
sudo ./test_ntp.sh test  # Run all tests
sudo ./test_ntp.sh info  # Show detailed information
```

### `integrate_ntp.sh` - Integration Script
- Integrates NTP installation into main SyHub setup
- Interactive installation prompts
- Error handling and fallbacks

**Usage:**
```bash
sudo ./integrate_ntp.sh install  # Interactive installation
sudo ./integrate_ntp.sh test     # Test after installation
sudo ./integrate_ntp.sh info     # Show information
```

## Quick Start

### Standalone Installation
```bash
# Make scripts executable
sudo chmod +x scripts/setup_ntp.sh scripts/test_ntp.sh

# Install NTP server
sudo ./scripts/setup_ntp.sh install

# Test installation
sudo ./scripts/test_ntp.sh test
```

### Integration with SyHub
```bash
# Run integration script
sudo ./scripts/integrate_ntp.sh install
```

## Features

- **Raspberry Pi Optimized**: Configured for Pi hardware constraints
- **Robust Time Sources**: Multiple external NTP servers
- **Local Network Support**: Broadcast and multicast enabled
- **Security**: Proper access controls and firewall rules
- **Monitoring**: Built-in diagnostic tools
- **Fallback Mode**: Local clock when internet unavailable

## Client Configuration

### Linux/Unix
```bash
sudo ntpdate <raspberry_pi_ip>
```

### Windows
```cmd
w32tm /config /syncfromflags:manual /manualpeerlist:<raspberry_pi_ip>
```

### IoT Devices (ESP32)
```cpp
const char* ntpServer = "<raspberry_pi_ip>";
configTime(0, 0, ntpServer);
```

## Monitoring

### Service Status
```bash
sudo systemctl status ntp
sudo ntpq -p
sudo ntpstat
```

### Logs
```bash
sudo journalctl -u ntp -f
sudo tail -f /var/log/ntp.log
```

## Troubleshooting

### Common Issues
1. **Service won't start**: Check logs with `sudo journalctl -u ntp`
2. **No external sync**: Test connectivity with `ping 0.pool.ntp.org`
3. **Firewall blocking**: Allow UDP port 123

### Diagnostic Commands
```bash
sudo ./scripts/test_ntp.sh test  # Comprehensive diagnostics
netstat -uln | grep :123         # Check port availability
sudo ntpdate -q 127.0.0.1        # Test local query
```

## Configuration

The NTP server is configured with:
- **Port**: 123/UDP
- **External servers**: pool.ntp.org, time.nist.gov, time.google.com
- **Local fallback**: 127.127.1.0 (stratum 10)
- **Access control**: Local network only
- **Broadcast**: Enabled for automatic discovery

## Security

- UDP port 123 opened for NTP traffic
- Access restricted to local network
- No external access allowed
- Optional authentication available

## Performance

- **Memory**: ~2-5MB RAM
- **CPU**: <1% on idle
- **Network**: ~1KB/s typical usage
- **Storage**: <10MB for logs and drift

## Support

For detailed documentation, see:
- `docs/NTP_SERVER_SETUP.md` - Comprehensive setup guide
- `docs/INTEGRATION_GUIDE.md` - Integration instructions

For issues:
1. Run diagnostic tests: `sudo ./scripts/test_ntp.sh test`
2. Check service logs: `sudo journalctl -u ntp`
3. Verify network connectivity: `ping 0.pool.ntp.org` 