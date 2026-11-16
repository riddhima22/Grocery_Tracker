import os
import sys
from datetime import timedelta
from pathlib import Path

import environ
from django.core.exceptions import ImproperlyConfigured

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent.parent

env = environ.Env()
# Read environment file
environ.Env.read_env(os.path.join(BASE_DIR, '.env'))

DEBUG = env.bool('DEBUG', default=False)

# In production (DEBUG=False), require SECRET_KEY at startup; keep fallback for dev/tests
is_dev_or_test = DEBUG or ('test' in sys.argv) or ('development' in os.environ.get('DJANGO_SETTINGS_MODULE', ''))
if not is_dev_or_test:
    SECRET_KEY = env('SECRET_KEY')
    if not SECRET_KEY:
        raise ImproperlyConfigured("SECRET_KEY environment variable is required and cannot be empty when DEBUG=False.")
else:
    SECRET_KEY = env('SECRET_KEY', default='django-insecure-freshtrack-secret')

if not is_dev_or_test:
    ALLOWED_HOSTS = env.list('ALLOWED_HOSTS', default=[])
else:
    ALLOWED_HOSTS = env.list('ALLOWED_HOSTS', default=['*'])

# Custom User Model
AUTH_USER_MODEL = 'accounts.User'

# Application definition
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',

    # Third-party apps
    'rest_framework',
    'rest_framework_simplejwt',
    'rest_framework_simplejwt.token_blacklist',
    'corsheaders',

    # Local apps
    'apps.accounts.apps.AccountsConfig',
    'apps.groceries.apps.GroceriesConfig',
    'apps.scans.apps.ScansConfig',
    'apps.recipes.apps.RecipesConfig',
    'apps.grocery_lists.apps.GroceryListsConfig',
    'apps.notifications.apps.NotificationsConfig',
    'apps.meals.apps.MealsConfig',
]

MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'config.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'
ASGI_APPLICATION = 'config.asgi.application'

# Database
# If DATABASE_URL environment variable is provided, parse it. Otherwise, fallback to local sqlite.
DATABASES = {
    'default': env.db('DATABASE_URL', default=f'sqlite:///{BASE_DIR}/db.sqlite3')
}
# Enable persistent DB connections to reduce latency on remote PostgreSQL (Neon/Render)
DATABASES['default']['CONN_MAX_AGE'] = env.int('DB_CONN_MAX_AGE', default=600)

# In Django 4.1+, CONN_HEALTH_CHECKS ensures stale/terminated connections are verified and reconnected
DATABASES['default']['CONN_HEALTH_CHECKS'] = env.bool('DB_CONN_HEALTH_CHECKS', default=True)

# PostgreSQL-specific network stability options (TCP keepalives and connect timeout)
if 'postgresql' in DATABASES['default']['ENGINE']:
    db_options = DATABASES['default'].setdefault('OPTIONS', {})
    # Keepalive options prevent intermediaries/firewalls (Render routers, AWS NAT) from dropping idle connections
    db_options.setdefault('connect_timeout', env.int('DB_CONNECT_TIMEOUT', default=10))
    db_options.setdefault('keepalives', 1)
    db_options.setdefault('keepalives_idle', env.int('DB_KEEPALIVES_IDLE', default=30))
    db_options.setdefault('keepalives_interval', env.int('DB_KEEPALIVES_INTERVAL', default=10))
    db_options.setdefault('keepalives_count', env.int('DB_KEEPALIVES_COUNT', default=5))
    if 'DB_SSLMODE' in env:
        db_options['sslmode'] = env('DB_SSLMODE')

# Password validation
AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
        'OPTIONS': {'min_length': 8},
    },
    {
        'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator',
    },
]

# Internationalization
LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'Asia/Kolkata' # Target market is India
USE_I18N = True
USE_TZ = True

# Static files (CSS, JavaScript, Images)
STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
STATIC_ROOT.mkdir(parents=True, exist_ok=True)

STORAGES = {
    "default": {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}

# Production S3-compatible Object Storage (AWS S3, Cloudflare R2, MinIO, etc.)
AWS_STORAGE_BUCKET_NAME = env('AWS_STORAGE_BUCKET_NAME', default=None)
if AWS_STORAGE_BUCKET_NAME:
    STORAGES["default"] = {
        "BACKEND": "storages.backends.s3boto3.S3Boto3Storage",
        "OPTIONS": {
            "bucket_name": AWS_STORAGE_BUCKET_NAME,
            "region_name": env('AWS_S3_REGION_NAME', default='us-east-1'),
            "endpoint_url": env('AWS_S3_ENDPOINT_URL', default=None),
            "access_key": env('AWS_ACCESS_KEY_ID', default=None),
            "secret_key": env('AWS_SECRET_ACCESS_KEY', default=None),
            "custom_domain": env('AWS_S3_CUSTOM_DOMAIN', default=None),
            "file_overwrite": False,
            "default_acl": None,
        }
    }
    s3_domain = env('AWS_S3_CUSTOM_DOMAIN', default=None) or f"{AWS_STORAGE_BUCKET_NAME}.s3.amazonaws.com"
    MEDIA_URL = f"https://{s3_domain}/"
else:
    MEDIA_URL = 'media/'
    MEDIA_ROOT = BASE_DIR / 'media'

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# REST Framework settings
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticated',
    ),
    'DEFAULT_THROTTLE_CLASSES': [
        'rest_framework.throttling.AnonRateThrottle',
        'rest_framework.throttling.UserRateThrottle',
        'rest_framework.throttling.ScopedRateThrottle',
    ],
    'DEFAULT_THROTTLE_RATES': {
        'anon': '100/day',
        'user': '1000/day',
        'auth_register': '5/minute',
        'auth_login': '10/minute',
        'scan_upload': '10/minute',
        'recipe_generate': '5/minute',
        'list_generate': '5/minute',
    },
    'EXCEPTION_HANDLER': 'common.exception_handler.custom_exception_handler',
    'DEFAULT_RENDERER_CLASSES': (
        'common.renderers.WrappedJSONRenderer',
        'rest_framework.renderers.BrowsableAPIRenderer',
    ),
}

# Simple JWT Configuration
SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=env.int('JWT_ACCESS_TOKEN_LIFETIME_MINUTES', default=15)),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=env.int('JWT_REFRESH_TOKEN_LIFETIME_DAYS', default=7)),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'UPDATE_LAST_LOGIN': True,
    'ALGORITHM': 'HS256',
    'SIGNING_KEY': SECRET_KEY,
    'AUTH_HEADER_TYPES': ('Bearer',),
    'AUTH_TOKEN_CLASSES': ('rest_framework_simplejwt.tokens.AccessToken',),
    'USER_ID_FIELD': 'id',
    'USER_ID_CLAIM': 'user_id',
}

# CORS Configuration
CORS_ALLOW_ALL_ORIGINS = False # In production this would be locked down

# Redis & Celery Settings
# Support CELERY_BROKER_URL, REDIS_URL, or REDIS_TLS_URL (e.g. Render/Upstash/AWS)
CELERY_BROKER_URL = env(
    'CELERY_BROKER_URL',
    default=env('REDIS_URL', default=env('REDIS_TLS_URL', default=None))
)
if not CELERY_BROKER_URL:
    if is_dev_or_test:
        CELERY_BROKER_URL = 'redis://localhost:6379/0'
    else:
        raise ImproperlyConfigured(
            "REDIS_URL or CELERY_BROKER_URL environment variable is required in production."
        )

CELERY_RESULT_BACKEND = env(
    'CELERY_RESULT_BACKEND',
    default=CELERY_BROKER_URL
)
CELERY_ACCEPT_CONTENT = ['json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_TIMEZONE = TIME_ZONE
CELERY_TASK_ALWAYS_EAGER = env.bool('CELERY_TASK_ALWAYS_EAGER', default=False)
CELERY_TASK_EAGER_PROPAGATES = True
CELERY_BROKER_CONNECTION_RETRY_ON_STARTUP = True

# Celery Reliability & Task Execution Safeguards
CELERY_TASK_ACKS_LATE = True
CELERY_TASK_REJECT_ON_WORKER_LOST = True
CELERY_TASK_TRACK_STARTED = True

# Worker Optimization for Render 512MB RAM constraints
CELERY_WORKER_PREFETCH_MULTIPLIER = 1
CELERY_WORKER_MAX_TASKS_PER_CHILD = env.int('CELERY_WORKER_MAX_TASKS_PER_CHILD', default=50)

# Task execution time limits (75s hard limit, 60s soft limit for responsive scans)
CELERY_TASK_TIME_LIMIT = env.int('CELERY_TASK_TIME_LIMIT', default=75)
CELERY_TASK_SOFT_TIME_LIMIT = env.int('CELERY_TASK_SOFT_TIME_LIMIT', default=60)

CELERY_BROKER_TRANSPORT_OPTIONS = {
    'visibility_timeout': 3600,
    'socket_timeout': env.float('REDIS_SOCKET_TIMEOUT', default=15.0),
    'socket_connect_timeout': env.float('REDIS_CONNECT_TIMEOUT', default=15.0),
    'retry_on_timeout': True,
}

# Handle rediss:// TLS certificate requirements seamlessly for cloud Redis
if CELERY_BROKER_URL and CELERY_BROKER_URL.startswith('rediss://'):
    import ssl
    cert_reqs = env('REDIS_SSL_CERT_REQS', default='none').lower()
    cert_map = {
        'none': ssl.CERT_NONE,
        'optional': ssl.CERT_OPTIONAL,
        'required': ssl.CERT_REQUIRED,
    }
    CELERY_BROKER_TRANSPORT_OPTIONS['ssl_cert_reqs'] = cert_map.get(cert_reqs, ssl.CERT_NONE)

from celery.schedules import crontab

# Celery Beat Periodic Schedules
CELERY_BEAT_SCHEDULE = {
    'send-daily-expiry-alerts': {
        'task': 'apps.notifications.tasks.send_expiry_alerts_task',
        'schedule': crontab(hour=8, minute=0),  # Daily at 08:00 AM
    },
}

# Gemini configuration
GEMINI_API_KEY = env('GEMINI_API_KEY', default='')
# gemini-3.5-flash-lite provides fast (~2s) responses without high-demand 503 errors
GEMINI_MODEL_NAME = env('GEMINI_MODEL_NAME', default='gemini-3.5-flash-lite')
GEMINI_RECIPE_MODEL_NAME = env('GEMINI_RECIPE_MODEL_NAME', default='gemini-3.5-flash-lite')
GEMINI_FALLBACK_MODELS = env.list(
    'GEMINI_FALLBACK_MODELS',
    default=['gemini-3.5-flash-lite', 'gemini-3.6-flash', 'gemini-3.5-flash', 'gemini-3.8-flash']
)
AI_REQUEST_TIMEOUT_SECONDS = env.int('AI_REQUEST_TIMEOUT_SECONDS', default=22)
GEMINI_TIMEOUT_SECONDS = env.int('GEMINI_TIMEOUT_SECONDS', default=AI_REQUEST_TIMEOUT_SECONDS)
AI_MAX_IMAGE_DIMENSION = env.int('AI_MAX_IMAGE_DIMENSION', default=1280)
AI_IMAGE_QUALITY = env.int('AI_IMAGE_QUALITY', default=82)

# OpenAI configuration
_raw_openai_key = env('OPENAI_API_KEY', default='')
OPENAI_API_KEY = _raw_openai_key.strip().strip('\'"') if isinstance(_raw_openai_key, str) else ''
_raw_openai_model = env('OPENAI_MODEL', default=env('OPENAI_MODEL_NAME', default='gpt-4.1-mini'))
OPENAI_MODEL = _raw_openai_model.strip().strip('\'"') if isinstance(_raw_openai_model, str) else 'gpt-4.1-mini'
OPENAI_MODEL_NAME = OPENAI_MODEL
_raw_openai_project = env('OPENAI_PROJECT_ID', default='')
OPENAI_PROJECT_ID = _raw_openai_project.strip().strip('\'"') if isinstance(_raw_openai_project, str) and _raw_openai_project.strip() else None
_raw_openai_org = env('OPENAI_ORG_ID', default='')
OPENAI_ORG_ID = _raw_openai_org.strip().strip('\'"') if isinstance(_raw_openai_org, str) and _raw_openai_org.strip() else None
_raw_openai_base_url = env('OPENAI_BASE_URL', default='')
OPENAI_BASE_URL = _raw_openai_base_url.strip().strip('\'"') if isinstance(_raw_openai_base_url, str) and _raw_openai_base_url.strip() else None

# AI Provider Fallback Order
# Prioritize OpenAI (gpt-4o-mini) as the primary provider whenever OPENAI_API_KEY is configured
default_ai_provider_order = ['openai', 'gemini'] if OPENAI_API_KEY else ['gemini', 'openai']
AI_PROVIDER_ORDER = env.list('AI_PROVIDER_ORDER', default=default_ai_provider_order)


# OCR configurations
OCR_ENABLED = env.bool('OCR_ENABLED', default=True)
OCR_PROVIDER = env('OCR_PROVIDER', default='TEXT_DETECTION')
GOOGLE_APPLICATION_CREDENTIALS_JSON = env('GOOGLE_APPLICATION_CREDENTIALS_JSON', default='')
GOOGLE_APPLICATION_CREDENTIALS = env('GOOGLE_APPLICATION_CREDENTIALS', default='')


# Scanning validation limits
AI_MAX_IMAGE_SIZE_BYTES = env.int('AI_MAX_IMAGE_SIZE_BYTES', default=5 * 1024 * 1024)
AI_MAX_IMAGES_PER_SCAN = env.int('AI_MAX_IMAGES_PER_SCAN', default=10)
AI_BLUR_VARIANCE_THRESHOLD = env.float('AI_BLUR_VARIANCE_THRESHOLD', default=100.0)

# Open Food Facts configuration
OPEN_FOOD_FACTS_BASE_URL = env('OPEN_FOOD_FACTS_BASE_URL', default='https://world.openfoodfacts.org')


# Import security checks so they register on startup
import config.checks  # noqa: F401
