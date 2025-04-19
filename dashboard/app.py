import os
import json
import time
import yaml
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
    """SSE endpoint - proxy to Node-RED SSE endpoint"""
    def generate():
        # Forward the SSE request to Node-RED
        req = requests.get(f"{NODERED_URL}/api/events", stream=True)
        for line in req.iter_lines():
            if line:
                yield f"{line.decode('utf-8')}\n\n"
            time.sleep(0.01)  # Small delay to reduce CPU usage

    return Response(stream_with_context(generate()), 
                  mimetype="text/event-stream", 
                  headers={'Cache-Control': 'no-cache', 
                           'Connection': 'keep-alive'})

@app.route('/api/tank-settings', methods=['GET', 'POST'])
def tank_settings():
    """Proxy for tank settings API"""
    if request.method == 'GET':
        response = requests.get(f"{NODERED_URL}/api/tank-settings")
        return jsonify(response.json())
    elif request.method == 'POST':
        data = request.json
        response = requests.post(f"{NODERED_URL}/api/tank-settings", json=data)
        return jsonify(response.json())

@app.route('/api/latest')
def latest_data():
    """Get latest sensor data"""
    response = requests.get(f"{NODERED_URL}/api/latest")
    return jsonify(response.json())

@app.route('/api/query')
def query_data():
    """Query historical data"""
    # Forward query parameters to Node-RED API
    params = request.args.to_dict()
    response = requests.get(f"{NODERED_URL}/api/query", params=params)
    return jsonify(response.json())

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
        resp = requests.get(f"{NODERED_URL}/api/latest", timeout=2)
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