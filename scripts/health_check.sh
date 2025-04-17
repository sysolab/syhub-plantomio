#!/bin/bash

# Health Check Script for SyHub
# Monitors services and restarts them if they fail
# Date: April 17, 2025

LOG_FILE="/tmp/syhub_health.log"

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

SERVICES=(
    "mosquitto"
    "victoriametrics"
    "nodered"
    "__PROJECT_NAME__-processor"
    "__PROJECT_NAME__-alerter"
    "__PROJECT_NAME__-dashboard"
)

while true; do
    for service in "${SERVICES[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            log "ERROR" "Service $service is not active. Restarting..."
            sudo systemctl restart "$service"
            if systemctl is-active --quiet "$service"; then
                log "INFO" "Service $service restarted successfully."
            else
                log "ERROR" "Failed to restart service $service."
            fi
        fi
    done
    sleep 60
done