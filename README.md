PROJECT_NAME IoT Monitoring System
An IoT solution for monitoring plant-related telemetry data (temperature, pH, ORP, TDS, EC, distance) on a Raspberry Pi 3B. Features WiFi AP+STA, MQTT broker (Mosquitto), time-series storage (VictoriaMetrics), data processing (Node-RED and Python), alerting, health checks, and a Flask-based dashboard with Chart.js.
Prerequisites

Raspberry Pi 3B with Raspberry Pi OS 64-bit Lite (Bookworm).
MicroSD card (8GB+).
Temporary internet access (Ethernet or WiFi).

Telemetry Data Format
Publish JSON data to the MQTT topic __MQTT_TOPIC__:
{
  "temperature": 25.0,
  "pH": 7.0,
  "ORP": 300.0,
  "TDS": 500.0,
  "EC": 1.0,
  "distance": 50.0
}

Setup Instructions

Prepare SD Card:

Flash Raspberry Pi OS 64-bit Lite to the SD card.
Boot the Pi and ensure the user is __SYSTEM_USER__.


Create Project Structure:

Create directories: mkdir -p __BASE_DIR__/{config,scripts,src/static/css,.node-red,venv,backups}
Add files as specified.


Configure:

Edit config/config.yml with your settings (WiFi, MQTT, email, etc.).


Run Setup Script:
chmod +x scripts/setup.sh
sudo bash scripts/setup.sh setup


Access System:

Connect to WiFi AP (__WIFI_AP_SSID__) if configured.
Verify STA mode: iwconfig wlan0.
Access Node-RED: http://__HOSTNAME__:__NODE_RED_PORT__/admin.
Access dashboard: http://__HOSTNAME__:__DASHBOARD_PORT__.



Usage

Setup: sudo bash scripts/setup.sh setup
Backup: sudo bash scripts/setup.sh backup
Check Logs: cat __LOG_FILE__, cat /tmp/syhub_processor.log, cat /tmp/syhub_alerter.log, cat /tmp/syhub_health.log
Service Status: sudo systemctl status mosquitto victoriametrics nodered __PROJECT_NAME__-processor __PROJECT_NAME__-alerter __PROJECT_NAME__-dashboard __PROJECT_NAME__-healthcheck

Troubleshooting

Mosquitto:
Logs: journalctl -xeu mosquitto.service
Config: cat /etc/mosquitto/conf.d/__PROJECT_NAME__.conf


VictoriaMetrics:
Status: sudo systemctl status victoriametrics
Test: curl http://__HOSTNAME__:__VICTORIA_METRICS_PORT__/api/v1/query?query=telemetry


Node-RED:
Access: http://__HOSTNAME__:__NODE_RED_PORT__/admin
Flows: cat __BASE_DIR__/.node-red/flows.json


Data Processor:
Logs: cat /tmp/syhub_processor.log


Alerter:
Logs: cat /tmp/syhub_alerter.log


Dashboard:
Status: sudo systemctl status __PROJECT_NAME__-dashboard


Health Check:
Logs: cat /tmp/syhub_health.log



Resource Optimization

Node-RED: Limited to NODE_RED_MEMORY_LIMIT MB.
VictoriaMetrics: Efficient storage in VICTORIA_METRICS_DATA_DIR.
Flask: DASHBOARD_WORKERS workers.
Data Processor and Alerter: ~50MB each.
Mosquitto: Minimal overhead with authentication.

