#!/bin/bash

# Script to update Node-RED flows with configurable project name and metrics prefix
set -e

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Get directory paths
BASE_DIR=$(get_base_dir)
FLOWS_FILE="$BASE_DIR/node-red-files/flows.json"
CONFIG_FILE="$BASE_DIR/config/config.yml"
BACKUP_DIR="$BASE_DIR/backups"

# Load configuration
log "Loading configuration..."
load_config "$CONFIG_FILE" || exit 1

PROJECT_NAME="${config_project_name}"
METRICS_PREFIX="${config_project_metrics_prefix}"
FLOW_ID="${config_service_names_flow_id}"

if [ -z "$FLOW_ID" ]; then
  log "Error: Missing required configuration value service_names.flow_id"
  exit 1
fi

log "Updating Node-RED flows:"
log "- Project name: $PROJECT_NAME"
log "- Metrics prefix: $METRICS_PREFIX"
log "- Flow ID: $FLOW_ID"

# Check if flows file exists
if [ ! -f "$FLOWS_FILE" ]; then
  log "Error: Flows file not found: $FLOWS_FILE"
  exit 1
fi

# Backup the flows file before modifying
backup_file "$FLOWS_FILE" "$BACKUP_DIR"

# Replace plantomio_ metric prefix with configured prefix
safe_replace "$FLOWS_FILE" "plantomio_" "${METRICS_PREFIX}"

# Replace plantomio-flow with configured flow ID
safe_replace "$FLOWS_FILE" "plantomio-flow" "${FLOW_ID}"

# Update flow label
safe_replace "$FLOWS_FILE" "\"label\": \"Plantomio Data Flow\"" "\"label\": \"${PROJECT_NAME} Data Flow\""

log "Node-RED flows updated successfully!" 