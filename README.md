# Plantomio IoT Dashboard

A lightweight, efficient IoT monitoring system optimized for Raspberry Pi 3B. This system collects sensor data via MQTT, stores it in VictoriaMetrics, and displays it in a responsive web dashboard.

## Features

- **Real-time updates**: Uses Server-Sent Events (SSE) for efficient real-time data updates
- **Responsive design**: Works on mobile, tablet, and desktop
- **Resource-efficient**: Optimized for Raspberry Pi 3B's limited resources
- **Water level visualization**: Shows water level in a tank with configurable settings
- **Historical data trends**: View sensor data trends over various time periods
- **Easy setup**: Simple installation script sets up the entire system

## System Requirements

- Raspberry Pi 3B or better
- Raspberry Pi OS 64-bit (Bookworm)
- At least 1GB of free disk space
- Internet connection for initial setup

## Quick Installation

1. Clone or download this repository to your Raspberry Pi
2. Make the setup script executable: `chmod +x setup.sh`
3. Run the setup script as root: `sudo ./setup.sh`
4. Wait for the installation to complete (5-10 minutes)

## Accessing the Dashboard

After installation, you can access the various services:

- **Dashboard**: `http://plantomio.local:5000/` or `http://<your-pi-ip>:5000/`
- **Node-RED**: `http://plantomio.local:1880/` or `http://<your-pi-ip>:1880/`
- **VictoriaMetrics**: `http://plantomio.local:8428/` or `http://<your-pi-ip>:8428/`

## Configuration

The system configuration is stored in `/home/<your-user>/syhub/config/config.yml`. You can modify this file to adjust settings such as:

- MQTT broker credentials
- Web dashboard port
- Data retention period
- System hostname

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

Publish this data to the topic `v1/devices/me/telemetry`.

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