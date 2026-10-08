from .base import *

DEBUG = False

# Setup production hosts via env list (default to Render domain if unset)
ALLOWED_HOSTS = env.list('ALLOWED_HOSTS', default=['grocery-tracker-backend-rcwl.onrender.com', 'localhost', '127.0.0.1'])

# Security Headers & Proxy Configuration
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
USE_X_FORWARDED_HOST = True
SECURE_SSL_REDIRECT = env.bool('SECURE_SSL_REDIRECT', default=True)
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True

# HSTS Settings
SECURE_HSTS_SECONDS = env.int('SECURE_HSTS_SECONDS', default=31536000)
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True

# Disable CORS wildcard in production
CORS_ALLOW_ALL_ORIGINS = False
CORS_ALLOWED_ORIGINS = env.list('CORS_ALLOWED_ORIGINS', default=[])

# Ensure production Celery uses real background worker queue
CELERY_TASK_ALWAYS_EAGER = False

# Ensure production PostgreSQL on Render enforces SSL
if 'postgresql' in DATABASES['default']['ENGINE']:
    db_options = DATABASES['default'].setdefault('OPTIONS', {})
    if 'sslmode' not in db_options:
        db_options['sslmode'] = env.str('DB_SSLMODE', default='require')
