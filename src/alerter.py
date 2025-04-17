import requests
import smtplib
from email.mime.text import MIMEText
import yaml
import os
import logging
import time

# Setup logging
logging.basicConfig(filename='/tmp/syhub_alerter.log', level=logging.INFO)

# Read config.yml
with open(os.path.join(os.path.dirname(__file__), '../config/config.yml'), 'r') as f:
    config = yaml.safe_load(f)

VICTORIA_METRICS_PORT = config['victoria_metrics']['port']
HOSTNAME = config['hostname']
EMAIL_SENDER = config['email']['sender']
EMAIL_PASSWORD = config['email']['password']
EMAIL_RECEIVER = config['email']['receiver']
SMTP_SERVER = config['email']['smtp_server']
SMTP_PORT = config['email']['smtp_port']

# Thresholds
THRESHOLDS = {
    "temperature": (10.0, 30.0),  # Min, Max
    "pH": (6.0, 8.0),
    "ORP": (200.0, 800.0),
    "TDS": (0.0, 1000.0),
    "EC": (0.0, 2.0),
    "distance": (0.0, 100.0)
}

def send_alert(field, value, threshold_min, threshold_max):
    subject = f"{config['project']['name']} Alert: {field} Out of Range"
    body = f"Value for {field} is {value}, outside acceptable range ({threshold_min}, {threshold_max})."
    msg = MIMEText(body)
    msg['Subject'] = subject
    msg['From'] = EMAIL_SENDER
    msg['To'] = EMAIL_RECEIVER

    try:
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.starttls()
            server.login(EMAIL_SENDER, EMAIL_PASSWORD)
            server.sendmail(EMAIL_SENDER, EMAIL_RECEIVER, msg.as_string())
        logging.info(f"Alert sent for {field}: {value}")
    except Exception as e:
        logging.error(f"Failed to send alert: {e}")

def check_thresholds():
    for field in THRESHOLDS:
        try:
            response = requests.get(f'http://{HOSTNAME}:{VICTORIA_METRICS_PORT}/api/v1/query', params={
                'query': f'telemetry{{metric="{field}"}}'
            })
            data = response.json()['data']['result']
            if data:
                value = float(data[0]['value'][1])
                min_val, max_val = THRESHOLDS[field]
                if value < min_val or value > max_val:
                    send_alert(field, value, min_val, max_val)
        except Exception as e:
            logging.error(f"Error checking {field}: {e}")

while True:
    try:
        check_thresholds()
    except Exception as e:
        logging.error(f"Error checking thresholds: {e}")
    time.sleep(300)  # Check every 5 minutes