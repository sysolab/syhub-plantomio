#!/bin/bash

# Script to download frontend dependencies
set -e

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Get directory paths
BASE_DIR=$(get_base_dir)
STATIC_DIR="$BASE_DIR/dashboard/static"

# Create directories if they don't exist
mkdir -p "$STATIC_DIR/js"
mkdir -p "$STATIC_DIR/css"
mkdir -p "$STATIC_DIR/images"

log "Downloading Chart.js..."
# Download minified Chart.js
curl -s -L https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js -o "$STATIC_DIR/js/chart.min.js" || {
  log "Error downloading Chart.js. Please check your internet connection."
  exit 1
}

log "Creating placeholder favicon..."
# Create a simple favicon placeholder
cat > "$STATIC_DIR/images/favicon.ico" << EOF
000000000000000000000000
EOF

log "Dependencies downloaded successfully!" 