#!/bin/bash

# Fix Mosquitto Configuration Script
# Use this script if Mosquitto won't start due to configuration issues

echo "Fixing Mosquitto MQTT Broker configuration..."

# Backup current config if exists
if [ -f "/etc/mosquitto/mosquitto.conf" ]; then
  cp "/etc/mosquitto/mosquitto.conf" "/etc/mosquitto/mosquitto.conf.$(date +%Y%m%d%H%M%S).bak"
  echo "Backed up existing config"
fi

# Create a clean, working configuration
cat > "/etc/mosquitto/mosquitto.conf" << EOF
# Place your local configuration in /etc/mosquitto/conf.d/
#
# A full description of the configuration file is at
# /usr/share/doc/mosquitto/examples/mosquitto.conf.example

per_listener_settings true

pid_file /run/mosquitto/mosquitto.pid

persistence true
persistence_location /var/lib/mosquitto/

log_dest file /var/log/mosquitto/mosquitto.log

allow_anonymous false 
listener 1883  
password_file /etc/mosquitto/passwd
EOF

echo "Created new clean configuration"

# Remove any conflicting configs in conf.d
if [ -d "/etc/mosquitto/conf.d" ]; then
  echo "Checking for conflicting configs in conf.d directory..."
  for conf in /etc/mosquitto/conf.d/*.conf; do
    if [ -f "$conf" ]; then
      echo "Backing up and removing: $conf"
      cp "$conf" "$conf.$(date +%Y%m%d%H%M%S).bak"
      rm "$conf"
    fi
  done
fi

# Ensure password file exists
if [ ! -f "/etc/mosquitto/passwd" ]; then
  echo "Password file missing. Creating..."
  touch /etc/mosquitto/passwd
  chown mosquitto:mosquitto /etc/mosquitto/passwd
  echo "Please run 'sudo mosquitto_passwd -c /etc/mosquitto/passwd YOUR_USERNAME' to set up a user"
fi

# Check permissions
echo "Setting correct file permissions..."
chown mosquitto:mosquitto "/etc/mosquitto/mosquitto.conf"
chmod 644 "/etc/mosquitto/mosquitto.conf"
if [ -f "/etc/mosquitto/passwd" ]; then
  chown mosquitto:mosquitto "/etc/mosquitto/passwd"
  chmod 600 "/etc/mosquitto/passwd"
fi

# Validate configuration
echo "Validating Mosquitto configuration..."
if mosquitto -t -c /etc/mosquitto/mosquitto.conf; then
  echo "✓ Configuration is valid"
else
  echo "× Configuration validation failed"
fi

# Restart service
echo "Restarting Mosquitto service..."
systemctl restart mosquitto

# Check service status
if systemctl is-active --quiet mosquitto; then
  echo "✓ Mosquitto service is now RUNNING"
else
  echo "× Mosquitto service failed to start"
  echo "Service status:"
  systemctl status mosquitto
fi

echo "Fix attempt completed." 