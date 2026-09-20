from .base import *

DEBUG = True

ALLOWED_HOSTS = ['localhost', '127.0.0.1', '10.0.2.2', '*']

# Run Celery tasks synchronously in development to bypass Redis worker requirements
CELERY_TASK_ALWAYS_EAGER = True
CELERY_TASK_EAGER_PROPAGATES = True

# Enable CORS for all origins in development
CORS_ALLOW_ALL_ORIGINS = True

# Enable console logging for local debug
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
        },
    },
    'root': {
        'handlers': ['console'],
        'level': 'INFO',
    },
}
import sys
if 'test' in sys.argv:
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': ':memory:',
        }
    }
