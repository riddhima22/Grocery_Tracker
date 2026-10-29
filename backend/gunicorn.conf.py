import multiprocessing
import os

# Gunicorn configuration tailored for Render Free Tier (512MB RAM)
bind = f"0.0.0.0:{os.environ.get('PORT', '8000')}"

# Single worker with 2 threads prevents multi-worker memory exhaustion (OOM SIGKILL)
workers = 1
threads = 2

# Generous timeouts to prevent worker termination during complex AI operations
timeout = 120
graceful_timeout = 30
keepalive = 5

# Logging to standard output/error for Render log capture
accesslog = "-"
errorlog = "-"
loglevel = "info"
capture_output = True
