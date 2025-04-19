#!/bin/bash

# Verify MQTT Configuration Script
# This script checks if Mosquitto is correctly configured and running

echo "Verifying Mosquitto MQTT Broker configuration..."

# Check if config file exists
if [ ! -f "/etc/mosquitto/mosquitto.conf" ]; then
  echo "ERROR: Mosquitto config file not found at /etc/mosquitto/mosquitto.conf"
  exit 1
fi

# Check if config file has required settings
echo "Checking configuration file..."
required_settings=("per_listener_settings true" "listener" "allow_anonymous" "password_file")
for setting in "${required_settings[@]}"; do
  if ! grep -q "$setting" /etc/mosquitto/mosquitto.conf; then
    echo "WARNING: Missing required setting: $setting"
  else
    echo "✓ Found setting: $setting"
  fi
done

# Check if conflicting config exists in conf.d
if [ -f "/etc/mosquitto/conf.d/mqtt_config.conf" ]; then
  echo "WARNING: Potential conflicting config found in conf.d directory"
  echo "Content of conflicting file:"
  cat "/etc/mosquitto/conf.d/mqtt_config.conf"
fi

# Check if password file exists
if [ ! -f "/etc/mosquitto/passwd" ]; then
  echo "ERROR: Password file not found at /etc/mosquitto/passwd"
else
  echo "✓ Password file exists"
fi

# Check if service is running
echo "Checking Mosquitto service status..."
if systemctl is-active --quiet mosquitto; then
  echo "✓ Mosquitto service is RUNNING"
else
  echo "ERROR: Mosquitto service is NOT running"
  echo "Service status:"
  systemctl status mosquitto
fi

# Check if port is listening
echo "Checking if Mosquitto is listening on port..."
if command -v netstat > /dev/null; then
  if netstat -tuln | grep -q ":1883"; then
    echo "✓ Mosquitto is listening on port 1883"
  else
    echo "ERROR: Mosquitto is not listening on port 1883"
  fi
elif command -v ss > /dev/null; then
  if ss -tuln | grep -q ":1883"; then
    echo "✓ Mosquitto is listening on port 1883"
  else
    echo "ERROR: Mosquitto is not listening on port 1883"
  fi
else
  echo "WARNING: Cannot check if port is listening (netstat/ss not available)"
fi

echo "Verification complete." 