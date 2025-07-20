# NTP Server Setup for SyHub Raspberry Pi

This document describes how to set up and configure an NTP (Network Time Protocol) server on your Raspberry Pi hub to provide time synchronization for connected IoT devices.

## Overview

The NTP server allows all devices connected to your Raspberry Pi hub to synchronize their system clocks, which is essential for:
- Accurate data logging and timestamps
- Coordinated IoT device operations
- Reliable MQTT message ordering
- Consistent system behavior across your network

## Features

- **Optimized for Raspberry Pi**: Configured specifically for Raspberry Pi hardware and resource constraints
- **Robust Time Sources**: Multiple external NTP servers for redundancy
- **Local Network Support**: Broadcast and multicast support for automatic client discovery
- **Security**: Proper access controls and firewall configuration
- **Monitoring**: Built-in monitoring and diagnostic tools
- **Fallback Mode**: Local clock fallback when internet is unavailable

## Quick Installation

### Automatic Installation

```bash
# Make script executable and run
sudo chmod +x scripts/setup_ntp.sh
sudo ./scripts/setup_ntp.sh install
```

### Manual Installation

```bash
# Install NTP package
sudo apt update
sudo apt install -y ntp

# Configure NTP (see configuration section below)
sudo nano /etc/ntp.conf

# Start and enable service
sudo systemctl enable ntp
sudo systemctl start ntp
```

## Configuration

### NTP Server Configuration

The script creates an optimized `/etc/ntp.conf` with the following features:

#### Time Sources
- **Primary**: pool.ntp.org servers (0-3)
- **Fallback**: time.nist.gov, time.google.com
- **Local**: 127.127.1.0 (when internet is unavailable)

#### Access Control
- Allows localhost and local network clients
- Supports common subnets: 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12
- Broadcast support for automatic client discovery

#### Performance Tuning
- Optimized for Raspberry Pi resource constraints
- Reduced panic threshold for better stability
- Appropriate dispersion and stepout values

### Network Configuration

The script automatically:
- Configures UFW firewall rules (if enabled)
- Adds iptables rules (if UFW not available)
- Opens UDP port 123 for NTP traffic

## Usage

### Installation Commands

```bash
# Install NTP server
sudo ./scripts/setup_ntp.sh install

# Check status
sudo ./scripts/setup_ntp.sh status

# Test functionality
sudo ./scripts/setup_ntp.sh test

# Uninstall
sudo ./scripts/setup_ntp.sh uninstall
```

### Testing and Diagnostics

```bash
# Run comprehensive tests
sudo ./scripts/test_ntp.sh test

# Show detailed information
sudo ./scripts/test_ntp.sh info

# Manual monitoring
sudo ntpq -p                    # Show peers
sudo systemctl status ntp       # Service status
sudo journalctl -u ntp -f       # Live logs
```

## Client Configuration

### Linux/Unix Clients

```bash
# Manual sync
sudo ntpdate <raspberry_pi_ip>

# Configure as NTP server
echo "server <raspberry_pi_ip> iburst" | sudo tee -a /etc/ntp.conf
sudo systemctl restart ntp
```

### Windows Clients

```cmd
# Configure Windows Time service
w32tm /config /syncfromflags:manual /manualpeerlist:<raspberry_pi_ip>
w32tm /config /update
net stop w32time && net start w32time
```

### IoT Devices

For ESP32, Arduino, and other IoT devices:

```cpp
// Example for ESP32
#include <WiFi.h>
#include <time.h>

const char* ntpServer = "<raspberry_pi_ip>";
const long gmtOffset_sec = 0;
const int daylightOffset_sec = 3600;

void setup() {
    configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
}
```

### Docker Containers

```yaml
# docker-compose.yml
services:
  myapp:
    environment:
      - NTP_SERVER=<raspberry_pi_ip>
    volumes:
      - /etc/localtime:/etc/localtime:ro
```

## Monitoring and Maintenance

### Service Monitoring

```bash
# Check service status
sudo systemctl status ntp

# View real-time logs
sudo journalctl -u ntp -f

# Monitor peers
watch -n 5 'sudo ntpq -p'
```

### Performance Monitoring

```bash
# Check synchronization status
sudo ntpstat

# View detailed statistics
sudo ntpq -c "rv"

# Monitor drift
sudo ntpq -c "drift"
```

### Troubleshooting

#### Common Issues

1. **Service won't start**
   ```bash
   sudo journalctl -u ntp -n 50
   sudo ntpdate -q 0.pool.ntp.org  # Test external connectivity
   ```

2. **No peers synchronized**
   ```bash
   sudo ntpq -p  # Check peer status
   sudo systemctl restart ntp  # Restart service
   ```

3. **Firewall blocking**
   ```bash
   sudo ufw status  # Check UFW status
   sudo ufw allow 123/udp  # Allow NTP traffic
   ```

4. **High drift values**
   ```bash
   sudo ntpq -c "drift"  # Check drift
   sudo ntpq -c "pe"  # Check peer statistics
   ```

#### Diagnostic Commands

```bash
# Comprehensive diagnostics
sudo ./scripts/test_ntp.sh test

# Check network connectivity
ping -c 3 0.pool.ntp.org

# Test port availability
netstat -uln | grep :123

# Check system time
timedatectl status
```

## Security Considerations

### Access Control

The default configuration allows:
- Localhost access (127.0.0.1)
- Local network access (common subnets)
- Broadcast queries from local network

### Firewall Configuration

- UDP port 123 is opened for NTP traffic
- Only necessary network access is allowed
- External access is restricted to prevent abuse

### Authentication (Optional)

For enhanced security, you can enable NTP authentication:

```bash
# Generate NTP keys
sudo ntp-keygen -M

# Edit /etc/ntp.conf to enable authentication
# Uncomment and configure:
# keys /etc/ntp.keys
# trustedkey 1
# requestkey 1
# controlkey 1
```

## Integration with SyHub

### MQTT Integration

The NTP server works seamlessly with your MQTT infrastructure:

```python
# Example: Publish time sync status via MQTT
import paho.mqtt.client as mqtt
import time
import subprocess

def get_ntp_status():
    try:
        result = subprocess.run(['ntpstat'], capture_output=True, text=True)
        return result.stdout.strip()
    except:
        return "NTP not available"

# Publish status every minute
client.publish("syhub/ntp/status", get_ntp_status())
```

### Dashboard Integration

Add NTP status to your SyHub dashboard:

```javascript
// Example dashboard widget
function updateNTPStatus() {
    fetch('/api/ntp/status')
        .then(response => response.json())
        .then(data => {
            document.getElementById('ntp-status').textContent = data.status;
            document.getElementById('ntp-peers').textContent = data.peers;
        });
}
```

## Performance Optimization

### Raspberry Pi Specific

- **Memory Usage**: ~2-5MB RAM
- **CPU Usage**: Minimal (<1% on idle)
- **Network**: ~1KB/s for typical usage
- **Storage**: <10MB for logs and drift file

### Resource Monitoring

```bash
# Monitor resource usage
htop  # General system monitoring
iotop  # I/O monitoring
nethogs  # Network usage
```

## Backup and Recovery

### Configuration Backup

```bash
# Backup NTP configuration
sudo cp /etc/ntp.conf /etc/ntp.conf.backup

# Backup drift file
sudo cp /var/lib/ntp/drift /var/lib/ntp/drift.backup
```

### Recovery

```bash
# Restore configuration
sudo cp /etc/ntp.conf.backup /etc/ntp.conf
sudo systemctl restart ntp

# Restore drift file
sudo cp /var/lib/ntp/drift.backup /var/lib/ntp/drift
```

## Troubleshooting Guide

### Service Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| Service won't start | Configuration error | Check `/var/log/ntp.log` |
| No external sync | Network connectivity | Test with `ping 0.pool.ntp.org` |
| High drift | Hardware clock issues | Check RTC battery |
| Clients can't connect | Firewall blocking | Allow UDP port 123 |

### Log Analysis

```bash
# View NTP logs
sudo tail -f /var/log/ntp.log

# View system logs
sudo journalctl -u ntp -f

# Check for errors
sudo grep -i error /var/log/ntp.log
```

## Advanced Configuration

### Custom Time Sources

Edit `/etc/ntp.conf` to add custom time sources:

```
# Add custom servers
server your.ntp.server iburst
server another.ntp.server iburst
```

### Stratum Configuration

```bash
# Set local stratum (when no internet)
fudge 127.127.1.0 stratum 10
```

### Broadcast Configuration

```bash
# Enable broadcast for local network
broadcast 192.168.1.255
broadcast 10.3.141.255
```

## Support and Maintenance

### Regular Maintenance

- Monitor logs weekly
- Check peer status monthly
- Update NTP package quarterly
- Verify time accuracy annually

### Updates

```bash
# Update NTP package
sudo apt update
sudo apt upgrade ntp

# Restart service after update
sudo systemctl restart ntp
```

### Community Support

For additional support:
- Check system logs: `sudo journalctl -u ntp`
- Review NTP documentation: `man ntp.conf`
- Test with diagnostic script: `sudo ./scripts/test_ntp.sh`

## Conclusion

The NTP server provides reliable time synchronization for your SyHub IoT infrastructure. With proper configuration and monitoring, it ensures all connected devices maintain accurate time, which is crucial for data integrity and system coordination.

For questions or issues, refer to the troubleshooting section or run the diagnostic scripts provided. 