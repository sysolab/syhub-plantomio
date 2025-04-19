#!/bin/bash

# SyHub Setup Script - Optimized for Raspberry Pi 3B
# This script sets up a complete IoT monitoring infrastructure with MQTT, VictoriaMetrics, and Node-RED

set -e  # Exit on any error

# Flags
INTERACTIVE=false
SKIP_APT_UPDATE=false
UNINSTALL=false
FACTORY_RESET=false
COMPONENTS_TO_UPDATE=""

# Command to run
COMMAND="setup"

# Help function
show_help() {
  echo "Usage: $0 [OPTIONS] [COMMAND]"
  echo ""
  echo "Options:"
  echo "  -i, --interactive     : Interactive mode, ask before each step"
  echo "  -s, --skip-apt-update : Skip apt update during installation"
  echo "  -u, --uninstall       : Uninstall specified components"
  echo "  -f, --factory-reset   : Completely remove all installations"
  echo "  -c, --components=LIST : Comma-separated list of components to install/uninstall"
  echo "                           Available: vm,mqtt,nodejs,nodered,dashboard,nginx,wifi"
  echo ""
  echo "Commands:"
  echo "  setup   : Install components (default)"
  echo "  backup  : Create a backup of configuration files"
  echo "  info    : Display system information"
  echo ""
  echo "Examples:"
  echo "  $0 -i                        : Interactive installation"
  echo "  $0 --components=vm,mqtt      : Install only VictoriaMetrics and MQTT"
  echo "  $0 -u --components=dashboard : Uninstall only the dashboard"
  echo "  $0 -f                        : Factory reset (remove everything)"
  echo "  $0 info                      : Show system information"
  exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      show_help
      ;;
    -i|--interactive)
      INTERACTIVE=true
      shift
      ;;
    -s|--skip-apt-update)
      SKIP_APT_UPDATE=true
      shift
      ;;
    -u|--uninstall)
      UNINSTALL=true
      shift
      ;;
    -f|--factory-reset)
      FACTORY_RESET=true
      shift
      ;;
    -c=*|--components=*)
      COMPONENTS_TO_UPDATE="${1#*=}"
      shift
      ;;
    -c|--components)
      if [[ -n "$2" && "$2" != -* ]]; then
        COMPONENTS_TO_UPDATE="$2"
        shift 2
      else
        echo "Error: --components requires an argument"
        exit 1
      fi
      ;;
    setup|backup|info)
      COMMAND="$1"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help to see available options"
      exit 1
      ;;
  esac
done

# Function to check if a component should be processed
should_process_component() {
  local component=$1
  
  # If no specific components are specified, process all
  if [ -z "$COMPONENTS_TO_UPDATE" ]; then
    return 0
  fi
  
  # Check if the component is in the list
  echo "$COMPONENTS_TO_UPDATE" | tr ',' '\n' | grep -q "^$component$"
  return $?
}

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
  log_message "Installing dependencies"
  
  # Run apt update unless skipped
  if [ "$SKIP_APT_UPDATE" = false ]; then
    log_message "Updating package lists"
    apt update || {
      log_message "Error updating package lists. Check your internet connection."
      exit 1
    }
  else
    log_message "Skipping apt update as requested"
  fi
  
  log_message "Installing required packages"
  apt install -y python3 python3-pip python3-venv mosquitto mosquitto-clients \
    avahi-daemon nginx git curl build-essential procps \
    net-tools libavahi-compat-libdnssd-dev || {
    log_message "Error installing dependencies. Check your internet connection or disk space."
    exit 1
  }

  # Set hostname
  if [ "$HOSTNAME" != "$(hostname)" ]; then
    log_message "Setting hostname to $HOSTNAME"
  hostnamectl set-hostname "$HOSTNAME"
    
    # Add to hosts file if not already there
    if ! grep -q "$HOSTNAME" /etc/hosts; then
  echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
    fi
  else
    log_message "Hostname already set to $HOSTNAME"
  fi
  
  log_message "Basic dependencies installed"
}

# Setup VictoriaMetrics
setup_victoriametrics() {
  log_message "Setting up VictoriaMetrics $VM_VERSION"
  
  # Stop existing service if running
  if systemctl is-active --quiet victoriametrics; then
    log_message "Stopping existing VictoriaMetrics service"
    systemctl stop victoriametrics
    
    # Wait for service to fully stop
    sleep 2
  fi
  
  # Create service user if doesn't exist
  if ! id "$VM_USER" &>/dev/null; then
    log_message "Creating service user: $VM_USER"
    useradd -rs /bin/false "$VM_USER"
  fi
  
  # Create data directory
  if [ ! -d "$VM_DATA_DIR" ]; then
    log_message "Creating data directory: $VM_DATA_DIR"
  mkdir -p "$VM_DATA_DIR"
  fi
  
  # Set proper ownership
  chown -R "$VM_USER":"$VM_GROUP" "$VM_DATA_DIR"
  
  # Determine architecture for correct download
  ARCH=$(uname -m)
  VM_ARCH="arm64"
  
  if [ "$ARCH" = "x86_64" ]; then
    VM_ARCH="amd64"
  elif [[ "$ARCH" == "arm"* ]] || [ "$ARCH" = "aarch64" ]; then
    VM_ARCH="arm64"
  else
    log_message "Warning: Unsupported architecture: $ARCH. Trying arm64 version."
    VM_ARCH="arm64"
  fi
  
  log_message "Detected architecture: $ARCH, using VM architecture: $VM_ARCH"
  
  # Prepare temporary directory for download
  TEMP_DIR=$(mktemp -d)
  log_message "Using temporary directory: $TEMP_DIR"
  
  # Download VictoriaMetrics
  VM_BINARY_URL="https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/$VM_VERSION/victoria-metrics-linux-$VM_ARCH-$VM_VERSION.tar.gz"
  
  log_message "Downloading VictoriaMetrics from $VM_BINARY_URL"
  if ! curl -L "$VM_BINARY_URL" -o "$TEMP_DIR/vm.tar.gz"; then
    log_message "Error: Failed to download VictoriaMetrics. Check your internet connection."
    rm -rf "$TEMP_DIR"
    return 1
  fi
  
  # Verify the download
  if [ ! -s "$TEMP_DIR/vm.tar.gz" ]; then
    log_message "Error: Downloaded file is empty or not found."
    rm -rf "$TEMP_DIR"
    return 1
  fi
  
  # Extracting the file
  log_message "Extracting VictoriaMetrics"
  mkdir -p "$TEMP_DIR/extract"
  if ! tar -xzf "$TEMP_DIR/vm.tar.gz" -C "$TEMP_DIR/extract"; then
    log_message "Error: Failed to extract VictoriaMetrics archive."
    rm -rf "$TEMP_DIR"
    return 1
  fi
  
  # Find and copy the binary
  VM_BINARY=$(find "$TEMP_DIR/extract" -type f -executable | head -n 1)
  
  if [ -z "$VM_BINARY" ]; then
    log_message "Error: VictoriaMetrics binary not found in the downloaded archive"
    rm -rf "$TEMP_DIR"
    return 1
  fi
  
  log_message "Found VictoriaMetrics binary: $VM_BINARY"
  
  # Stop any running processes that might be using the binary
  if pgrep -f "victoria-metrics" > /dev/null; then
    log_message "Stopping existing VictoriaMetrics processes"
    pkill -f "victoria-metrics" || true
    sleep 3
  fi
  
  # Remove existing binary if it exists
  if [ -f /usr/local/bin/victoria-metrics ]; then
    log_message "Removing existing VictoriaMetrics binary"
    rm -f /usr/local/bin/victoria-metrics
    
    # If the file is still there (possibly due to being in use), try alternative approach
    if [ -f /usr/local/bin/victoria-metrics ]; then
      log_message "Binary is busy. Moving to a backup and installing new version."
      mv /usr/local/bin/victoria-metrics /usr/local/bin/victoria-metrics.old || true
    fi
  fi
  
  # Copy the new binary
  log_message "Installing VictoriaMetrics binary"
  if ! cp "$VM_BINARY" /usr/local/bin/victoria-metrics; then
    log_message "Error: Failed to copy VictoriaMetrics binary to /usr/local/bin/"
    rm -rf "$TEMP_DIR"
    return 1
  fi
  
  chmod +x /usr/local/bin/victoria-metrics
  
  # Clean up
  rm -rf "$TEMP_DIR"
  
  # Create systemd service
  log_message "Creating VictoriaMetrics service"
  cat > /etc/systemd/system/victoriametrics.service << EOF
[Unit]
Description=VictoriaMetrics Time Series Database
After=network.target
Wants=network-online.target

[Service]
User=$VM_USER
Group=$VM_GROUP
Type=simple
ExecStart=/usr/local/bin/victoria-metrics -storageDataPath=$VM_DATA_DIR -retentionPeriod=$VM_RETENTION -httpListenAddr=:$VM_PORT -search.maxUniqueTimeseries=1000 -memory.allowedPercent=30
Restart=always
RestartSec=5
LimitNOFILE=65536
TimeoutStopSec=20
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF

  # Reload, enable and start service
  log_message "Starting VictoriaMetrics service"
  systemctl daemon-reload
  
  # Test if we can start the service
  if ! systemctl start victoriametrics; then
    log_message "Error: Failed to start VictoriaMetrics service"
    systemctl status victoriametrics > /tmp/vm_status.log 2>&1
    log_message "VictoriaMetrics status saved to /tmp/vm_status.log"
    
    # Ask if we should continue despite the error
    if [ "$INTERACTIVE" = true ]; then
      read -p "VictoriaMetrics failed to start. Continue with setup anyway? [y/N]: " choice
      case "$choice" in
        y|Y) 
          log_message "Continuing setup despite VictoriaMetrics failure"
          systemctl enable victoriametrics || true
          ;;
        *) 
          log_message "Aborting setup due to VictoriaMetrics failure"
          return 1
          ;;
      esac
    else
      log_message "WARNING: VictoriaMetrics setup failed but continuing with installation"
      systemctl enable victoriametrics || true
    fi
  else
    log_message "VictoriaMetrics service started successfully"
  systemctl enable victoriametrics
  fi
  
  # Test if the HTTP endpoint is available
  log_message "Testing VictoriaMetrics HTTP endpoint"
  if command -v curl &> /dev/null; then
    RETRY_COUNT=0
    MAX_RETRIES=3
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
      if curl -s "http://localhost:$VM_PORT/health" | grep -q "VictoriaMetrics"; then
        log_message "VictoriaMetrics HTTP endpoint is responding correctly"
        break
      else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
          log_message "VictoriaMetrics endpoint not responding yet, retrying in 2 seconds..."
          sleep 2
        else
          log_message "WARNING: VictoriaMetrics endpoint not responding after $MAX_RETRIES attempts"
        fi
      fi
    done
  fi
  
  log_message "VictoriaMetrics setup completed"
}

# Setup Mosquitto MQTT broker
setup_mqtt() {
  log_message "Setting up Mosquitto MQTT broker"
  
  # Backup existing config if it exists
  if [ -f "/etc/mosquitto/mosquitto.conf" ]; then
    mv "/etc/mosquitto/mosquitto.conf" "/etc/mosquitto/mosquitto.conf.backup"
    log_message "Backed up existing mosquitto.conf"
  fi
  
  # Create a clean main config file with all settings in one place
  log_message "Creating Mosquitto configuration file"
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
listener $MQTT_PORT  
password_file /etc/mosquitto/passwd
EOF
    
  log_message "Created new mosquitto.conf with all required settings"
  
  # Set correct file permissions
  chown mosquitto:mosquitto "/etc/mosquitto/mosquitto.conf"
  chmod 644 "/etc/mosquitto/mosquitto.conf"
  
  # Remove any existing conf.d file that might cause conflicts
  if [ -d "/etc/mosquitto/conf.d" ]; then
    log_message "Checking conf.d directory for potential conflicts"
    for conf_file in /etc/mosquitto/conf.d/*.conf; do
      if [ -f "$conf_file" ]; then
        log_message "Removing potential conflicting config: $conf_file"
        mv "$conf_file" "${conf_file}.backup"
      fi
    done
  fi

  # Create password file with user
  log_message "Setting up MQTT credentials for user: $MQTT_USERNAME"
  
  # Make sure we're creating a new password file if needed
  if [ ! -f "/etc/mosquitto/passwd" ]; then
  touch /etc/mosquitto/passwd
    chown mosquitto:mosquitto /etc/mosquitto/passwd
    log_message "Created new password file"
  else
    # Backup existing password file
    cp "/etc/mosquitto/passwd" "/etc/mosquitto/passwd.backup"
    log_message "Backed up existing password file"
  fi
  
  # Create password entry (this overwrites existing entries with same username)
  mosquitto_passwd -b /etc/mosquitto/passwd "$MQTT_USERNAME" "$MQTT_PASSWORD" || {
    log_message "Error creating MQTT password entry. Trying alternative method..."
    
    # If mosquitto_passwd fails, try a different approach
    # First check if we have the required tools
    if command -v openssl > /dev/null; then
      log_message "Using OpenSSL to create password hash"
      # Create password hash using OpenSSL
      PASS_HASH=$(echo -n "$MQTT_PASSWORD" | openssl passwd -6 -stdin)
      echo "$MQTT_USERNAME:$PASS_HASH" > "/etc/mosquitto/passwd"
      chown mosquitto:mosquitto "/etc/mosquitto/passwd"
      chmod 600 "/etc/mosquitto/passwd"
    else
      log_message "ERROR: Cannot create MQTT password. Please set up manually after installation."
    fi
  }
  
  # Set correct permissions
  chmod 600 /etc/mosquitto/passwd
  chown mosquitto:mosquitto /etc/mosquitto/passwd
  
  # Validate configuration before restarting
  log_message "Validating Mosquitto configuration"
  if command -v mosquitto > /dev/null; then
    mosquitto -t -c /etc/mosquitto/mosquitto.conf || {
      log_message "Warning: Mosquitto configuration validation failed. Proceeding anyway."
    }
  fi
  
  # Restart service with more robust error handling
  log_message "Restarting Mosquitto service"
  if ! systemctl restart mosquitto; then
    log_message "Error restarting Mosquitto. Attempting automatic fix..."
    
    # Try to fix it with our repair script
    if [ -f "$BASE_DIR/scripts/fix_mosquitto.sh" ]; then
      log_message "Running mosquitto fix script"
      bash "$BASE_DIR/scripts/fix_mosquitto.sh"
      
      # Check if the fix worked
      if ! systemctl is-active --quiet mosquitto; then
        log_message "Automatic fix unsuccessful. Manual intervention required."
        
        # Get Mosquitto status for debugging
        systemctl status mosquitto > /tmp/mosquitto_status.log 2>&1
        log_message "Mosquitto status saved to /tmp/mosquitto_status.log"
        
        # Get logs for debugging
        journalctl -u mosquitto --no-pager -n 50 > /tmp/mosquitto_journal.log 2>&1
        log_message "Mosquitto logs saved to /tmp/mosquitto_journal.log"
        
        # Show error info
        log_message "Mosquitto failed to start. Please check:"
        log_message "  - Run 'systemctl status mosquitto' for details"
        log_message "  - Check logs with 'journalctl -xeu mosquitto.service'"
        
        # Ask if we should continue despite the error
        if [ "$INTERACTIVE" = true ]; then
          read -p "Mosquitto failed to start. Continue with setup anyway? [y/N]: " choice
          case "$choice" in
            y|Y) log_message "Continuing setup despite Mosquitto failure" ;;
            *) 
              log_message "Aborting setup due to Mosquitto failure"
              exit 1
              ;;
          esac
        else
          log_message "WARNING: Mosquitto setup failed but continuing with installation"
        fi
      else
        log_message "Automatic fix successful! Mosquitto is now running."
      fi
    else
      log_message "Fix script not found. Manual intervention required."
      
      # Show more diagnostic info
      systemctl status mosquitto
      log_message "Please run 'journalctl -xeu mosquitto.service' to see detailed logs"
      
      # Ask if we should continue despite the error
      if [ "$INTERACTIVE" = true ]; then
        read -p "Mosquitto failed to start. Continue with setup anyway? [y/N]: " choice
        case "$choice" in
          y|Y) log_message "Continuing setup despite Mosquitto failure" ;;
          *) 
            log_message "Aborting setup due to Mosquitto failure"
            exit 1
            ;;
        esac
      else
        log_message "WARNING: Mosquitto setup failed but continuing with installation"
      fi
    fi
  else 
    log_message "Mosquitto MQTT broker started successfully"
  fi
  
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
  
  # Check if Node-RED is already installed
  if ! command -v node-red &> /dev/null; then
    log_message "Installing Node-RED as global package"
    runuser -l "$SYSTEM_USER" -c 'npm install -g --unsafe-perm node-red' || {
      log_message "Error installing Node-RED. Please check npm installation."
      exit 1
    }
  else
    log_message "Node-RED is already installed"
  fi
  
  # Create Node-RED user directory
  mkdir -p "/home/$SYSTEM_USER/.node-red"
  chown "$SYSTEM_USER:$SYSTEM_USER" "/home/$SYSTEM_USER/.node-red"
  
  # Install required Node-RED nodes
  log_message "Installing Node-RED nodes"
  NODE_PACKAGES="node-red-dashboard node-red-node-ui-table"
  
  for package in $NODE_PACKAGES; do
    log_message "Installing Node-RED package: $package"
    runuser -l "$SYSTEM_USER" -c "cd ~/.node-red && npm install $package" || {
      log_message "Warning: Failed to install $package. Node-RED may have limited functionality."
    }
  done
  
  # Create Node-RED settings file
  log_message "Creating Node-RED settings file"
  cat > "/home/$SYSTEM_USER/.node-red/settings.js" << EOF
module.exports = {
    httpAdminRoot: '/admin',
    httpNodeRoot: '/',
    uiPort: $NODERED_PORT,
    userDir: '/home/$SYSTEM_USER/.node-red',
    adminAuth: {
        type: "credentials",
        users: [{
            username: "$NODERED_USERNAME",
            password: "$NODERED_PASSWORD_HASH",
            permissions: "*"
        }]
    },
    functionGlobalContext: {
        // Make project configuration available to functions
        config: {
            projectName: "$PROJECT_NAME",
            mqtt: {
                host: "localhost",
                port: $MQTT_PORT,
                username: "$MQTT_USERNAME",
                password: "$MQTT_PASSWORD"
            },
            vm: {
                host: "localhost",
                port: $VM_PORT
            }
        }
    },
    httpNodeCors: {
        origin: "*",
        methods: "GET,PUT,POST,DELETE"
    },
    editorTheme: { 
        projects: { enabled: false }
    }
};
EOF

  # Fix permissions on settings file
  chown "$SYSTEM_USER:$SYSTEM_USER" "/home/$SYSTEM_USER/.node-red/settings.js"

  # Create systemd service for Node-RED
  log_message "Creating Node-RED systemd service"
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

  # Setup flows from node-red-flows directory
  setup_nodered_flows
  
  # Reload, enable and start service
  log_message "Starting Node-RED service to apply flows..."
  systemctl daemon-reload
  systemctl enable nodered
  
  # Completely stop Node-RED first to ensure a clean start
  systemctl stop nodered 2>/dev/null || true
  sleep 2
  
  # Start Node-RED and wait for it to initialize
  systemctl start nodered
  log_message "Waiting for Node-RED to start and apply flows (this may take a moment)..."
  sleep 10
  
  # Check if Node-RED started successfully
  if systemctl is-active --quiet nodered; then
    log_message "✓ Node-RED started successfully with flows applied"
    
    # Perform additional verification
    if [ -f "/home/$SYSTEM_USER/.node-red/.flows.json.backup" ] && [ -f "/home/$SYSTEM_USER/.node-red/flows.json" ]; then
      log_message "✓ Flow files verified - flows are ready to use"
    else
      log_message "Warning: Flow backup files not found, flows may not be properly applied"
    fi
  else
    log_message "Warning: Node-RED service didn't start properly. Checking status..."
    systemctl status nodered
    log_message "You can check logs with: journalctl -xeu nodered.service"
    
    # Ask if we should continue despite the error
    if [ "$INTERACTIVE" = true ]; then
      read -p "Node-RED failed to start. Continue with setup anyway? [y/N]: " choice
      case "$choice" in
        y|Y) log_message "Continuing setup despite Node-RED failure" ;;
        *) 
          log_message "Aborting setup due to Node-RED failure"
          exit 1
          ;;
      esac
    else
      log_message "WARNING: Node-RED setup failed but continuing with installation"
    fi
  fi
  
  log_message "Node-RED setup completed with flows from node-red-flows"
}

# Setup Node-RED flows
setup_nodered_flows() {
  log_message "Setting up Node-RED flows"
  
  # Create Node-RED user directory
  mkdir -p "/home/$SYSTEM_USER/.node-red"
  chown "$SYSTEM_USER:$SYSTEM_USER" "/home/$SYSTEM_USER/.node-red"
  
  # Create node-red-flows directory if it doesn't exist
  mkdir -p "$BASE_DIR/node-red-flows"
  chown "$SYSTEM_USER:$SYSTEM_USER" "$BASE_DIR/node-red-flows"
  
  # Remove any flows.json from the root directory (we only use node-red-flows)
  if [ -f "$BASE_DIR/flows.json" ]; then
    log_message "Found flows.json in project root, moving to node-red-flows"
    # If no flows exist in node-red-flows, move the root one there
    if [ ! -f "$BASE_DIR/node-red-flows/flows.json" ]; then
      mv "$BASE_DIR/flows.json" "$BASE_DIR/node-red-flows/flows.json"
    else
      # If flows exist in both places, backup the root one and remove it
      mv "$BASE_DIR/flows.json" "$BASE_DIR/flows.json.bak"
    fi
    log_message "Removed flows.json from project root for cleaner structure"
  fi
  
  # If no flows.json in node-red-flows, create a minimal empty one
  if [ ! -f "$BASE_DIR/node-red-flows/flows.json" ]; then
    log_message "No flows.json found in node-red-flows, creating minimal empty flow"
    echo "[]" > "$BASE_DIR/node-red-flows/flows.json"
    chown "$SYSTEM_USER:$SYSTEM_USER" "$BASE_DIR/node-red-flows/flows.json"
  fi
  
  # Copy flows from node-red-flows to Node-RED directory
  log_message "Installing flows from node-red-flows to Node-RED"
  cp "$BASE_DIR/node-red-flows/flows.json" "/home/$SYSTEM_USER/.node-red/flows.json"
  
  # Create backup files needed by Node-RED
  cp "$BASE_DIR/node-red-flows/flows.json" "/home/$SYSTEM_USER/.node-red/flows_backup.json"
  cp "$BASE_DIR/node-red-flows/flows.json" "/home/$SYSTEM_USER/.node-red/.flows.json.backup"
  
  # Set permissions
  chown "$SYSTEM_USER:$SYSTEM_USER" "/home/$SYSTEM_USER/.node-red/flows.json"
  chown "$SYSTEM_USER:$SYSTEM_USER" "/home/$SYSTEM_USER/.node-red/flows_backup.json"
  chown "$SYSTEM_USER:$SYSTEM_USER" "/home/$SYSTEM_USER/.node-red/.flows.json.backup"
  
  log_message "Node-RED flows successfully installed"
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
    log_message "Warning: WiFi country code not set. Using 'DE' as default."
    config_wifi_country_code="DE"
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

# Uninstall VictoriaMetrics
uninstall_victoriametrics() {
  log_message "Uninstalling VictoriaMetrics"
  
  # Stop and disable service
  if systemctl is-active --quiet victoriametrics; then
    log_message "Stopping VictoriaMetrics service"
    systemctl stop victoriametrics
  fi
  
  if systemctl is-enabled --quiet victoriametrics; then
    log_message "Disabling VictoriaMetrics service"
    systemctl disable victoriametrics
  fi
  
  # Remove service file
  if [ -f /etc/systemd/system/victoriametrics.service ]; then
    log_message "Removing VictoriaMetrics service file"
    rm -f /etc/systemd/system/victoriametrics.service
  fi
  
  # Remove binary
  if [ -f /usr/local/bin/victoria-metrics ]; then
    log_message "Removing VictoriaMetrics binary"
    rm -f /usr/local/bin/victoria-metrics
  fi
  
  # Optionally remove data directory
  if [ "$FACTORY_RESET" = true ] && [ -d "$VM_DATA_DIR" ]; then
    log_message "Removing VictoriaMetrics data directory"
    rm -rf "$VM_DATA_DIR"
  fi
  
  systemctl daemon-reload
  log_message "VictoriaMetrics uninstalled"
}

# Uninstall MQTT
uninstall_mqtt() {
  log_message "Uninstalling MQTT configuration"
  
  # Restore original config if backup exists
  if [ -f "/etc/mosquitto/mosquitto.conf.backup" ]; then
    log_message "Restoring original Mosquitto configuration"
    mv "/etc/mosquitto/mosquitto.conf.backup" "/etc/mosquitto/mosquitto.conf"
  fi
  
  # Clean up any potential remaining conf.d file
  if [ -f "/etc/mosquitto/conf.d/${MOSQUITTO_CONF}.conf" ]; then
    log_message "Removing any MQTT configuration in conf.d directory"
    rm -f "/etc/mosquitto/conf.d/${MOSQUITTO_CONF}.conf"
  fi
  
  # Reset password file only on factory reset
  if [ "$FACTORY_RESET" = true ] && [ -f "/etc/mosquitto/passwd" ]; then
    log_message "Removing MQTT password file"
    rm -f "/etc/mosquitto/passwd"
  fi
  
  # Restart Mosquitto to apply changes
  if systemctl is-active --quiet mosquitto; then
    log_message "Restarting Mosquitto service"
    systemctl restart mosquitto || log_message "Warning: Failed to restart Mosquitto after configuration removal"
  fi
  
  log_message "MQTT configuration removed"
}

# Uninstall Node-RED
uninstall_nodered() {
  log_message "Uninstalling Node-RED"
  
  # Stop and disable service
  if systemctl is-active --quiet nodered; then
    log_message "Stopping Node-RED service"
    systemctl stop nodered
  fi
  
  if systemctl is-enabled --quiet nodered; then
    log_message "Disabling Node-RED service"
    systemctl disable nodered
  fi
  
  # Remove service file
  if [ -f /etc/systemd/system/nodered.service ]; then
    log_message "Removing Node-RED service file"
    rm -f /etc/systemd/system/nodered.service
  fi
  
  # Optionally remove Node-RED installation on factory reset
  if [ "$FACTORY_RESET" = true ]; then
    log_message "Removing Node-RED installation"
    runuser -l "$SYSTEM_USER" -c 'npm uninstall -g node-red' || true
    
    # Remove .node-red directory
    if [ -d "/home/$SYSTEM_USER/.node-red" ]; then
      log_message "Removing Node-RED user directory"
      rm -rf "/home/$SYSTEM_USER/.node-red"
    fi
  fi
  
  systemctl daemon-reload
  log_message "Node-RED uninstalled"
}

# Uninstall Dashboard
uninstall_dashboard() {
  log_message "Uninstalling Dashboard"
  
  # Stop and disable service
  if systemctl is-active --quiet dashboard; then
    log_message "Stopping Dashboard service"
    systemctl stop dashboard
  fi
  
  if systemctl is-enabled --quiet dashboard; then
    log_message "Disabling Dashboard service"
    systemctl disable dashboard
  fi
  
  # Remove service file
  if [ -f /etc/systemd/system/dashboard.service ]; then
    log_message "Removing Dashboard service file"
    rm -f /etc/systemd/system/dashboard.service
  fi
  
  # Optionally remove dashboard files on factory reset
  if [ "$FACTORY_RESET" = true ] && [ -d "$BASE_DIR/dashboard" ]; then
    log_message "Removing Dashboard files"
    rm -rf "$BASE_DIR/dashboard"
  fi
  
  systemctl daemon-reload
  log_message "Dashboard uninstalled"
}

# Uninstall Nginx configuration
uninstall_nginx() {
  log_message "Uninstalling Nginx configuration"
  
  # Remove site configuration
  if [ -f "/etc/nginx/sites-available/${NGINX_SITE}" ]; then
    log_message "Removing Nginx site configuration"
    rm -f "/etc/nginx/sites-available/${NGINX_SITE}"
  fi
  
  # Remove symbolic link if it exists
  if [ -f "/etc/nginx/sites-enabled/${NGINX_SITE}" ]; then
    log_message "Removing Nginx site symlink"
    rm -f "/etc/nginx/sites-enabled/${NGINX_SITE}"
  fi
  
  # Restart Nginx to apply changes
  if systemctl is-active --quiet nginx; then
    log_message "Restarting Nginx service"
    systemctl restart nginx
  fi
  
  log_message "Nginx configuration removed"
}

# Uninstall WiFi configuration
uninstall_wifi() {
  log_message "Uninstalling WiFi configuration"
  
  # Stop and disable services
  for service in hostapd dnsmasq ap-sta; do
    if systemctl is-active --quiet $service; then
      log_message "Stopping $service service"
      systemctl stop $service
    fi
    
    if systemctl is-enabled --quiet $service; then
      log_message "Disabling $service service"
      systemctl disable $service
    fi
  done
  
  # Remove configuration files
  if [ -f /etc/systemd/network/25-ap.network ]; then
    log_message "Removing network configuration"
    rm -f /etc/systemd/network/25-ap.network
  fi
  
  if [ -f /etc/hostapd/hostapd.conf ]; then
    log_message "Removing hostapd configuration"
    rm -f /etc/hostapd/hostapd.conf
  fi
  
  if [ -f /etc/systemd/system/ap-sta.service ]; then
    log_message "Removing AP+STA service"
    rm -f /etc/systemd/system/ap-sta.service
  fi
  
  if [ -f /usr/local/bin/setup-ap-sta ]; then
    log_message "Removing AP+STA script"
    rm -f /usr/local/bin/setup-ap-sta
  fi
  
  # Reset network forwarding
  if [ -f /etc/sysctl.d/10-network-forwarding.conf ]; then
    log_message "Removing network forwarding configuration"
    rm -f /etc/sysctl.d/10-network-forwarding.conf
    sysctl -p || true
  fi
  
  systemctl daemon-reload
  log_message "WiFi configuration removed"
}

# Factory reset - uninstall everything
factory_reset() {
  log_message "Performing factory reset"
  
  # Set factory reset flag to true for complete removal
  FACTORY_RESET=true
  
  # Load configuration to get paths and service names
  load_config
  
  # Uninstall each component
  if should_process_component "vm" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
    uninstall_victoriametrics
  fi
  
  if should_process_component "mqtt" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
    uninstall_mqtt
  fi
  
  if should_process_component "nodered" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
    uninstall_nodered
  fi
  
  if should_process_component "dashboard" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
    uninstall_dashboard
  fi
  
  if should_process_component "nginx" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
    uninstall_nginx
  fi
  
  if should_process_component "wifi" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
    uninstall_wifi
  fi
  
  # Remove base directory if completely factory resetting
  if [ -z "$COMPONENTS_TO_UPDATE" ] && [ -d "$BASE_DIR" ]; then
    log_message "Removing base directory: $BASE_DIR"
    rm -rf "$BASE_DIR"
  fi
  
  log_message "Factory reset completed"
}

# Uninstall selected components
uninstall_components() {
  log_message "Uninstalling selected components"
  
  # Load configuration to get paths and service names
  load_config
  
  # Uninstall specified components
  if should_process_component "vm"; then
    uninstall_victoriametrics
  fi
  
  if should_process_component "mqtt"; then
    uninstall_mqtt
  fi
  
  if should_process_component "nodered"; then
    uninstall_nodered
  fi
  
  if should_process_component "dashboard"; then
    uninstall_dashboard
  fi
  
  if should_process_component "nginx"; then
    uninstall_nginx
  fi
  
  if should_process_component "wifi"; then
    uninstall_wifi
  fi
  
  log_message "Uninstallation completed"
}

# Main execution flow
main() {
  log_message "Starting SyHub setup"
  
  # Interactive mode notice
  if [ "$INTERACTIVE" = true ]; then
    log_message "Running in interactive mode. You will be prompted before each component installation."
  fi
  
  # Component-specific mode notice
  if [ -n "$COMPONENTS_TO_UPDATE" ]; then
    log_message "Installing only specified components: $COMPONENTS_TO_UPDATE"
  fi
  
  # Download frontend dependencies if not already done and dashboard will be installed
  if ([ -z "$COMPONENTS_TO_UPDATE" ] || should_process_component "dashboard") && [ ! -f "$BASE_DIR/dashboard/static/js/chart.min.js" ]; then
    log_message "Downloading frontend dependencies"
    "$BASE_DIR/scripts/download_deps.sh" || {
      log_message "Error downloading dependencies. Please check your internet connection."
      exit 1
    }
  fi
  
  # Always load configuration
  load_config
  
  # Always install basic dependencies unless component-specific mode
  if [ -z "$COMPONENTS_TO_UPDATE" ] || should_process_component "core"; then
    if confirm_install "basic dependencies (required)"; then
  install_dependencies
    else
      log_message "Basic dependencies are required for full installation. Continuing with limited setup."
    fi
  fi
  
  # Setup VictoriaMetrics
  if should_process_component "vm" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
    if confirm_install "VictoriaMetrics time series database"; then
  setup_victoriametrics
    else
      log_message "Skipping VictoriaMetrics installation"
    fi
  fi
  
  # Setup MQTT
  if should_process_component "mqtt" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
    if confirm_install "Mosquitto MQTT broker"; then
  setup_mqtt
      
      # Verify MQTT setup
      if [ -f "$BASE_DIR/scripts/verify_mqtt.sh" ]; then
        log_message "Verifying MQTT setup"
        bash "$BASE_DIR/scripts/verify_mqtt.sh" | tee -a "$LOG_FILE"
      fi
    else
      log_message "Skipping MQTT installation"
    fi
  fi
  
  # Setup Node.js
  if should_process_component "nodejs" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
    if confirm_install "Node.js"; then
  setup_nodejs
    else
      log_message "Skipping Node.js installation"
    fi
  fi
  
  # Setup Node-RED
  if should_process_component "nodered" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
    if confirm_install "Node-RED flow editor"; then
  setup_nodered
    else
      log_message "Skipping Node-RED installation"
    fi
  fi
  
  # Setup Dashboard
  if should_process_component "dashboard" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
    if confirm_install "Flask Dashboard"; then
  setup_dashboard
    else
      log_message "Skipping Dashboard installation"
    fi
  fi
  
  # Setup Nginx
  if should_process_component "nginx" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
    if confirm_install "Nginx web server"; then
  setup_nginx
    else
      log_message "Skipping Nginx installation"
    fi
  fi
  
  # Setup WiFi
  if should_process_component "wifi" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
    if [ "$CONFIGURE_NETWORK" = "true" ]; then
      if confirm_install "WiFi in AP+STA mode" "N"; then
        setup_wifi
      else
        log_message "Skipping WiFi setup"
      fi
    else
      log_message "Network configuration disabled in config"
    fi
  fi
  
  log_message "Setup completed successfully!"
  
  # Verify all services are running
  log_message "Verifying services..."
  services_status=""
  
  if systemctl is-active --quiet mosquitto; then
    services_status="${services_status}✓ Mosquitto: RUNNING\n"
  else
    services_status="${services_status}× Mosquitto: NOT RUNNING\n"
  fi
  
  if systemctl is-active --quiet victoriametrics; then
    services_status="${services_status}✓ VictoriaMetrics: RUNNING\n"
  else
    services_status="${services_status}× VictoriaMetrics: NOT RUNNING\n"
  fi
  
  if systemctl is-active --quiet nodered; then
    services_status="${services_status}✓ Node-RED: RUNNING\n"
  else
    services_status="${services_status}× Node-RED: NOT RUNNING\n"
  fi
  
  if systemctl is-active --quiet dashboard; then
    services_status="${services_status}✓ Dashboard: RUNNING\n"
  else
    services_status="${services_status}× Dashboard: NOT RUNNING\n"
  fi
  
  if systemctl is-active --quiet nginx; then
    services_status="${services_status}✓ Nginx: RUNNING\n"
  else
    services_status="${services_status}× Nginx: NOT RUNNING\n"
  fi
  
  log_message "Services status:\n${services_status}"
  
  # Show access information
  echo "===================================================="
  echo "Installation complete! Access your services at:"
  
  if should_process_component "dashboard" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
  echo "Dashboard: http://$HOSTNAME/"
  fi
  
  if should_process_component "nodered" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
    echo "Node-RED: http://$HOSTNAME/node-red/admin"
  fi
  
  if should_process_component "vm" || [ -z "$COMPONENTS_TO_UPDATE" ]; then
    echo "VictoriaMetrics: http://$HOSTNAME:$VM_PORT"
  fi
  
  echo ""
  echo "MQTT Broker: $HOSTNAME:$MQTT_PORT"
  echo "MQTT Username: $MQTT_USERNAME"
  echo "MQTT Password: $MQTT_PASSWORD"
  echo "===================================================="
  
  # Suggest to run the verification scripts if any services failed
  if [[ "$services_status" == *"NOT RUNNING"* ]]; then
    echo ""
    echo "ATTENTION: Some services failed to start. For detailed diagnostics, run:"
    
    if [[ "$services_status" == *"Mosquitto: NOT RUNNING"* ]]; then
      echo "  sudo bash $BASE_DIR/scripts/fix_mosquitto.sh"
    fi
    
    if [[ "$services_status" == *"Node-RED: NOT RUNNING"* ]]; then
      echo "  sudo systemctl status nodered"
      echo "  sudo journalctl -xeu nodered.service"
    fi
    
    if [[ "$services_status" == *"VictoriaMetrics: NOT RUNNING"* ]]; then
      echo "  sudo systemctl status victoriametrics"
      echo "  sudo journalctl -xeu victoriametrics.service"
    fi
    
    echo ""
  fi
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
    if [ "$FACTORY_RESET" = true ]; then
      # Factory reset before setup
      factory_reset
      main
    elif [ "$UNINSTALL" = true ]; then
      # Uninstall specified components
      uninstall_components
    else
      # Normal setup
      main
    fi
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
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo "Use --help to see available options"
    exit 1
    ;;
esac 