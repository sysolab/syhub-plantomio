# SyHub - Plantomio IoT Monitoring System

![Plantomio](assets/logo.png)

An integrated IoT monitoring system for sensor data collection, storage, visualization, and automation. SyHub combines MQTT, VictoriaMetrics, and Node-RED to create a powerful platform for IoT projects, with Plantomio as the project name.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Installation](#installation)
  - [Prerequisites](#prerequisites)
  - [Setup Options](#setup-options)
  - [Running the Setup](#running-the-setup)
- [Usage](#usage)
  - [Accessing Dashboards](#accessing-dashboards)
  - [Sending Data to the System](#sending-data-to-the-system)
  - [Querying Data](#querying-data)
- [Configuration](#configuration)
  - [config.yml](#configyml)
  - [MQTT Configuration](#mqtt-configuration)
  - [Node-RED Configuration](#node-red-configuration)
- [Customization](#customization)
  - [Adding New Sensors](#adding-new-sensors)
  - [Customizing Dashboards](#customizing-dashboards)
  - [Adding Custom Flows](#adding-custom-flows)
- [Troubleshooting](#troubleshooting)
  - [MQTT Issues](#mqtt-issues)
  - [Node-RED Issues](#node-red-issues)
  - [Dashboard Not Showing Data](#dashboard-not-showing-data)
- [API Reference](#api-reference)
- [Contributing](#contributing)
- [License](#license)

## Overview

SyHub is a comprehensive IoT platform designed for monitoring sensor data. It provides a complete infrastructure for:

- Collecting sensor data via MQTT
- Storing time series data in VictoriaMetrics
- Processing data flows with Node-RED
- Visualizing data through customizable dashboards

Perfect for home automation, environmental monitoring, agricultural projects, and more.

## Features

- **MQTT Broker**: Secure MQTT server for device communication
- **Time Series Database**: Efficient storage and querying of sensor data
- **Visual Flow Programming**: Node-RED for data processing and automation
- **Dashboards**: Real-time visualization of sensor data
- **Modular Architecture**: Easy to extend and customize
- **Low Resource Requirements**: Runs well on Raspberry Pi and similar devices

## Architecture

SyHub consists of several integrated components:

1. **Mosquitto MQTT Broker**: Handles device communication
2. **VictoriaMetrics**: Time series database for storing sensor data
3. **Node-RED**: Processing engine and dashboard provider
4. **Nginx**: Web server and reverse proxy (optional)

The typical data flow is:
- Sensors → MQTT → Node-RED → VictoriaMetrics → Dashboard

## Installation

### Prerequisites

- Raspberry Pi (3B+ or newer) or similar device
- Debian/Ubuntu based OS (Raspberry Pi OS recommended)
- At least 1GB RAM
- 8GB+ storage space
- Internet connection for package installation

### Setup Options

SyHub can be installed with different options depending on your needs:

- **Full Installation**: All components (recommended)
- **Component Selection**: Choose which components to install
- **Interactive Mode**: Guided installation with prompts
- **Non-Interactive Mode**: Automated installation with defaults

### Running the Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/syhub.git
   cd syhub
   ```

2. Run the setup script:
   ```bash
   sudo ./setup.sh -i
   ```
   The `-i` flag runs in interactive mode, allowing you to choose which components to install.

3. For a specific component installation:
   ```bash
   sudo ./setup.sh --components=mqtt,nodered
   ```

4. Once installation completes, the system will be running automatically and set to start on boot.

## Usage

### Accessing Dashboards

After installation, access your dashboards at:

- **Main Dashboard**: http://syhub.local:1880/ui
- **Node-RED Editor**: http://syhub.local:1880/admin
- **VictoriaMetrics**: http://syhub.local:8428

Default login credentials:
- **Node-RED**: Username: `admin`, Password: As configured during setup

### Sending Data to the System

Send sensor data to the MQTT broker using the topic format specified in your config:

```bash
mosquitto_pub -h syhub.local -p 1883 -u plantomioX1 -P plantomioX1Pass -t v1/devices/me/telemetry -m '{"deviceID":"plt-404cca470da0","temperature":"21.813","distance":"2.762","pH":"42.091"}'
```

For Arduino/ESP32/ESP8266 code examples, see the `examples` directory.

### Querying Data

Data can be queried directly from VictoriaMetrics:

```bash
curl -G "http://syhub.local:8428/api/v1/query" --data-urlencode "query=plnt_temperature{device=\"plt-404cca470da0\"}"
```

Or use the Node-RED flows to create custom queries.

## Configuration

### config.yml

The main configuration file is located at `config/config.yml`. Key settings include:

```yaml
project:
  name: plantomio            # Project name
  metrics_prefix: plnt_      # Prefix for VictoriaMetrics metrics

mqtt:
  port: 1883
  username: plantomioX1
  password: plantomioX1Pass
  topic_telemetry: v1/devices/me/telemetry

victoria_metrics:
  port: 8428
  retention_period: 1y

node_red:
  port: 1880
  username: admin
  password_hash: "$2b$08$..."
```

After modifying config.yml, run the setup script again to apply changes:

```bash
sudo ./setup.sh --components=mqtt
```

### MQTT Configuration

The MQTT broker configuration is managed by the setup script but can be manually adjusted at `/etc/mosquitto/mosquitto.conf`. Key settings:

```
per_listener_settings true
pid_file /run/mosquitto/mosquitto.pid
persistence true
persistence_location /var/lib/mosquitto/
log_dest file /var/log/mosquitto/mosquitto.log
allow_anonymous false
listener 1883 0.0.0.0  # Listen on all interfaces
password_file /etc/mosquitto/passwd
```

### Node-RED Configuration

Node-RED configuration is stored in `/home/youruser/.node-red/settings.js`. This includes:

- Authentication settings
- UI configuration
- Global context settings

## Customization

### Adding New Sensors

1. **Create MQTT Client**: Configure your sensors to publish data to the MQTT broker:
   ```
   Topic: v1/devices/me/telemetry
   Payload: {"deviceID":"your-device-id","sensorName1":"value1","sensorName2":"value2"}
   ```

2. **Update Flows**: In Node-RED, modify the existing flows or create new ones to process your sensor data.

3. **Add Dashboard Elements**: Create new dashboard nodes in Node-RED to visualize your sensor data.

### Customizing Dashboards

1. Access the Node-RED editor at http://syhub.local:1880/admin

2. Navigate to the "Plantomio" flow tab

3. Add dashboard nodes from the node palette:
   - Charts
   - Gauges
   - Text displays
   - Control buttons

4. Connect the dashboard nodes to your data flows

5. Deploy your changes

### Adding Custom Flows

1. Export your existing flows:
   ```bash
   sudo ./scripts/manage_flows.sh export
   ```

2. Edit the `node-red-files/flows.json` file or create new flows in the Node-RED editor

3. Import your modified flows:
   ```bash
   sudo ./scripts/manage_flows.sh import
   ```

## Troubleshooting

### MQTT Issues

If you're having trouble with MQTT:

1. Test the MQTT connection:
   ```bash
   sudo ./scripts/test_mqtt.sh
   ```

2. Check Mosquitto status:
   ```bash
   sudo systemctl status mosquitto
   ```

3. Verify the configuration:
   ```bash
   sudo mosquitto -t -c /etc/mosquitto/mosquitto.conf
   ```

4. Common issues:
   - Incorrect password in passwd file
   - Mosquitto not listening on all interfaces
   - Port conflicts

### Node-RED Issues

If Node-RED is not working correctly:

1. Check Node-RED status:
   ```bash
   sudo systemctl status nodered
   ```

2. View logs:
   ```bash
   sudo journalctl -u nodered -f
   ```

3. If authentication issues occur, reset the admin password:
   ```bash
   sudo nano /home/youruser/.node-red/settings.js
   # Comment out the adminAuth section temporarily
   sudo systemctl restart nodered
   ```

### Dashboard Not Showing Data

If your dashboard isn't showing data:

1. Verify data is being received via MQTT:
   ```bash
   mosquitto_sub -h localhost -p 1883 -u plantomioX1 -P plantomioX1Pass -t "v1/devices/me/telemetry" -v
   ```

2. Check VictoriaMetrics contains your data:
   ```bash
   curl -G "http://syhub.local:8428/api/v1/query" --data-urlencode "query=plnt_temperature"
   ```

3. In Node-RED, enable debug nodes to view the data flow

4. Make sure your queries include the correct prefix (default: `plnt_`)

## API Reference

### MQTT Topics

- `v1/devices/me/telemetry` - Send sensor data
- `v1/devices/me/attributes` - Send device attributes

### VictoriaMetrics API

- `/api/v1/query` - Instant queries
- `/api/v1/query_range` - Range queries
- `/api/v1/import/prometheus` - Import data in OpenMetrics format

For complete API details, see the [VictoriaMetrics documentation](https://docs.victoriametrics.com/).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 