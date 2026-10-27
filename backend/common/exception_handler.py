import logging
import uuid

from django.core.exceptions import (
    ObjectDoesNotExist,
)
from django.core.exceptions import (
    PermissionDenied as DjangoPermissionDenied,
)
from django.core.exceptions import (
    ValidationError as DjangoValidationError,
)
from django.db import IntegrityError
from django.http import Http404
from rest_framework import status
from rest_framework.exceptions import (
    NotAuthenticated,
    Throttled,
)
from rest_framework.exceptions import (
    NotFound as DRFNotFound,
)
from rest_framework.exceptions import (
    PermissionDenied as DRFPermissionDenied,
)
from rest_framework.exceptions import (
    ValidationError as DRFValidationError,
)
from rest_framework.response import Response
from rest_framework.views import exception_handler

logger = logging.getLogger('freshtrack.api')


def custom_exception_handler(exc, context):
    correlation_id = str(uuid.uuid4())

    # 1. Safely extract request information without triggering DB/lazy-eval exceptions
    request = context.get('request') if context else None
    path = getattr(request, 'path', 'Unknown path') if request else 'Unknown path'
    method = getattr(request, 'method', 'Unknown method') if request else 'Unknown method'

    user_str = 'Anonymous'
    if request:
        try:
            user_obj = getattr(request, 'user', None)
            if user_obj and getattr(user_obj, 'is_authenticated', False):
                user_str = getattr(user_obj, 'email', str(user_obj))
        except Exception:
            user_str = 'Unauthenticated'

    # 2. Map Django-level exceptions to DRF exceptions before DRF handler runs
    if isinstance(exc, DjangoValidationError):
        # Convert Django internal model validation / bad UUID into DRF ValidationError (400)
        if hasattr(exc, 'message_dict'):
            detail = exc.message_dict
        elif hasattr(exc, 'messages'):
            detail = exc.messages
        else:
            detail = str(exc)
        exc = DRFValidationError(detail)
    elif isinstance(exc, (ObjectDoesNotExist, Http404)):
        exc = DRFNotFound("The requested resource was not found.")
    elif isinstance(exc, DjangoPermissionDenied):
        exc = DRFPermissionDenied("You do not have permission to perform this action.")
    elif isinstance(exc, IntegrityError):
        # Handle database unique constraint / duplicate violations as 409 Conflict instead of 500
        logger.warning(f"Database IntegrityError [{correlation_id}] on {method} {path}: {exc}")
        return Response({
            "success": False,
            "message": "A database conflict occurred with existing records.",
            "error": {
                "code": "CONFLICT",
                "message": "Resource conflict. A record with matching unique details already exists.",
                "fields": {},
                "correlation_id": correlation_id,
            }
        }, status=status.HTTP_409_CONFLICT)

    # 3. Call DRF's standard exception handler
    response = exception_handler(exc, context)

    # Log the error safely
    logger.error(
        f"API Error [{correlation_id}] on {method} {path} by user {user_str}: {exc!s}",
        exc_info=True
    )

    # Base error structures
    error_code = "INTERNAL_SERVER_ERROR"
    error_message = "An unexpected error occurred. Please try again later."
    fields = {}

    if response is not None:
        status_code = response.status_code

        if isinstance(exc, DRFValidationError):
            error_code = "VALIDATION_ERROR"
            error_message = "Validation check failed. Please check the submitted fields."
            if isinstance(response.data, dict):
                fields = response.data
                # Extract first meaningful validation message for top-level message
                for k, v in fields.items():
                    if isinstance(v, list) and v:
                        error_message = f"{k.capitalize()}: {v[0]}"
                        break
                    elif isinstance(v, str):
                        error_message = f"{k.capitalize()}: {v}"
                        break
            elif isinstance(response.data, list):
                fields = {'non_field_errors': response.data}
                if response.data:
                    error_message = str(response.data[0])
        elif isinstance(exc, Throttled):
            error_code = "RATE_LIMIT_EXCEEDED"
            error_message = f"Too many requests. Please retry in {exc.wait} seconds."
        elif isinstance(exc, NotAuthenticated):
            error_code = "UNAUTHORIZED"
            error_message = "Authentication credentials were not provided or are invalid."
        elif isinstance(exc, DRFPermissionDenied):
            error_code = "FORBIDDEN"
            error_message = "You do not have permission to perform this action."
        elif isinstance(exc, DRFNotFound):
            error_code = "NOT_FOUND"
            error_message = str(exc.detail) if hasattr(exc, 'detail') else "The requested resource was not found."
        elif hasattr(exc, 'code'):
            error_code = str(exc.code).upper()
            error_message = str(exc.detail) if hasattr(exc, 'detail') else str(exc)
        else:
            error_code = exc.__class__.__name__.replace('Exception', '').upper()
            if isinstance(response.data, dict) and 'detail' in response.data:
                error_message = str(response.data['detail'])
            else:
                error_message = str(exc)
    else:
        # Unhandled 500 error
        status_code = status.HTTP_500_INTERNAL_SERVER_ERROR
        response = Response(status=status_code)
        error_code = "INTERNAL_SERVER_ERROR"
        error_message = "An unexpected server error occurred. Please try again later."

    response.data = {
        "success": False,
        "message": error_message,
        "error": {
            "code": error_code,
            "message": error_message,
            "fields": fields,
            "correlation_id": correlation_id,
        }
    }
    return response
