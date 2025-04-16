#!/bin/bash
echo "Fixing syhub components..."

# Define the main directories
syhub_DIR="/home/$(whoami)/syhub"
NODE_RED_DIR="/home/$(whoami)/.node-red"
MQTT_USER="admin"
MQTT_PASS="admin"  # Default fallback password

# Create necessary directories
mkdir -p "$syhub_DIR/config"
mkdir -p "$NODE_RED_DIR"

# Fix 1: Create config file if missing
if [ ! -f "$syhub_DIR/config/config.yml" ]; then
    echo "Creating default config.yml..."
    mkdir -p "$syhub_DIR/config"
    cat > "$syhub_DIR/config/config.yml" << EOL
project:
  hostname: "plantomio"
  mqtt:
    host: "localhost"
    port: 1883
    username: "admin"
    password: "admin"
  victoria_metrics:
    host: "localhost" 
    port: 8428
EOL
fi

# Fix 2: Node-RED Flow
echo "Fixing Node-RED flow..."
sudo systemctl stop nodered || true

# Create a simpler flow file
cat > "$NODE_RED_DIR/flows.json" << 'EOL'
[
    {
        "id": "mqtt-to-vm-flow",
        "type": "tab",
        "label": "MQTT to VictoriaMetrics",
        "disabled": false
    },
    {
        "id": "mqtt-in",
        "type": "mqtt in",
        "z": "mqtt-to-vm-flow",
        "name": "MQTT In",
        "topic": "#",
        "qos": "2",
        "datatype": "json",
        "broker": "mqtt-broker",
        "nl": false,
        "rap": true,
        "rh": "0",
        "x": 120,
        "y": 120,
        "wires": [["format-function"]]
    },
    {
        "id": "format-function",
        "type": "function",
        "z": "mqtt-to-vm-flow",
        "name": "Format for VM",
        "func": "// Convert MQTT data to InfluxDB line protocol\nconst topic = msg.topic;\nconst parts = topic.split('/');\nconst measurement = parts[0] || 'data';\nconst deviceId = parts[1] || 'device';\n\nlet fields = [];\nfor (const key in msg.payload) {\n    if (msg.payload.hasOwnProperty(key) && typeof msg.payload[key] === 'number') {\n        fields.push(`${key}=${msg.payload[key]}`);\n    }\n}\n\nif (fields.length === 0) return null;\n\nmsg.payload = `${measurement},device=${deviceId} ${fields.join(',')}`;\nmsg.headers = {'Content-Type': 'text/plain'};\nreturn msg;",
        "outputs": 1,
        "noerr": 0,
        "x": 300,
        "y": 120,
        "wires": [["vm-request"]]
    },
    {
        "id": "vm-request",
        "type": "http request",
        "z": "mqtt-to-vm-flow",
        "name": "To VictoriaMetrics",
        "method": "POST",
        "ret": "txt",
        "paytoqs": "ignore",
        "url": "http://localhost:8428/api/v1/write",
        "x": 500,
        "y": 120,
        "wires": [[]]
    },
    {
        "id": "mqtt-broker",
        "type": "mqtt-broker",
        "name": "MQTT Broker",
        "broker": "localhost",
        "port": "1883",
        "clientid": "",
        "autoConnect": true,
        "usetls": false,
        "protocolVersion": "4",
        "keepalive": "60",
        "cleansession": true
    }
]
EOL

# Create credentials file
cat > "$NODE_RED_DIR/flows_cred.json" << EOL
{
    "mqtt-broker": {
        "user": "${MQTT_USER}",
        "password": "${MQTT_PASS}"
    }
}
EOL
chmod 600 "$NODE_RED_DIR/flows_cred.json"
chown -R $(whoami):$(whoami) "$NODE_RED_DIR"

# Fix 3: Dashboard Service
echo "Fixing Dashboard service..."
sudo apt update
sudo apt install -y python3-gunicorn python3-flask python3-socketio python3-paho-mqtt python3-eventlet

# Find gunicorn path
GUNICORN_PATH=$(which gunicorn3 2>/dev/null || which gunicorn 2>/dev/null)
if [ -z "$GUNICORN_PATH" ]; then
    echo "Gunicorn not found, installing..."
    sudo apt install -y gunicorn
    GUNICORN_PATH=$(which gunicorn3 2>/dev/null || which gunicorn 2>/dev/null)
fi

# Create a basic Flask app if it doesn't exist
if [ ! -f "$syhub_DIR/flask_app.py" ]; then
    echo "Creating basic Flask app..."
    cat > "$syhub_DIR/flask_app.py" << 'EOL'
from flask import Flask, render_template_string
import paho.mqtt.client as mqtt
import os
import time

app = Flask(__name__)

# Basic HTML template
HTML = """
<!DOCTYPE html>
<html>
<head>
    <title>syhub Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <h1>syhub Dashboard</h1>
    <p>Welcome to your syhub IoT platform!</p>
    <ul>
        <li><a href="http://{{request.host.split(':')[0]}}:1880/" target="_blank">Node-RED</a></li>
        <li><a href="http://{{request.host.split(':')[0]}}:8428/" target="_blank">VictoriaMetrics</a></li>
    </ul>
</body>
</html>
"""

# MQTT Configuration
MQTT_HOST = "localhost"
MQTT_PORT = 1883
MQTT_USER = "admin"
MQTT_PASS = "admin"

def connect_mqtt():
    for attempt in range(1, 6):
        try:
            print(f"Attempting to connect to MQTT broker (Attempt {attempt}/5)...")
            client = mqtt.Client()
            client.username_pw_set(MQTT_USER, MQTT_PASS)
            client.connect(MQTT_HOST, MQTT_PORT, 60)
            print("Connected to MQTT broker")
            return client
        except Exception as e:
            print(f"Failed to connect to MQTT: {e}")
            if attempt < 5:
                retry_delay = 2 ** (attempt - 1)
                print(f"Retrying in {retry_delay} seconds...")
                time.sleep(retry_delay)
            else:
                print("Max retries reached. MQTT connection failed.")
                return None

@app.route('/')
def index():
    return render_template_string(HTML)

if __name__ == '__main__':
    # Try to connect to MQTT
    mqtt_client = connect_mqtt()
    
    # Run the app
    app.run(host='0.0.0.0', port=5000, debug=True)
EOL
    chown $(whoami):$(whoami) "$syhub_DIR/flask_app.py"
fi

# Create static folder if it doesn't exist
mkdir -p "$syhub_DIR/static"
chown -R $(whoami):$(whoami) "$syhub_DIR"

# Fix the service file
sudo bash -c "cat > /etc/systemd/system/syhub-dashboard.service << EOL
[Unit]
Description=syhub Dashboard
After=network.target

[Service]
User=$(whoami)
WorkingDirectory=$syhub_DIR
ExecStart=$GUNICORN_PATH --workers 2 --worker-class eventlet --bind 0.0.0.0:5000 flask_app:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL"

# Fix 4: MQTT Connection
echo "Fixing MQTT connection..."

# Fix Mosquitto configuration
sudo bash -c "cat > /etc/mosquitto/mosquitto.conf << EOL
# Default listener
listener 1883 0.0.0.0

# Persistence
persistence true
persistence_location /var/lib/mosquitto/

# Logging
log_dest syslog
log_dest stdout

# Authentication
allow_anonymous false
password_file /etc/mosquitto/passwd
EOL"

# Create a new password file
sudo rm -f /etc/mosquitto/passwd
sudo touch /etc/mosquitto/passwd
sudo mosquitto_passwd -b /etc/mosquitto/passwd "$MQTT_USER" "$MQTT_PASS"
sudo chmod 600 /etc/mosquitto/passwd

# Restart all services
echo "Restarting services..."
sudo systemctl daemon-reload
sudo systemctl restart mosquitto
sudo systemctl enable mosquitto
sudo systemctl restart nodered
sudo systemctl enable nodered
sudo systemctl restart syhub-dashboard
sudo systemctl enable syhub-dashboard

echo "Fix complete. Checking service status..."
sleep 3
sudo systemctl status nodered mosquitto syhub-dashboard --no-pager