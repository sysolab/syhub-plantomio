#!/bin/bash

# Script to download frontend dependencies
set -e

# Ensure script is run from the correct directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
STATIC_DIR="$BASE_DIR/dashboard/static"

# Create directories if they don't exist
mkdir -p "$STATIC_DIR/js"
mkdir -p "$STATIC_DIR/css"
mkdir -p "$STATIC_DIR/images"

echo "Downloading Chart.js..."
# Download minified Chart.js
curl -s -L https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js -o "$STATIC_DIR/js/chart.min.js"

echo "Creating placeholder favicon..."
# Create a simple favicon placeholder
cat > "$STATIC_DIR/images/favicon.ico" << EOF
000000000000000000000000
EOF

echo "Dependencies downloaded successfully!" 