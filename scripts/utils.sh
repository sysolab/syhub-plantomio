#!/bin/bash

# Common utility functions for SyHub scripts

# Get absolute path to script directory
get_script_dir() {
  echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

# Get absolute path to base directory (parent of script directory)
get_base_dir() {
  local script_dir=$(get_script_dir)
  echo "$(dirname "$script_dir")"
}

# Parse YAML function - improved for nested structures
parse_yaml() {
  local yaml_file=$1
  local prefix=$2
  local s
  local w
  local fs

  s='[[:space:]]*'
  w='[a-zA-Z0-9_]*'
  fs="$(echo @|tr @ '\034')"
  
  # Debug
  echo "# Debug: Parsing YAML file: $yaml_file" >&2
  
  sed -n -e "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
         -e "s|^\($s\)\($w\)$s[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" "$yaml_file" |
  awk -F"$fs" '{
    indent = length($1)/2;
    if (indent == 0) {
      vname[indent] = $2;
    } else {
      vname[indent] = vname[indent-1]"_"$2;
    }
    if (length($3) > 0) {
      vn = vname[indent];
      gsub(/[^a-zA-Z0-9_]/, "_", vn);
      printf("%s%s=\"%s\"\n", "'$prefix'", vn, $3);
    }
  }' | grep -v "^#"
}

# Load configuration
load_config() {
  local config_file=$1
  
  # Check if config file exists
  if [ ! -f "$config_file" ]; then
    echo "Error: Configuration file not found: $config_file"
    return 1
  fi
  
  # Source the parsed YAML
  eval $(parse_yaml "$config_file" "config_")
  
  # Check required configuration values
  if [ -z "$config_project_name" ]; then
    echo "Error: Missing required configuration value: project.name"
    return 1
  fi
  
  if [ -z "$config_project_metrics_prefix" ]; then
    echo "Error: Missing required configuration value: project.metrics_prefix"
    return 1
  fi
  
  return 0
}

# Create a backup of a file before modifying it
backup_file() {
  local file=$1
  local backup_dir=$2
  
  # Create backup directory if it doesn't exist
  mkdir -p "$backup_dir"
  
  # Only backup if file exists
  if [ -f "$file" ]; then
    local timestamp=$(date +"%Y%m%d-%H%M%S")
    local filename=$(basename "$file")
    cp "$file" "$backup_dir/${filename}.${timestamp}.bak"
    echo "Backed up $file to $backup_dir/${filename}.${timestamp}.bak"
  fi
}

# Function to safely replace a string in a file
safe_replace() {
  local file=$1
  local search=$2
  local replace=$3
  
  # Create a temporary file
  local tmp_file=$(mktemp)
  
  # Replace the string
  sed "s|${search}|${replace}|g" "$file" > "$tmp_file"
  
  # Check if the replacement was successful
  if [ $? -eq 0 ]; then
    # Copy back to original location
    cp "$tmp_file" "$file"
  else
    echo "Error: Failed to replace '$search' with '$replace' in $file"
  fi
  
  # Clean up
  rm -f "$tmp_file"
}

# Logging function
log() {
  local message=$1
  local log_file=$2
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  
  echo "[$timestamp] $message"
  
  if [ -n "$log_file" ]; then
    echo "[$timestamp] $message" >> "$log_file"
  fi
} 