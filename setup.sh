#!/bin/bash

# SyHub Setup Script - Optimized for Raspberry Pi 3B
# This script sets up a complete IoT monitoring infrastructure with MQTT, VictoriaMetrics, and Node-RED

set -e  # Exit on any error

# Interactive mode flag
INTERACTIVE=false

# Command to run
COMMAND="setup"

# Parse command line arguments
for arg in "$@"; do
  case $arg in
    --interactive|-i)
      INTERACTIVE=true
      shift
      ;;
    setup|backup|info)
      COMMAND="$arg"
      shift
      ;;
    *)
      # Unknown option
      echo "Unknown option: $arg"
      echo "Usage: $0 [--interactive|-i] [setup|backup|info]"
      exit 1
      ;;
  esac
done

# Function to ask for confirmation in interactive mode
confirm_install() {
  local component=$1
  local default=${2:-Y}
  
  if [ "$INTERACTIVE" = true ]; then
    local prompt="Install $component? [Y/n]: "
    [ "$default" = "N" ] && prompt="Install $component? [y/N]: "
    
    read -p "$prompt" choice
    choice=${choice:-$default}
    
    case "$choice" in
      y|Y) return 0 ;;
      n|N) return 1 ;;
      *) 
        echo "Invalid choice. Please enter Y or N."
        confirm_install "$component" "$default"
        ;;
    esac
  else
    # In non-interactive mode, always install
    return 0
  fi
}

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
LOG_FILE="$BASE_DIR/log/syhub_setup.log"

# Create log directory
mkdir -p "$BASE_DIR/log"

# Logging function 
log_message() {
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Install yq if not available
install_yq() {
  if ! command -v yq &> /dev/null; then
    log_message "Installing yq YAML processor..."
    YQ_VERSION="v4.40.5"
    ARCH=$(uname -m)
    
    case "$ARCH" in
      arm*|aarch64)
        wget "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_arm64" -O /tmp/yq || { 
          log_message "Error downloading yq. Please check your internet connection."
          return 1
        }
        ;;
      x86_64)
        wget "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -O /tmp/yq || {
          log_message "Error downloading yq. Please check your internet connection."
          return 1
        }
        ;;
      *)
        log_message "Unsupported architecture: $ARCH"
        return 1
        ;;
    esac
    
    chmod +x /tmp/yq
    mv /tmp/yq /usr/local/bin/yq
    log_message "yq installed successfully."
    return 0
  fi
  return 0
}

# Handle installation from different locations
if [ "$SCRIPT_DIR" != "$BASE_DIR" ]; then
  log_message "Installing from external location to $BASE_DIR..."
  
  # Create the target directory if it doesn't exist
  mkdir -p "$BASE_DIR"

  # Copy the required files to the target directory
  log_message "Copying files to $BASE_DIR..."
  cp -r "$SCRIPT_DIR/"* "$BASE_DIR/"
  
  # Make scripts executable
  chmod +x "$BASE_DIR/setup.sh"
  find "$BASE_DIR/scripts" -type f -name "*.sh" -exec chmod +x {} \;
  
  # Download frontend dependencies
  log_message "Downloading dependencies..."
  "$BASE_DIR/scripts/download_deps.sh" || {
    log_message "Error downloading dependencies. Please check your internet connection."
    exit 1
  }
  
  log_message "Files copied successfully. Launching setup..."
  
  # Execute the script in the target location
  exec "$BASE_DIR/setup.sh" "$@"
  exit 0
fi

# Load configuration
load_config() {
  log_message "Loading configuration from $CONFIG_FILE"
  
  if [ ! -f "$CONFIG_FILE" ]; then
    log_message "Error: Configuration file not found: $CONFIG_FILE"
    exit 1
  fi
  
  # Try to use yq for better YAML parsing
  if command -v yq &> /dev/null; then
    log_message "Using yq for YAML parsing"
    
    # Parse config.yml with yq
    PROJECT_NAME=$(yq e '.project.name' "$CONFIG_FILE" 2>/dev/null)
    HOSTNAME=$(yq e '.hostname' "$CONFIG_FILE" 2>/dev/null)
    
    # Service names
    MOSQUITTO_CONF=$(yq e '.service_names.mosquitto_conf' "$CONFIG_FILE" 2>/dev/null)
    NGINX_SITE=$(yq e '.service_names.nginx_site' "$CONFIG_FILE" 2>/dev/null)
    
    # WiFi AP settings
    WIFI_AP_SSID=$(yq e '.wifi.ap_ssid' "$CONFIG_FILE" 2>/dev/null)
    WIFI_AP_PASSWORD=$(yq e '.wifi.ap_password' "$CONFIG_FILE" 2>/dev/null)
    
    # MQTT settings
    MQTT_PORT=$(yq e '.mqtt.port' "$CONFIG_FILE" 2>/dev/null)
    MQTT_USERNAME=$(yq e '.mqtt.username' "$CONFIG_FILE" 2>/dev/null)
    MQTT_CLIENT_ID=$(yq e '.mqtt.client_id_base' "$CONFIG_FILE" 2>/dev/null)
    MQTT_PASSWORD=$(yq e '.mqtt.password' "$CONFIG_FILE" 2>/dev/null)
    
    # VictoriaMetrics config
    VM_VERSION=$(yq e '.victoria_metrics.version' "$CONFIG_FILE" 2>/dev/null)
    VM_PORT=$(yq e '.victoria_metrics.port' "$CONFIG_FILE" 2>/dev/null)
    VM_DATA_DIR=$(yq e '.victoria_metrics.data_directory' "$CONFIG_FILE" 2>/dev/null)
    VM_RETENTION=$(yq e '.victoria_metrics.retention_period' "$CONFIG_FILE" 2>/dev/null)
    VM_USER=$(yq e '.victoria_metrics.service_user' "$CONFIG_FILE" 2>/dev/null)
    VM_GROUP=$(yq e '.victoria_metrics.service_group' "$CONFIG_FILE" 2>/dev/null)
    
    # Node-RED config
    NODERED_PORT=$(yq e '.node_red.port' "$CONFIG_FILE" 2>/dev/null)
    NODERED_MEMORY=$(yq e '.node_red.memory_limit_mb' "$CONFIG_FILE" 2>/dev/null)
    NODERED_USERNAME=$(yq e '.node_red.username' "$CONFIG_FILE" 2>/dev/null)
    NODERED_PASSWORD_HASH=$(yq e '.node_red.password_hash' "$CONFIG_FILE" 2>/dev/null)
    
    # Dashboard config
    DASHBOARD_PORT=$(yq e '.dashboard.port' "$CONFIG_FILE" 2>/dev/null)
    DASHBOARD_WORKERS=$(yq e '.dashboard.workers' "$CONFIG_FILE" 2>/dev/null)
    
    # Node.js config
    NODEJS_VERSION=$(yq e '.nodejs.install_version' "$CONFIG_FILE" 2>/dev/null)
    
    # Network config
    CONFIGURE_NETWORK=$(yq e '.configure_network' "$CONFIG_FILE" 2>/dev/null)
  else
    log_message "WARNING: yq not found, trying to install..."
    if ! install_yq; then
      log_message "WARNING: yq installation failed, falling back to basic YAML parsing"
      # Use our source function if yq is not available
      if [ -f "$BASE_DIR/scripts/utils.sh" ]; then
        source "$BASE_DIR/scripts/utils.sh"
        # Source the parsed YAML
        eval $(parse_yaml "$CONFIG_FILE" "config_")
        PROJECT_NAME="${config_project_name}"
        HOSTNAME="${config_hostname}"
        MOSQUITTO_CONF="${config_service_names_mosquitto_conf}"
        NGINX_SITE="${config_service_names_nginx_site}"
        MQTT_PORT="${config_mqtt_port}"
        MQTT_USERNAME="${config_mqtt_username}"
        MQTT_CLIENT_ID="${config_mqtt_client_id_base}"
        MQTT_PASSWORD="${config_mqtt_password}"
        VM_VERSION="${config_victoria_metrics_version}"
        VM_PORT="${config_victoria_metrics_port}"
        VM_DATA_DIR="${config_victoria_metrics_data_directory}"
        VM_RETENTION="${config_victoria_metrics_retention_period}"
        VM_USER="${config_victoria_metrics_service_user}"
        VM_GROUP="${config_victoria_metrics_service_group}"
        NODERED_PORT="${config_node_red_port}"
        NODERED_MEMORY="${config_node_red_memory_limit_mb}"
        NODERED_USERNAME="${config_node_red_username}"
        NODERED_PASSWORD_HASH="${config_node_red_password_hash}"
        DASHBOARD_PORT="${config_dashboard_port}"
        DASHBOARD_WORKERS="${config_dashboard_workers}"
        NODEJS_VERSION="${config_nodejs_install_version}"
        CONFIGURE_NETWORK="${config_configure_network}"
        WIFI_AP_SSID="${config_wifi_ap_ssid}"
        WIFI_AP_PASSWORD="${config_wifi_ap_password}"
      else
        log_message "ERROR: utils.sh not found, cannot parse YAML"
        exit 1
      fi
    else
      # Try again with yq
      load_config
      return
    fi
  fi
  
  log_message "Checking project name: '$PROJECT_NAME'"
  
  # Check required configuration values
  if [ -z "$PROJECT_NAME" ]; then
    log_message "Error: Missing required configuration value: project.name"
    exit 1
  fi
  
  # Handle auto-configuration parameters
  
  # WiFi AP settings
  if [ "$WIFI_AP_SSID" = "auto" ]; then
    WIFI_AP_SSID="${PROJECT_NAME}_ap"
    log_message "Auto-configured WiFi AP SSID: $WIFI_AP_SSID"
  fi
  
  if [ "$WIFI_AP_PASSWORD" = "auto" ]; then
    WIFI_AP_PASSWORD="${PROJECT_NAME}123"
    log_message "Auto-configured WiFi AP password: $WIFI_AP_PASSWORD"
  fi
  
  # MQTT settings
  if [ "$MQTT_USERNAME" = "auto" ]; then
    MQTT_USERNAME="${PROJECT_NAME}"
    log_message "Auto-configured MQTT username: $MQTT_USERNAME"
  fi
  
  if [ "$MQTT_CLIENT_ID" = "auto" ]; then
    MQTT_CLIENT_ID="${PROJECT_NAME}"
    log_message "Auto-configured MQTT client ID: $MQTT_CLIENT_ID"
  fi
  
  if [ "$MQTT_PASSWORD" = "auto" ]; then
    MQTT_PASSWORD="${PROJECT_NAME}Pass"
    log_message "Auto-configured MQTT password: $MQTT_PASSWORD"
  fi
  
  log_message "Configuration loaded successfully"
}

# Update and install dependencies
install_dependencies() {
  log_message "Updating package lists and installing dependencies"
  apt update || {
    log_message "Error updating package lists. Check your internet connection."
    exit 1
  }
  
  apt install -y python3 python3-pip python3-venv mosquitto mosquitto-clients \
    avahi-daemon nginx git curl build-essential procps \
    net-tools libavahi-compat-libdnssd-dev || {
    log_message "Error installing dependencies. Check your internet connection or disk space."
    exit 1
  }

  # Set hostname
  hostnamectl set-hostname "$HOSTNAME"
  echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
  
  log_message "Basic dependencies installed"
}

# Setup VictoriaMetrics
setup_victoriametrics() {
  log_message "Setting up VictoriaMetrics $VM_VERSION"
  
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
  
  log_message "VictoriaMetrics setup completed"
}

# Setup Mosquitto MQTT broker
setup_mqtt() {
  log_message "Setting up Mosquitto MQTT broker"
  
  # Configure Mosquitto
  cat > /etc/mosquitto/conf.d/${MOSQUITTO_CONF}.conf << EOF
listener $MQTT_PORT
allow_anonymous false
password_file /etc/mosquitto/passwd
EOF

  # Create password file with user
  touch /etc/mosquitto/passwd
  mosquitto_passwd -b /etc/mosquitto/passwd "$MQTT_USERNAME" "$MQTT_PASSWORD"
  
  # Restart service
  systemctl restart mosquitto
  
  log_message "MQTT broker setup completed"
}

# Setup Node.js
setup_nodejs() {
  log_message "Setting up Node.js"
  
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
  
  log_message "Node.js setup completed"
}

# Setup Node-RED
setup_nodered() {
  log_message "Setting up Node-RED"
  
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

  # Update Node-RED flows with configurable prefix
  log_message "Updating Node-RED flows with project configuration"
  chmod +x "$BASE_DIR/scripts/update_flows.sh"
  "$BASE_DIR/scripts/update_flows.sh"

  # Import Node-RED flows
  cp $BASE_DIR/node-red-flows/flows.json /home/$SYSTEM_USER/.node-red/flows.json
  chown $SYSTEM_USER:$SYSTEM_USER /home/$SYSTEM_USER/.node-red/flows.json
  
  # Reload, enable and start service
  systemctl daemon-reload
  systemctl enable nodered
  systemctl start nodered
  
  log_message "Node-RED setup completed"
}

# Setup Flask Dashboard
setup_dashboard() {
  log_message "Setting up Flask dashboard"
  
  # Create Python virtual environment
  python3 -m venv "$BASE_DIR/dashboard/venv"
  chown -R $SYSTEM_USER:$SYSTEM_USER "$BASE_DIR/dashboard/venv"
  
  # Install Python dependencies
  runuser -l $SYSTEM_USER -c "cd $BASE_DIR/dashboard && source venv/bin/activate && pip install flask gunicorn requests pyyaml"
  
  # Update dashboard JS files with configurable prefix
  log_message "Updating dashboard JS files with project configuration"
  chmod +x "$BASE_DIR/scripts/update_js_files.sh"
  "$BASE_DIR/scripts/update_js_files.sh"
  
  # Create systemd service
  cat > /etc/systemd/system/dashboard.service << EOF
[Unit]
Description=${PROJECT_NAME} Dashboard
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
  
  log_message "Dashboard setup completed"
}

# Setup Nginx as a reverse proxy
setup_nginx() {
  log_message "Setting up Nginx as a reverse proxy"
  
  # Create Nginx configuration
  cat > /etc/nginx/sites-available/${NGINX_SITE} << EOF
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
  ln -sf /etc/nginx/sites-available/${NGINX_SITE} /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default
  
  # Test and restart Nginx
  nginx -t
  systemctl restart nginx
  
  log_message "Nginx setup completed"
}

# Setup WiFi
setup_wifi() {
  if [ "${config_configure_network}" != "true" ]; then
    log_message "Network configuration skipped by config"
    return 0
  fi
  
  log_message "Setting up WiFi in AP+STA mode"
  
  # Check required parameters
  if [ -z "${config_wifi_ap_interface}" ] || [ -z "${config_wifi_ap_ip}" ] || 
     [ -z "$WIFI_AP_SSID" ] || [ -z "$WIFI_AP_PASSWORD" ]; then
    log_message "Error: Missing required WiFi configuration parameters."
    log_message "Check your config.yml file for WiFi settings."
    return 1
  fi
  
  # Check country code
  if [ -z "${config_wifi_country_code}" ]; then
    log_message "Warning: WiFi country code not set. Using 'US' as default."
    config_wifi_country_code="US"
  fi
  
  # Install necessary packages
  apt install -y hostapd dnsmasq || {
    log_message "Error installing hostapd and dnsmasq. WiFi AP setup failed."
    return 1
  }

  # Setup AP interface
  cat > /etc/systemd/network/25-ap.network << EOF
[Match]
Name=${config_wifi_ap_interface}

[Network]
Address=${config_wifi_ap_ip}/24
DHCPServer=yes

[DHCPServer]
PoolOffset=100
PoolSize=50
EmitDNS=yes
DNS=8.8.8.8
EOF

  # Setup hostapd for the AP
  cat > /etc/hostapd/hostapd.conf << EOF
interface=${config_wifi_ap_interface}
driver=nl80211
ssid=$WIFI_AP_SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$WIFI_AP_PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
country_code=${config_wifi_country_code}
EOF

  # Enable and start services
  systemctl enable hostapd || log_message "Warning: Failed to enable hostapd service"
  systemctl enable dnsmasq || log_message "Warning: Failed to enable dnsmasq service"
  
  # Setup network forwarding
  echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/10-network-forwarding.conf
  sysctl -p /etc/sysctl.d/10-network-forwarding.conf || log_message "Warning: Failed to apply network forwarding settings"
  
  # Create AP+STA startup script
  cat > /usr/local/bin/setup-ap-sta << EOF
#!/bin/bash
iw phy phy0 interface add ${config_wifi_ap_interface} type __ap
systemctl restart systemd-networkd
systemctl restart hostapd
systemctl restart dnsmasq
EOF

  chmod +x /usr/local/bin/setup-ap-sta
  
  # Add to startup
  cat > /etc/systemd/system/ap-sta.service << EOF
[Unit]
Description=Setup AP+STA Wifi Mode
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-ap-sta
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable ap-sta.service || log_message "Warning: Failed to enable AP+STA service"
  
  log_message "WiFi AP+STA setup completed"
  return 0
}

# Main execution flow
main() {
  log_message "Starting SyHub setup"
  
  # Interactive mode notice
  if [ "$INTERACTIVE" = true ]; then
    log_message "Running in interactive mode. You will be prompted before each component installation."
  fi
  
  # Download frontend dependencies if not already done
  if [ ! -f "$BASE_DIR/dashboard/static/js/chart.min.js" ]; then
    log_message "Downloading frontend dependencies"
    "$BASE_DIR/scripts/download_deps.sh" || {
      log_message "Error downloading dependencies. Please check your internet connection."
      exit 1
    }
  fi
  
  # Always load configuration
  load_config
  
  # Always install basic dependencies
  if confirm_install "basic dependencies (required)"; then
    install_dependencies
  else
    log_message "Basic dependencies are required. Exiting."
    exit 1
  fi
  
  # Setup VictoriaMetrics
  if confirm_install "VictoriaMetrics time series database"; then
    setup_victoriametrics
  else
    log_message "Skipping VictoriaMetrics installation"
  fi
  
  # Setup MQTT
  if confirm_install "Mosquitto MQTT broker"; then
    setup_mqtt
  else
    log_message "Skipping MQTT installation"
  fi
  
  # Setup Node.js
  if confirm_install "Node.js"; then
    setup_nodejs
  else
    log_message "Skipping Node.js installation"
  fi
  
  # Setup Node-RED
  if confirm_install "Node-RED flow editor"; then
    setup_nodered
  else
    log_message "Skipping Node-RED installation"
  fi
  
  # Setup Dashboard
  if confirm_install "Flask Dashboard"; then
    setup_dashboard
  else
    log_message "Skipping Dashboard installation"
  fi
  
  # Setup Nginx
  if confirm_install "Nginx web server"; then
    setup_nginx
  else
    log_message "Skipping Nginx installation"
  fi
  
  # Setup WiFi
  if [ "$CONFIGURE_NETWORK" = "true" ]; then
    if confirm_install "WiFi in AP+STA mode" "N"; then
      setup_wifi
    else
      log_message "Skipping WiFi setup"
    fi
  else
    log_message "Network configuration disabled in config"
  fi
  
  log_message "Setup completed successfully!"
  
  # Show access information
  echo "===================================================="
  echo "Installation complete! Access your services at:"
  echo "Dashboard: http://$HOSTNAME/"
  echo "Node-RED: http://$HOSTNAME/node-red/"
  echo "VictoriaMetrics: http://$HOSTNAME/victoria/"
  echo "===================================================="
}

# Backup function (adapted from older script)
backup() {
  log_message "Creating backup..."
  
  # Ensure backup directory exists
  BACKUP_DIR="backups"
  mkdir -p "$BASE_DIR/$BACKUP_DIR"
  
  # Create backup with timestamp
  BACKUP_FILE="$BASE_DIR/$BACKUP_DIR/backup-$(date +%F).tar.gz"
  tar -czf "$BACKUP_FILE" "$BASE_DIR/config" "$BASE_DIR/dashboard" "$BASE_DIR/node-red-flows" > /dev/null 2>&1 || { 
    log_message "Error creating backup"
    return 1
  }
  
  log_message "Backup created at: $BACKUP_FILE"
}

# Show info function
show_info() {
  echo "========================================"
  echo "  $PROJECT_NAME System Information"
  echo "========================================"
  echo "Project Name: $PROJECT_NAME"
  echo "Installation Directory: $BASE_DIR"
  echo "Hostname: $HOSTNAME"
  
  # Check service status
  echo ""
  echo "Services Status:"
  for service in mosquitto victoriametrics nodered dashboard; do
    if systemctl is-active --quiet "$service"; then
      echo "  $service: RUNNING"
    else
      echo "  $service: STOPPED"
    fi
  done
  
  # Show URLs
  echo ""
  echo "Access URLs:"
  echo "  Dashboard: http://$HOSTNAME:$DASHBOARD_PORT"
  echo "  Node-RED: http://$HOSTNAME:$NODERED_PORT"
  echo "  VictoriaMetrics: http://$HOSTNAME:$VM_PORT"
  
  # Show credentials
  echo ""
  echo "Credentials:"
  echo "  MQTT Username: $MQTT_USERNAME"
  echo "  Node-RED Username: $NODERED_USERNAME"
}

# Handle command
case "$COMMAND" in
  setup)
    main
    ;;
  backup)
    load_config
    backup
    ;;
  info)
    load_config
    show_info
    ;;
  *)
    echo "Unknown command: $COMMAND"
    echo "Usage: $0 [--interactive|-i] [setup|backup|info]"
    exit 1
    ;;
esac 