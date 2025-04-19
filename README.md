# SyHub IoT Dashboard

A lightweight, efficient IoT monitoring system optimized for Raspberry Pi 3B. This system collects sensor data via MQTT, stores it in VictoriaMetrics, and displays it in a responsive web dashboard.

## Features

- **Real-time updates**: Uses Server-Sent Events (SSE) for efficient real-time data updates
- **Responsive design**: Works on mobile, tablet, and desktop
- **Resource-efficient**: Optimized for Raspberry Pi 3B's limited resources
- **Water level visualization**: Shows water level in a tank with configurable settings
- **Historical data trends**: View sensor data trends over various time periods
- **Easy setup**: Simple installation script sets up the entire system
- **Fully configurable**: All system components can be configured from a single YAML file

## System Requirements

- Raspberry Pi 3B or better
- Raspberry Pi OS 64-bit (Bookworm)
- At least 1GB of free disk space
- Internet connection for initial setup

## Quick Installation

1. Clone or download this repository to your Raspberry Pi
2. Edit `config/config.yml` to customize your setup
3. Make the setup script executable: `chmod +x setup.sh`
4. Run the setup script as root: `sudo ./setup.sh`
5. Wait for the installation to complete (5-10 minutes)

## Accessing the Dashboard

After installation, you can access the various services:

- **Dashboard**: `http://<your-hostname>/` or `http://<your-pi-ip>/`
- **Node-RED**: `http://<your-hostname>/node-red/` or `http://<your-pi-ip>/node-red/`
- **VictoriaMetrics**: `http://<your-hostname>/victoria/` or `http://<your-pi-ip>/victoria/`

The default hostname is set in your `config.yml` file.

## Configuration

The system configuration is stored in `config/config.yml`. You can modify this file to adjust settings such as:

- Project name and hostname
- MQTT broker credentials
- Web dashboard port
- Data retention period
- WiFi access point settings (optional)

## MQTT Data Format

The system expects sensor data in the following JSON format:

```json
{
  "temperature": 25.0,
  "pH": 7.0,
  "ORP": 300.0,
  "TDS": 500.0,
  "EC": 1.0,
  "distance": 50.0
}
```

Publish this data to the topic defined in your config file (default: `v1/devices/me/telemetry`).

## Tank Level Configuration

Configure your tank's water level calculation in the Settings page of the dashboard:

1. Set Maximum Distance (Empty Tank): Distance sensor reading when tank is empty (0% level)
2. Set Minimum Distance (Full Tank): Distance sensor reading when tank is full (100% level)

## Troubleshooting

- **Dashboard not loading**: Check if the dashboard service is running: `systemctl status dashboard`
- **No data updates**: Verify MQTT broker is running: `systemctl status mosquitto`
- **Charts not displaying**: Check if VictoriaMetrics is running: `systemctl status victoriametrics`

## License

This project is open source and available under the MIT License. 