#!/bin/bash

# Node-RED Flows Management Script
# This script helps manage flows.json files between the Node-RED installation
# and your project's node-red-files directory

set -e  # Exit on any error

# Get the actual user who invoked sudo
if [ -n "$SUDO_USER" ]; then
  SYSTEM_USER="$SUDO_USER"
else
  SYSTEM_USER="$(whoami)"
fi

# Base directory determination
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR=$(dirname "$SCRIPT_DIR")
NODE_RED_DIR="/home/$SYSTEM_USER/.node-red"
PROJECT_FLOWS_DIR="$BASE_DIR/node-red-files"
PROJECT_FLOW="$PROJECT_FLOWS_DIR/flows.json"

# Ensure we're running as sudo/root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

# Show help function
show_help() {
  echo "Node-RED Flows Management Script"
  echo "================================"
  echo ""
  echo "This script manages flows.json between Node-RED and your project."
  echo ""
  echo "Usage: sudo $0 [COMMAND]"
  echo ""
  echo "Commands:"
  echo "  export    Export flows from Node-RED to node-red-files directory"
  echo "  import    Import flows from node-red-files directory to Node-RED"
  echo "  backup    Create a timestamped backup of current Node-RED flows"
  echo "  help      Show this help message"
  echo ""
  echo "Examples:"
  echo "  sudo $0 export    # Export flows from Node-RED to project"
  echo "  sudo $0 import    # Import flows from project to Node-RED"
  echo ""
  exit 0
}

# Export flows from Node-RED to node-red-files directory
export_flows() {
  echo "Exporting flows from Node-RED to node-red-files directory..."
  
  if [ ! -f "$NODE_RED_DIR/flows.json" ]; then
    echo "Error: Node-RED flows.json not found at $NODE_RED_DIR/flows.json"
    echo "Make sure Node-RED has been installed and used at least once"
    exit 1
  fi
  
  # Create node-red-files directory if it doesn't exist
  if [ ! -d "$PROJECT_FLOWS_DIR" ]; then
    mkdir -p "$PROJECT_FLOWS_DIR"
    chown "$SYSTEM_USER:$SYSTEM_USER" "$PROJECT_FLOWS_DIR"
    echo "Created node-red-files directory"
  fi
  
  # Create a backup of the project flows if it exists
  if [ -f "$PROJECT_FLOW" ]; then
    cp "$PROJECT_FLOW" "${PROJECT_FLOW}.$(date +%Y%m%d%H%M%S).bak"
    echo "Backed up existing project flows.json"
  fi
  
  # Copy the Node-RED flows to the project
  cp "$NODE_RED_DIR/flows.json" "$PROJECT_FLOW"
  echo "Successfully exported Node-RED flows to $PROJECT_FLOW"
  
  # Fix ownership
  chown "$SYSTEM_USER:$SYSTEM_USER" "$PROJECT_FLOW"
  
  echo "Done! Your updated flows.json is now in the node-red-files directory."
}

# Import flows from node-red-files directory to Node-RED
import_flows() {
  echo "Importing flows from node-red-files directory to Node-RED..."
  
  if [ ! -f "$PROJECT_FLOW" ]; then
    echo "Error: Project flows.json not found at $PROJECT_FLOW"
    echo "Make sure you have a flows.json file in your node-red-files directory"
    exit 1
  fi
  
  # Create Node-RED directory if it doesn't exist
  if [ ! -d "$NODE_RED_DIR" ]; then
    mkdir -p "$NODE_RED_DIR"
    chown "$SYSTEM_USER:$SYSTEM_USER" "$NODE_RED_DIR"
    echo "Created Node-RED directory"
  fi
  
  # Create a backup of the Node-RED flows if it exists
  if [ -f "$NODE_RED_DIR/flows.json" ]; then
    cp "$NODE_RED_DIR/flows.json" "${NODE_RED_DIR}/flows.$(date +%Y%m%d%H%M%S).backup.json"
    echo "Backed up existing Node-RED flows"
  fi
  
  # Copy the project flows to Node-RED
  cp "$PROJECT_FLOW" "$NODE_RED_DIR/flows.json"
  chown "$SYSTEM_USER:$SYSTEM_USER" "$NODE_RED_DIR/flows.json"
  echo "Successfully imported flows to Node-RED"
  
  # Restart Node-RED to apply changes
  if systemctl is-active --quiet nodered; then
    echo "Restarting Node-RED to apply changes..."
    systemctl restart nodered
    echo "Node-RED restarted"
  else
    echo "Node-RED service is not running. Start it with: sudo systemctl start nodered"
  fi
  
  echo "Done! Your flows have been imported to Node-RED."
}

# Backup current Node-RED flows
backup_flows() {
  echo "Creating backup of current Node-RED flows..."
  
  # Check if Node-RED directory exists
  if [ ! -d "$NODE_RED_DIR" ]; then
    echo "Error: Node-RED directory not found at $NODE_RED_DIR"
    exit 1
  fi
  
  # Check if flows.json exists
  if [ ! -f "$NODE_RED_DIR/flows.json" ]; then
    echo "Error: No flows.json found in Node-RED directory"
    exit 1
  fi
  
  # Create backups directory
  BACKUP_DIR="$BASE_DIR/backups/flows"
  mkdir -p "$BACKUP_DIR"
  
  # Create timestamped backup
  BACKUP_FILE="$BACKUP_DIR/flows.$(date +%Y%m%d%H%M%S).json"
  cp "$NODE_RED_DIR/flows.json" "$BACKUP_FILE"
  chown "$SYSTEM_USER:$SYSTEM_USER" "$BACKUP_FILE"
  
  echo "Backup created at: $BACKUP_FILE"
}

# Process command argument
if [ $# -eq 0 ]; then
  show_help
fi

case "$1" in
  "export")
    export_flows
    ;;
  "import")
    import_flows
    ;;
  "backup")
    backup_flows
    ;;
  "help" | "-h" | "--help")
    show_help
    ;;
  *)
    echo "Unknown command: $1"
    echo "Run '$0 help' for usage information"
    exit 1
    ;;
esac 