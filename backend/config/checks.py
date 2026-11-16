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

@register(Tags.compatibility, deploy=True)
def check_packaging_installed_for_kombu(app_configs, **kwargs):
    errors = []
    try:
        import packaging  # noqa: F401
    except ImportError:
        errors.append(
            Error(
                'The "packaging" package is not installed. Celery Kombu Redis transport requires "packaging".',
                hint='Ensure packaging>=23.2 is installed in your production environment.',
                id='freshtrack.E003',
            )
        )
    return errors


@register(Tags.compatibility)
def check_openai_configuration(app_configs, **kwargs):
    """
    Safe startup configuration check for OpenAI API credentials.
    Reports whether the key is configured without ever logging, printing,
    or exposing any part or character of the key.
    """
    messages = []
    import os
    raw_key = os.environ.get('OPENAI_API_KEY') or getattr(settings, 'OPENAI_API_KEY', '')
    is_key_present = bool(isinstance(raw_key, str) and raw_key.strip().strip('\'"'))

    provider_order = [p.lower().strip() for p in getattr(settings, 'AI_PROVIDER_ORDER', ['gemini', 'openai'])]

    if 'openai' in provider_order:
        try:
            import openai  # noqa: F401
        except ImportError:
            messages.append(
                Warning(
                    'The "openai" package is not installed, but "openai" is listed in AI_PROVIDER_ORDER.',
                    hint='Ensure openai>=1.0.0 is installed in your environment.',
                    id='freshtrack.W002',
                )
            )

        if not is_key_present:
            messages.append(
                Warning(
                    'OPENAI_API_KEY is not configured or is empty.',
                    hint=(
                        'Set OPENAI_API_KEY in Render environment variables for both the '
                        'Web Service and the Celery Background Worker to enable OpenAI fallback.'
                    ),
                    id='freshtrack.W003',
                )
            )

    return messages
