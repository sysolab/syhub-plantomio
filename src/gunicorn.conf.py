# Gunicorn configuration file for Plantomio
# Save this as /home/user/syhub/src/gunicorn.conf.py

import multiprocessing
import os

# Server socket
bind = "0.0.0.0:5000"  # Replace with your port from config
backlog = 2048

# Worker processes
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = 'gthread'
threads = 2
worker_connections = 1000
timeout = 30
keepalive = 2

# Process naming
proc_name = 'plantomio-dashboard'
pythonpath = '/home/user/syhub/src'  # Replace with your actual path

# Logging
accesslog = '/var/log/plantomio/access.log'
errorlog = '/var/log/plantomio/error.log'
loglevel = 'info'
access_log_format = '%({X-Real-IP}i)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s"'

# Server mechanics
daemon = False
pidfile = '/var/run/plantomio/gunicorn.pid'
umask = 0o27
user = 'user'  # Replace with your system username
group = 'user'  # Replace with your system group

# Max requests
max_requests = 1000
max_requests_jitter = 50

# SSL 
# keyfile = '/etc/ssl/private/key.pem'
# certfile = '/etc/ssl/certs/cert.pem'

# Environment variables
raw_env = [
    "PYTHONUNBUFFERED=1",
    "WEB_CONCURRENCY=2"
]

# Hooks
def on_starting(server):
    server.log.info("Starting Plantomio Dashboard")

def on_reload(server):
    server.log.info("Reloading Plantomio Dashboard")

def post_fork(server, worker):
    server.log.info("Worker spawned (pid: %s)", worker.pid)

def pre_fork(server, worker):
    pass

def pre_exec(server):
    server.log.info("Forked child, re-executing.")

# Startup
preload_app = True

# Ensure directories exist
os.makedirs('/var/log/plantomio', exist_ok=True)
os.makedirs('/var/run/plantomio', exist_ok=True)