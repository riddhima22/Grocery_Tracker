from django.conf import settings
from django.core.checks import Error, Tags, register

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
