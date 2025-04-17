#!/bin/bash

# BeeHiveLite Project Creation Script
# Creates all directories and files for BeeHiveLite IoT Monitoring System
# Run as: bash create_beehivelite.sh
# Date: April 17, 2025

set -e

# Use current user's home directory
BASE_DIR="./"

# Create directory structure
echo "Creating directory structure..."
mkdir -p "$BASE_DIR/config"
mkdir -p "$BASE_DIR/scripts"
mkdir -p "$BASE_DIR/src/static/css"
mkdir -p "$BASE_DIR/logs"
mkdir -p "$BASE_DIR/backups"

# Create config/.env
echo "Creating config/.env..."
cat << EOF > "$BASE_DIR/config/.env"
# BeeHiveLite Configuration
WIFI_SSID=beehivelite_ap
WIFI_PASSWORD=beehivelite123
STA_WIFI_SSID=YourRouterSSID
STA_WIFI_PASSWORD=YourRouterPassword
MQTT_USERNAME=beehivelite
MQTT_PASSWORD=beehivelitePass
MQTT_PORT=1883
MQTT_TOPIC=v1/devices/me/telemetry
INFLUXDB_PASSWORD=adminPass
DASHBOARD_PORT=5000
EMAIL_SENDER=beehivelite@example.com
EMAIL_PASSWORD=your-email-password
EMAIL_RECEIVER=admin@example.com
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
EOF

# Create config/hostapd.conf.j2
echo "Creating config/hostapd.conf.j2..."
cat << EOF > "$BASE_DIR/config/hostapd.conf.j2"
interface=wlan0
driver=nl80211
ssid=__WIFI_SSID__
hw_mode=g
channel=6
wpa=2
wpa_passphrase=__WIFI_PASSWORD__
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
EOF

# Create config/dhcpcd.conf.j2
echo "Creating config/dhcpcd.conf.j2..."
cat << EOF > "$BASE_DIR/config/dhcpcd.conf.j2"
interface wlan0
static ip_address=192.168.4.1/24
nohook wpa_supplicant

profile YourRouterSSID
interface wlan0
ssid __STA_WIFI_SSID__
psk __STA_WIFI_PASSWORD__
EOF

# Create config/dnsmasq.conf.j2
echo "Creating config/dnsmasq.conf.j2..."
cat << EOF > "$BASE_DIR/config/dnsmasq.conf.j2"
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
EOF

# Create config/mosquitto.conf.j2
echo "Creating config/mosquitto.conf.j2..."
cat << EOF > "$BASE_DIR/config/mosquitto.conf.j2"
listener __MQTT_PORT__
allow_anonymous false
password_file /etc/mosquitto/passwd
EOF

# Create config/influxdb.conf
echo "Creating config/influxdb.conf..."
cat << EOF > "$BASE_DIR/config/influxdb.conf"
[meta]
  dir = /var/lib/influxdb/meta
[data]
  dir = /var/lib/influxdb/data
  wal-dir = /var/lib/influxdb/wal
[http]
  bind-address = ":8086"
EOF

# Create config/logrotate.conf
echo "Creating config/logrotate.conf..."
cat << EOF > "$BASE_DIR/config/logrotate.conf"
./logs/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 644 pi pi
}
EOF

# Create scripts/setup.sh
echo "Creating scripts/setup.sh..."
cat << 'EOF' > "$BASE_DIR/scripts/setup.sh"
#!/bin/bash

# BeeHiveLite Setup Script
# Sets up IoT monitoring system on Raspberry Pi 3B with Raspberry Pi OS 64-bit Lite
# Date: April 17, 2025

# Exit on error
set -e

# Logging function
LOG_FILE="./logs/setup.log"
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Error handling function
handle_error() {
    log "ERROR" "Failed at step: $1"
    exit 1
}

# Check internet connectivity with retries
check_internet() {
    log "INFO" "Checking internet connectivity..."
    for i in {1..3}; do
        if ping -c 1 github.com &>/dev/null; then
            log "INFO" "Internet connection verified."
            return 0
        fi
        log "WARNING" "No internet connection. Retrying ($i/3)..."
        sleep 5
    done
    handle_error "Internet connectivity check"
}

# Install dependencies
install_dependencies() {
    log "INFO" "Updating package lists..."
    sudo apt update || handle_error "APT update"

    log "INFO" "Installing dependencies..."
    sudo apt install -y \
        python3 python3-pip python3-venv \
        mosquitto mosquitto-clients \
        hostapd dnsmasq \
        influxdb influxdb-client \
        git wget curl logrotate \
        || handle_error "Dependency installation"

    # Install Python packages
    log "INFO" "Setting up Python virtual environment..."
    python3 -m venv ./venv
    source ./venv/bin/activate
    pip install flask gunicorn paho-mqtt python-dotenv requests influxdb-client smtplib || handle_error "Python package installation"
    deactivate
}

# Configure WiFi AP+STA
configure_wifi() {
    log "INFO" "Configuring WiFi AP+STA..."
    source ./config/.env

    # Backup existing configs
    sudo mv /etc/dhcpcd.conf /etc/dhcpcd.conf.bak-$(date +%F) 2>/dev/null || true
    sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak-$(date +%F) 2>/dev/null || true
    sudo mv /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.bak-$(date +%F) 2>/dev/null || true

    # Process templates
    for template in dhcpcd.conf.j2 dnsmasq.conf.j2 hostapd.conf.j2; do
        sed -e "s/__WIFI_SSID__/$WIFI_SSID/" \
            -e "s/__WIFI_PASSWORD__/$WIFI_PASSWORD/" \
            -e "s/__STA_WIFI_SSID__/$STA_WIFI_SSID/" \
            -e "s/__STA_WIFI_PASSWORD__/$STA_WIFI_PASSWORD/" \
            ./config/$template > /etc/${template%.j2} || handle_error "Template processing: $template"
    done

    # Enable services
    sudo systemctl unmask hostapd
    sudo systemctl enable hostapd dnsmasq
    sudo systemctl restart hostapd dnsmasq || handle_error "WiFi service restart"
}

# Configure Mosquitto
configure_mosquitto() {
    log "INFO" "Configuring Mosquitto MQTT broker..."
    source ./config/.env

    # Create password file
    echo "$MQTT_USERNAME:$(openssl passwd -6 $MQTT_PASSWORD)" | sudo tee /etc/mosquitto/passwd >/dev/null
    sudo chown mosquitto:mosquitto /etc/mosquitto/passwd
    sudo chmod 600 /etc/mosquitto/passwd

    # Process Mosquitto config
    sed -e "s/__MQTT_PORT__/$MQTT_PORT/" \
        ./config/mosquitto.conf.j2 > /etc/mosquitto/conf.d/beehivelite.conf || handle_error "Mosquitto config processing"

    # Restart Mosquitto
    sudo systemctl enable mosquitto
    sudo systemctl restart mosquitto || handle_error "Mosquitto service restart"
}

# Configure InfluxDB
configure_influxdb() {
    log "INFO" "Configuring InfluxDB..."
    sudo cp ./config/influxdb.conf /etc/influxdb/influxdb.conf
    sudo systemctl enable influxdb
    sudo systemctl restart influxdb || handle_error "InfluxDB service restart"

    # Initialize database
    sleep 5
    influx setup --org beehivelite --bucket telemetry --username admin --password "$INFLUXDB_PASSWORD" --force || handle_error "InfluxDB setup"
}

# Configure Log Rotation
configure_logrotate() {
    log "INFO" "Configuring log rotation..."
    sudo cp ./config/logrotate.conf /etc/logrotate.d/beehivelite
    sudo chown root:root /etc/logrotate.d/beehivelite
    sudo chmod 644 /etc/logrotate.d/beehivelite
}

# Configure Services
configure_services() {
    log "INFO" "Configuring systemd services..."

    # Data Processor Service
    cat << EOF | sudo tee /etc/systemd/system/beehivelite-processor.service
[Unit]
Description=BeeHiveLite Data Processor
After=network.target mosquitto.service influxdb.service

[Service]
ExecStart=./venv/bin/python ./src/data_processor.py
WorkingDirectory=./src
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF

    # Alerter Service
    cat << EOF | sudo tee /etc/systemd/system/beehivelite-alerter.service
[Unit]
Description=BeeHiveLite Alerter
After=network.target influxdb.service

[Service]
ExecStart=./venv/bin/python ./src/alerter.py
WorkingDirectory=./src
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF

    # Flask Dashboard Service
    cat << EOF | sudo tee /etc/systemd/system/beehivelite-dashboard.service
[Unit]
Description=BeeHiveLite Flask Dashboard
After=network.target

[Service]
ExecStart=./venv/bin/gunicorn --workers 2 --bind 0.0.0.0:5000 app:app
WorkingDirectory=./src
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF

    # Health Check Service
    cat << EOF | sudo tee /etc/systemd/system/beehivelite-healthcheck.service
[Unit]
Description=BeeHiveLite Health Check
After=network.target

[Service]
ExecStart=/bin/bash ./scripts/health_check.sh
WorkingDirectory=./scripts
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl enable beehivelite-processor beehivelite-alerter beehivelite-dashboard beehivelite-healthcheck
    sudo systemctl restart beehivelite-processor beehivelite-alerter beehivelite-dashboard beehivelite-healthcheck || handle_error "Service restart"
}

# Main setup function
main() {
    log "INFO" "Starting BeeHiveLite setup..."

    # Create directories
    mkdir -p ./{config,scripts,src/static/css,logs,backups} || handle_error "Directory creation"

    # Check internet
    check_internet

    # Install dependencies
    install_dependencies

    # Configure WiFi
    configure_wifi

    # Configure Mosquitto
    configure_mosquitto

    # Configure InfluxDB
    configure_influxdb

    # Configure log rotation
    configure_logrotate

    # Configure services
    configure_services

    # Setup cron for backups
    echo "0 0 * * * /bin/bash ./scripts/setup.sh backup" | crontab -

    log "INFO" "Setup completed successfully!"
    log "INFO" "Access dashboard at http://beehivelite.local:5000"
}

# Backup function
backup() {
    log "INFO" "Creating backup..."
    tar -czf ./backups/backup-$(date +%F).tar.gz ./src ./config || handle_error "Backup creation"
}

# Handle script arguments
case "$1" in
    setup)
        main
        ;;
    backup)
        backup
        ;;
    *)
        echo "Usage: $0 {setup|backup}"
        exit 1
        ;;
esac
EOF

# Create scripts/health_check.sh
echo "Creating scripts/health_check.sh..."
cat << 'EOF' > "$BASE_DIR/scripts/health_check.sh"
#!/bin/bash

LOG_FILE="./logs/health_check.log"
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

SERVICES=(
    "mosquitto"
    "influxdb"
    "beehivelite-processor"
    "beehivelite-alerter"
    "beehivelite-dashboard"
)

while true; do
    for service in "${SERVICES[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            log "ERROR" "Service $service is not active. Restarting..."
            sudo systemctl restart "$service"
            if systemctl is-active --quiet "$service"; then
                log "INFO" "Service $service restarted successfully."
            else
                log "ERROR" "Failed to restart service $service."
            fi
        fi
    done
    sleep 60
done
EOF

# Create src/data_processor.py
echo "Creating src/data_processor.py..."
cat << 'EOF' > "$BASE_DIR/src/data_processor.py"
import paho.mqtt.client as mqtt
import json
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import WritePrecision
from dotenv import load_dotenv
import os
import logging

# Setup logging
logging.basicConfig(filename='./logs/processor.log', level=logging.INFO)

# Load environment variables
load_dotenv('./config/.env')

# Configuration
MQTT_BROKER = "localhost"
MQTT_PORT = int(os.getenv("MQTT_PORT"))
MQTT_TOPIC = os.getenv("MQTT_TOPIC")
MQTT_USERNAME = os.getenv("MQTT_USERNAME")
MQTT_PASSWORD = os.getenv("MQTT_PASSWORD")
INFLUXDB_URL = "http://localhost:8086"
INFLUXDB_TOKEN = os.getenv("INFLUXDB_PASSWORD")
INFLUXDB_ORG = "beehivelite"
INFLUXDB_BUCKET = "telemetry"

# Valid telemetry fields
VALID_FIELDS = {"temperature", "pH", "ORP", "TDS", "EC", "distance"}

# InfluxDB client
influx_client = InfluxDBClient(url=INFLUXDB_URL, token=INFLUXDB_TOKEN, org=INFLUXDB_ORG)
write_api = influx_client.write_api()

def validate_data(data):
    """Validate telemetry data."""
    for key, value in data.items():
        if key not in VALID_FIELDS:
            logging.warning(f"Invalid field: {key}")
            return False
        try:
            float(value)
        except (ValueError, TypeError):
            logging.warning(f"Non-numeric value for {key}: {value}")
            return False
    return True

def on_connect(client, userdata, flags, rc):
    if rc == 0:
        logging.info("Connected to MQTT broker")
        client.subscribe(MQTT_TOPIC)
    else:
        logging.error(f"Failed to connect to MQTT broker with code {rc}")

def on_message(client, userdata, msg):
    try:
        data = json.loads(msg.payload.decode())
        if validate_data(data):
            point = Point("telemetry")
            for key, value in data.items():
                point.field(key, float(value))
            point.time(WritePrecision.NS)
            write_api.write(bucket=INFLUXDB_BUCKET, org=INFLUXDB_ORG, record=point)
            logging.info(f"Stored data: {data}")
        else:
            logging.error(f"Invalid data received: {data}")
    except Exception as e:
        logging.error(f"Error processing message: {e}")

# Setup MQTT client
mqtt_client = mqtt.Client()
mqtt_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
mqtt_client.on_connect = on_connect
mqtt_client.on_message = on_message

# Connect and start loop
try:
    mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
    mqtt_client.loop_forever()
except Exception as e:
    logging.error(f"Failed to start MQTT client: {e}")
EOF

# Create src/alerter.py
echo "Creating src/alerter.py..."
cat << 'EOF' > "$BASE_DIR/src/alerter.py"
import smtplib
from email.mime.text import MIMEText
from influxdb_client import InfluxDBClient
from dotenv import load_dotenv
import os
import logging
import time

# Setup logging
logging.basicConfig(filename='./logs/alerter.log', level=logging.INFO)

# Load environment variables
load_dotenv('./config/.env')

# InfluxDB configuration
INFLUXDB_URL = "http://localhost:8086"
INFLUXDB_TOKEN = os.getenv("INFLUXDB_PASSWORD")
INFLUXDB_ORG = "beehivelite"
INFLUXDB_BUCKET = "telemetry"

# Email configuration
EMAIL_SENDER = os.getenv("EMAIL_SENDER", "beehivelite@example.com")
EMAIL_PASSWORD = os.getenv("EMAIL_PASSWORD", "your-email-password")
EMAIL_RECEIVER = os.getenv("EMAIL_RECEIVER", "admin@example.com")
SMTP_SERVER = os.getenv("SMTP_SERVER", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", 587))

# Thresholds
THRESHOLDS = {
    "temperature": (10.0, 30.0),  # Min, Max
    "pH": (6.0, 8.0),
    "ORP": (200.0, 800.0),
    "TDS": (0.0, 1000.0),
    "EC": (0.0, 2.0),
    "distance": (0.0, 100.0)
}

client = InfluxDBClient(url=INFLUXDB_URL, token=INFLUXDB_TOKEN, org=INFLUXDB_ORG)
query_api = client.query_api()

def send_alert(field, value, threshold_min, threshold_max):
    subject = f"BeeHiveLite Alert: {field} Out of Range"
    body = f"Value for {field} is {value}, outside acceptable range ({threshold_min}, {threshold_max})."
    msg = MIMEText(body)
    msg['Subject'] = subject
    msg['From'] = EMAIL_SENDER
    msg['To'] = EMAIL_RECEIVER

    try:
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.starttls()
            server.login(EMAIL_SENDER, EMAIL_PASSWORD)
            server.sendmail(EMAIL_SENDER, EMAIL_RECEIVER, msg.as_string())
        logging.info(f"Alert sent for {field}: {value}")
    except Exception as e:
        logging.error(f"Failed to send alert: {e}")

def check_thresholds():
    query = f'''
    from(bucket: "{INFLUXDB_BUCKET}")
      |> range(start: -5m)
      |> filter(fn: (r) => r._measurement == "telemetry")
      |> last()
    '''
    tables = query_api.query(query)
    for table in tables:
        for record in table.records:
            field = record.get_field()
            value = record.get_value()
            if field in THRESHOLDS:
                min_val, max_val = THRESHOLDS[field]
                if value < min_val or value > max_val:
                    send_alert(field, value, min_val, max_val)

while True:
    try:
        check_thresholds()
    except Exception as e:
        logging.error(f"Error checking thresholds: {e}")
    time.sleep(300)  # Check every 5 minutes
EOF

# Create src/app.py
echo "Creating src/app.py..."
cat << 'EOF' > "$BASE_DIR/src/app.py"
from flask import Flask, render_template
from influxdb_client import InfluxDBClient
from dotenv import load_dotenv
import os

app = Flask(__name__)

# Load environment variables
load_dotenv('./config/.env')

# InfluxDB configuration
INFLUXDB_URL = "http://localhost:8086"
INFLUXDB_TOKEN = os.getenv("INFLUXDB_PASSWORD")
INFLUXDB_ORG = "beehivelite"
INFLUXDB_BUCKET = "telemetry"

client = InfluxDBClient(url=INFLUXDB_URL, token=INFLUXDB_TOKEN, org=INFLUXDB_ORG)
query_api = client.query_api()

@app.route('/')
def index():
    # Query recent data
    query = f'''
    from(bucket: "{INFLUXDB_BUCKET}")
      |> range(start: -1h)
      |> filter(fn:Topics (r) => r._measurement == "telemetry")
    '''
    tables = query_api.query(query)
    data = {}
    for table in tables:
        for record in table.records:
            field = record.get_field()
            value = record.get_value()
            time = record.get_time().isoformat()
            if field not in data:
                data[field] = []
            data[field].append({'time': time, 'value': value})

    return render_template('index.html', data=data)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.getenv("DASHBOARD_PORT")))
EOF

# Create src/static/index.html
echo "Creating src/static/index.html..."
cat << 'EOF' > "$BASE_DIR/src/static/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BeeHiveLite Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <link href="/static/css/styles.css" rel="stylesheet">
</head>
<body class="bg-gray-100">
    <div class="container mx-auto p-4">
        <h1 class="text-3xl font-bold mb-4">BeeHiveLite IoT Dashboard</h1>
        {% for field, values in data.items() %}
        <div class="bg-white p-4 mb-4 rounded shadow">
            <h2 class="text-xl font-semibold">{{ field | capitalize }}</h2>
            <canvas id="{{ field }}-chart"></canvas>
            <script>
                const ctx_{{ field }} = document.getElementById('{{ field }}-chart').getContext('2d');
                new Chart(ctx_{{ field }}, {
                    type: 'line',
                    data: {
                        labels: [{% for v in values %}'{{ v.time }}',{% endfor %}],
                        datasets: [{
                            label: '{{ field }}',
                            data: [{% for v in values %}{{ v.value }},{% endfor %}],
                            borderColor: 'rgba(75, 192, 192, 1)',
                            fill: false
                        }]
                    },
                    options: {
                        responsive: true,
                        scales: {
                            x: { type: 'time', time: { unit: 'minute' } }
                        }
                    }
                });
            </script>
        </div>
        {% endfor %}
    </div>
</body>
</html>
EOF

# Create src/static/css/styles.css
echo "Creating src/static/css/styles.css..."
cat << EOF > "$BASE_DIR/src/static/css/styles.css"
@tailwind base;
@tailwind components;
@tailwind utilities;
EOF

# Create backups/README.md
echo "Creating backups/README.md..."
cat << EOF > "$BASE_DIR/backups/README.md"
# Backups

This directory stores backups created by the BeeHiveLite system. Backups are generated daily via cron and include the `src/` and `config/` directories.

To restore a backup:
\`\`\`bash
tar -xzf backup-<date>.tar.gz -C /home/pi/beehivelite
\`\`\`
EOF

# Create README.md
echo "Creating README.md..."
cat << 'EOF' > "$BASE_DIR/README.md"
# BeeHiveLite IoT Monitoring System

A lightweight IoT solution for monitoring plant-related telemetry data (temperature, pH, ORP, TDS, EC, distance) on a Raspberry Pi 3B. Features WiFi AP+STA, MQTT broker (Mosquitto), time-series storage (InfluxDB), data processing (Python), alerting, and a Flask-based dashboard with Chart.js.

## Prerequisites

- Raspberry Pi 3B with Raspberry Pi OS 64-bit Lite (Bookworm).
- MicroSD card (8GB+).
- Temporary internet access (Ethernet or WiFi).

## Telemetry Data Format

Publish JSON data to the MQTT topic `v1/devices/me/telemetry`:

```json
{
  "temperature": 25.0,
  "pH": 7.0,
  "ORP": 300.0,
  "TDS": 500.0,
  "EC": 1.0,
  "distance": 50.0
}
```

All values must be numeric. Invalid data is logged and discarded.

## Setup Instructions

1. **Prepare SD Card**:

   - Flash Raspberry Pi OS 64-bit Lite to the SD card.
   - Boot the Pi and ensure the user is `pi`.

2. **Clone Repository**:

   ```bash
   git clone <repository_url> /home/pi/beehivelite
   cd /home/pi/beehivelite
   ```

3. **Configure**:

   - Edit `config/.env` with your WiFi, MQTT, and email settings.

   - Example:

     ```
     WIFI_SSID=beehivelite_ap
     WIFI_PASSWORD=beehivelite123
     STA_WIFI_SSID=YourRouterSSID
     STA_WIFI_PASSWORD=YourRouterPassword
     MQTT_USERNAME=beehivelite
     MQTT_PASSWORD=beehivelitePass
     MQTT_PORT=1883
     MQTT_TOPIC=v1/devices/me/telemetry
     INFLUXDB_PASSWORD=adminPass
     DASHBOARD_PORT=5000
     EMAIL_SENDER=beehivelite@example.com
     EMAIL_PASSWORD=your-email-password
     EMAIL_RECEIVER=admin@example.com
     SMTP_SERVER=smtp.gmail.com
     SMTP_PORT=587
     ```

4. **Run Setup Script**:

   ```bash
   chmod +x scripts/setup.sh
   sudo bash scripts/setup.sh setup
   ```

5. **Access System**:

   - Connect to WiFi AP (`beehivelite_ap`).
   - Verify STA mode: `iwconfig wlan0`.
   - Access dashboard: `http://beehivelite.local:5000`.

## Usage

- **Setup**: `sudo bash scripts/setup.sh setup`
- **Backup**: `sudo bash scripts/setup.sh backup`
- **Check Logs**: `cat logs/setup.log`, `cat logs/processor.log`, `cat logs/alerter.log`
- **Service Status**: `sudo systemctl status beehivelite-processor beehivelite-alerter beehivelite-dashboard mosquitto influxdb`

## Troubleshooting

- **Mosquitto Issues**:
  - Check logs: `journalctl -xeu mosquitto.service`
  - Verify config: `cat /etc/mosquitto/conf.d/beehivelite.conf`
  - Test: `mosquitto_sub -u beehivelite -P beehivelitePass -t v1/devices/me/telemetry`
- **InfluxDB Issues**:
  - Check status: `sudo systemctl status influxdb`
  - Test write: `influx write -b telemetry -p s "telemetry temperature=25"`
- **WiFi Issues**:
  - Check AP: `journalctl -u hostapd`
  - Check STA: `iwconfig wlan0`
- **Alerting Issues**:
  - Check logs: `cat logs/alerter.log`
  - Verify email settings in `.env`.

## Resource Optimization

- Flask: 2 workers (~100MB).
- InfluxDB: Minimal storage (~100MB).
- Mosquitto: Lightweight (~10MB).
- Data Processor: ~50MB.
- Alerter: ~50MB.
- Total: ~310MB, within 1GB RAM.

## Future Enhancements

- Add data export to CSV.
- Enhance dashboard with time range selection.
- Support additional alert channels (e.g., SMS).
EOF

# Set permissions
echo "Setting permissions..."
chmod +x "$BASE_DIR/scripts/setup.sh"
chmod +x "$BASE_DIR/scripts/health_check.sh"
chown -R pi:pi "$BASE_DIR"

echo "BeeHiveLite project structure created successfully in $BASE_DIR!"
echo "Next steps:"
echo "1. Edit $BASE_DIR/config/.env with your WiFi and email settings."
echo "2. Run: sudo bash $BASE_DIR/scripts/setup.sh setup"
EOF

### Instructions to Run
1. **Prepare Raspberry Pi**:
   - Flash Raspberry Pi OS 64-bit Lite (Bookworm) to an 8GB+ MicroSD card.
   - Boot the Pi, log in as the `pi` user, and ensure internet access (Ethernet or temporary WiFi).

2. **Create the Script**:
   - Copy the contents of `create_beehivelite.sh` (from the `<xaiArtifact>` above) into a file on the Raspberry Pi:
     ```bash
     nano /home/pi/create_beehivelite.sh
     ```
   - Paste the script content, save, and exit (`Ctrl+O`, `Enter`, `Ctrl+X`).

3. **Make Executable**:
   ```bash
   chmod +x /home/pi/create_beehivelite.sh
   ```

4. **Run the Script**:
   ```bash
   bash /home/pi/create_beehivelite.sh
   ```
   This will create all directories and files in `/home/pi/beehivelite`, set permissions, and output instructions for the next steps.

5. **Next Steps**:
   - Edit `config/.env` to set your WiFi, MQTT, and email settings (e.g., `STA_WIFI_SSID`, `EMAIL_SENDER`).
   - Run the setup script:
     ```bash
     sudo bash ./scripts/setup.sh setup
     ```
   - Follow the `README.md` instructions to access the system.

### Verification
After running the script, verify the structure:
```bash
ls -R /home/pi/beehivelite
```
Expected output:
```
/home/pi/beehivelite:
backups  config  logs  README.md  scripts  src

./backups:
README.md

./config:
.env  dhcpcd.conf.j2  dnsmasq.conf.j2  hostapd.conf.j2  influxdb.conf  logrotate.conf  mosquitto.conf.j2

./logs:

./scripts:
health_check.sh  setup.sh

./src:
alerter.py  app.py  data_processor.py  static

./src/static:
css  index.html

./src/static/css:
styles.css
```

Check a file’s content:
```bash
cat ./config/.env
```

### Notes
- **Single Command**: The `bash /home/pi/create_beehivelite.sh` command creates everything, making it easy to set up the project structure.
- **Permissions**: The script sets `pi:pi` ownership and makes scripts executable.
- **Error Handling**: The script uses `set -e` to stop on errors, ensuring robustness.
- **Portability**: If you need to transfer the script to the Pi, you can use `scp` or copy it via a USB drive.
- **Post-Creation**: The `.env` file contains placeholder values (e.g., `YourRouterSSID`). Update these before running `setup.sh`.

If you encounter issues (e.g., permission errors), ensure you’re running as the `pi` user and have write access to `/home/pi`. Let me know if you need help with specific steps or troubleshooting!