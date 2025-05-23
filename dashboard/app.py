"""
Modified app.py with optimized API endpoints for more efficient data handling
Key changes:
1. Improved error handling in trend data processing
2. Optimized VictoriaMetrics query format
3. Better data structure for frontend consumption
4. Fixed data format issues between VM and frontend
"""

import os
import json
import time
import yaml
import requests
from datetime import datetime, timedelta
from flask import Flask, render_template, request, Response, jsonify, stream_with_context

# Load config
config_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'config/config.yml')
with open(config_path, 'r') as file:
    config = yaml.safe_load(file)

app = Flask(__name__)

# Configuration
NODERED_URL = f"http://localhost:{config['node_red']['port']}"
VICTORIA_URL = f"http://localhost:{config['victoria_metrics']['port']}"
PROJECT_NAME = config['project']['name']
UPDATE_INTERVAL = 60  # Update interval in seconds

# Available metrics and their last known values
metrics = {
    "temperature": {"value": 0, "last_updated": None},
    "pH": {"value": 0, "last_updated": None},
    "EC": {"value": 0, "last_updated": None},
    "TDS": {"value": 0, "last_updated": None},
    "waterLevel": {"value": 0, "last_updated": None},
    "distance": {"value": 0, "last_updated": None},
    "ORP": {"value": 0, "last_updated": None}
}

# Tank configuration with default values
tank_config = {
    "maxDistance": 3.0,  # m when tank is empty (0%)
    "minDistance": 0.3,    # m when tank is full (100%)
    "alertLevel": 10       # % alert level
}

# Calculate water level percentage based on distance and tank configuration
def calculate_water_level(distance):
    max_distance = tank_config["maxDistance"]
    min_distance = tank_config["minDistance"]
    
    # Handle invalid configurations
    if max_distance <= min_distance:
        return 50.0  # Return default if configuration is invalid
    
    # Calculate percentage (reverse scale - shorter distance means higher water level)
    level = ((max_distance - distance) / (max_distance - min_distance)) * 100
    
    # Clamp to 0-100 range
    return max(0, min(100, level))

def get_current_values():
    """Query VictoriaMetrics for the latest data points for each metric"""
    now = int(time.time())
    
    # Get the device list from VM
    devices = get_device_list()
    
    # Return early if no devices
    if not devices:
        return {
            "deviceID": None,
            "lastUpdate": datetime.now().isoformat(),
            "timestamp": now
        }
    
    # Use the first device or a provided default
    device_id = devices[0]
    
    result = {
        "deviceID": device_id,
        "lastUpdate": datetime.now().isoformat(),
        "timestamp": now
    }
    
    # Query each metric individually with improved error handling
    available_metrics = ["temperature", "pH", "EC", "TDS", "distance", "ORP"]
    metric_timestamps = []  # To track all timestamps from metrics
    
    for metric_name in available_metrics:
        try:
            # Use instant query for current value with timeout to prevent hanging
            query_url = f"{VICTORIA_URL}/api/v1/query"
            params = {
                'query': f'{metric_name}{{device="{device_id}"}}',
                'time': now
            }
            
            response = requests.get(query_url, params=params, timeout=2)
            
            if response.status_code == 200:
                data = response.json()
                if data.get('data', {}).get('result') and len(data['data']['result']) > 0:
                    # Get the first result and extract value and timestamp
                    first_result = data['data']['result'][0]
                    if 'value' in first_result:
                        value = first_result['value'][1]
                        timestamp = int(first_result['value'][0])
                        
                        # Keep track of the timestamp for this metric
                        metric_timestamps.append(timestamp)
                        
                        # Skip NaN values but include them in result as null for proper handling
                        if value == "NaN" or value == "nan":
                            result[metric_name] = None
                        else:
                            try:
                                # Always convert to float for consistency
                                value = float(value)
                                # Store in metrics cache
                                metrics[metric_name]['value'] = value
                                metrics[metric_name]['last_updated'] = timestamp
                                result[metric_name] = value
                            except ValueError:
                                # If conversion fails, use null
                                result[metric_name] = None
        except Exception as e:
            app.logger.error(f"Error querying {metric_name}: {str(e)}")
            
            # Use cached value if available, otherwise set to null
            if metrics[metric_name]['last_updated']:
                result[metric_name] = metrics[metric_name]['value']
            else:
                result[metric_name] = None
    
    # Use the latest timestamp as the device timestamp
    if metric_timestamps:
        result["timestamp"] = max(metric_timestamps)
    
    # Calculate water level if we have distance
    if "distance" in result and result["distance"] is not None:
        try:
            # Ensure distance is a float for calculation
            distance_value = float(result["distance"]) if isinstance(result["distance"], str) else result["distance"]
            result["waterLevel"] = calculate_water_level(distance_value)
        except (ValueError, TypeError):
            result["waterLevel"] = 50.0  # Default if conversion fails
    elif "waterLevel" not in result:
        result["waterLevel"] = 50.0  # Default water level
    
    return result

def get_device_list():
    """Get list of available devices from VictoriaMetrics with improved error handling"""
    try:
        # Query for a common metric to get device list with increased timeout
        query_url = f"{VICTORIA_URL}/api/v1/query"
        params = {
            'query': 'temperature',  # Use temperature as it's likely always present
        }
        
        response = requests.get(query_url, params=params, timeout=3)
        
        if response.status_code == 200:
            data = response.json()
            devices = []
            
            if data.get('data', {}).get('result'):
                for result in data['data']['result']:
                    if 'metric' in result and 'device' in result['metric']:
                        devices.append(result['metric']['device'])
            
            # Deduplicate the list
            return list(set(devices))
        return ['plt-404cca470da0']  # Fallback to default if query fails
    except Exception as e:
        app.logger.error(f"Error getting device list: {str(e)}")
        return ['plt-404cca470da0']  # Fallback to default

@app.route('/')
def index():
    """Main dashboard page"""
    return render_template('index.html', project_name=PROJECT_NAME)

@app.route('/settings')
def settings():
    """Settings page"""
    return render_template('settings.html', project_name=PROJECT_NAME, config=config, tank_config=tank_config)

@app.route('/trends')
def trends():
    """Trends and charts page"""
    return render_template('trends.html', project_name=PROJECT_NAME)

@app.route('/api/events')
def events():
    """SSE endpoint with real data from VictoriaMetrics"""
    def generate():
        last_sent_timestamp = 0
        
        try:
            # Send initial connection message
            yield f"data: {json.dumps({'status': 'connected', 'timestamp': datetime.now().isoformat()})}\n\n"
            
            # Send data updates only when new device data is available
            max_time = 25  # seconds (just under gunicorn's default 30 sec timeout)
            start_time = time.time()
            
            while (time.time() - start_time) < max_time:
                # Get the latest data
                current_data = get_current_values()
                
                # Check if data has a new timestamp from the device
                device_timestamp = current_data.get("timestamp", 0)
                
                # Only send data if it's truly a new reading with a new timestamp
                if device_timestamp > last_sent_timestamp:
                    # Update last sent timestamp
                    last_sent_timestamp = device_timestamp
                    
                    # Send the new data
                    yield f"data: {json.dumps(current_data)}\n\n"
                
                # Sleep for update interval, but don't exceed max time
                remaining = max(0, min(UPDATE_INTERVAL, max_time - (time.time() - start_time)))
                if remaining > 0:
                    time.sleep(remaining)
                else:
                    break
                    
            # Tell client to reconnect
            yield f"retry: 100\n\n"
            
        except Exception as e:
            app.logger.error(f"Error in SSE stream: {str(e)}")
            yield f"data: {{\"error\": \"{str(e)}\"}}\n\n"
            # Add retry directive for client
            yield f"retry: 5000\n\n"

    return Response(stream_with_context(generate()), 
                  mimetype="text/event-stream", 
                  headers={'Cache-Control': 'no-cache', 
                           'Connection': 'keep-alive',
                           'X-Accel-Buffering': 'no',
                           'Access-Control-Allow-Origin': '*'})

@app.route('/api/tank-settings', methods=['GET', 'POST'])
def tank_settings():
    """Tank settings API"""
    global tank_config
    
    if request.method == 'GET':
        return jsonify(tank_config)
    elif request.method == 'POST':
        try:
            data = request.get_json()
            
            # Update configuration if valid values provided
            if 'maxDistance' in data and isinstance(data['maxDistance'], (int, float)) and data['maxDistance'] > 0:
                tank_config['maxDistance'] = float(data['maxDistance'])
            
            if 'minDistance' in data and isinstance(data['minDistance'], (int, float)) and data['minDistance'] >= 0:
                tank_config['minDistance'] = float(data['minDistance'])
            
            if 'alertLevel' in data and isinstance(data['alertLevel'], (int, float)) and 0 <= data['alertLevel'] <= 100:
                tank_config['alertLevel'] = float(data['alertLevel'])
                
            return jsonify({"status": "success", "config": tank_config})
        except Exception as e:
            app.logger.error(f"Error updating tank settings: {str(e)}")
            return jsonify({"status": "error", "message": str(e)}), 400

@app.route('/api/latest')
def latest_data():
    """Get latest sensor data from VictoriaMetrics"""
    try:
        # Get current values from VictoriaMetrics
        current_data = get_current_values()
        return jsonify(current_data)
    except Exception as e:
        app.logger.error(f"Error fetching latest data: {str(e)}")
        return jsonify({"status": "error", "error": str(e)}), 500

@app.route('/api/query')
def query_data():
    """Query historical data from VictoriaMetrics"""
    try:
        # Get parameters
        metric = request.args.get('metric', 'temperature')
        device_id = request.args.get('device', '')
        
        # Parse time range parameters (default to last 24 hours)
        minutes = int(request.args.get('minutes', 1440))
        
        # Get custom step size if provided, otherwise calculate based on time range
        step_size = request.args.get('step')
        
        # Calculate time range
        now = int(time.time())
        start = now - (minutes * 60)
        
        # Construct device filter if provided
        device_filter = f',device="{device_id}"' if device_id else ''
        
        # If step size is not provided, calculate it based on time range
        if not step_size:
            if minutes >= 10080:  # 7 days
                step_size = '2h'
            elif minutes >= 1440:  # 24 hours
                step_size = '15m'
            elif minutes >= 720:  # 12 hours
                step_size = '8m'
            else:
                step_size = '1m'
        
        # Construct query
        query = f'{metric}{{{device_filter}}}'
        
        params = {
            'query': query,
            'start': start,
            'end': now,
            'step': step_size
        }
        
        app.logger.info(f"VM Query: {query}, Step: {step_size}")
        
        # Increase timeout for larger queries
        response = requests.get(f"{VICTORIA_URL}/api/v1/query_range", params=params, timeout=10)
        
        if response.status_code == 200:
            data = response.json()
            
            # Process data for frontend consumption
            if data.get('data', {}).get('result') and len(data['data']['result']) > 0:
                result = data['data']['result'][0]
                
                # Process values to handle NaN
                if 'values' in result:
                    processed_values = []
                    
                    for timestamp, value in result['values']:
                        if value == "NaN" or value == "nan":
                            processed_values.append([timestamp, None])
                        else:
                            try:
                                processed_values.append([timestamp, float(value)])
                            except ValueError:
                                processed_values.append([timestamp, None])
                    
                    # Replace values with processed ones
                    result['values'] = processed_values
            
            return jsonify({"status": "success", "data": data})
        
        # Return empty result with success status if no data
        return jsonify({
            "status": "success",
            "data": {
                "resultType": "matrix",
                "result": []
            }
        })
    except Exception as e:
        app.logger.error(f"Error querying data: {str(e)}", exc_info=True)
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/trends')
def trends_data():
    """Query multiple metrics over time for trends page"""
    try:
        # Get parameters
        metrics_str = request.args.get('metrics', 'temperature,pH,EC,TDS,distance,ORP')
        metrics_list = metrics_str.split(',')
        device_id = request.args.get('device', '')
        
        # Parse time range (default to last 24 hours)
        try:
            minutes = int(request.args.get('minutes', 1440))
        except ValueError:
            minutes = 1440
            
        # Get custom step size if provided
        step_size = request.args.get('step')
        
        # Calculate time range
        now = int(time.time())
        start = now - (minutes * 60)
        
        # Initialize results
        results = {}
        
        # Process each metric
        for metric in metrics_list:
            metric = metric.strip()
            if not metric:
                continue
                
            try:
                # Build device filter
                device_filter = f'device="{device_id}"' if device_id else ''
                
                # Build query
                query = f'{metric}{{{device_filter}}}' if device_filter else metric
                
                # If step size is not provided, calculate it based on time range
                current_step = step_size
                if not current_step:
                    if minutes >= 10080:  # 7 days
                        current_step = '2h'
                    elif minutes >= 1440:  # 24 hours
                        current_step = '15m'
                    elif minutes >= 720:  # 12 hours
                        current_step = '8m'
                    else:
                        current_step = '1m'
                
                # Query Victoria Metrics
                query_url = f"{VICTORIA_URL}/api/v1/query_range"
                params = {
                    'query': query,
                    'start': start,
                    'end': now,
                    'step': current_step
                }
                
                app.logger.info(f"VM Query: {query}, Step: {current_step}")
                
                # Use longer timeout for range queries
                response = requests.get(query_url, params=params, timeout=10)
                
                # Process response
                values = []
                if response.status_code == 200:
                    data = response.json()
                    
                    if data.get('data', {}).get('result') and len(data['data']['result']) > 0:
                        result = data['data']['result'][0]
                        
                        if 'values' in result:
                            for point in result['values']:
                                if len(point) == 2:
                                    timestamp, value = point
                                    
                                    # Handle NaN values
                                    if value == "NaN" or value == "nan":
                                        values.append([int(timestamp), None])
                                    else:
                                        try:
                                            values.append([int(timestamp), float(value)])
                                        except (ValueError, TypeError):
                                            values.append([int(timestamp), None])
                
                # Store in results
                results[metric] = values
            except Exception as e:
                app.logger.error(f"Error processing metric {metric}: {str(e)}")
                results[metric] = []
        
        return jsonify({"status": "success", "data": results})
    except Exception as e:
        app.logger.error(f"Error in trends_data: {str(e)}", exc_info=True)
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/health')
def health_check():
    """Enhanced health check endpoint"""
    services = {
        "dashboard": {"status": "ok"},
        "node_red": {"status": "unknown"},
        "victoria_metrics": {"status": "unknown"},
        "mqtt": {"status": "unknown"},
        "ap_mode": {"status": "unknown"}
    }
    
    # Check Node-RED
    try:
        import socket
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(1)
        result = s.connect_ex(('localhost', config['node_red']['port']))
        services["node_red"]["status"] = "ok" if result == 0 else "error"
        s.close()
    except:
        services["node_red"]["status"] = "error"
    
    # Check VictoriaMetrics with timeout
    try:
        resp = requests.get(f"{VICTORIA_URL}/health", timeout=2)
        services["victoria_metrics"]["status"] = "ok" if resp.status_code == 200 else "error"
    except:
        services["victoria_metrics"]["status"] = "error"
    
    # Check MQTT (assuming standard port 1883)
    try:
        import socket
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(1)
        result = s.connect_ex(('localhost', 1883))
        services["mqtt"]["status"] = "ok" if result == 0 else "error"
        s.close()
    except:
        # If we can't check MQTT, leave as unknown
        pass
    
    # Check AP mode status using system commands
    try:
        import subprocess
        result = subprocess.run(["iwconfig"], capture_output=True, text=True)
        if "Mode:Master" in result.stdout:
            services["ap_mode"]["status"] = "ok"
        else:
            services["ap_mode"]["status"] = "inactive"
    except:
        # If can't check AP mode, leave as unknown
        pass
    
    return jsonify({"status": "ok", "services": services})

@app.route('/api/devices')
def devices():
    """Get a list of available devices"""
    try:
        devices = get_device_list()
        return jsonify({"status": "success", "devices": devices})
    except Exception as e:
        app.logger.error(f"Error fetching devices: {str(e)}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/export')
def export_data():
    """Export full resolution data without step size for a given metric"""
    try:
        # Get parameters
        metric = request.args.get('metric', 'temperature')
        device_id = request.args.get('device', '')
        
        # Parse time range parameters (default to last 24 hours)
        minutes = int(request.args.get('minutes', 1440))
        
        # Calculate time range
        now = int(time.time())
        start = now - (minutes * 60)
        
        # Construct device filter if provided
        device_filter = f',device="{device_id}"' if device_id else ''
        
        # Construct query - we don't use step size for export to get all data points
        query = f'{metric}{{{device_filter}}}'
        
        params = {
            'query': query,
            'start': start,
            'end': now
        }
        
        app.logger.info(f"Export Query: {query} (full resolution)")
        
        # Increase timeout for export queries as they might be larger
        response = requests.get(f"{VICTORIA_URL}/api/v1/query_range", params=params, timeout=20)
        
        if response.status_code == 200:
            data = response.json()
            
            # Process data for export
            result = {
                "status": "success",
                "metric": metric,
                "device": device_id,
                "data": []
            }
            
            if data.get('data', {}).get('result') and len(data['data']['result']) > 0:
                values = data['data']['result'][0].get('values', [])
                
                for timestamp, value in values:
                    try:
                        if value != "NaN" and value != "nan":
                            result["data"].append({
                                "timestamp": int(timestamp),
                                "datetime": datetime.fromtimestamp(int(timestamp)).strftime('%Y-%m-%d %H:%M:%S'),
                                "value": float(value)
                            })
                    except (ValueError, TypeError):
                        # Skip invalid values
                        pass
            
            return jsonify(result)
        
        return jsonify({"status": "error", "message": "No data available"}), 404
    except Exception as e:
        app.logger.error(f"Error exporting data: {str(e)}", exc_info=True)
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=config['dashboard']['port'], debug=True)