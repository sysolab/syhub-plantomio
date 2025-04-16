#!/bin/bash

# Exit on any error
set -e

# Determine the invoking user (since this script runs with sudo)
USER=${SUDO_USER:-$(whoami)}
HOME_DIR=$(eval echo ~$USER)
INSTALL_DIR="$HOME_DIR/syhub"
CONFIG_PATH="$INSTALL_DIR/config/config.yml"
NODE_RED_DIR="$HOME_DIR/.node-red"
TEMPLATES_DIR="$INSTALL_DIR/templates"

# Logging function with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run with sudo"
        exit 1
    fi
}

# Function to check if a package is installed
is_package_installed() {
    dpkg -l | grep -q "$1"
    return $?
}

# Function to check if a service is enabled
is_service_enabled() {
    systemctl is-enabled "$1" 2>/dev/null | grep -q "enabled"
    return $?
}

# Function to check if a service is running
is_service_running() {
    systemctl is-active "$1" 2>/dev/null | grep -q "active"
    return $?
}

# Function to compute file hash
file_hash() {
    if [ -f "$1" ]; then
        sha256sum "$1" | cut -d ' ' -f 1
    else
        echo ""
    fi
}

# Function to render templates (simplified for shell, assuming templates are pre-rendered or static)
render_template() {
    local template_name=$1
    local dest=$2
    local temp_dir=$3
    local temp_file="$temp_dir/$(basename "$dest")"
    cp "$TEMPLATES_DIR/$template_name" "$temp_file"
    echo "$temp_file"
}

# Function to update file if changed
update_file_if_changed() {
    local template_name=$1
    local dest=$2
    local temp_dir=$3
    local temp_file
    temp_file=$(render_template "$template_name" "$dest" "$temp_dir")
    local temp_hash
    local dest_hash
    temp_hash=$(file_hash "$temp_file")
    dest_hash=$(file_hash "$dest")
    if [ "$temp_hash" != "$dest_hash" ]; then
        log "Updating $dest..."
        mv "$temp_file" "$dest"
        chown root:root "$dest"
        chmod 644 "$dest"
        return 0
    else
        log "$dest is up-to-date, skipping."
        return 1
    fi
}

setup_wifi_ap() {
    local temp_dir=$1
    log "Configuring WiFi AP..."
    # Install required packages
    for pkg in hostapd dnsmasq avahi-daemon; do
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

    # Update configuration files
    configs_changed=0
    update_file_if_changed "dhcpcd.conf.j2" "/etc/dhcpcd.conf" "$temp_dir" && configs_changed=1
    update_file_if_changed "hostapd.conf.j2" "/etc/hostapd/hostapd.conf" "$temp_dir" && configs_changed=1
    update_file_if_changed "dnsmasq.conf.j2" "/etc/dnsmasq.conf" "$temp_dir" && configs_changed=1

    # Update /etc/default/hostapd
    default_hostapd="/etc/default/hostapd"
    default_content='DAEMON_CONF="/etc/hostapd/hostapd.conf"'
    if [ "$(file_hash "$default_hostapd")" != "$(echo "$default_content" | sha256sum | cut -d ' ' -f 1)" ]; then
        log "Updating /etc/default/hostapd..."
        echo "$default_content" > "$default_hostapd"
    fi

    # Update hostname (hardcoding for simplicity; in practice, read from config.yml)
    hostname="plantomio.local"
    if [ "$(cat /etc/hostname)" != "$hostname" ]; then
        log "Updating hostname..."
        echo "$hostname" > /etc/hostname
        sed -i "s/127.0.0.1.*/127.0.1.1 $hostname/" /etc/hosts
    fi

    # Enable IP forwarding
    if [ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]; then
        log "Enabling IP forwarding..."
        sysctl -w net.ipv4.ip_forward=1
    fi

    # Enable and start services
    for service in hostapd dnsmasq avahi-daemon; do
        if is_service_enabled "$service"; then
            log "$service is enabled, skipping."
        else
            systemctl enable "$service" 2>/dev/null || true
        fi
        if is_service_running "$service" && [ "$configs_changed" -eq 0 ]; then
            log "$service is running, skipping start."
        else
            log "Starting $service..."
            systemctl start "$service" 2>/dev/null || true
        fi
    done
}

install_mosquitto() {
    local temp_dir=$1
    log "Installing Mosquitto..."
    if is_package_installed "mosquitto"; then
        log "Mosquitto is installed, skipping."
    else
        apt install -y mosquitto mosquitto-clients
    fi

    # Update Mosquitto configuration
    configs_changed=0
    update_file_if_changed "mosquitto.conf.j2" "/etc/mosquitto/mosquitto.conf" "$temp_dir" && configs_changed=1

    # Update Mosquitto password (hardcoding for simplicity; in practice, read from config.yml)
    passwd_file="/etc/mosquitto/passwd"
    passwd_content="admin:password"
    if [ "$(file_hash "$passwd_file")" != "$(echo "$passwd_content" | sha256sum | cut -d ' ' -f 1)" ]; then
        log "Updating Mosquitto password..."
        echo "$passwd_content" > "$passwd_file"
        mosquitto_passwd -U "$passwd_file"
    fi

    # Enable and start Mosquitto service
    if is_service_enabled "mosquitto"; then
        log "Mosquitto service is enabled, skipping."
    else
        systemctl enable mosquitto 2>/dev/null || true
    fi
    if is_service_running "mosquitto" && [ "$configs_changed" -eq 0 ]; then
        log "Mosquitto is running, skipping start."
    else
        log "Starting Mosquitto..."
        systemctl start mosquitto 2>/dev/null || true
    fi
}

install_victoria_metrics() {
    local temp_dir=$1
    log "Installing VictoriaMetrics..."
    vm_binary="/usr/local/bin/victoria-metrics"
    if [ -x "$vm_binary" ]; then
        log "VictoriaMetrics binary exists, skipping download."
    else
        rm -f "$vm_binary" /usr/local/bin/victoria-metrics-prod 2>/dev/null || true
        mkdir -p /usr/local/bin
        chmod 755 /usr/local/bin
        vm_url="https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v1.115.0/victoria-metrics-linux-arm64-v1.115.0.tar.gz"
        vm_tar="/tmp/vm.tar.gz"
        log "Downloading VictoriaMetrics from $vm_url..."
        wget "$vm_url" -O "$vm_tar"
        if [ ! -f "$vm_tar" ]; then
            log "Failed to download VictoriaMetrics."
            exit 1
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
            exit 1
        fi
        chmod +x "$vm_binary"
        rm -f "$vm_tar"
    fi

    # Update VictoriaMetrics configuration
    update_file_if_changed "victoria_metrics.yml.j2" "/etc/victoria-metrics.yml" "$temp_dir"

    # Create victoria-metrics user
    if id victoria-metrics >/dev/null 2>&1; then
        log "victoria-metrics user exists, skipping."
    else
        useradd -r victoria-metrics
    fi
    chown victoria-metrics:victoria-metrics "$vm_binary"
    mkdir -p /var/lib/victoria-metrics
    chown victoria-metrics:victoria-metrics /var/lib/victoria-metrics

    # Configure VictoriaMetrics service (hardcoding port for simplicity; in practice, read from config.yml)
    vm_service="/etc/systemd/system/victoria-metrics.service"
    service_content=$(cat << EOF
[Unit]
Description=VictoriaMetrics
After=network.target

[Service]
User=victoria-metrics
Group=victoria-metrics
ExecStart=$vm_binary --storageDataPath=/var/lib/victoria-metrics --httpListenAddr=:8428
Restart=always

[Install]
WantedBy=multi-user.target
EOF
)
    if [ "$(file_hash "$vm_service")" != "$(echo "$service_content" | sha256sum | cut -d ' ' -f 1)" ]; then
        log "Updating VictoriaMetrics service..."
        echo "$service_content" > "$vm_service"
        systemctl daemon-reload
    fi

    # Enable and start VictoriaMetrics service
    if is_service_enabled "victoria-metrics"; then
        log "VictoriaMetrics service is enabled, skipping."
    else
        systemctl enable victoria-metrics 2>/dev/null || true
    fi
    if is_service_running "victoria-metrics"; then
        log "VictoriaMetrics is running, skipping start."
    else
        log "Starting VictoriaMetrics..."
        systemctl start victoria-metrics 2>/dev/null || true
    fi
}

install_node_red() {
    local temp_dir=$1
    log "Installing Node-RED..."
    # Check if Node-RED is installed
    if sudo -u "$USER" which node-red >/dev/null 2>&1; then
        log "Node-RED is installed, cleaning up for fresh install..."
        systemctl stop nodered 2>/dev/null || true
        systemctl disable nodered 2>/dev/null || true
        rm -f /lib/systemd/system/nodered.service 2>/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
        rm -rf /usr/bin/node-red* /usr/local/bin/node-red* /root/.node-red "$NODE_RED_DIR" 2>/dev/null || true
    fi

    # Install Node.js and Node-RED
    log "Ensuring Node.js is installed..."
    apt update
    apt install -y nodejs npm
    log "Installing Node-RED using npm as user $USER..."
    sudo -u "$USER" npm install -g --unsafe-perm node-red

    # Ensure Node-RED directory exists with correct permissions
    mkdir -p "$NODE_RED_DIR"
    chown "$USER:$USER" "$NODE_RED_DIR"
    chmod -R u+rw "$NODE_RED_DIR"

    # Install node-red-contrib-victoriametrics
    log "Installing node-red-contrib-victoriametrics..."
    sudo -u "$USER" bash -c "cd $NODE_RED_DIR && npm install node-red-contrib-victoriametrics"

    # Configure Node-RED flow (hardcoding for simplicity; in practice, read from config.yml)
    flows_file="$NODE_RED_DIR/flows.json"
    vm_url="http://localhost:8428/api/v1/write"
    cat > "$flows_file" << EOF
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
        "func": "// Format MQTT data into InfluxDB line protocol for VictoriaMetrics\\nvar deviceID = msg.payload.deviceID || 'unknown';\\nvar timestamp = (msg.payload.timestamp || Math.floor(Date.now() / 1000)) * 1000; // Ensure timestamp in milliseconds\\nvar lines = [];\\nvar errors = [];\\n\\n// Define measurements\\nvar measurements = [\\n    { name: 'temperature', value: parseFloat(msg.payload.temperature) },\\n    { name: 'distance', value: parseFloat(msg.payload.distance) },\\n    { name: 'pH', value: parseFloat(msg.payload.pH) },\\n    { name: 'ORP', value: parseFloat(msg.payload.ORP) },\\n    { name: 'TDS', value: parseFloat(msg.payload.TDS) },\\n    { name: 'EC', value: parseFloat(msg.payload.EC) }\\n];\\n\\n// Validate and create a line for each measurement\\nmeasurements.forEach(function(m) {\\n    if (typeof msg.payload[m.name] === 'undefined') {\\n        errors.push('Missing field: ' + m.name);\\n    } else if (isNaN(m.value)) {\\n        errors.push('Invalid value for ' + m.name + ': ' + msg.payload[m.name]);\\n    } else {\\n        var line = \`\${m.name},deviceID=\${deviceID} value=\${m.value} \${timestamp}\`;\\n        lines.push(line);\\n    }\\n});\\n\\n// Log errors if any\\nif (errors.length > 0) {\\n    node.warn('Errors in MQTT data: ' + errors.join('; '));\\n}\\n\\n// Join lines with newlines\\nmsg.payload = lines.join('\\\\n');\\nmsg.headers = { 'Content-Type': 'text/plain' };\\nreturn msg;",
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
        "url": "$vm_url",
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
        "broker": "localhost",
        "port": "1883",
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
        "sessionExpiry": "",
        "credentials": {
            "user": "admin",
            "password": "password"
        }
    }
]
EOF
    chown "$USER:$USER" "$flows_file"
    chmod 644 "$flows_file"

    # Update Node-RED service
    nodered_service="/lib/systemd/system/nodered.service"
    node_red_path=$(sudo -u "$USER" which node-red || echo "/usr/local/bin/node-red")
    service_content=$(cat << EOF
[Unit]
Description=Node-RED graphical event wiring tool
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$NODE_RED_DIR
Environment="NODE_RED_HOME=$NODE_RED_DIR"
ExecStart=$node_red_path --userDir $NODE_RED_DIR --max-old-space-size=512
Restart=on-failure
KillSignal=SIGINT
SyslogIdentifier=Node-RED

[Install]
WantedBy=multi-user.target
EOF
)
    if [ "$(file_hash "$nodered_service")" != "$(echo "$service_content" | sha256sum | cut -d ' ' -f 1)" ]; then
        log "Updating Node-RED service..."
        echo "$service_content" > "$nodered_service"
        systemctl daemon-reload
    fi

    # Enable and start Node-RED service
    if is_service_enabled "nodered"; then
        log "Node-RED service is enabled, skipping."
    else
        systemctl enable nodered 2>/dev/null || true
    fi
    if is_service_running "nodered"; then
        log "Node-RED is running, restarting to apply changes..."
        systemctl restart nodered 2>/dev/null || true
    else
        log "Starting Node-RED..."
        systemctl start nodered 2>/dev/null || true
    fi
}

install_dashboard() {
    local temp_dir=$1
    log "Installing Dashboard..."
    apt update && apt install -y python3-flask python3-socketio python3-paho-mqtt python3-requests python3-eventlet python3-psutil
    dashboard_file="$INSTALL_DIR/flask_app.py"
    update_file_if_changed "flask_app.py" "$dashboard_file" "$temp_dir"
    chown "$USER:$USER" "$dashboard_file"
    chmod 644 "$dashboard_file"

    # Fix index.html if needed
    index_html="$INSTALL_DIR/static/index.html"
    if [ -f "$index_html" ] && grep -q 'tojson(pretty=true)' "$index_html"; then
        log "Fixing Jinja2 template in index.html..."
        sed 's/tojson(pretty=true)/tojson | safe/' "$index_html" > "$temp_dir/index.html"
        mv "$temp_dir/index.html" "$index_html"
        chown "$USER:$USER" "$index_html"
        chmod 644 "$index_html"
    fi

    # Configure dashboard service
    dashboard_service="/etc/systemd/system/syhub-dashboard.service"
    service_content=$(cat << EOF
[Unit]
Description=syhub Dashboard
After=network.target

[Service]
User=$USER
ExecStart=/usr/bin/python3 $dashboard_file
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
)
    if [ "$(file_hash "$dashboard_service")" != "$(echo "$service_content" | sha256sum | cut -d ' ' -f 1)" ]; then
        log "Updating Dashboard service..."
        echo "$service_content" > "$dashboard_service"
        systemctl daemon-reload
    fi

    # Enable and start dashboard service
    if is_service_enabled "syhub-dashboard"; then
        log "Dashboard service is enabled, skipping."
    else
        systemctl enable syhub-dashboard 2>/dev/null || true
    fi
    if is_service_running "syhub-dashboard"; then
        log "Dashboard is running, restarting to apply changes..."
        systemctl restart syhub-dashboard 2>/dev/null || true
    else
        log "Starting Dashboard..."
        systemctl start syhub-dashboard 2>/dev/null || true
    fi
}

main() {
    check_root
    log "Setting up a fresh Raspberry Pi OS installation..."
    # Set permissions for the script itself
    sysohub_script="$INSTALL_DIR/scripts/syhub.py"
    log "Setting permissions for $sysohub_script..."
    chown "$USER:$USER" "$sysohub_script"
    chmod 755 "$sysohub_script"

    # Update system packages
    apt update && apt upgrade -y

    # Create a temporary directory
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT

    # Run setup tasks in parallel using background jobs
    setup_wifi_ap "$temp_dir" &
    install_mosquitto "$temp_dir" &
    install_victoria_metrics "$temp_dir" &
    install_node_red "$temp_dir" &
    install_dashboard "$temp_dir" &

    # Wait for all background jobs to complete
    wait

    log "Setup complete. Rebooting..."
    reboot
}

main