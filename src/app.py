from flask import Flask, jsonify
import requests
import os
import yaml

app = Flask(__name__, static_folder='static')

# Read config.yml
with open(os.path.join(os.path.dirname(__file__), '../config/config.yml'), 'r') as f:
    config = yaml.safe_load(f)

VICTORIA_METRICS_PORT = config['victoria_metrics']['port']
HOSTNAME = config['hostname']

@app.route('/')
def index():
    return app.send_static_file('index.html')

@app.route('/data/<field>')
def data(field):
    try:
        response = requests.get(f'http://{HOSTNAME}:{VICTORIA_METRICS_PORT}/api/v1/query_range', params={
            'query': f'telemetry{{metric="{field}"}}',
            'start': 'now-1h',
            'step': '1m'
        })
        data = response.json()['data']['result'][0]['values']
        return jsonify([{'time': float(t), 'value': float(v)} for t, v in data])
    except Exception as e:
        return jsonify([]), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(config['dashboard']['port']))