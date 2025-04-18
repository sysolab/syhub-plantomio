from flask import Flask, jsonify, request, send_from_directory
import requests
import os
import yaml
import multiprocessing
import logging
import time
from datetime import datetime, timedelta

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.FileHandler('/tmp/plantomio_dashboard.log'), logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

# Read config.yml
config_path = os.path.join(os.path.dirname(__file__), '../config/config.yml')
try:
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)
except Exception as e:
    logger.error(f"Failed to load config from {config_path}: {e}")
    config = {"hostname": "localhost", "victoria_metrics": {"port": 8428}, "dashboard": {"port": 5000}}

VICTORIA_METRICS_PORT = config['victoria_metrics']['port']
HOSTNAME = config['hostname']

app = Flask(__name__, static_folder='static')

# In-memory cache for data to reduce database load
data_cache = {}
cache_time = {}
CACHE_LIFETIME = 10  # Cache lifetime in seconds

@app.route('/')
def index():
    """Serve the main dashboard page."""
    try:
        return app.send_static_file('index.html')
    except Exception as e:
        logger.error(f"Error serving index.html: {e}")
        return "Error loading dashboard. Please check logs.", 500

@app.route('/static/<path:path>')
def static_files(path):
    """Serve static files with proper cache headers."""
    try:
        response = send_from_directory('static', path)
        # Set cache headers for better performance
        if path.endswith('.css') or path.endswith('.js'):
            response.headers['Cache-Control'] = 'public, max-age=86400'  # 1 day
        elif path.endswith('.png') or path.endswith('.jpg') or path.endswith('.svg'):
            response.headers['Cache-Control'] = 'public, max-age=604800'  # 1 week
        return response
    except Exception as e:
        logger.error(f"Error serving static file {path}: {e}")
        return "File not found", 404

@app.route('/sw.js')
def service_worker():
    """Serve the service worker for offline capabilities."""
    return app.send_static_file('js/sw.js')

@app.route('/api/latest')
def latest_data():
    """Return the latest values for all metrics in a single API call."""
    try:
        # Check if we have a 'since' parameter for conditional requests
        since_timestamp = request.args.get('since', None)
        
        # Use ETag for efficient data transfer
        request_etag = request.headers.get('If-None-Match', '')
        
        # Check if we have cached data that's still fresh
        cache_key = 'latest_data'
        if cache_key in data_cache and (time.time() - cache_time.get(cache_key, 0)) < CACHE_LIFETIME:
            cached_data = data_cache[cache_key]
            
            # If the client already has this data, return 304 Not Modified
            if request_etag and request_etag == cached_data.get('etag'):
                return '', 304
                
            # Return cached data with ETag
            response = jsonify(cached_data['data'])
            response.headers['ETag'] = cached_data['etag']
            return response
        
        # Build the optimal query for metrics
        metrics = ['temperature', 'pH', 'ORP', 'TDS', 'EC', 'distance']
        query_parts = []
        for metric in metrics:
            query_parts.append(f'{{{metric}{{}}}}')
        
        # Query all metrics at once for latest value
        result = {}
        
        # Make a single query to get the latest value for each metric
        query = '{__name__=~"temperature|pH|ORP|TDS|EC|distance"}'
        response = requests.get(f'http://{HOSTNAME}:{VICTORIA_METRICS_PORT}/api/v1/query', params={
            'query': query
        }, timeout=5)
        
        # If successful, extract data
        if response.status_code == 200:
            data = response.json()
            if 'data' in data and 'result' in data['data']:
                # Get deviceID if available
                device_id = None
                
                for item in data['data']['result']:
                    if '__name__' in item['metric']:
                        metric_name = item['metric']['__name__']
                        
                        # Get device ID if available
                        if 'device' in item['metric'] and not device_id:
                            device_id = item['metric']['device']
                            
                        if metric_name in metrics and 'value' in item:
                            timestamp, value = item['value']
                            result[metric_name] = {
                                'time': float(timestamp),
                                'value': float(value)
                            }
                
                # Add device ID if found
                if device_id:
                    result['deviceID'] = device_id
                
                # Also fetch some recent historical data for the charts
                timeSeriesData = {}
                
                # Only fetch historical data if we need to (new client, client specifies since, etc.)
                if not since_timestamp or not request_etag:
                    # Get last hour of data for each metric for time series
                    for metric in metrics:
                        query = f'{metric}{{device=~".+"}}'
                        try:
                            ts_response = requests.get(f'http://{HOSTNAME}:{VICTORIA_METRICS_PORT}/api/v1/query_range', params={
                                'query': query,
                                'start': 'now-1h',
                                'step': '1m'
                            }, timeout=5)
                            
                            if ts_response.status_code == 200:
                                ts_data = ts_response.json()
                                if 'data' in ts_data and 'result' in ts_data['data'] and ts_data['data']['result']:
                                    timeSeriesData[metric] = [
                                        {'time': float(t), 'value': float(v)} 
                                        for t, v in ts_data['data']['result'][0]['values']
                                    ]
                        except Exception as e:
                            logger.warning(f"Error fetching time series for {metric}: {e}")
                
                # Add time series data if we have it
                if timeSeriesData:
                    result['timeSeriesData'] = timeSeriesData
                
                # Generate ETag based on content
                import hashlib
                etag = hashlib.md5(str(result).encode()).hexdigest()
                
                # Cache the data
                data_cache[cache_key] = {
                    'data': result,
                    'etag': etag
                }
                cache_time[cache_key] = time.time()
                
                # Return response with ETag
                response = jsonify(result)
                response.headers['ETag'] = etag
                return response
        
        # If no data, return empty object
        logger.warning(f"No data found in VictoriaMetrics for latest metrics")
        return jsonify({})
        
    except Exception as e:
        logger.error(f"Error retrieving latest data: {e}")
        return jsonify({"error": "Failed to fetch data"}), 500

@app.route('/data/<field>')
def data(field):
    """Fetch time-series data for a specific field.
    
    Attempts to get the last hour of data. If no data is available in the last hour,
    falls back to the most recent data point.
    """
    try:
        # Check if we have cached data
        cache_key = f'data_{field}'
        if cache_key in data_cache and (time.time() - cache_time.get(cache_key, 0)) < CACHE_LIFETIME:
            return jsonify(data_cache[cache_key])
        
        logger.info(f"Fetching data for {field}")
        # Try to get the last hour of data
        response = requests.get(f'http://{HOSTNAME}:{VICTORIA_METRICS_PORT}/api/v1/query_range', params={
            'query': f'{field}{{device=~".+"}}',
            'start': 'now-1h',
            'step': '10s'
        }, timeout=5)
        
        data = response.json()
        if 'data' in data and 'result' in data['data'] and len(data['data']['result']) > 0:
            # Extract values from the response
            values = data['data']['result'][0]['values']
            result = [{'time': float(t), 'value': float(v)} for t, v in values]
            logger.info(f"Found {len(values)} data points for {field}")
            
            # Cache the result
            data_cache[cache_key] = result
            cache_time[cache_key] = time.time()
            
            return jsonify(result)
        else:
            logger.warning(f"No time series data found for {field}, trying latest value")
            # If no data in the last hour, try to get the most recent data point
            fallback_response = requests.get(f'http://{HOSTNAME}:{VICTORIA_METRICS_PORT}/api/v1/query', params={
                'query': f'{field}{{device=~".+"}}',
            }, timeout=5)
            
            fallback_data = fallback_response.json()
            if 'data' in fallback_data and 'result' in fallback_data['data'] and len(fallback_data['data']['result']) > 0:
                # Get most recent single value
                result = fallback_data['data']['result'][0]
                if 'value' in result:
                    timestamp, value = result['value']
                    result = [{'time': float(timestamp), 'value': float(value)}]
                    logger.info(f"Found latest value for {field}: {value} at {timestamp}")
                    
                    # Cache the result
                    data_cache[cache_key] = result
                    cache_time[cache_key] = time.time()
                    
                    return jsonify(result)
            
            # No data available at all
            logger.warning(f"No data available for {field}")
            return jsonify([])
    except Exception as e:
        logger.error(f"Error retrieving data for {field}: {e}")
        return jsonify([]), 500

@app.route('/api/system/info')
def system_info():
    """Return system information for the dashboard."""
    try:
        # CPU usage (simplified - in production use psutil)
        cpu_percent = 30  # Placeholder, use psutil in production
        
        # Memory usage (simplified)
        memory_percent = 45  # Placeholder, use psutil in production
        
        # Disk usage (simplified)
        disk_percent = 18  # Placeholder, use psutil in production
        
        # Network usage (simplified)
        network_percent = 70  # Placeholder, use psutil in production
        
        return jsonify({
            'cpu': {
                'percent': cpu_percent,
                'cores': multiprocessing.cpu_count()
            },
            'memory': {
                'percent': memory_percent
            },
            'disk': {
                'percent': disk_percent
            },
            'network': {
                'percent': network_percent
            }
        })
    except Exception as e:
        logger.error(f"Error getting system info: {e}")
        return jsonify({'error': str(e)}), 500

# Periodic cleanup of cache
def cleanup_cache():
    """Remove old items from cache."""
    current_time = time.time()
    for key in list(cache_time.keys()):
        if current_time - cache_time[key] > CACHE_LIFETIME:
            cache_time.pop(key, None)
            data_cache.pop(key, None)

# Regularly clean up cache
import threading
def start_cleanup_thread():
    threading.Timer(60.0, start_cleanup_thread).start()
    cleanup_cache()

# Start the cleanup thread when running directly
if __name__ == '__main__':
    # Start cache cleanup thread
    start_cleanup_thread()
    
    # Get number of CPU cores for gunicorn workers
    cores = multiprocessing.cpu_count()
    logger.info(f"Detected {cores} CPU cores")
    
    # Get port from config
    port = int(config['dashboard']['port'])
    logger.info(f"Starting development server on port {port}")
    
    # Run the Flask app directly (for development only)
    app.run(host='0.0.0.0', port=port, threaded=True)