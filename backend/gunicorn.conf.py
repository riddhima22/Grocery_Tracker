import os

# Gunicorn configuration optimized for Render Free Tier (512MB RAM constraint)
# Setting workers=1 and threads=2 prevents out-of-memory (OOM) killer terminations
# while handling concurrent requests and asynchronous I/O cleanly.

bind = os.getenv("GUNICORN_BIND", "0.0.0.0:8000")
workers = int(os.getenv("WEB_CONCURRENCY", "1"))
threads = int(os.getenv("GUNICORN_THREADS", "2"))
worker_class = "gthread"
timeout = int(os.getenv("GUNICORN_TIMEOUT", "120"))
keepalive = 5

# Periodically recycle worker processes to prevent memory leaks from Pillow / NumPy
max_requests = 1000
max_requests_jitter = 50

# Logging
accesslog = "-"
errorlog = "-"
loglevel = os.getenv("GUNICORN_LOG_LEVEL", "info")
