#!/usr/bin/env python3
"""
VictoriaMetrics Query Helper

This script helps you verify what data exists in your VictoriaMetrics
database and how to query it correctly.
"""

import requests
import json
import argparse
import yaml
import os

# Read config
with open('../config/config.yml', 'r') as f:
    config = yaml.safe_load(f)

VICTORIA_METRICS_PORT = config['victoria_metrics']['port']
HOSTNAME = config['hostname']
BASE_URL = f"http://{HOSTNAME}:{VICTORIA_METRICS_PORT}"

def list_metrics():
    """List all metric names in the database"""
    response = requests.get(f"{BASE_URL}/api/v1/label/__name__/values")
    metrics = response.json()['data']
    print("Available metrics:")
    for metric in sorted(metrics):
        print(f"- {metric}")
    return metrics

def list_devices():
    """List all devices in the database"""
    response = requests.get(f"{BASE_URL}/api/v1/label/device/values")
    devices = response.json().get('data', [])
    if devices:
        print("\nAvailable devices:")
        for device in sorted(devices):
            print(f"- {device}")
    else:
        print("\nNo device labels found")
    return devices

def query_metric(metric_name):
    """Query a specific metric for the last hour"""
    print(f"\nQuerying for metric: {metric_name}")
    
    # Try different query formats
    queries = [
        f'{metric_name}', 
        f'{metric_name}{{}}',
        f'{metric_name}{{device=~".+"}}',
    ]
    
    for query in queries:
        print(f"\nTrying query: {query}")
        try:
            response = requests.get(f"{BASE_URL}/api/v1/query", params={
                'query': query,
            })
            
            data = response.json()
            if 'data' in data and 'result' in data['data'] and data['data']['result']:
                print(f"✅ Query successful! Found {len(data['data']['result'])} series")
                for idx, result in enumerate(data['data']['result']):
                    print(f"\nSeries {idx+1}:")
                    print(f"  Labels: {json.dumps(result['metric'])}")
                    if 'value' in result:
                        print(f"  Latest value: {result['value'][1]}")
                    elif 'values' in result:
                        print(f"  Values: {len(result['values'])} points")
                        if result['values']:
                            print(f"  Latest value: {result['values'][-1][1]}")
                return data
            else:
                print("❌ No data found with this query")
        except Exception as e:
            print(f"❌ Error: {e}")
    
    print("\nTroubleshooting tips:")
    print("1. Make sure data is being sent to VictoriaMetrics")
    print("2. Check your metric names and labels")
    print("3. Verify timestamps are not too old or in the future")
    return None

def main():
    parser = argparse.ArgumentParser(description='VictoriaMetrics Query Helper')
    parser.add_argument('--list-metrics', action='store_true', help='List all metrics')
    parser.add_argument('--list-devices', action='store_true', help='List all devices')
    parser.add_argument('--query', type=str, help='Query a specific metric')
    args = parser.parse_args()

    if args.list_metrics:
        list_metrics()
    if args.list_devices:
        list_devices()
    if args.query:
        query_metric(args.query)
    if not (args.list_metrics or args.list_devices or args.query):
        metrics = list_metrics()
        list_devices()
        if metrics:
            query_metric(metrics[0])

if __name__ == "__main__":
    main()