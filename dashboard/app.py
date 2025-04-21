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
UPDATE_INTERVAL = 60  # Update interval in seconds - CHANGED from 1 to 60 seconds to match device frequency

# Available metrics and their last known values
metrics = {
    "temperature": {"value": 0, "last_updated": None},
    "pH": {"value": 0, "last_updated": None},
    "EC": {"value": 0, "last_updated": None},
    "TDS": {"value": 0, "last_updated": None},
    "waterLevel": {"value": 0, "last_updated": None},
    "distance": {"value": 0, "last_updated": None},
    "ORP": {"value": 0, "last_updated": None}  # Added ORP to available metrics
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
        "timestamp": now  # Default to current time, will be updated if we find an actual timestamp
    }
    
    # Query each metric individually
    available_metrics = ["temperature", "pH", "EC", "TDS", "distance", "ORP"]
    metric_timestamps = []  # To track all timestamps from metrics
    
    for metric_name in available_metrics:
        try:
            # Use instant query for current value
            query_url = f"{VICTORIA_URL}/api/v1/query"
            params = {
                'query': f'{metric_name}{{device="{device_id}"}}',  # Query specific device
                'time': now
            }
            
            response = requests.get(query_url, params=params, timeout=1)
            
            if response.status_code == 200:
                data = response.json()
                if data.get('data', {}).get('result') and len(data['data']['result']) > 0:
                    # Get the first result and extract value and timestamp
                    first_result = data['data']['result'][0]
                    if 'value' in first_result:
                        value = first_result['value'][1]
                        timestamp = int(first_result['value'][0])  # Ensure it's an integer
                        
                        # Keep track of the timestamp for this metric
                        metric_timestamps.append(timestamp)
                        
                        # Skip NaN values but include them in result as "NaN"
                        if value != "NaN" and value != "nan":
                            value = float(value)
                            # Store in metrics cache
                            metrics[metric_name]['value'] = value
                            metrics[metric_name]['last_updated'] = timestamp
                        
                        # Always add to result, even if NaN
                        result[metric_name] = value
        except Exception as e:
            app.logger.error(f"Error querying {metric_name}: {str(e)}")
            
            # Use cached value if available, otherwise default value
            if metrics[metric_name]['last_updated']:
                result[metric_name] = metrics[metric_name]['value']
    
    # Use the latest common timestamp as the device timestamp (all metrics should share the same timestamp)
    if metric_timestamps:
        # Find the most common timestamp (the one that appears most frequently)
        from collections import Counter
        timestamp_counts = Counter(metric_timestamps)
        most_common_timestamp = timestamp_counts.most_common(1)[0][0]
        result["timestamp"] = most_common_timestamp
    
    # Add default values for missing metrics
    default_values = {
        "temperature": 25.0,
        "pH": 7.0,
        "EC": 1.0,
        "TDS": 500,
        "distance": 10.0,
        "ORP": 300.0
    }
    
    for metric_name, default in default_values.items():
        if metric_name not in result:
            result[metric_name] = default
    
    # Calculate water level if we have distance
    if "distance" in result and result["distance"] != "NaN" and result["distance"] != "nan":
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
    """Get list of available devices from VictoriaMetrics"""
    try:
        # Query for a common metric to get device list
        query_url = f"{VICTORIA_URL}/api/v1/query"
        params = {
            'query': 'temperature',  # Use temperature as it's likely always present
        }
        
        response = requests.get(query_url, params=params, timeout=2)
        
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
        sent_data = {}  # Track previously sent data to avoid duplicates
        last_sent_timestamp = 0  # Track the last device timestamp we've sent
        
        try:
            # Send initial connection message
            yield f"data: {json.dumps({'status': 'connected', 'timestamp': datetime.now().isoformat()})}\n\n"
            
            # Send data updates only when new device data is available, limiting total time to avoid worker timeout
            max_time = 25  # seconds (just under gunicorn's default 30 sec timeout)
            start_time = time.time()
            
            while (time.time() - start_time) < max_time:
                # Get the latest data
                current_data = get_current_values()
                
                # Check if data has a new timestamp from the device (not just our query timestamp)
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
        return jsonify({"error": str(e)}), 500

@app.route('/api/query')
def query_data():
    """Query historical data from VictoriaMetrics"""
    try:
        # Get parameters
        metric = request.args.get('metric', 'temperature')
        device_id = request.args.get('device', '')
        
        # Parse time range parameters (default to last 24 hours)
        minutes = int(request.args.get('minutes', 1440))
        
        # Calculate time range
        now = int(time.time())
        start = now - (minutes * 60)  # Convert minutes to seconds
        
        # Construct device filter if provided - using device as the field name (from VM data)
        device_filter = f',device="{device_id}"' if device_id else ''
        
        # Log the request for debugging
        app.logger.info(f"Query data request: metric={metric}, device={device_id}, minutes={minutes}")
        
        # Query VictoriaMetrics for range data
        query_url = f"{VICTORIA_URL}/api/v1/query_range"
        
        # Optimize step size based on time range to reduce data points
        # This ensures we get a reasonable number of data points (~100) for any time range
        if minutes >= 10080:  # 7 days
            step_size = '2h'  # 2 hour intervals for week view (84 points)
        elif minutes >= 1440:  # 24 hours
            step_size = '15m'  # 15 minute intervals for day view (96 points)
        elif minutes >= 720:  # 12 hours
            step_size = '8m'  # 8 minute intervals (90 points)
        else:
            step_size = '1m'  # 1 minute for shorter ranges
        
        # Construct query with exact metric name
        query = f'{metric}{{{device_filter}}}'
        
        params = {
            'query': query,
            'start': start,
            'end': now,
            'step': step_size  # Optimized step size
        }
        
        # Log the actual query for debugging
        app.logger.info(f"VM Query: {query}")
        
        response = requests.get(query_url, params=params, timeout=5)
        
        if response.status_code == 200:
            data = response.json()
            
            # Log the result briefly for debugging
            result_count = len(data.get('data', {}).get('result', []))
            app.logger.info(f"VM Response for {metric}: got {result_count} results")
            
            # Check if we have actual data
            if data.get('data', {}).get('result') and len(data['data']['result']) > 0:
                result = data['data']['result'][0]
                
                # Filter out duplicate timestamps and keep only unique data points
                unique_values = []
                seen_timestamps = set()
                
                if 'values' in result:
                    for timestamp, value in result['values']:
                        # Include NaN values with null for proper gap rendering in chart
                        if value == "NaN" or value == "nan":
                            if timestamp not in seen_timestamps:
                                seen_timestamps.add(timestamp)
                                unique_values.append([timestamp, None])
                            continue
                            
                        if timestamp not in seen_timestamps:
                            seen_timestamps.add(timestamp)
                            try:
                                # Convert string values to floats for consistency
                                unique_values.append([timestamp, float(value)])
                            except (ValueError, TypeError):
                                # If conversion fails, include as string
                                unique_values.append([timestamp, value])
                    
                    # Replace the values with unique ones
                    result['values'] = unique_values
                    data['data']['result'][0] = result
                
                return jsonify(data)
        
        # If no data or query failed, return empty result structure
        return jsonify({
            "status": "success",
            "data": {
                "resultType": "matrix",
                "result": []
            }
        })
    except Exception as e:
        app.logger.error(f"Error querying data: {str(e)}")
        return jsonify({"error": str(e)}), 500

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
            minutes = int(request.args.get('minutes', 1440))  # Default to 24 hours
        except ValueError:
            minutes = 1440  # Fallback if parsing fails
        
        # Calculate time range
        now = int(time.time())
        start = now - (minutes * 60)  # Convert minutes to seconds
        
        # Construct device filter if provided - using device as the field name (from VM data)
        device_filter = f',device="{device_id}"' if device_id else ''
        
        # Optimize step size based on time range to reduce data points
        if minutes >= 10080:  # 7 days
            step_size = '2h'  # 2 hour intervals for week view (84 points)
        elif minutes >= 1440:  # 24 hours
            step_size = '15m'  # 15 minute intervals for day view (96 points)
        elif minutes >= 720:  # 12 hours
            step_size = '8m'  # 8 minute intervals (90 points)
        else:
            step_size = '1m'  # 1 minute for shorter ranges
        
        # Check if we need the older format used by trends.html or the newer format
        is_trends_page = 'trends=' in request.query_string.decode('utf-8')
        is_single_metric = len(metrics_list) == 1
        
        # This section is for the trends.html page that expects a specific format
        if request.path == '/api/trends' and not is_trends_page:
            # Create result object for each metric
            results = {}
            
            # Log the request for debugging
            app.logger.info(f"Trends data request: metrics={metrics_list}, device={device_id}, minutes={minutes}")
            
            # Query each metric
            for metric in metrics_list:
                try:
                    # Ensure exact case match for metric name in VM
                    metric_name = metric.strip()
                    if not metric_name:
                        continue
                    
                    query_url = f"{VICTORIA_URL}/api/v1/query_range"
                    query = f'{metric_name}{{{device_filter}}}'
                    
                    params = {
                        'query': query,
                        'start': start,
                        'end': now,
                        'step': step_size  # Optimized step size to reduce data volume
                    }
                    
                    # Log the specific query for debugging
                    app.logger.info(f"VM Query: {query}")
                    
                    response = requests.get(query_url, params=params, timeout=5)  # Increased timeout for bulk data
                    if response.status_code == 200:
                        data = response.json()
                        
                        # Format for trends.html
                        timestamps = []
                        values = []
                        
                        if data.get('data', {}).get('result') and len(data['data']['result']) > 0:
                            # Extract unique timestamps and values
                            seen_timestamps = set()
                            
                            for point in data['data']['result'][0].get('values', []):
                                try:
                                    timestamp, value = point
                                    
                                    # Include NaN values as null for proper gap rendering
                                    if value == "NaN" or value == "nan":
                                        if timestamp not in seen_timestamps:
                                            seen_timestamps.add(timestamp)
                                            # Format timestamp for display
                                            date = datetime.fromtimestamp(timestamp)
                                            time_str = date.strftime('%H:%M')
                                            timestamps.append(time_str)
                                            values.append(None)
                                        continue
                                        
                                    if timestamp not in seen_timestamps:
                                        seen_timestamps.add(timestamp)
                                        # Format timestamp for display
                                        date = datetime.fromtimestamp(timestamp)
                                        time_str = date.strftime('%H:%M')
                                        timestamps.append(time_str)
                                        try:
                                            # Convert string values to floats for consistent charting
                                            values.append(float(value))
                                        except (ValueError, TypeError):
                                            # If conversion fails, include as null
                                            values.append(None)
                                except Exception as e:
                                    app.logger.error(f"Error processing data point {point}: {str(e)}")
                                    # Skip this point if there's an error
                                    continue
                        
                        # Add to results
                        results[metric_name] = {
                            "timestamps": timestamps,
                            "values": values
                        }
                except Exception as e:
                    app.logger.error(f"Error querying {metric} for trends: {str(e)}")
                    # Continue with next metric
                    results[metric] = {
                        "timestamps": [],
                        "values": []
                    }
            
            return jsonify(results)
        # This is the original format used by the main dashboard
        else:
            # Legacy format with the "data" wrapper
            results = {}
            
            # Query each metric
            for metric in metrics_list:
                try:
                    # Ensure exact case match for metric name in VM
                    metric_name = metric.strip()
                    
                    query_url = f"{VICTORIA_URL}/api/v1/query_range"
                    query = f'{metric_name}{{{device_filter}}}'
                    
                    params = {
                        'query': query,
                        'start': start,
                        'end': now,
                        'step': step_size  # Optimized step size to reduce data volume
                    }
                    
                    # Log the specific query for debugging
                    app.logger.info(f"VM Query: {query}")
                    
                    response = requests.get(query_url, params=params, timeout=5)  # Increased timeout for bulk data
                    if response.status_code == 200:
                        data = response.json()
                        
                        if data.get('data', {}).get('result') and len(data['data']['result']) > 0:
                            # Extract unique timestamps and values
                            values = []
                            seen_timestamps = set()
                            
                            for point in data['data']['result'][0].get('values', []):
                                try:
                                    timestamp, value = point
                                    
                                    # Include NaN values as null for proper gap rendering
                                    if value == "NaN" or value == "nan":
                                        if timestamp not in seen_timestamps:
                                            seen_timestamps.add(timestamp)
                                            values.append([timestamp, None])
                                        continue
                                        
                                    if timestamp not in seen_timestamps:
                                        seen_timestamps.add(timestamp)
                                        try:
                                            # Convert string values to floats for consistent charting
                                            values.append([timestamp, float(value)])
                                        except (ValueError, TypeError):
                                            # If conversion fails, include as original value
                                            values.append([timestamp, value])
                                except Exception as e:
                                    app.logger.error(f"Error processing data point {point}: {str(e)}")
                                    # Skip this point if there's an error
                                    continue
                            
                            results[metric] = values
                except Exception as e:
                    app.logger.error(f"Error querying {metric} for trends: {str(e)}")
                    # Continue with next metric
            
            return jsonify({"status": "success", "data": results})
    except Exception as e:
        app.logger.error(f"Error fetching trends data: {str(e)}", exc_info=True)
        return jsonify({"status": "error", "error": str(e)}), 500

@app.route('/health')
def health_check():
    """Enhanced health check endpoint that also checks MQTT"""
    services = {
        "dashboard": {"status": "ok"},
        "node_red": {"status": "unknown"},
        "victoria_metrics": {"status": "unknown"},
        "mqtt": {"status": "unknown"},
        "ap_mode": {"status": "unknown"}
    }
    
    # Check Node-RED - just check if port is open instead of HTTP
    try:
        import socket
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(1)
        result = s.connect_ex(('localhost', config['node_red']['port']))
        services["node_red"]["status"] = "ok" if result == 0 else "error"
        s.close()
    except:
        services["node_red"]["status"] = "error"
    
    # Check VictoriaMetrics
    try:
        resp = requests.get(f"{VICTORIA_URL}/health", timeout=1)
        services["victoria_metrics"]["status"] = "ok" if resp.status_code == 200 else "error"
    except:
        services["victoria_metrics"]["status"] = "error"
    
    # Check MQTT (assuming standard port 1883)
    try:
        import socket
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(1)
        # Check if MQTT port is open (typically 1883)
        mqtt_port = 1883
        result = s.connect_ex(('localhost', mqtt_port))
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
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=config['dashboard']['port'], debug=True) 