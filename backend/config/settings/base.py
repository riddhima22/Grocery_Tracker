import os
from pathlib import Path
from datetime import timedelta
import environ

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent.parent

env = environ.Env()
# Read environment file
environ.Env.read_env(os.path.join(BASE_DIR, '.env'))

SECRET_KEY = env('SECRET_KEY', default='django-insecure-freshtrack-secret')
DEBUG = env.bool('DEBUG', default=False)
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

STORAGES = {
    "default": {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}

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
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=15),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=7),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'UPDATE_LAST_LOGIN': True,
    'ALGORITHM': 'HS256',
    'SIGNING_KEY': SECRET_KEY,
    'AUTH_HEADER_TYPES': ('Bearer',),
}

# CORS Configuration
CORS_ALLOW_ALL_ORIGINS = False # In production this would be locked down

# Redis & Celery Settings
CELERY_BROKER_URL = env('REDIS_URL', default='redis://localhost:6379/0')
CELERY_RESULT_BACKEND = env('REDIS_URL', default='redis://localhost:6379/0')
CELERY_ACCEPT_CONTENT = ['json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_TIMEZONE = TIME_ZONE

# Gemini configuration
GEMINI_API_KEY = env('GEMINI_API_KEY', default='')
# Check https://ai.google.dev/gemini-api/docs/models for latest stable GA Flash releases
GEMINI_MODEL_NAME = env('GEMINI_MODEL_NAME', default='gemini-3.6-flash')
# Check https://ai.google.dev/gemini-api/docs/models for latest stable GA Flash releases
GEMINI_RECIPE_MODEL_NAME = env('GEMINI_RECIPE_MODEL_NAME', default='gemini-3.6-flash')

# OpenAI configuration
OPENAI_API_KEY = env('OPENAI_API_KEY', default='')
OPENAI_MODEL_NAME = env('OPENAI_MODEL_NAME', default='gpt-4o-mini')

# AI Provider Fallback Order
AI_PROVIDER_ORDER = env.list('AI_PROVIDER_ORDER', default=['gemini', 'openai'])


# OCR configurations
OCR_ENABLED = env.bool('OCR_ENABLED', default=True)
OCR_PROVIDER = env('OCR_PROVIDER', default='TEXT_DETECTION')

# Scanning validation limits
AI_MAX_IMAGE_SIZE_BYTES = env.int('AI_MAX_IMAGE_SIZE_BYTES', default=5 * 1024 * 1024)
AI_MAX_IMAGES_PER_SCAN = env.int('AI_MAX_IMAGES_PER_SCAN', default=10)
AI_BLUR_VARIANCE_THRESHOLD = env.float('AI_BLUR_VARIANCE_THRESHOLD', default=100.0)

# Open Food Facts configuration
OPEN_FOOD_FACTS_BASE_URL = env('OPEN_FOOD_FACTS_BASE_URL', default='https://world.openfoodfacts.org')


# Import security checks so they register on startup
import config.checks  # noqa: F401
