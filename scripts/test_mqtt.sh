#!/bin/bash

# Test MQTT Connection Script
# This script tests if Mosquitto is properly set up by sending and receiving a test message

set -e  # Exit on any error

# Configuration - get from config.yml if possible
if [ -f "../config/config.yml" ]; then
  # Try to extract values from config.yml
  CONFIG_FILE="../config/config.yml"
elif [ -f "./config/config.yml" ]; then
  CONFIG_FILE="./config/config.yml"
else
  # Fallback values
  MQTT_HOST="localhost"
  MQTT_PORT="1883"
  MQTT_USERNAME="plantomioX1"
  MQTT_PASSWORD="plantomioX1Pass"
  MQTT_TOPIC="v1/devices/me/telemetry"
  CONFIG_FILE=""
fi

# Parse config if available
if [ -n "$CONFIG_FILE" ]; then
  echo "Using config from $CONFIG_FILE"
  if command -v yq &> /dev/null; then
    # Use yq to parse YAML
    MQTT_PORT=$(yq e '.mqtt.port' "$CONFIG_FILE" 2>/dev/null || echo "1883")
    MQTT_USERNAME=$(yq e '.mqtt.username' "$CONFIG_FILE" 2>/dev/null || echo "plantomioX1")
    MQTT_PASSWORD=$(yq e '.mqtt.password' "$CONFIG_FILE" 2>/dev/null || echo "plantomioX1Pass")
    MQTT_TOPIC=$(yq e '.mqtt.topic_telemetry' "$CONFIG_FILE" 2>/dev/null || echo "v1/devices/me/telemetry")
  else
    echo "Warning: yq not found, using default values"
  fi
fi

MQTT_HOST="localhost"  # Always use localhost for direct testing

# Function to show usage
show_usage() {
  echo "MQTT Connection Test"
  echo "==================="
  echo "This script tests Mosquitto MQTT broker by publishing and subscribing to a test message."
  echo ""
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  -h, --host HOSTNAME   : MQTT broker hostname (default: $MQTT_HOST)"
  echo "  -p, --port PORT       : MQTT broker port (default: $MQTT_PORT)"
  echo "  -u, --user USERNAME   : MQTT username (default: $MQTT_USERNAME)"
  echo "  -w, --pass PASSWORD   : MQTT password (default: $MQTT_PASSWORD)"
  echo "  -t, --topic TOPIC     : MQTT topic (default: $MQTT_TOPIC)"
  echo "  --help                : Show this help message"
  echo ""
  echo "Example:"
  echo "  $0 -h localhost -p 1883 -u admin -w password"
  exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--host)
      MQTT_HOST="$2"
      shift 2
      ;;
    -p|--port)
      MQTT_PORT="$2"
      shift 2
      ;;
    -u|--user)
      MQTT_USERNAME="$2"
      shift 2
      ;;
    -w|--pass)
      MQTT_PASSWORD="$2"
      shift 2
      ;;
    -t|--topic)
      MQTT_TOPIC="$2"
      shift 2
      ;;
    --help)
      show_usage
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help to see available options"
      exit 1
      ;;
  esac
done

# Check if mosquitto_pub/sub commands are available
if ! command -v mosquitto_pub &> /dev/null || ! command -v mosquitto_sub &> /dev/null; then
  echo "Error: mosquitto_pub or mosquitto_sub commands not found."
  echo "Please install the Mosquitto clients package:"
  echo "sudo apt install -y mosquitto-clients"
  exit 1
fi

echo "Testing MQTT connection with the following parameters:"
echo "Host: $MQTT_HOST"
echo "Port: $MQTT_PORT"
echo "Username: $MQTT_USERNAME"
echo "Topic: $MQTT_TOPIC"
echo "-------------------------"

# Create a temporary message ID
MSG_ID=$(date +%s)
TEST_MESSAGE="{\"deviceID\":\"test-device\",\"timestamp\":$MSG_ID,\"test_value\":\"$RANDOM\"}"

# Start a subscriber in the background
echo "Starting MQTT subscriber... (will timeout after 10 seconds)"
mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" -t "$MQTT_TOPIC" -C 1 -W 10 > /tmp/mqtt_result.txt &
SUB_PID=$!

# Wait a moment for subscriber to connect
sleep 2

# Publish test message
echo "Publishing test message: $TEST_MESSAGE"
if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" -t "$MQTT_TOPIC" -m "$TEST_MESSAGE"; then
  echo "✓ Message published successfully"
else
  echo "× Failed to publish message"
  echo "Error details:"
  echo "- Check if Mosquitto is running: sudo systemctl status mosquitto"
  echo "- Check if port is open: sudo netstat -tulpn | grep 1883"
  echo "- Check if credentials are correct: /etc/mosquitto/passwd"
  echo "- Check if mosquitto.conf has 'listener 1883 0.0.0.0'"
  exit 1
fi

# Wait for subscriber to receive
wait $SUB_PID
EXIT_CODE=$?

if [ -s /tmp/mqtt_result.txt ] && [ $EXIT_CODE -eq 0 ]; then
  echo "✓ Message received successfully:"
  cat /tmp/mqtt_result.txt
  echo "-------------------------"
  echo "✓ MQTT connection test PASSED!"
else
  echo "× Failed to receive message (timeout or error)"
  echo "Error details:"
  echo "- Check if Mosquitto is listening on all interfaces"
  echo "- Check firewall settings"
  echo "- Check DNS resolution for hostname"
  echo "- Try using IP address instead of hostname"
  echo "- Run 'sudo systemctl status mosquitto' for more details"
  exit 1
fi

# Clean up
rm -f /tmp/mqtt_result.txt 