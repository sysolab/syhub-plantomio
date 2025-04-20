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
UPDATE_INTERVAL = 1  # Update interval in seconds

# Available metrics and their last known values
metrics = {
    "temperature": {"value": 0, "last_updated": None},
    "pH": {"value": 0, "last_updated": None},
    "EC": {"value": 0, "last_updated": None},
    "TDS": {"value": 0, "last_updated": None},
    "waterLevel": {"value": 0, "last_updated": None},
    "distance": {"value": 0, "last_updated": None}
}

# Tank configuration with default values
tank_config = {
    "maxDistance": 50.0,  # cm when tank is empty (0%)
    "minDistance": 5.0,    # cm when tank is full (100%)
    "alertLevel": 20       # % alert level
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
    result = {
        "deviceID": "plt-404cca470da0",
        "lastUpdate": datetime.now().isoformat()
    }
    
    # Current timestamp for instant queries
    now = int(time.time())
    
    # Query each metric individually
    for metric_name in metrics.keys():
        try:
            # Use instant query for current value
            query_url = f"{VICTORIA_URL}/api/v1/query"
            params = {
                'query': f'{metric_name}{{}}',  # Query all devices
                'time': now
            }
            
            response = requests.get(query_url, params=params, timeout=1)
            
            if response.status_code == 200:
                data = response.json()
                if data.get('data', {}).get('result') and len(data['data']['result']) > 0:
                    # Get the first result and extract value and timestamp
                    first_result = data['data']['result'][0]
                    if 'value' in first_result:
                        value = float(first_result['value'][1])
                        timestamp = first_result['value'][0]
                        
                        # Store in metrics cache
                        metrics[metric_name]['value'] = value
                        metrics[metric_name]['last_updated'] = timestamp
                        
                        # Add to result
                        result[metric_name] = value
        except Exception as e:
            app.logger.error(f"Error querying {metric_name}: {str(e)}")
            
            # Use cached value if available, otherwise default value
            if metrics[metric_name]['last_updated']:
                result[metric_name] = metrics[metric_name]['value']
    
    # Add default values for missing metrics
    default_values = {
        "temperature": 25.0,
        "pH": 7.0,
        "EC": 1.0,
        "TDS": 500,
        "distance": 10.0
    }
    
    for metric_name, default in default_values.items():
        if metric_name not in result:
            result[metric_name] = default
    
    # Calculate water level if we have distance
    if "distance" in result:
        result["waterLevel"] = calculate_water_level(result["distance"])
    elif "waterLevel" not in result:
        result["waterLevel"] = 50.0  # Default water level
    
    return result

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
        
        try:
            # Send initial connection message
            yield f"data: {json.dumps({'status': 'connected', 'timestamp': datetime.now().isoformat()})}\n\n"
            
            # Send data updates every second
            while True:
                # Get the latest data
                current_data = get_current_values()
                
                # Check if data is different from last sent
                current_hash = hash(json.dumps(current_data, sort_keys=True))
                if current_hash not in sent_data or len(sent_data) > 100:
                    # Reset sent_data if it gets too large
                    if len(sent_data) > 100:
                        sent_data = {}
                    
                    # Add current hash to sent data
                    sent_data[current_hash] = time.time()
                    
                    # Send data
                    yield f"data: {json.dumps(current_data)}\n\n"
                
                # Sleep for update interval
                time.sleep(UPDATE_INTERVAL)
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
        
        # Parse time range parameters (default to last 10 minutes)
        minutes = int(request.args.get('minutes', 10))
        
        # Calculate time range
        now = int(time.time())
        start = now - (minutes * 60)  # Convert minutes to seconds
        
        # Construct device filter if provided
        device_filter = f',device="{device_id}"' if device_id else ''
        
        # Query VictoriaMetrics for range data
        query_url = f"{VICTORIA_URL}/api/v1/query_range"
        params = {
            'query': f'{metric}{{{device_filter}}}',
            'start': start,
            'end': now,
            'step': '10s'  # 10-second intervals for more detail
        }
        
        response = requests.get(query_url, params=params, timeout=5)
        
        if response.status_code == 200:
            data = response.json()
            # Check if we have actual data
            if data.get('data', {}).get('result') and len(data['data']['result']) > 0:
                result = data['data']['result'][0]
                
                # Filter out duplicate timestamps and keep only unique data points
                unique_values = []
                seen_timestamps = set()
                
                if 'values' in result:
                    for timestamp, value in result['values']:
                        if timestamp not in seen_timestamps:
                            seen_timestamps.add(timestamp)
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
        metrics_list = request.args.get('metrics', 'temperature,pH,EC,TDS,waterLevel').split(',')
        
        # Parse time range (default to last 10 minutes)
        minutes = int(request.args.get('minutes', 10))
        
        # Calculate time range
        now = int(time.time())
        start = now - (minutes * 60)  # Convert minutes to seconds
        
        results = {}
        
        # Query each metric
        for metric in metrics_list:
            try:
                query_url = f"{VICTORIA_URL}/api/v1/query_range"
                params = {
                    'query': f'{metric}{{}}',
                    'start': start,
                    'end': now,
                    'step': '10s'  # 10-second intervals
                }
                
                response = requests.get(query_url, params=params, timeout=3)
                if response.status_code == 200:
                    data = response.json()
                    if data.get('data', {}).get('result') and len(data['data']['result']) > 0:
                        # Extract unique timestamps and values
                        values = []
                        seen_timestamps = set()
                        
                        for point in data['data']['result'][0].get('values', []):
                            timestamp, value = point
                            if timestamp not in seen_timestamps:
                                seen_timestamps.add(timestamp)
                                values.append([timestamp, value])
                        
                        results[metric] = values
            except Exception as e:
                app.logger.error(f"Error querying {metric} for trends: {str(e)}")
        
        return jsonify({"status": "success", "data": results})
    except Exception as e:
        app.logger.error(f"Error fetching trends data: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/health')
def health_check():
    """Simple health check endpoint"""
    services = {
        "dashboard": {"status": "ok"},
        "node_red": {"status": "unknown"},
        "victoria_metrics": {"status": "unknown"}
    }
    
    # Check Node-RED
    try:
        resp = requests.get(f"{NODERED_URL}/", timeout=1)
        services["node_red"]["status"] = "ok" if resp.status_code == 200 else "error"
    except:
        services["node_red"]["status"] = "error"
    
    # Check VictoriaMetrics
    try:
        resp = requests.get(f"{VICTORIA_URL}/health", timeout=1)
        services["victoria_metrics"]["status"] = "ok" if resp.status_code == 200 else "error"
    except:
        services["victoria_metrics"]["status"] = "error"
    
    return jsonify({"status": "ok", "services": services})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=config['dashboard']['port'], debug=True) 