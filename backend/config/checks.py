from django.conf import settings
from django.core.checks import Error, Tags, Warning, register

INSECURE_SECRET_KEY = 'django-insecure-freshtrack-secret'

@register(Tags.security, deploy=True)
def check_secret_key_not_insecure(app_configs, **kwargs):
    errors = []
    if not settings.DEBUG and settings.SECRET_KEY == INSECURE_SECRET_KEY:
        errors.append(
            Error(
                'SECRET_KEY is set to the insecure default value.',
                hint='Set a strong, unique SECRET_KEY environment variable for production.',
                id='freshtrack.E001',
            )
        )
    if not settings.DEBUG and settings.SECRET_KEY == '':
        errors.append(
            Error(
                'SECRET_KEY is empty.',
                hint='Set a strong, unique SECRET_KEY environment variable.',
                id='freshtrack.E002',
            )
        )
    return errors

@register(Tags.compatibility, deploy=True)
def check_celery_broker_in_production(app_configs, **kwargs):
    warnings = []
    if not settings.DEBUG and not getattr(settings, 'CELERY_TASK_ALWAYS_EAGER', True):
        broker = getattr(settings, 'CELERY_BROKER_URL', '')
        if 'localhost' in broker or '127.0.0.1' in broker:
            warnings.append(
                Warning(
                    f'CELERY_BROKER_URL is configured to localhost ({broker}) in production.',
                    hint='Ensure REDIS_URL or CELERY_BROKER_URL points to your production Redis instance (e.g. Render internal Redis URL).',
                    id='freshtrack.W001',
                )
            )
    return warnings
