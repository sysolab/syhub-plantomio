import paho.mqtt.client
import json
import requests
import yaml
import os
import logging

# Setup logging
logging.basicConfig(filename='/tmp/syhub_processor.log', level=logging.INFO)

# Read config.yml
with open(os.path.join(os.path.dirname(__file__), '../config/config.yml'), 'r') as f:
    config = yaml.safe_load(f)

MQTT_BROKER = "localhost"
MQTT_PORT = config['mqtt']['port']
MQTT_TOPIC = config['mqtt']['topic_telemetry']
MQTT_USERNAME = config['mqtt']['username']
MQTT_PASSWORD = config['mqtt']['password']
VICTORIA_METRICS_URL = f"http://{config['hostname']}:{config['victoria_metrics']['port']}/api/v1/write"

# Valid telemetry fields
VALID_FIELDS = {"temperature", "pH", "ORP", "TDS", "EC", "distance"}

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
            lines = [f'telemetry{{metric="{key}"}} {float(value)}' for key, value in data.items()]
            response = requests.post(VICTORIA_METRICS_URL, data='\n'.join(lines))
            if response.status_code == 204:
                logging.info(f"Stored data: {data}")
            else:
                logging.error(f"Failed to store data: {response.status_code}")
        else:
            logging.error(f"Invalid data received: {data}")
    except Exception as e:
        logging.error(f"Error processing message: {e}")

# Setup MQTT client
client = paho.mqtt.client.Client()
client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
client.on_connect = on_connect
client.on_message = on_message

# Connect and start loop
try:
    client.connect(MQTT_BROKER, MQTT_PORT, 60)
    client.loop_forever()
except Exception as e:
    logging.error(f"Failed to start MQTT client: {e}")