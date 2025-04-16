#!/bin/bash

# syhub IoT Setup Script - Complete installation for Raspberry Pi OS 64 lite
# Version
VERSION="1.1.0"

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run with sudo"
    exit 1
fi

# Determine the user who invoked sudo
if [ -n "$SUDO_USER" ]; then
    USER=$SUDO_USER
else
    USER=$(whoami)
fi

# Set up paths
HOME_DIR=$(eval echo ~$USER)
INSTALL_DIR="$HOME_DIR/syhub"
CONFIG_PATH="$INSTALL_DIR/config/config.yml"
TEMPLATES_DIR="$INSTALL_DIR/templates"
NODE_RED_DIR="$HOME_DIR/.node-red"
SCRIPT_LOG="/var/log/syhub_setup.log"
MAX_BACKUPS=3

# Logging function with timestamp that writes to both console and log file
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1"
    echo "[$timestamp] $1" >> "$SCRIPT_LOG"
}

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$SCRIPT_LOG")"
touch "$SCRIPT_LOG"
chmod 644 "$SCRIPT_LOG"

log "Starting syhub_setup.sh version $VERSION"
log "User: $USER, Home: $HOME_DIR, Install dir: $INSTALL_DIR"

# Function to check if a package is installed
is_package_installed() {
    dpkg -l | grep -q "$1"
    return $?
}

# Function to check if a service is enabled
is_service_enabled() {
    local result
    result=$(systemctl is-enabled "$1" 2>/dev/null || echo "disabled")
    [ "$result" = "enabled" ]
    return $?
}

# Function to check if a service is running
is_service_running() {
    local result
    result=$(systemctl is-active "$1" 2>/dev/null || echo "inactive")
    [ "$result" = "active" ]
    return $?
}

# Function to calculate a file's SHA-256 hash
file_hash() {
    if [ -f "$1" ]; then
        sha256sum "$1" | cut -d' ' -f1
    else
        echo ""
    fi
}

# Function to prompt user for overwriting components
prompt_overwrite() {
    if [ "$2" = true ]; then
        log "$1 detected or update available."
        read -p "Install/Update $1? This will replace existing components and configs. [y/N]: " response
        [ "${response,,}" = "y" ]
        return $?
    fi
    return 0
}

# Function to check config file exists or create default
check_config() {
    if [ ! -f "$CONFIG_PATH" ]; then
        log "Config file not found at $CONFIG_PATH. Creating default config..."
        mkdir -p "$INSTALL_DIR/config"
        cat > "$CONFIG_PATH" << EOL
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
        chown -R "$USER:$USER" "$INSTALL_DIR/config"
        log "Default config created at $CONFIG_PATH"
    else
        log "Config file found at $CONFIG_PATH"
    fi
}

# Install yq for YAML parsing
install_yq() {
    if ! is_package_installed "yq"; then
        log "Installing yq package to parse YAML configuration..."
        apt update
        apt install -y yq
    fi
}

# Function to load YAML configuration using yq
load_config() {
    check_config
    
    install_yq
    
    log "Loading configuration from $CONFIG_PATH..."
    
    # Extract configuration values
    HOSTNAME=$(yq '.project.hostname' "$CONFIG_PATH")
    
    # Extract MQTT settings
    MQTT_HOST=$(yq '.project.mqtt.host' "$CONFIG_PATH")
    MQTT_PORT=$(yq '.project.mqtt.port' "$CONFIG_PATH")
    MQTT_USERNAME=$(yq '.project.mqtt.username' "$CONFIG_PATH")
    MQTT_PASSWORD=$(yq '.project.mqtt.password' "$CONFIG_PATH")
    
    # Extract VictoriaMetrics settings
    VM_HOST=$(yq '.project.victoria_metrics.host' "$CONFIG_PATH")
    VM_PORT=$(yq '.project.victoria_metrics.port' "$CONFIG_PATH")
    
    log "Configuration loaded successfully."
}

# Function to update system packages
update_system_packages() {
    log "Updating system packages..."
    apt update
    apt upgrade -y
    # Install common essential packages
    apt install -y git curl wget vim htop raspi-config
}

# Function to render templates from the templates directory
render_template() {
    local template_path="$TEMPLATES_DIR/$1"
    local dest_path="$2"
    local temp_file="/tmp/$(basename "$dest_path")"
    
    if [ ! -f "$template_path" ]; then
        log "Template $template_path not found."
        return 1
    fi
    
    # Copy template to temp file
    cp "$template_path" "$temp_file"
    
    # Replace placeholders with values
    sed -i "s/{{hostname}}/$HOSTNAME/g" "$temp_file"
    sed -i "s/{{mqtt_host}}/$MQTT_HOST/g" "$temp_file"
    sed -i "s/{{mqtt_port}}/$MQTT_PORT/g" "$temp_file"
    sed -i "s/{{mqtt_username}}/$MQTT_USERNAME/g" "$temp_file"
    sed -i "s/{{mqtt_password}}/$MQTT_PASSWORD/g" "$temp_file"
    sed -i "s/{{vm_host}}/$VM_HOST/g" "$temp_file"
    sed -i "s/{{vm_port}}/$VM_PORT/g" "$temp_file"
    
    echo "$temp_file"
}

# Function to update a file if it has changed
update_file_if_changed() {
    local template_name="$1"
    local dest_path="$2"
    
    local temp_file=$(render_template "$template_name" "$dest_path")
    if [ -z "$temp_file" ]; then
        return 1
    fi
    
    local temp_hash=$(file_hash "$temp_file")
    local dest_hash=$(file_hash "$dest_path")
    
    if [ "$temp_hash" != "$dest_hash" ]; then
        log "Updating $dest_path..."
        mv "$temp_file" "$dest_path"
        chown root:root "$dest_path"
        chmod 644 "$dest_path"
        return 0
    else
        log "$dest_path is up-to-date, skipping."
        rm -f "$temp_file"
        return 1
    fi
}

# Simplified function to set up WiFi Access Point
setup_wifi_ap() {
    local update_mode=$1
    log "Configuring WiFi AP..."
    
    # Install required packages
    local ap_packages="hostapd dnsmasq avahi-daemon"
    if [ "$update_mode" = true ] && ! prompt_overwrite "WiFi Access Point packages" "$(is_package_installed "hostapd")"; then
        log "Skipping WiFi AP package installation/update."
    else
        for pkg in $ap_packages; do
            if is_package_installed "$pkg"; then
                log "$pkg is installed, skipping."
            else
                apt install -y "$pkg"
            fi
        done
    fi
    
    # Stop services before configuration
    for service in hostapd dnsmasq avahi-daemon; do
        systemctl unmask "$service" 2>/dev/null || true
        systemctl stop "$service" 2>/dev/null || true
    done
    
    # Update config files
    configs_changed=false
    
    # Configure dhcpcd.conf if template exists
    if [ -f "$TEMPLATES_DIR/dhcpcd.conf.j2" ]; then
        if update_file_if_changed "dhcpcd.conf.j2" "/etc/dhcpcd.conf"; then
            configs_changed=true
        fi
    fi
    
    # Configure hostapd.conf if template exists
    if [ -f "$TEMPLATES_DIR/hostapd.conf.j2" ]; then
        if update_file_if_changed "hostapd.conf.j2" "/etc/hostapd/hostapd.conf"; then
            configs_changed=true
        fi
    fi
    
    # Configure dnsmasq.conf if template exists
    if [ -f "$TEMPLATES_DIR/dnsmasq.conf.j2" ]; then
        if update_file_if_changed "dnsmasq.conf.j2" "/etc/dnsmasq.conf"; then
            configs_changed=true
        fi
    fi
    
    # Enable hostapd daemon
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' > /etc/default/hostapd
    
    # Configure hostname at the end
    if [ -n "$HOSTNAME" ]; then
        local current_hostname=$(cat /etc/hostname 2>/dev/null || echo "")
        if [ "$current_hostname" != "$HOSTNAME" ]; then
            log "Will update hostname to $HOSTNAME at the end of setup..."
            echo "#!/bin/bash" > /tmp/update_hostname.sh
            echo "echo \"$HOSTNAME\" > /etc/hostname" >> /tmp/update_hostname.sh
            echo "sed -i \"s/127.0.0.1.*/127.0.1.1 $HOSTNAME/\" /etc/hosts" >> /tmp/update_hostname.sh
            chmod +x /tmp/update_hostname.sh
        fi
    fi
    
    # Enable IP forwarding
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-syhub.conf
    sysctl -w net.ipv4.ip_forward=1
    
    # Enable services
    for service in hostapd dnsmasq avahi-daemon; do
        systemctl enable "$service" || true
    done
    
    log "WiFi AP configuration complete, services will be started at the end of setup."
}

# Function to install and configure Mosquitto MQTT broker
install_mosquitto() {
    local update_mode=$1
    log "Installing Mosquitto..."
    
    if [ "$update_mode" = true ] && ! prompt_overwrite "Mosquitto MQTT broker" "$(is_package_installed "mosquitto")"; then
        log "Skipping Mosquitto installation/update."
        return
    fi
    
    if is_package_installed "mosquitto"; then
        log "Mosquitto is installed, skipping package installation."
    else
        apt install -y mosquitto mosquitto-clients
    fi
    
    # Update configuration
    configs_changed=false
    if [ -f "$TEMPLATES_DIR/mosquitto.conf.j2" ]; then
        if update_file_if_changed "mosquitto.conf.j2" "/etc/mosquitto/mosquitto.conf"; then
            configs_changed=true
        fi
    else
        # Create a basic config if template doesn't exist
        log "Creating basic Mosquitto configuration..."
        cat > "/etc/mosquitto/mosquitto.conf" << EOF
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

# Include other config files
include_dir /etc/mosquitto/conf.d
EOF
        configs_changed=true
    fi
    
    # Update password file
    passwd_file="/etc/mosquitto/passwd"
    log "Setting up Mosquitto password..."
    touch "$passwd_file"
    mosquitto_passwd -b "$passwd_file" "$MQTT_USERNAME" "$MQTT_PASSWORD"
    chown mosquitto:mosquitto "$passwd_file"
    chmod 600 "$passwd_file"
    
    # Enable and start service
    systemctl enable mosquitto
    
    if [ "$configs_changed" = true ] || ! is_service_running "mosquitto"; then
        log "Starting Mosquitto..."
        systemctl restart mosquitto
    else
        log "Mosquitto is running, skipping restart."
    fi
}

# Function to install and configure VictoriaMetrics
install_victoria_metrics() {
    local update_mode=$1
    log "Installing VictoriaMetrics..."
    
    vm_binary="/usr/local/bin/victoria-metrics"
    
    if [ "$update_mode" = true ] && ! prompt_overwrite "VictoriaMetrics" "$([ -f "$vm_binary" ] && echo true || echo false)"; then
        log "Skipping VictoriaMetrics installation/update."
        return
    fi
    
    if [ -f "$vm_binary" ] && [ -x "$vm_binary" ]; then
        log "VictoriaMetrics binary exists, skipping download."
    else
        rm -f "$vm_binary" "/usr/local/bin/victoria-metrics-prod" || true
        mkdir -p /usr/local/bin
        chmod 755 /usr/local/bin
        
        vm_url="https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v1.115.0/victoria-metrics-linux-arm64-v1.115.0.tar.gz"
        vm_tar="/tmp/vm.tar.gz"
        
        log "Downloading VictoriaMetrics from $vm_url..."
        wget "$vm_url" -O "$vm_tar"
        
        if [ ! -f "$vm_tar" ]; then
            log "Failed to download VictoriaMetrics."
            return 1
        fi
        
        log "Extracting VictoriaMetrics binary..."
        tar -xzf "$vm_tar" -C /usr/local/bin
        
        prod_binary="/usr/local/bin/victoria-metrics-prod"
        if [ -f "$prod_binary" ] && [ ! -f "$vm_binary" ]; then
            log "Renaming $prod_binary to $vm_binary..."
            mv "$prod_binary" "$vm_binary"
        fi
        
        if [ ! -f "$vm_binary" ]; then
            log "Failed to extract VictoriaMetrics to $vm_binary."
            return 1
        fi
        
        chmod +x "$vm_binary"
        rm -f "$vm_tar"
    fi
    
    # Update VM configuration
    if [ -f "$TEMPLATES_DIR/victoria_metrics.yml.j2" ]; then
        update_file_if_changed "victoria_metrics.yml.j2" "/etc/victoria-metrics.yml"
    fi
    
    # Create victoria-metrics user if it doesn't exist
    if ! id victoria-metrics &>/dev/null; then
        log "Creating victoria-metrics user..."
        useradd -r victoria-metrics || true
    else
        log "victoria-metrics user exists, skipping."
    fi
    
    # Set permissions
    chown victoria-metrics:victoria-metrics "$vm_binary"
    mkdir -p /var/lib/victoria-metrics
    chown victoria-metrics:victoria-metrics /var/lib/victoria-metrics
    
    # Create service file
    vm_service="/etc/systemd/system/victoria-metrics.service"
    service_content="[Unit]
Description=VictoriaMetrics
After=network.target

[Service]
User=victoria-metrics
Group=victoria-metrics
ExecStart=$vm_binary --storageDataPath=/var/lib/victoria-metrics --httpListenAddr=:$VM_PORT
Restart=always

[Install]
WantedBy=multi-user.target
"
    
    service_hash=$(echo -n "$service_content" | sha256sum | cut -d' ' -f1)
    if [ "$(file_hash "$vm_service")" != "$service_hash" ]; then
        log "Updating VictoriaMetrics service..."
        echo "$service_content" > "$vm_service"
        systemctl daemon-reload
    fi
    
    # Enable and start service
    systemctl enable victoria-metrics
    
    if ! is_service_running "victoria-metrics"; then
        log "Starting VictoriaMetrics..."
        systemctl start victoria-metrics
    else
        log "VictoriaMetrics is running, skipping start."
    fi
}

# Function to install and configure Node-RED with proper error handling
install_node_red() {
    local update_mode=$1
    log "Installing Node-RED..."
    
    # Check if Node-RED is installed
    node_red_installed=false
    node_path=""
    node_red_path=""
    
    # Check for node executable
    node_path=$(which node 2>/dev/null)
    if [ -z "$node_path" ]; then
        log "Node.js is not installed or not in PATH"
    else
        log "Found Node.js at $node_path"
    fi
    
    # Check for node-red executable as the user
    node_red_path=$(sudo -u "$USER" bash -c 'which node-red 2>/dev/null || echo ""')
    if [ -n "$node_red_path" ]; then
        node_red_installed=true
        log "Found Node-RED at $node_red_path"
    else
        log "Node-RED is not installed or not in PATH"
    fi
    
    if [ "$update_mode" = true ] && ! prompt_overwrite "Node-RED" "$node_red_installed"; then
        log "Skipping Node-RED installation/update."
        return
    fi
    
    # If updating or reinstalling, clean up first
    if [ "$node_red_installed" = true ]; then
        log "Stopping and disabling existing Node-RED service..."
        systemctl stop nodered 2>/dev/null || true
        systemctl disable nodered 2>/dev/null || true
        rm -f /lib/systemd/system/nodered.service 2>/dev/null || true
        rm -f /etc/systemd/system/nodered.service 2>/dev/null || true
        systemctl daemon-reload
    fi
    
    # Keep Node.js 20.x if already installed, otherwise install it
    if [ -z "$node_path" ]; then
        log "Installing Node.js 20.x..."
        # Use NodeSource repository for Node.js 20.x
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt install -y nodejs
        node_path=$(which node)
        if [ -z "$node_path" ]; then
            log "Failed to install Node.js"
            return 1
        fi
        log "Node.js installed at $node_path"
    fi
    
    # Check Node.js version
    node_version=$(node -v)
    log "Using Node.js version $node_version"
    
    # Install Node-RED globally
    log "Installing Node-RED globally..."
    npm install -g --unsafe-perm node-red
    node_red_path=$(which node-red)
    if [ -z "$node_red_path" ]; then
        log "Failed to install Node-RED"
        return 1
    fi
    log "Node-RED installed at $node_red_path"
    
    # Ensure Node-RED directory exists with correct permissions
    mkdir -p "$NODE_RED_DIR"
    chown "$USER:$USER" "$NODE_RED_DIR"
    chmod -R u+rw "$NODE_RED_DIR"
    
    # Install required Node-RED modules for MQTT and HTTP
    log "Installing required Node-RED modules..."
    su -c "cd $NODE_RED_DIR && npm install node-red-contrib-influxdb node-red-node-mysql node-red-contrib-mqtt-broker" - "$USER" || true
    
    # Create optimized Node-RED settings file
    log "Creating optimized Node-RED settings..."
    cat > "$NODE_RED_DIR/settings.js" << 'EOL'
// Node-RED Settings file - optimized for resource-constrained devices
module.exports = {
    // Flowfile location
    flowFile: 'flows.json',
    
    // Limit memory usage
    nodeMaxMessageBufferLength: 50,
    
    // Configure user directory
    userDir: process.env.NODE_RED_HOME,
    
    // Logging settings
    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: false
        }
    },
    
    // Disable unused nodes to save memory
    nodesExcludes: [
        'node-red-node-email',
        'node-red-node-twitter',
        'node-red-node-rbe'
    ],
    
    // Reduce websocket ping interval to save resources
    webSocketKeepAliveTime: 60000,
    
    // Reduce context store memory usage
    contextStorage: {
        default: { module: 'memory', config: { flushInterval: 30 } },
    },
    
    // Limit concurrent HTTP requests
    httpRequestTimeout: 60000,
    httpNodeMaxConcurrentRequests: 10,
    
    // Editor settings
    editorTheme: {
        projects: {
            enabled: false
        },
        palette: {
            catalogues: [
                'https://catalogue.nodered.org/catalogue.json'
            ]
        },
        page: {
            title: "syhub Node-RED",
            favicon: "/usr/lib/node_modules/node-red/public/favicon.ico"
        }
    },
    
    // Function global context
    functionGlobalContext: {
        // Add global context items here
    }
};
EOL
    
    chown "$USER:$USER" "$NODE_RED_DIR/settings.js"
    chmod 644 "$NODE_RED_DIR/settings.js"
    
    # Configure Node-RED flow for MQTT to VictoriaMetrics using InfluxDB line protocol
    log "Configuring Node-RED flows for MQTT to VictoriaMetrics..."
    flows_file="$NODE_RED_DIR/flows.json"
    vm_url="http://$VM_HOST:$VM_PORT/api/v1/write"
    
    # Create flows.json with a simpler MQTT to VictoriaMetrics flow
    cat > "$flows_file" << EOL
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
        "url": "${vm_url}",
        "x": 500,
        "y": 120,
        "wires": [[]]
    },
    {
        "id": "mqtt-broker",
        "type": "mqtt-broker",
        "name": "MQTT Broker",
        "broker": "${MQTT_HOST}",
        "port": "${MQTT_PORT}",
        "clientid": "node-red-${HOSTNAME}",
        "autoConnect": true,
        "usetls": false,
        "protocolVersion": "4",
        "keepalive": "60",
        "cleansession": true
    }
]
EOL
    
    chown "$USER:$USER" "$flows_file"
    chmod 644 "$flows_file"
    
    # Create credentials file for MQTT
    credentials_file="$NODE_RED_DIR/flows_cred.json"
    cat > "$credentials_file" << EOL
{
    "mqtt-broker": {
        "user": "${MQTT_USERNAME}",
        "password": "${MQTT_PASSWORD}"
    }
}
EOL
    
    chown "$USER:$USER" "$credentials_file"
    chmod 600 "$credentials_file"
    
    # Create service file
    log "Creating Node-RED service..."
    nodered_service="/lib/systemd/system/nodered.service"
    service_content="[Unit]
Description=Node-RED graphical event wiring tool
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$NODE_RED_DIR
Environment=\"NODE_RED_HOME=$NODE_RED_DIR\"
Environment=\"NODE_OPTIONS=--max_old_space_size=512\"
ExecStart=$node_path $node_red_path --userDir $NODE_RED_DIR --max-old-space-size=512
Restart=on-failure
KillSignal=SIGINT
SyslogIdentifier=Node-RED

[Install]
WantedBy=multi-user.target
"
    
    service_hash=$(echo -n "$service_content" | sha256sum | cut -d' ' -f1)
    if [ "$(file_hash "$nodered_service")" != "$service_hash" ]; then
        log "Updating Node-RED service file..."
        echo "$service_content" > "$nodered_service"
        systemctl daemon-reload
    fi
    
    # Enable service
    systemctl enable nodered
    
    # Start service
    log "Starting Node-RED service..."
    systemctl restart nodered
    
    # Verify service is running
    sleep 5
    if is_service_running "nodered"; then
        log "Node-RED is running successfully."
    else
        log "Warning: Node-RED service failed to start. Check with: journalctl -u nodered -n 50"
        journalctl -u nodered -n 50 >> "$SCRIPT_LOG"
    fi
}

# Function to install and configure the Dashboard
install_dashboard() {
    local update_mode=$1
    log "Installing Dashboard..."
    
    flask_installed=$(is_package_installed "python3-flask")
    if [ "$update_mode" = true ] && ! prompt_overwrite "Dashboard dependencies" "$flask_installed"; then
        log "Skipping dashboard dependencies installation/update."
        return
    fi
    
    apt update && apt install -y python3-flask python3-socketio python3-paho-mqtt python3-requests python3-eventlet python3-psutil python3-gunicorn
    
    # Create static directory if it doesn't exist
    mkdir -p "$INSTALL_DIR/static"
    chown -R "$USER:$USER" "$INSTALL_DIR"
    
    # Update dashboard files using templates
    if [ -f "$TEMPLATES_DIR/flask_app.py" ]; then
        update_file_if_changed "flask_app.py" "$INSTALL_DIR/flask_app.py"
        chown "$USER:$USER" "$INSTALL_DIR/flask_app.py"
        chmod 644 "$INSTALL_DIR/flask_app.py"
    else
        log "Warning: flask_app.py template not found, creating a simple one..."
        cat > "$INSTALL_DIR/flask_app.py" << 'EOL'
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
        chown "$USER:$USER" "$INSTALL_DIR/flask_app.py"
        chmod 644 "$INSTALL_DIR/flask_app.py"
    fi
    
    # Create dashboard service
    dashboard_service="/etc/systemd/system/syhub-dashboard.service"
    service_content="[Unit]
Description=syhub Dashboard
After=network.target

[Service]
User=$USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/gunicorn --workers 4 --worker-class eventlet --bind 0.0.0.0:5000 flask_app:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
"
    
    service_hash=$(echo -n "$service_content" | sha256sum | cut -d' ' -f1)
    if [ "$(file_hash "$dashboard_service")" != "$service_hash" ]; then
        log "Updating Dashboard service..."
        echo "$service_content" > "$dashboard_service"
        systemctl daemon-reload
    fi
    
    # Enable and start service
    systemctl enable syhub-dashboard
    
    if is_service_running "syhub-dashboard"; then
        log "Dashboard is running, restarting to apply changes..."
        systemctl restart syhub-dashboard
    else
        log "Starting Dashboard..."
        systemctl start syhub-dashboard
    fi
}

# Function to create a backup with compression, limiting to 3 backups
backup() {
    log "Creating backup..."
    backup_dir="$HOME_DIR/backups"
    timestamp=$(date +%Y%m%d_%H%M%S)
    mkdir -p "$backup_dir"
    backup_file="$backup_dir/syhub_backup_$timestamp.tar.gz"
    
    # Create a list of important files to back up
    cat > /tmp/backup_list.txt << EOL
$INSTALL_DIR
$NODE_RED_DIR
/etc/mosquitto
/etc/victoria-metrics.yml
/var/lib/victoria-metrics
/etc/systemd/system/victoria-metrics.service
/etc/systemd/system/syhub-dashboard.service
/lib/systemd/system/nodered.service
/etc/hostapd
/etc/dnsmasq.conf
/etc/dhcpcd.conf
EOL
    
    # Create a compressed backup with maximum compression
    log "Creating compressed backup (this may take a while)..."
    tar -czf "$backup_file" --exclude="node_modules" -T /tmp/backup_list.txt 2>/dev/null || true
    rm /tmp/backup_list.txt
    
    # Limit number of backups to MAX_BACKUPS
    log "Cleaning up old backups, keeping maximum $MAX_BACKUPS backups..."
    backup_count=$(ls -1 "$backup_dir"/syhub_backup_*.tar.gz 2>/dev/null | wc -l)
    if [ "$backup_count" -gt "$MAX_BACKUPS" ]; then
        ls -1t "$backup_dir"/syhub_backup_*.tar.gz | tail -n +$(($MAX_BACKUPS + 1)) | xargs rm -f
    fi
    
    log "Backup created at $backup_file"
    log "Total backups: $(ls -1 "$backup_dir"/syhub_backup_*.tar.gz 2>/dev/null | wc -l)/$MAX_BACKUPS"
}

# Function to display service status
status() {
    log "Service status:"
    for service in hostapd dnsmasq avahi-daemon mosquitto victoria-metrics nodered syhub-dashboard; do
        log "Status for $service:"
        systemctl status "$service" --no-pager || true
        echo ""
    done
    
    # Display network information
    log "Network information:"
    ip addr show
    
    # Display Node-RED information
    log "Node-RED information:"
    if [ -d "$NODE_RED_DIR" ]; then
        ls -la "$NODE_RED_DIR"
    else
        log "Node-RED directory not found."
    fi
    
    # Display VictoriaMetrics information
    log "VictoriaMetrics information:"
    curl -s "http://$VM_HOST:$VM_PORT/metrics" | grep -E "vm_app_version|vm_http_requests_total" || true
}

# Function to purge all components with proper cleanup
purge() {
    log "Purging all syhub components..."
    
    # Create a backup before purging
    if prompt_overwrite "Create backup before purging" true; then
        backup
    fi
    
    # Stop all services
    log "Stopping all services..."
    for service in hostapd dnsmasq avahi-daemon mosquitto victoria-metrics nodered syhub-dashboard; do
        systemctl stop "$service" 2>/dev/null || true
        systemctl disable "$service" 2>/dev/null || true
        log "Stopped and disabled $service"
    done
    
    # Remove service files
    log "Removing service files..."
    rm -f /etc/systemd/system/victoria-metrics.service 2>/dev/null || true
    rm -f /etc/systemd/system/syhub-dashboard.service 2>/dev/null || true
    rm -f /lib/systemd/system/nodered.service 2>/dev/null || true
    systemctl daemon-reload
    
    # Remove packages if requested
    if prompt_overwrite "Remove installed packages (hostapd, dnsmasq, mosquitto, etc.)" true; then
        log "Removing packages..."
        apt remove -y mosquitto mosquitto-clients python3-flask python3-socketio python3-paho-mqtt python3-requests python3-eventlet python3-psutil python3-gunicorn || true
        
        if prompt_overwrite "Remove network packages (hostapd, dnsmasq, avahi-daemon)" false; then
            apt remove -y hostapd dnsmasq avahi-daemon || true
        fi
        
        apt autoremove -y || true
    fi
    
    # Remove VictoriaMetrics
    log "Removing VictoriaMetrics..."
    rm -rf /usr/local/bin/victoria-metrics /var/lib/victoria-metrics /etc/victoria-metrics.yml
    userdel victoria-metrics 2>/dev/null || true
    
    # Remove Node-RED
    log "Removing Node-RED data..."
    rm -rf "$NODE_RED_DIR"
    
    # Node.js removal is optional
    if prompt_overwrite "Remove Node.js" false; then
        log "Removing Node.js..."
        apt remove -y nodejs npm || true
    fi
    
    # Back up configuration files
    log "Backing up configuration files..."
    for file in /etc/dhcpcd.conf /etc/hostapd/hostapd.conf /etc/dnsmasq.conf /etc/default/hostapd /etc/mosquitto/mosquitto.conf /etc/mosquitto/passwd; do
        if [ -f "$file" ]; then
            mv "$file" "$file.bak" || true
            log "Backed up $file to $file.bak"
        fi
    done
    
    # Reset IP forwarding
    log "Resetting IP forwarding..."
    sysctl -w net.ipv4.ip_forward=0 || true
    rm -f /etc/sysctl.d/99-syhub.conf
    
    # Remove project directory
    log "Removing syhub installation directory..."
    rm -rf "$INSTALL_DIR"
    
    # Clean up
    apt autoremove -y && apt autoclean
    
    log "Purge complete. System is in a near-fresh state."
    
    if prompt_overwrite "Reboot system now" true; then
        log "Rebooting system..."
        reboot
    else
        log "Skipping reboot. Please reboot manually when convenient."
    fi
}

# Function to perform a full setup
setup() {
    log "Setting up a fresh syhub installation on Raspberry Pi OS..."
    
    # Check if config exists, create if needed
    check_config
    
    # Set permissions for syhub script itself if it exists
    syhub_script="$INSTALL_DIR/scripts/syhub_setup.sh"
    if [ -f "$syhub_script" ]; then
        log "Setting permissions for $syhub_script..."
        chown "$USER:$USER" "$syhub_script"
        chmod 755 "$syhub_script"
    fi
    
    # Load configuration
    load_config
    
    # Update system packages
    if prompt_overwrite "System packages" true; then
        update_system_packages
    fi
    
    # Create required directories
    mkdir -p "$INSTALL_DIR"
    chown -R "$USER:$USER" "$INSTALL_DIR"
    
    # Run setup components (order matters)
    install_mosquitto false         # Start with MQTT broker
    install_victoria_metrics false  # Then time series DB
    install_node_red false          # Then Node-RED
    install_dashboard false         # Then web dashboard
    setup_wifi_ap false             # WiFi AP configuration last (can interrupt network)
    
    # Start network services that might have been deferred
    log "Starting network services..."
    for service in hostapd dnsmasq avahi-daemon; do
        systemctl start "$service" || true
    done
    
    # Run hostname update if needed
    if [ -f "/tmp/update_hostname.sh" ]; then
        log "Updating hostname..."
        bash /tmp/update_hostname.sh
    fi
    
    log "Setup complete. Reboot recommended."
    read -p "Reboot now? [Y/n]: " reboot_response
    if [ -z "$reboot_response" ] || [ "${reboot_response,,}" = "y" ]; then
        log "Rebooting system..."
        sleep 2
        reboot
    else
        log "Skipping reboot. Please reboot manually when convenient."
    fi
}

# Function to update components with checks
update() {
    log "Updating syhub components..."
    
    # Check if config exists, create if needed
    check_config
    
    # Load configuration
    load_config
    
    # Check if any services are already running before update
    services_running=false
    for service in mosquitto victoria-metrics nodered syhub-dashboard; do
        if is_service_running "$service"; then
            services_running=true
            break
        fi
    done
    
    if [ "$services_running" = true ] && ! prompt_overwrite "Services are already running. Continue with update" true; then
        log "Update cancelled by user."
        return
    fi
    
    # Update system packages if requested
    if prompt_overwrite "System packages" true; then
        update_system_packages
    fi
    
    # Update components in a specific order to minimize disruption
    install_mosquitto true          # MQTT first (least disruptive)
    install_victoria_metrics true   # Then time series DB
    install_node_red true           # Then Node-RED
    install_dashboard true          # Then web dashboard
    setup_wifi_ap true              # WiFi AP configuration last (can interrupt network)
    
    # Run hostname update if needed
    if [ -f "/tmp/update_hostname.sh" ]; then
        log "Updating hostname..."
        bash /tmp/update_hostname.sh
    fi
    
    log "Update complete. All services have been updated."
    
    if prompt_overwrite "Reboot system to complete update" false; then
        log "Rebooting system..."
        reboot
    else
        log "Skipping reboot. Please reboot manually if needed."
    fi
}

# Function to handle installation of Node-RED only
fix_node_red() {
    log "Fixing Node-RED installation..."
    
    # Load configuration
    load_config
    
    # Stop the service
    systemctl stop nodered 2>/dev/null || true
    
    # Fix installation
    install_node_red false
    
    log "Node-RED fix complete."
}

# Main script execution
main() {
    # Check command
    if [ $# -eq 0 ]; then
        echo "Usage: $0 [setup|update|purge|backup|status|fix-nodered]"
        exit 1
    fi
    
    command="$1"
    
    case "$command" in
        setup)
            setup
            ;;
        update)
            update
            ;;
        purge)
            purge
            ;;
        backup)
            backup
            ;;
        status)
            status
            ;;
        fix-nodered)
            fix_node_red
            ;;
        *)
            echo "Unknown command: $command"
            echo "Usage: $0 [setup|update|purge|backup|status|fix-nodered]"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"