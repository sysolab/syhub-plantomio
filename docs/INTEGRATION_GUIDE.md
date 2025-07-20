# SyHub Integration Guide

This guide shows how to integrate additional services into your SyHub Raspberry Pi setup.

## NTP Server Integration

### Option 1: Standalone Installation

Install NTP server independently:

```bash
# Make scripts executable
sudo chmod +x scripts/setup_ntp.sh
sudo chmod +x scripts/test_ntp.sh

# Install NTP server
sudo ./scripts/setup_ntp.sh install

# Test installation
sudo ./scripts/test_ntp.sh test
```

### Option 2: Integration with Main Setup Script

To integrate NTP server installation into your main `setup.sh` script, add the following section after the WiFi setup and before the final status display:

```bash
# Add this section to setup.sh main() function after WiFi setup
# Setup NTP Server
if should_process_component "ntp" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
  if confirm_install "NTP time synchronization server"; then
    log_message "Setting up NTP server"
    
    # Check if NTP integration script exists
    if [ -f "$BASE_DIR/scripts/integrate_ntp.sh" ]; then
      chmod +x "$BASE_DIR/scripts/integrate_ntp.sh"
      "$BASE_DIR/scripts/integrate_ntp.sh" install
    else
      log_message "NTP integration script not found, installing directly"
      if [ -f "$BASE_DIR/scripts/setup_ntp.sh" ]; then
        chmod +x "$BASE_DIR/scripts/setup_ntp.sh"
        "$BASE_DIR/scripts/setup_ntp.sh" install
      else
        log_message "NTP setup script not found, skipping NTP installation"
      fi
    fi
  else
    log_message "Skipping NTP server installation"
  fi
fi
```

### Option 3: Add to System Information Display

Add NTP status to the system information display by modifying the `display_system_info()` function:

```bash
# Add this section to display_system_info() function
# NTP Status
if systemctl is-active --quiet ntp; then
  NTP_STATUS=$(systemctl is-active ntp)
  echo "NTP Server: $NTP_STATUS"
  echo "NTP Port: 123/UDP"
  
  # Get IP addresses for client configuration
  local ipv4_addresses=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -3)
  if [ -n "$ipv4_addresses" ]; then
    echo "NTP Client IPs:"
    echo "$ipv4_addresses" | while read -r ip; do
      echo "  $ip"
    done
  fi
else
  echo "NTP Server: Not installed"
fi
echo ""
```

## Configuration Options

### Add NTP to Component Selection

To make NTP a selectable component, add it to the command line options in `setup.sh`:

```bash
# Add to the argument parsing section
SKIP_NTP=false

# Add to the argument parsing loop
-s|--skip-ntp)
SKIP_NTP=true
shift
;;

# Add to the help function
echo "  -t, --skip-ntp         : Skip NTP server installation"
```

### Add NTP to Configuration File

Add NTP configuration to your `config.yml`:

```yaml
# Add to config.yml
ntp:
  enabled: true
  port: 123
  external_servers:
    - "0.pool.ntp.org"
    - "1.pool.ntp.org"
    - "time.nist.gov"
  local_network: true
  broadcast: true
```

## Usage Examples

### Install Only NTP Server

```bash
sudo ./setup.sh --skip-mqtt --skip-nodered --skip-dashboard --skip-vm
```

### Install with NTP Server

```bash
sudo ./setup.sh
# Answer 'Y' when prompted for NTP server installation
```

### Test NTP Server

```bash
# Test NTP functionality
sudo ./scripts/test_ntp.sh test

# Show detailed information
sudo ./scripts/test_ntp.sh info

# Check service status
sudo systemctl status ntp
```

## Client Configuration Examples

### Linux/Unix Clients

```bash
# Manual time sync
sudo ntpdate <raspberry_pi_ip>

# Configure as permanent NTP server
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

### IoT Devices (ESP32/Arduino)

```cpp
// ESP32 example
#include <WiFi.h>
#include <time.h>

const char* ntpServer = "<raspberry_pi_ip>";
const long gmtOffset_sec = 0;
const int daylightOffset_sec = 3600;

void setup() {
    configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
}
```

## Monitoring and Maintenance

### Service Monitoring

```bash
# Check service status
sudo systemctl status ntp

# View real-time logs
sudo journalctl -u ntp -f

# Monitor peers
sudo ntpq -p

# Check synchronization
sudo ntpstat
```

### Performance Monitoring

```bash
# Monitor resource usage
htop  # General system monitoring
sudo ntpq -c "rv"  # NTP statistics
sudo ntpq -c "drift"  # Clock drift
```

## Troubleshooting

### Common Issues

1. **Service won't start**
   ```bash
   sudo journalctl -u ntp -n 50
   sudo ntpdate -q 0.pool.ntp.org
   ```

2. **No external sync**
   ```bash
   ping -c 3 0.pool.ntp.org
   sudo ntpq -p
   ```

3. **Firewall blocking**
   ```bash
   sudo ufw status
   sudo ufw allow 123/udp
   ```

### Diagnostic Commands

```bash
# Comprehensive diagnostics
sudo ./scripts/test_ntp.sh test

# Check network connectivity
netstat -uln | grep :123

# Test local query
sudo ntpdate -q 127.0.0.1
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

## Integration Benefits

### For IoT Applications

- **Accurate Timestamps**: All devices have synchronized time
- **Data Integrity**: Consistent time ordering of events
- **Coordinated Operations**: Devices can work in sync
- **Reliable Logging**: All logs use the same time reference

### For MQTT Infrastructure

- **Message Ordering**: MQTT messages have accurate timestamps
- **Event Correlation**: Events from different devices can be correlated
- **Data Analysis**: Time-series data is properly aligned

### For System Administration

- **Centralized Time**: Single source of truth for time
- **Reduced Complexity**: No need to configure time on each device
- **Offline Operation**: Works even without internet connectivity
- **Easy Monitoring**: Centralized time synchronization monitoring

## Conclusion

Integrating an NTP server into your SyHub setup provides reliable time synchronization for all connected devices. This is essential for IoT applications where accurate timing is crucial for data integrity and system coordination.

The provided scripts make installation and configuration straightforward, while the monitoring tools help ensure the service is working correctly. 