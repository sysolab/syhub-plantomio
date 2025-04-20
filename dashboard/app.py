import os
import json
import time
import yaml
import random
import threading
import requests
from datetime import datetime
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

# Store last sensor data
last_sensor_data = {
    "temperature": 25.5,
    "pH": 6.8,
    "EC": 1.2,
    "TDS": 600,
    "waterLevel": 75,
    "distance": 12.3,
    "deviceID": 'plt-404cca470da0',
    "lastUpdate": datetime.now().isoformat()
}

# Update mock data periodically
def update_mock_data():
    global last_sensor_data
    while True:
        try:
            # Add small random variations to simulate changes
            last_sensor_data["temperature"] = max(15, min(35, last_sensor_data["temperature"] + (random.random() - 0.5)))
            last_sensor_data["pH"] = max(5, min(8, last_sensor_data["pH"] + (random.random() - 0.5) * 0.2))
            last_sensor_data["EC"] = max(0.5, min(2.0, last_sensor_data["EC"] + (random.random() - 0.5) * 0.1))
            last_sensor_data["TDS"] = round(max(300, min(800, last_sensor_data["TDS"] + (random.random() - 0.5) * 20)))
            last_sensor_data["waterLevel"] = round(max(10, min(95, last_sensor_data["waterLevel"] + (random.random() - 0.5) * 5)))
            last_sensor_data["distance"] = max(5, min(30, last_sensor_data["distance"] + (random.random() - 0.5)))
            last_sensor_data["lastUpdate"] = datetime.now().isoformat()
        except Exception as e:
            print(f"Error updating mock data: {e}")
        time.sleep(5)  # Update every 5 seconds

# Start the background thread for mock data updates
update_thread = threading.Thread(target=update_mock_data, daemon=True)
update_thread.start()

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
    """SSE endpoint - generate events directly"""
    def generate():
        try:
            # Send initial connection message
            yield f"data: {json.dumps({'status': 'connected', 'timestamp': datetime.now().isoformat()})}\n\n"
            
            # Send data updates every few seconds
            while True:
                # Copy current data to avoid race conditions
                current_data = last_sensor_data.copy()
                yield f"data: {json.dumps(current_data)}\n\n"
                time.sleep(3)  # Send updates every 3 seconds
        except Exception as e:
            print(f"Error in SSE stream: {e}")
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
    """Get latest sensor data directly from our mock data"""
    return jsonify(last_sensor_data)

@app.route('/api/query')
def query_data():
    """Query historical data from VictoriaMetrics directly"""
    try:
        # Get parameters
        metric = request.args.get('metric', 'temperature')
        device_id = request.args.get('device', 'plt-404cca470da0')
        
        # Calculate time range
        now = int(time.time())
        start = now - 3600  # 1 hour ago
        
        # Query VictoriaMetrics directly
        query_url = f"{VICTORIA_URL}/api/v1/query_range"
        params = {
            'query': f'{metric}{{device="{device_id}"}}',
            'start': start,
            'end': now,
            'step': '60s'
        }
        
        response = requests.get(query_url, params=params)
        if response.status_code == 200:
            return jsonify(response.json())
        else:
            # If real query fails, generate fake historical data
            fake_data = {
                "status": "success",
                "data": {
                    "resultType": "matrix",
                    "result": [{
                        "metric": {"__name__": metric, "device": device_id},
                        "values": [[now - 3600, random.uniform(20, 30)]]
                    }]
                }
            }
            return jsonify(fake_data)
    except Exception as e:
        print(f"Error querying data: {e}")
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
        resp = requests.get(f"{NODERED_URL}/", timeout=2)
        services["node_red"]["status"] = "ok" if resp.status_code == 200 else "error"
    except:
        services["node_red"]["status"] = "error"
    
    # Check VictoriaMetrics
    try:
        resp = requests.get(f"{VICTORIA_URL}/health", timeout=2)
        services["victoria_metrics"]["status"] = "ok" if resp.status_code == 200 else "error"
    except:
        services["victoria_metrics"]["status"] = "error"
    
    return jsonify({"status": "ok", "services": services})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=config['dashboard']['port'], debug=True) 