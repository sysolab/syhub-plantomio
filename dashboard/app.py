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
UPDATE_INTERVAL = 1  # Faster update interval in seconds (was 5)

# Available metrics and their last known values
metrics = {
    "temperature": {"value": 0, "last_updated": None},
    "pH": {"value": 0, "last_updated": None},
    "EC": {"value": 0, "last_updated": None},
    "TDS": {"value": 0, "last_updated": None},
    "waterLevel": {"value": 0, "last_updated": None},
    "distance": {"value": 0, "last_updated": None}
}

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
            
            response = requests.get(query_url, params=params, timeout=1)  # Reduced timeout from 2s to 1s
            
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
        "waterLevel": 50,
        "distance": 10.0
    }
    
    for metric_name, default in default_values.items():
        if metric_name not in result:
            result[metric_name] = default
    
    return result

@app.route('/')
def index():
    """Main dashboard page"""
    return render_template('index.html', project_name=PROJECT_NAME)

@app.route('/settings')
def settings():
    """Settings page"""
    return render_template('settings.html', project_name=PROJECT_NAME)

@app.route('/trends')
def trends():
    """Trends and charts page"""
    return render_template('trends.html', project_name=PROJECT_NAME)

@app.route('/api/events')
def events():
    """SSE endpoint with real data from VictoriaMetrics"""
    def generate():
        try:
            # Send initial connection message
            yield f"data: {json.dumps({'status': 'connected', 'timestamp': datetime.now().isoformat()})}\n\n"
            
            # Send data updates every second
            while True:
                # Get the latest data
                current_data = get_current_values()
                yield f"data: {json.dumps(current_data)}\n\n"
                time.sleep(UPDATE_INTERVAL)  # Fast updates every second
        except Exception as e:
            app.logger.error(f"Error in SSE stream: {str(e)}")
            yield f"data: {{\"error\": \"{str(e)}\"}}\n\n"

    return Response(stream_with_context(generate()), 
                  mimetype="text/event-stream", 
                  headers={'Cache-Control': 'no-cache', 
                           'Connection': 'keep-alive',
                           'Access-Control-Allow-Origin': '*'})

@app.route('/api/tank-settings', methods=['GET', 'POST'])
def tank_settings():
    """Tank settings API"""
    if request.method == 'GET':
        return jsonify({
            "tankCapacity": 100,
            "alertLevel": 20,
            "units": "liters"
        })
    elif request.method == 'POST':
        # Just return success response for demo
        return jsonify({"status": "success"})

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
        
        # Parse time range parameters or use defaults
        hours = int(request.args.get('hours', 1))
        
        # Calculate time range
        now = int(time.time())
        start = now - (hours * 3600)  # Convert hours to seconds
        
        # Construct device filter if provided
        device_filter = f',device="{device_id}"' if device_id else ''
        
        # Query VictoriaMetrics for range data
        query_url = f"{VICTORIA_URL}/api/v1/query_range"
        params = {
            'query': f'{metric}{{{device_filter}}}',
            'start': start,
            'end': now,
            'step': '60s'  # 1-minute intervals
        }
        
        response = requests.get(query_url, params=params, timeout=5)
        
        if response.status_code == 200:
            data = response.json()
            # Check if we have actual data
            if data.get('data', {}).get('result') and len(data['data']['result']) > 0:
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
        resp = requests.get(f"{NODERED_URL}/", timeout=1)  # Reduced timeout from 2s to 1s
        services["node_red"]["status"] = "ok" if resp.status_code == 200 else "error"
    except:
        services["node_red"]["status"] = "error"
    
    # Check VictoriaMetrics
    try:
        resp = requests.get(f"{VICTORIA_URL}/health", timeout=1)  # Reduced timeout from 2s to 1s
        services["victoria_metrics"]["status"] = "ok" if resp.status_code == 200 else "error"
    except:
        services["victoria_metrics"]["status"] = "error"
    
    return jsonify({"status": "ok", "services": services})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=config['dashboard']['port'], debug=True) 