#!/bin/bash

# SyHub Setup Script - Optimized for Raspberry Pi 3B
# This script sets up the entire infrastructure for plantomio IoT system

set -e  # Exit on any error

# Detect if script is run with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

# Get the actual user who invoked sudo
if [ -n "$SUDO_USER" ]; then
  SYSTEM_USER="$SUDO_USER"
else
  SYSTEM_USER="$(whoami)"
fi

# Base directory determination
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="/home/$SYSTEM_USER/syhub"
CONFIG_FILE="$BASE_DIR/config/config.yml"

# Handle installation from different locations
if [ "$SCRIPT_DIR" != "$BASE_DIR" ]; then
  echo "Installing from external location to $BASE_DIR..."
  
  # Create the target directory if it doesn't exist
  mkdir -p "$BASE_DIR"

  # Copy the required files to the target directory
  echo "Copying files to $BASE_DIR..."
  cp -r "$SCRIPT_DIR/"* "$BASE_DIR/"
  
  # Make scripts executable
  chmod +x "$BASE_DIR/setup.sh"
  chmod +x "$BASE_DIR/scripts/"*.sh
  
  # Download frontend dependencies
  echo "Downloading dependencies..."
  "$BASE_DIR/scripts/download_deps.sh"
  
  echo "Files copied successfully. Launching setup..."
  
  # Execute the script in the target location
  exec "$BASE_DIR/setup.sh"
  exit 0
fi

# Continue with standard setup if we're already in the right directory
# Create log directory
mkdir -p "$BASE_DIR/log"
LOG_FILE="$BASE_DIR/log/syhub_setup.log"

# Logging function
log() {
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Function to parse YAML - basic implementation
parse_yaml() {
  local yaml_file=$1
  local prefix=$2
  cat "$yaml_file" | \
  grep -v "^#" | \
  sed -e 's/:[^:\/\/]/="/g' \
      -e 's/$/"/g' \
      -e 's/ *=/=/g' \
  | grep "^[a-zA-Z0-9_]*="
}

# Load configuration
load_config() {
  log "Loading configuration from $CONFIG_FILE"
  
  # Source the parsed YAML
  eval $(parse_yaml "$CONFIG_FILE" "config_")
  
  PROJECT_NAME="${config_project_name}"
  HOSTNAME="${config_hostname}"
  
  # MQTT config
  MQTT_PORT="${config_mqtt_port}"
  MQTT_USERNAME="${config_mqtt_username}"
  MQTT_PASSWORD="${config_mqtt_password}"
  
  # VictoriaMetrics config
  VM_VERSION="${config_victoria_metrics_version}"
  VM_PORT="${config_victoria_metrics_port}"
  VM_DATA_DIR="${config_victoria_metrics_data_directory}"
  VM_RETENTION="${config_victoria_metrics_retention_period}"
  VM_USER="${config_victoria_metrics_service_user}"
  VM_GROUP="${config_victoria_metrics_service_group}"
  
  # Node-RED config
  NODERED_PORT="${config_node_red_port}"
  NODERED_MEMORY="${config_node_red_memory_limit_mb}"
  NODERED_USERNAME="${config_node_red_username}"
  NODERED_PASSWORD_HASH="${config_node_red_password_hash}"
  
  # Dashboard config
  DASHBOARD_PORT="${config_dashboard_port}"
  DASHBOARD_WORKERS="${config_dashboard_workers}"
  
  # Node.js config
  NODEJS_VERSION="${config_nodejs_install_version}"
  
  log "Configuration loaded successfully"
}

# Update and install dependencies
install_dependencies() {
  log "Updating package lists and installing dependencies"
  apt update
  apt install -y python3 python3-pip python3-venv mosquitto mosquitto-clients \
    avahi-daemon nginx git curl build-essential procps \
    net-tools libavahi-compat-libdnssd-dev

  # Set hostname
  hostnamectl set-hostname "$HOSTNAME"
  echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
  
  log "Basic dependencies installed"
}

# Setup VictoriaMetrics
setup_victoriametrics() {
  log "Setting up VictoriaMetrics $VM_VERSION"
  
  # Create service user if doesn't exist
  if ! id "$VM_USER" &>/dev/null; then
    useradd -rs /bin/false "$VM_USER"
  fi
  
  # Create data directory
  mkdir -p "$VM_DATA_DIR"
  chown -R "$VM_USER":"$VM_GROUP" "$VM_DATA_DIR"
  
  # Download VictoriaMetrics
  VM_BINARY_URL="https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/$VM_VERSION/victoria-metrics-linux-arm-$VM_VERSION.tar.gz"
  curl -L "$VM_BINARY_URL" | tar xz
  mv victoria-metrics-linux-arm-* /usr/local/bin/victoria-metrics
  chmod +x /usr/local/bin/victoria-metrics
  
  # Create systemd service
  cat > /etc/systemd/system/victoriametrics.service << EOF
[Unit]
Description=VictoriaMetrics Time Series Database
After=network.target

[Service]
User=$VM_USER
Group=$VM_GROUP
Type=simple
ExecStart=/usr/local/bin/victoria-metrics -storageDataPath=$VM_DATA_DIR -retentionPeriod=$VM_RETENTION -httpListenAddr=:$VM_PORT -search.maxUniqueTimeseries=1000 -memory.allowedPercent=30
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  # Reload, enable and start service
  systemctl daemon-reload
  systemctl enable victoriametrics
  systemctl restart victoriametrics
  
  log "VictoriaMetrics setup completed"
}

# Setup Mosquitto MQTT broker
setup_mqtt() {
  log "Setting up Mosquitto MQTT broker"
  
  # Configure Mosquitto
  cat > /etc/mosquitto/conf.d/plantomio.conf << EOF
listener $MQTT_PORT
allow_anonymous false
password_file /etc/mosquitto/passwd
EOF

  # Create password file with user
  touch /etc/mosquitto/passwd
  mosquitto_passwd -b /etc/mosquitto/passwd "$MQTT_USERNAME" "$MQTT_PASSWORD"
  
  # Restart service
  systemctl restart mosquitto
  
  log "MQTT broker setup completed"
}

# Setup Node.js
setup_nodejs() {
  log "Setting up Node.js"
  
  # Install Node.js using n version manager
  if ! command -v node &> /dev/null; then
    curl -L https://raw.githubusercontent.com/tj/n/master/bin/n -o /tmp/n
    bash /tmp/n "$NODEJS_VERSION"
    rm /tmp/n
  fi
  
  # Fix permissions for npm global packages
  mkdir -p /home/$SYSTEM_USER/.npm-global
  chown -R $SYSTEM_USER:$SYSTEM_USER /home/$SYSTEM_USER/.npm-global
  
  # Set npm global path
  runuser -l $SYSTEM_USER -c 'npm config set prefix "~/.npm-global"'
  
  # Set PATH for npm global binaries
  if ! grep -q "NPM_GLOBAL" /home/$SYSTEM_USER/.bashrc; then
    echo 'export PATH=~/.npm-global/bin:$PATH' >> /home/$SYSTEM_USER/.bashrc
  fi
  
  log "Node.js setup completed"
}

# Setup Node-RED
setup_nodered() {
  log "Setting up Node-RED"
  
  # Install Node-RED as global package
  runuser -l $SYSTEM_USER -c 'npm install -g --unsafe-perm node-red'
  
  # Install required Node-RED nodes
  runuser -l $SYSTEM_USER -c 'cd ~/.node-red && npm install node-red-contrib-victoriam node-red-dashboard node-red-node-ui-table'
  
  # Create Node-RED settings file
  mkdir -p /home/$SYSTEM_USER/.node-red
  cat > /home/$SYSTEM_USER/.node-red/settings.js << EOF
module.exports = {
    uiPort: $NODERED_PORT,
    mqttReconnectTime: 15000,
    serialReconnectTime: 15000,
    adminAuth: {
        type: "credentials",
        users: [{
            username: "$NODERED_USERNAME",
            password: "$NODERED_PASSWORD_HASH",
            permissions: "*"
        }]
    },
    functionGlobalContext: {},
    httpNodeCors: {
        origin: "*",
        methods: "GET,PUT,POST,DELETE"
    },
    flowFilePretty: true,
    editorTheme: {
        projects: {
            enabled: false
        }
    },
    nodeMessageBufferMaxLength: 50,
    ioMessageBufferMaxLength: 50,
};
EOF

  # Create systemd service for Node-RED
  cat > /etc/systemd/system/nodered.service << EOF
[Unit]
Description=Node-RED
After=network.target

[Service]
User=$SYSTEM_USER
Group=$SYSTEM_USER
WorkingDirectory=/home/$SYSTEM_USER
Environment="NODE_OPTIONS=--max_old_space_size=$NODERED_MEMORY"
ExecStart=/home/$SYSTEM_USER/.npm-global/bin/node-red --max-old-space-size=$NODERED_MEMORY
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  # Import Node-RED flows
  cp $BASE_DIR/node-red-flows/flows.json /home/$SYSTEM_USER/.node-red/flows.json
  chown $SYSTEM_USER:$SYSTEM_USER /home/$SYSTEM_USER/.node-red/flows.json
  
  # Reload, enable and start service
  systemctl daemon-reload
  systemctl enable nodered
  systemctl start nodered
  
  log "Node-RED setup completed"
}

# Setup Flask Dashboard
setup_dashboard() {
  log "Setting up Flask dashboard"
  
  # Create Python virtual environment
  python3 -m venv /home/$SYSTEM_USER/syhub/dashboard/venv
  chown -R $SYSTEM_USER:$SYSTEM_USER /home/$SYSTEM_USER/syhub/dashboard/venv
  
  # Install Python dependencies
  runuser -l $SYSTEM_USER -c "cd $BASE_DIR/dashboard && source venv/bin/activate && pip install flask gunicorn requests pyyaml"
  
  # Create systemd service
  cat > /etc/systemd/system/dashboard.service << EOF
[Unit]
Description=Plantomio Dashboard
After=network.target

[Service]
User=$SYSTEM_USER
Group=$SYSTEM_USER
WorkingDirectory=$BASE_DIR/dashboard
ExecStart=$BASE_DIR/dashboard/venv/bin/gunicorn --workers $DASHBOARD_WORKERS --bind 0.0.0.0:$DASHBOARD_PORT app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  # Reload, enable and start service
  systemctl daemon-reload
  systemctl enable dashboard
  systemctl start dashboard
  
  log "Dashboard setup completed"
}

# Setup Nginx as a reverse proxy
setup_nginx() {
  log "Setting up Nginx as a reverse proxy"
  
  # Create Nginx configuration
  cat > /etc/nginx/sites-available/plantomio << EOF
server {
    listen 80;
    server_name $HOSTNAME;
    
    # Dashboard
    location / {
        proxy_pass http://localhost:$DASHBOARD_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Node-RED
    location /node-red/ {
        proxy_pass http://localhost:$NODERED_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # VictoriaMetrics
    location /victoria/ {
        proxy_pass http://localhost:$VM_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

  # Enable site
  ln -sf /etc/nginx/sites-available/plantomio /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default
  
  # Test and restart Nginx
  nginx -t
  systemctl restart nginx
  
  log "Nginx setup completed"
}

# Main execution flow
main() {
  log "Starting SyHub setup for Raspberry Pi 3B"
  
  # Download frontend dependencies if not already done
  if [ ! -f "$BASE_DIR/dashboard/static/js/chart.min.js" ]; then
    log "Downloading frontend dependencies"
    "$BASE_DIR/scripts/download_deps.sh"
  fi
  
  load_config
  install_dependencies
  setup_victoriametrics
  setup_mqtt
  setup_nodejs
  setup_nodered
  setup_dashboard
  setup_nginx
  
  log "Setup completed successfully!"
  
  # Show access information
  echo "===================================================="
  echo "Installation complete! Access your services at:"
  echo "Dashboard: http://$HOSTNAME/"
  echo "Node-RED: http://$HOSTNAME/node-red/"
  echo "VictoriaMetrics: http://$HOSTNAME/victoria/"
  echo "===================================================="
}

# Execute main function
main 