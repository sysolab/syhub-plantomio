#!/bin/bash

# Script to update dashboard JS files with configurable metrics prefix
set -e

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Get directory paths
BASE_DIR=$(get_base_dir)
JS_DIR="$BASE_DIR/dashboard/static/js"
CONFIG_FILE="$BASE_DIR/config/config.yml"
BACKUP_DIR="$BASE_DIR/backups"

# Load configuration
log "Loading configuration..."
load_config "$CONFIG_FILE" || exit 1

METRICS_PREFIX="${config_project_metrics_prefix}"

log "Updating dashboard JS files with metrics prefix: $METRICS_PREFIX"

# Check if JS directory exists
if [ ! -d "$JS_DIR" ]; then
  log "Warning: JS directory not found: $JS_DIR. Creating it."
  mkdir -p "$JS_DIR"
  # Exit if there are no files to process
  log "No JS files to process. Exiting."
  exit 0
fi

# Get all JS files
JS_FILES=$(find "$JS_DIR" -name "*.js" 2>/dev/null)

if [ -z "$JS_FILES" ]; then
  log "Warning: No JS files found in $JS_DIR. Nothing to update."
  exit 0
fi

# Update each file
for file in $JS_FILES; do
  log "Processing file: $file"
  
  # Backup the file before modifying
  backup_file "$file" "$BACKUP_DIR"
  
  # Replace plantomio_ with configured prefix
  safe_replace "$file" "plantomio_" "${METRICS_PREFIX}"
done

log "Dashboard JS files updated successfully!" 