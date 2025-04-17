#!/bin/bash

# SyHub Setup Script
# Sets up IoT monitoring system on Raspberry Pi 3B with Raspberry Pi OS 64-bit Lite
# Date: April 17, 2025

set -e

# Read config.yml
CONFIG_FILE="$HOME/syhub/config/config.yml"
if ! command -v yq &>/dev/null; then
    sudo apt update
    sudo apt install -y yq || { echo "Failed to install yq"; exit 1; }
fi

PROJECT_NAME=$(yq e '.project.name' "$CONFIG_FILE")
BASE_DIR=$(yq e '.base_dir // "'"$HOME/syhub"'"' "$CONFIG_FILE")
LOG_FILE=$(yq e '.log_file' "$CONFIG_FILE")
BACKUP_DIR=$(yq e '.backup_directory' "$CONFIG_FILE")
SYSTEM_USER=$(whoami)
HOSTNAME=$(yq e '.hostname' "$CONFIG_FILE")
CONFIGURE_NETWORK=$(yq e '.configure_network' "$CONFIG_FILE")
WIFI_AP_INTERFACE=$(yq e '.wifi.ap_interface' "$CONFIG_FILE")
WIFI_AP_IP=$(yq e '.wifi.ap_ip' "$CONFIG_FILE")
WIFI_AP_SUBNET_MASK=$(yq e '.wifi.ap_subnet_mask' "$CONFIG_FILE")
WIFI_AP_DHCP_RANGE_START=$(yq e '.wifi.ap_dhcp_range_start' "$CONFIG_FILE")
WIFI_AP_DHCP_RANGE_END=$(yq e '.wifi.ap_dhcp_range_end' "$CONFIG_FILE")
WIFI_AP_DHCP_LEASE_TIME=$(yq e '.wifi.ap_dhcp_lease_time' "$CONFIG_FILE")
WIFI_AP_SSID=$(yq e '.wifi.ap_ssid' "$CONFIG_FILE")
WIFI_AP_PASSWORD=$(yq e '.wifi.ap_password' "$CONFIG_FILE")
WIFI_COUNTRY_CODE=$(yq e '.wifi.country_code' "$CONFIG_FILE")
WIFI_STA_SSID=$(yq e '.wifi.sta_ssid' "$CONFIG_FILE")
WIFI_STA_PASSWORD=$(yq e '.wifi.sta_password' "$CONFIG_FILE")
MQTT_PORT=$(yq e '.mqtt.port' "$CONFIG_FILE")
MQTT_USERNAME=$(yq e '.mqtt.username' "$CONFIG_FILE")
MQTT_PASSWORD=$(yq e '.mqtt.password' "$CONFIG_FILE")
MQTT_TOPIC=$(yq e '.mqtt.topic_telemetry' "$CONFIG_FILE")
VICTORIA_METRICS_VERSION=$(yq e '.victoria_metrics.version' "$CONFIG_FILE")
VICTORIA_METRICS_PORT=$(yq e '.victoria_metrics.port' "$CONFIG_FILE")
VICTORIA_METRICS_DATA_DIR=$(yq e '.victoria_metrics.data_directory' "$CONFIG_FILE")
VICTORIA_METRICS_RETENTION=$(yq e '.victoria_metrics.retention_period' "$CONFIG_FILE")
VICTORIA_METRICS_USER=$(yq e '.victoria_metrics.service_user' "$CONFIG_FILE")
VICTORIA_METRICS_GROUP=$(yq e '.victoria_metrics.service_group' "$CONFIG_FILE")
NODE_RED_PORT=$(yq e '.node_red.port' "$CONFIG_FILE")
NODE_RED_MEMORY_LIMIT=$(yq e '.node_red.memory_limit_mb' "$CONFIG_FILE")
NODE_RED_USERNAME=$(yq e '.node_red.username' "$CONFIG_FILE")
NODE_RED_PASSWORD_HASH=$(yq e '.node_red.password_hash' "$CONFIG_FILE")
DASHBOARD_PORT=$(yq e '.dashboard.port' "$CONFIG_FILE")
DASHBOARD_WORKERS=$(yq e '.dashboard.workers' "$CONFIG_FILE")
NODEJS_VERSION=$(yq e '.nodejs.install_version' "$CONFIG_FILE")

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Error handling function
handle_error() {
    log "ERROR" "Failed at step: $1"
    exit 1
}

# Check internet connectivity
check_internet() {
    log "INFO" "Checking internet connectivity..."
    for i in {1..3}; do
        if ping -c 1 github.com &>/dev/null; then
            log "INFO" "Internet connection verified."
            return 0
        fi
        log "WARNING" "No internet connection. Retrying ($i/3)..."
        sleep 5
    done
    handle_error "Internet connectivity check"
}

# Install dependencies
install_dependencies() {
    log "INFO" "Updating package lists..."
    sudo apt update || handle_error "APT update"

    log "INFO" "Installing dependencies..."
    sudo apt install -y \
        python3 python3-pip python3-venv \
        mosquitto mosquitto-clients \
        hostapd dnsmasq avahi-daemon \
        git wget curl yq \
        || handle_error "Dependency installation"

    log "INFO" "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_"$NODEJS_VERSION".x | sudo -E bash -
    sudo apt install -y nodejs || handle_error "Node.js installation"

    log "INFO" "Setting up Python virtual environment..."
    python3 -m venv "$BASE_DIR/venv"
    source "$BASE_DIR/venv/bin/activate"
    pip install flask gunicorn requests paho-mqtt pyyaml smtplib || handle_error "Python package installation"
    deactivate
}

# Configure WiFi AP+STA
configure_wifi() {
    if [ "$CONFIGURE_NETWORK" != "true" ]; then
        log "INFO" "Skipping network configuration (configure_network=false)"
        return
    fi

    log "INFO" "Configuring WiFi AP+STA..."
    sudo mv /etc/dhcpcd.conf /etc/dhcpcd.conf.bak-$(date +%F) 2>/dev/null || true
    sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak-$(date +%F) 2>/dev/null || true
    sudo mv /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.bak-$(date +%F) 2>/dev/null || true

    for template in dhcpcd.conf.j2 dnsmasq.conf.j2 hostapd.conf.j2; do
        sed -e "s|__WIFI_AP_INTERFACE__|$WIFI_AP_INTERFACE|" \
            -e "s|__WIFI_AP_IP__|$WIFI_AP_IP|" \
            -e "s|__WIFI_AP_SUBNET_MASK__|$WIFI_AP_SUBNET_MASK|" \
            -e "s|__WIFI_AP_DHCP_RANGE_START__|$WIFI_AP_DHCP_RANGE_START|" \
            -e "s|__WIFI_AP_DHCP_RANGE_END__|$WIFI_AP_DHCP_RANGE_END|" \
            -e "s|__WIFI_AP_DHCP_LEASE_TIME__|$WIFI_AP_DHCP_LEASE_TIME|" \
            -e "s|__WIFI_AP_SSID__|$WIFI_AP_SSID|" \
            -e "s|__WIFI_AP_PASSWORD__|$WIFI_AP_PASSWORD|" \
            -e "s|__WIFI_COUNTRY_CODE__|$WIFI_COUNTRY_CODE|" \
            -e "s|__WIFI_STA_SSID__|$WIFI_STA_SSID|" \
            -e "s|__WIFI_STA_PASSWORD__|$WIFI_STA_PASSWORD|" \
            "$BASE_DIR/config/$template" > "/etc/${template%.j2}" || handle_error "Template processing: $template"
    done

    sudo systemctl unmask hostapd
    sudo systemctl enable hostapd dnsmasq
    sudo systemctl restart hostapd dnsmasq || handle_error "WiFi service restart"
}

# Configure Mosquitto
configure_mosquitto() {
    log "INFO" "Configuring Mosquitto MQTT broker..."
    echo "$MQTT_USERNAME:$(openssl passwd -6 "$MQTT_PASSWORD")" | sudo tee /etc/mosquitto/passwd >/dev/null
    sudo chown mosquitto:mosquitto /etc/mosquitto/passwd
    sudo chmod 600 /etc/mosquitto/passwd

    sed -e "s|__MQTT_PORT__|$MQTT_PORT|" \
        "$BASE_DIR/config/mosquitto.conf.j2" > "/etc/mosquitto/conf.d/$PROJECT_NAME.conf" || handle_error "Mosquitto config processing"

    sudo systemctl enable mosquitto
    sudo systemctl restart mosquitto || handle_error "Mosquitto service restart"
}

# Configure VictoriaMetrics
configure_victoriametrics() {
    log "INFO" "Configuring VictoriaMetrics..."
    sudo useradd -r -s /bin/false "$VICTORIA_METRICS_USER" 2>/dev/null || true
    sudo groupadd "$VICTORIA_METRICS_GROUP" 2>/dev/null || true
    sudo usermod -a -G "$VICTORIA_METRICS_GROUP" "$VICTORIA_METRICS_USER"

    sudo mkdir -p "$VICTORIA_METRICS_DATA_DIR"
    sudo chown "$VICTORIA_METRICS_USER:$VICTORIA_METRICS_GROUP" "$VICTORIA_METRICS_DATA_DIR"

    wget "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/$VICTORIA_METRICS_VERSION/victoria-metrics-linux-arm64-$VICTORIA_METRICS_VERSION.tar.gz" -O /tmp/vm.tar.gz || handle_error "VictoriaMetrics download"
    sudo tar -xzf /tmp/vm.tar.gz -C /usr/local/bin
    sudo mv /usr/local/bin/victoria-metrics-prod /usr/local/bin/victoria-metrics
    sudo chmod +x /usr/local/bin/victoria-metrics

    sed -e "s|__VICTORIA_METRICS_PORT__|$VICTORIA_METRICS_PORT|" \
        -e "s|__VICTORIA_METRICS_RETENTION_PERIOD__|$VICTORIA_METRICS_RETENTION|" \
        "$BASE_DIR/config/victoria_metrics.yml.j2" > /etc/victoriametrics.yml || handle_error "VictoriaMetrics config processing"

    cat << EOF | sudo tee /etc/systemd/system/victoriametrics.service
[Unit]
Description=VictoriaMetrics Time Series Database
After=network.target

[Service]
ExecStart=/usr/local/bin/victoria-metrics --config=/etc/victoriametrics.yml --storageDataPath=$VICTORIA_METRICS_DATA_DIR
User=$VICTORIA_METRICS_USER
Group=$VICTORIA_METRICS_GROUP
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl enable victoriametrics
    sudo systemctl restart victoriametrics || handle_error "VictoriaMetrics service restart"
}

# Configure Node-RED
configure_nodered() {
    log "INFO" "Configuring Node-RED..."
    sudo npm install -g --unsafe-perm node-red
    mkdir -p "$BASE_DIR/.node-red"
    cat << EOF > "$BASE_DIR/.node-red/settings.js"
module.exports = {
    httpAdminRoot: '/admin',
    httpNodeRoot: '/',
    userDir: '$BASE_DIR/.node-red',
    adminAuth: {
        type: "credentials",
        users: [{
            username: "$NODE_RED_USERNAME",
            password: "$NODE_RED_PASSWORD_HASH",
            permissions: "*"
        }]
    },
    editorTheme: { projects: { enabled: false } }
}
EOF

    cat << EOF > "$BASE_DIR/.node-red/flows.json"
[
    {
        "id": "mqtt_in",
        "type": "mqtt in",
        "name": "MQTT Input",
        "topic": "$MQTT_TOPIC",
        "broker": "mqtt_broker",
        "x": 100,
        "y": 100,
        "wires": [["json_parse"]]
    },
    {
        "id": "json_parse",
        "type": "json",
        "name": "Parse JSON",
        "x": 300,
        "y": 100,
        "wires": [["format_metrics"]]
    },
    {
        "id": "format_metrics",
        "type": "function",
        "name": "Format for VictoriaMetrics",
        "func": "var lines = [];\nfor (var key in msg.payload) {\n    lines.push(\`telemetry{metric=\\"\${key}\\"} \${msg.payload[key]}\`);\n}\nmsg.payload = lines.join('\\n');\nreturn msg;",
        "x": 500,
        "y": 100,
        "wires": [["http_request"]]
    },
    {
        "id": "http_request",
        "type": "http request",
        "name": "Send to VictoriaMetrics",
        "method": "POST",
        "url": "http://$HOSTNAME:$VICTORIA_METRICS_PORT/api/v1/write",
        "x": 700,
        "y": 100,
        "wires": []
    },
    {
        "id": "mqtt_broker",
        "type": "mqtt-broker",
        "name": "MQTT Broker",
        "broker": "localhost",
        "port": "$MQTT_PORT",
        "clientid": "$PROJECT_NAME",
        "usetls": false,
        "protocolVersion": "4",
        "credentials": {
            "user": "$MQTT_USERNAME",
            "password": "$MQTT_PASSWORD"
        }
    }
]
EOF

    cat << EOF | sudo tee /etc/systemd/system/nodered.service
[Unit]
Description=Node-RED
After=network.target

[Service]
ExecStart=/usr/bin/node-red --max-old-space-size=$NODE_RED_MEMORY_LIMIT -p $NODE_RED_PORT
WorkingDirectory=$BASE_DIR/.node-red
User=$SYSTEM_USER
Restart=always
Environment=NODE_RED_HOME=$BASE_DIR/.node-red

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl enable nodered
    sudo systemctl restart nodered || handle_error "Node-RED service restart"
}

# Configure Data Processor
configure_data_processor() {
    log "INFO" "Configuring Data Processor..."
    cat << EOF | sudo tee /etc/systemd/system/$PROJECT_NAME-processor.service
[Unit]
Description=$PROJECT_NAME Data Processor
After=network.target mosquitto.service victoriametrics.service

[Service]
ExecStart=$BASE_DIR/venv/bin/python $BASE_DIR/src/data_processor.py
WorkingDirectory=$BASE_DIR/src
Restart=always
User=$SYSTEM_USER

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl enable "$PROJECT_NAME"-processor
    sudo systemctl restart "$PROJECT_NAME"-processor || handle_error "Data Processor service restart"
}

# Configure Alerter
configure_alerter() {
    log "INFO" "Configuring Alerter..."
    cat << EOF | sudo tee /etc/systemd/system/$PROJECT_NAME-alerter.service
[Unit]
Description=$PROJECT_NAME Alerter
After=network.target victoriametrics.service

[Service]
ExecStart=$BASE_DIR/venv/bin/python $BASE_DIR/src/alerter.py
WorkingDirectory=$BASE_DIR/src
Restart=always
User=$SYSTEM_USER

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl enable "$PROJECT_NAME"-alerter
    sudo systemctl restart "$PROJECT_NAME"-alerter || handle_error "Alerter service restart"
}

# Configure Flask Dashboard
configure_dashboard() {
    log "INFO" "Configuring Flask Dashboard..."
    cat << EOF | sudo tee /etc/systemd/system/$PROJECT_NAME-dashboard.service
[Unit]
Description=$PROJECT_NAME Flask Dashboard
After=network.target

[Service]
ExecStart=$BASE_DIR/venv/bin/gunicorn --workers $DASHBOARD_WORKERS --bind 0.0.0.0:$DASHBOARD_PORT app:app
WorkingDirectory=$BASE_DIR/src
Restart=always
User=$SYSTEM_USER

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl enable "$PROJECT_NAME"-dashboard
    sudo systemctl restart "$PROJECT_NAME"-dashboard || handle_error "Dashboard service restart"
}

# Configure Health Check
configure_health_check() {
    log "INFO" "Configuring Health Check..."
    cat << EOF | sudo tee /etc/systemd/system/$PROJECT_NAME-healthcheck.service
[Unit]
Description=$PROJECT_NAME Health Check
After=network.target

[Service]
ExecStart=/bin/bash $BASE_DIR/scripts/health_check.sh
WorkingDirectory=$BASE_DIR/scripts
Restart=always
User=$SYSTEM_USER

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl enable "$PROJECT_NAME"-healthcheck
    sudo systemctl restart "$PROJECT_NAME"-healthcheck || handle_error "Health Check service restart"
}

# Main setup function
main() {
    log "INFO" "Starting $PROJECT_NAME setup..."
    check_internet
    install_dependencies
    configure_wifi
    configure_mosquitto
    configure_victoriametrics
    configure_nodered
    configure_data_processor
    configure_alerter
    configure_dashboard
    configure_health_check

    # Setup cron for backups
    echo "0 0 * * * /bin/bash $BASE_DIR/scripts/setup.sh backup" | crontab -

    log "INFO" "Setup completed successfully!"
    log "INFO" "Access dashboard at http://$HOSTNAME:$DASHBOARD_PORT"
}

# Backup function
backup() {
    log "INFO" "Creating backup..."
    tar -czf "$BASE_DIR/$BACKUP_DIR/backup-$(date +%F).tar.gz" "$BASE_DIR/config" "$BASE_DIR/src" "$BASE_DIR/.node-red" || handle_error "Backup creation"
}

# Handle script arguments
case "$1" in
    setup)
        main
        ;;
    backup)
        backup
        ;;
    *)
        echo "Usage: $0 {setup|backup}"
        exit 1
        ;;
esac