#!/bin/bash

# syhub IoT Setup Script - Improved with network resilience
# A shell script equivalent of the Python setup script

# Version
VERSION="1.0.0"

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
        read -p "Install/Update $1? [y/N]: " response
        [ "${response,,}" = "y" ]
        return $?
    fi
    return 0
}

# Install yq for YAML parsing
install_yq() {
    if [ ! -f "/usr/bin/yq" ]; then
        log "Installing yq to parse YAML configuration..."
        wget -q -O /usr/bin/yq https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_arm64
        chmod +x /usr/bin/yq
    fi
}

# Function to load YAML configuration using yq
load_config() {
    if [ ! -f "$CONFIG_PATH" ]; then
        log "Config not found at $CONFIG_PATH"
        exit 1
    fi
    
    install_yq
    
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

# Function to set up WiFi Access Point
setup_wifi_ap() {
    local update_mode=$1
    log "Configuring WiFi AP..."
    
    # Install required packages
    for pkg in hostapd dnsmasq avahi-daemon; do
        if [ "$update_mode" = true ] && ! prompt_overwrite "$pkg" "$(is_package_installed "$pkg")"; then
            log "Skipping $pkg installation/update."
            continue
        fi
        
        if is_package_installed "$pkg"; then
            log "$pkg is installed, skipping."
        else
            apt update && apt install -y "$pkg"
        fi
    done
    
    # Stop services before configuration
    for service in hostapd dnsmasq avahi-daemon; do
        systemctl unmask "$service" 2>/dev/null || true
        systemctl stop "$service" 2>/dev/null || true
    done
    
    # Create backup of network configuration
    log "Creating backup of network configuration..."
    local backup_dir="$HOME_DIR/syhub_backups/network_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    for file in /etc/dhcpcd.conf /etc/hostapd/hostapd.conf /etc/dnsmasq.conf /etc/default/hostapd; do
        if [ -f "$file" ]; then
            cp "$file" "$backup_dir/$(basename "$file")" || true
        fi
    done
    
    # Update configuration files
    configs_changed=false
    for template in dhcpcd.conf.j2 hostapd.conf.j2 dnsmasq.conf.j2; do
        dest_path=""
        case "$template" in
            dhcpcd.conf.j2) dest_path="/etc/dhcpcd.conf" ;;
            hostapd.conf.j2) dest_path="/etc/hostapd/hostapd.conf" ;;
            dnsmasq.conf.j2) dest_path="/etc/dnsmasq.conf" ;;
        esac
        
        if update_file_if_changed "$template" "$dest_path"; then
            configs_changed=true
        fi
    done
    
    # Configure hostapd defaults
    default_hostapd="/etc/default/hostapd"
    if [ "$(file_hash "$default_hostapd")" != "$(echo -n 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | sha256sum | cut -d' ' -f1)" ]; then
        log "Updating /etc/default/hostapd..."
        echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' > "$default_hostapd"
    fi
    
    # Create a script to update hostname at the end, to avoid network interruption
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
    ip_forward=$(sysctl net.ipv4.ip_forward | grep -q "= 1" && echo true || echo false)
    if [ "$ip_forward" != "true" ]; then
        log "Enabling IP forwarding..."
        sysctl -w net.ipv4.ip_forward=1
        echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-syhub.conf
    fi
    
    # Enable services
    for service in hostapd dnsmasq avahi-daemon; do
        if is_service_enabled "$service"; then
            log "$service is enabled, skipping."
        else
            systemctl enable "$service" || true
        fi
    done
    
    # Services will be started at the end of the setup to avoid network interruption
    log "WiFi AP configuration complete, services will be started at the end of setup."
}

# Function to install and configure Mosquitto MQTT broker
install_mosquitto() {
    local update_mode=$1
    log "Installing Mosquitto..."
    
    if [ "$update_mode" = true ] && ! prompt_overwrite "Mosquitto" "$(is_package_installed "mosquitto")"; then
        log "Skipping Mosquitto installation/update."
        return
    fi
    
    if is_package_installed "mosquitto"; then
        log "Mosquitto is installed, skipping."
    else
        apt install -y mosquitto mosquitto-clients
    fi
    
    # Update configuration
    configs_changed=false
    if update_file_if_changed "mosquitto.conf.j2" "/etc/mosquitto/mosquitto.conf"; then
        configs_changed=true
    fi
    
    # Update password file
    passwd_file="/etc/mosquitto/passwd"
    passwd_content="$MQTT_USERNAME:$MQTT_PASSWORD"
    passwd_hash=$(echo -n "$passwd_content" | sha256sum | cut -d' ' -f1)
    
    if [ "$(file_hash "$passwd_file")" != "$passwd_hash" ]; then
        log "Updating Mosquitto password..."
        echo "$passwd_content" > "$passwd_file"
        mosquitto_passwd -U "$passwd_file"
    fi
    
    # Enable and start service
    if is_service_enabled "mosquitto"; then
        log "Mosquitto service is enabled, skipping."
    else
        systemctl enable mosquitto || true
    fi
    
    if [ "$configs_changed" = true ] || ! is_service_running "mosquitto"; then
        log "Starting Mosquitto..."
        systemctl restart mosquitto || true
    else
        log "Mosquitto is running, skipping start."
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
    update_file_if_changed "victoria_metrics.yml.j2" "/etc/victoria-metrics.yml"
    
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
    if is_service_enabled "victoria-metrics"; then
        log "VictoriaMetrics service is enabled, skipping."
    else
        systemctl enable victoria-metrics || true
    fi
    
    if ! is_service_running "victoria-metrics"; then
        log "Starting VictoriaMetrics..."
        systemctl start victoria-metrics || true
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
    
    # Install Node.js if not present
    if [ -z "$node_path" ]; then
        log "Installing Node.js..."
        # Use NodeSource repository for newer Node.js version
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt install -y nodejs
        node_path=$(which node)
        if [ -z "$node_path" ]; then
            log "Failed to install Node.js"
            return 1
        fi
        log "Node.js installed at $node_path"
    fi
    
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
    
    // Function global context
    functionGlobalContext: {
        // Add global context items here
    }
};
EOL
    
    chown "$USER:$USER" "$NODE_RED_DIR/settings.js"
    chmod 644 "$NODE_RED_DIR/settings.js"
    
    # Install node-red-contrib-victoriametrics
    log "Installing node-red-contrib-victoriametrics..."
    if ! su -c "cd $NODE_RED_DIR && npm install node-red-contrib-victoriametrics" - "$USER"; then
        log "Warning: Failed to install node-red-contrib-victoriametrics, but continuing"
    fi
    
    # Configure Node-RED flow for MQTT to VictoriaMetrics
    log "Configuring Node-RED flows..."
    flows_file="$NODE_RED_DIR/flows.json"
    vm_url="http://$VM_HOST:$VM_PORT/api/v1/write"
    
    # Create flows.json with basic MQTT to VictoriaMetrics configuration
    cat > "$flows_file" << EOL
[
    {
        "id": "mqtt-to-vm",
        "type": "tab",
        "label": "MQTT to VictoriaMetrics",
        "disabled": false,
        "info": ""
    },
    {
        "id": "mqtt-in",
        "type": "mqtt in",
        "z": "mqtt-to-vm",
        "name": "MQTT In",
        "topic": "v1/devices/me/telemetry",
        "qos": "2",
        "datatype": "json",
        "broker": "mqtt-broker",
        "nl": false,
        "rap": true,
        "rh": "0",
        "inputs": 0,
        "x": 100,
        "y": 100,
        "wires": [["function-node"]]
    },
    {
        "id": "function-node",
        "type": "function",
        "z": "mqtt-to-vm",
        "name": "Format for VictoriaMetrics",
        "func": "// Format MQTT data into InfluxDB line protocol for VictoriaMetrics\\nvar deviceID = msg.payload.deviceID || 'unknown';\\nvar timestamp = (msg.payload.timestamp || Math.floor(Date.now() / 1000)) * 1000; // Ensure timestamp in milliseconds\\nvar lines = [];\\nvar errors = [];\\n\\n// Define measurements\\nvar measurements = [\\n    { name: 'temperature', value: parseFloat(msg.payload.temperature) },\\n    { name: 'distance', value: parseFloat(msg.payload.distance) },\\n    { name: 'pH', value: parseFloat(msg.payload.pH) },\\n    { name: 'ORP', value: parseFloat(msg.payload.ORP) },\\n    { name: 'TDS', value: parseFloat(msg.payload.TDS) },\\n    { name: 'EC', value: parseFloat(msg.payload.EC) }\\n];\\n\\n// Validate and create a line for each measurement\\nmeasurements.forEach(function(m) {\\n    if (typeof msg.payload[m.name] === 'undefined') {\\n        errors.push('Missing field: ' + m.name);\\n    } else if (isNaN(m.value)) {\\n        errors.push('Invalid value for ' + m.name + ': ' + msg.payload[m.name]);\\n    } else {\\n        var line = `\${m.name},deviceID=\${deviceID} value=\${m.value} \${timestamp}`;\\n        lines.push(line);\\n    }\\n});\\n\\n// Log errors if any\\nif (errors.length > 0) {\\n    node.warn('Errors in MQTT data: ' + errors.join('; '));\\n}\\n\\n// Join lines with newlines\\nmsg.payload = lines.join('\\\\n');\\nmsg.headers = { 'Content-Type': 'text/plain' };\\nreturn msg;",
        "outputs": 1,
        "noerr": 0,
        "initialize": "",
        "finalize": "",
        "libs": [],
        "x": 300,
        "y": 100,
        "wires": [["http-request-node", "debug-node"]]
    },
    {
        "id": "http-request-node",
        "type": "http request",
        "z": "mqtt-to-vm",
        "name": "Send to VictoriaMetrics",
        "method": "POST",
        "ret": "txt",
        "paytoqs": "ignore",
        "url": "${vm_url}",
        "persist": false,
        "authType": "",
        "x": 500,
        "y": 100,
        "wires": [["debug-node"]]
    },
    {
        "id": "debug-node",
        "type": "debug",
        "z": "mqtt-to-vm",
        "name": "Debug Output",
        "active": true,
        "tosidebar": true,
        "console": false,
        "tostatus": false,
        "complete": "true",
        "statusVal": "",
        "statusType": "auto",
        "x": 700,
        "y": 100,
        "wires": []
    },
    {
        "id": "mqtt-broker",
        "type": "mqtt-broker",
        "name": "MQTT Broker",
        "broker": "${MQTT_HOST}",
        "port": "${MQTT_PORT}",
        "clientid": "",
        "autoConnect": true,
        "usetls": false,
        "protocolVersion": "4",
        "keepalive": "60",
        "cleansession": true,
        "birthTopic": "",
        "birthQos": "0",
        "birthPayload": "",
        "closeTopic": "",
        "closeQos": "0",
        "closePayload": "",
        "willTopic": "",
        "willQos": "0",
        "willPayload": "",
        "userProps": "",
        "sessionExpiry": ""
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
    if is_service_enabled "nodered"; then
        log "Node-RED service is already enabled, skipping."
    else
        log "Enabling Node-RED service..."
        systemctl enable nodered || true
    fi
    
    # Start service
    log "Starting Node-RED service..."
    systemctl restart nodered || true
    
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
    
    # Update dashboard files using templates
    if [ -f "$TEMPLATES_DIR/flask_app.py" ]; then
        update_file_if_changed "flask_app.py" "$INSTALL_DIR/flask_app.py"
        chown "$USER:$USER" "$INSTALL_DIR/flask_app.py"
        chmod 644 "$INSTALL_DIR/flask_app.py"
    else
        log "Warning: flask_app.py template not found, skipping."
    fi
    
    # Fix Jinja2 template in index.html if needed
    index_html="$INSTALL_DIR/static/index.html"
    if [ -f "$index_html" ]; then
        if grep -q "tojson(pretty=true)" "$index_html"; then
            log "Fixing Jinja2 template in index.html..."
            sed -i 's/tojson(pretty=true)/tojson | safe/g' "$index_html"
            chown "$USER:$USER" "$index_html"
            chmod 644 "$index_html"
        fi
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
    if is_service_enabled "syhub-dashboard"; then
        log "Dashboard service is enabled, skipping."
    else
        systemctl enable syhub-dashboard || true
    fi
    
    if is_service_running "syhub-dashboard"; then
        log "Dashboard is running, restarting to apply changes..."
        systemctl restart syhub-dashboard || true
    else
        log "Starting Dashboard..."
        systemctl start syhub-dashboard || true
    fi
}

# Function to create a backup
backup() {
    log "Creating backup..."
    backup_dir="$HOME_DIR/backups"
    timestamp=$(date +%Y%m%d_%H%M%S)
    mkdir -p "$backup_dir"
    backup_file="$backup_dir/iot_backup_$timestamp.tar.gz"
    tar -czf "$backup_file" "$INSTALL_DIR"
    log "Backup created at $backup_file"
}

# Function to display service status
status() {
    log "Service status:"
    for service in hostapd dnsmasq avahi-daemon mosquitto victoria-metrics nodered syhub-dashboard; do
        systemctl status "$service" --no-pager || true
    done
}

# Function to purge all components
purge() {
    log "Purging all components..."
    
    # Stop all services
    for service in hostapd dnsmasq avahi-daemon mosquitto victoria-metrics nodered syhub-dashboard; do
        systemctl stop "$service" 2>/dev/null || true
        systemctl disable "$service" 2>/dev/null || true
        rm -f "/etc/systemd/system/$service.service" 2>/dev/null || true
        rm -f "/lib/systemd/system/$service.service" 2>/dev/null || true
    done
    systemctl daemon-reload
    
    # Remove packages
    apt remove -y hostapd dnsmasq avahi-daemon mosquitto mosquitto-clients nodejs npm \
               python3-flask python3-socketio python3-paho-mqtt python3-requests python3-eventlet python3-psutil || true
    apt autoremove -y || true
    
    # Remove VictoriaMetrics
    rm -rf /usr/local/bin/victoria-metrics /var/lib/victoria-metrics /etc/victoria-metrics.yml
    userdel victoria-metrics 2>/dev/null || true
    
    # Remove Node-RED
    rm -rf /usr/bin/node-red* /usr/local/bin/node-red* /root/.node-red "$NODE_RED_DIR"
    
    # Back up configuration files
    for file in /etc/dhcpcd.conf /etc/hostapd/hostapd.conf /etc/dnsmasq.conf /etc/default/hostapd \
                /etc/mosquitto/mosquitto.conf /etc/mosquitto/passwd; do
        if [ -f "$file" ]; then
            mv "$file" "$file.bak" || true
        fi
    done
    
    # Reset IP forwarding
    sysctl -w net.ipv4.ip_forward=0 || true
    
    # Remove project directory
    rm -rf "$INSTALL_DIR"
    
    # Clean up
    apt autoremove -y && apt autoclean
    
    log "Purge complete. System is in a near-fresh state. Rebooting..."
    reboot
}

# Function to perform a full setup
setup() {
    log "Setting up a fresh Raspberry Pi OS installation..."
    
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
    prompt_overwrite "System packages" true
    if [ $? -eq 0 ]; then
        log "Updating system packages..."
        apt update && apt upgrade -y
    fi
    
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

# Function to update components
update() {
    log "Updating components..."
    
    # Load configuration
    load_config
    
    # Update system packages if requested
    prompt_overwrite "System packages" true
    if [ $? -eq 0 ]; then
        log "Updating system packages..."
        apt update && apt upgrade -y
    fi
    
    # Update components in a specific order to minimize disruption
    install_mosquitto true      # MQTT first (least disruptive)
    install_victoria_metrics true   # Then time series DB
    install_node_red true          # Then Node-RED
    install_dashboard true         # Then web dashboard
    setup_wifi_ap true             # WiFi AP configuration last (can interrupt network)
    
    # Run hostname update if needed
    if [ -f "/tmp/update_hostname.sh" ]; then
        log "Updating hostname..."
        bash /tmp/update_hostname.sh
    fi
    
    log "Update complete. All services have been updated."
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