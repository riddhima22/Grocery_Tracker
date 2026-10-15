import uuid
import logging
from django.http import JsonResponse

logger = logging.getLogger('freshtrack.errors')


def server_error_500(request):
    correlation_id = str(uuid.uuid4())
    path = getattr(request, 'path', 'Unknown path')
    method = getattr(request, 'method', 'Unknown method')
    logger.error(f"Root 500 error [{correlation_id}] on {method} {path}", exc_info=True)
    return JsonResponse({
        "success": False,
        "message": "An unexpected server error occurred. Please try again later.",
        "error": {
            "code": "INTERNAL_SERVER_ERROR",
            "message": "Server error. Please try again later.",
            "fields": {},
            "correlation_id": correlation_id,
        }
    }, status=500)


def not_found_404(request, exception=None):
    path = getattr(request, 'path', 'Unknown path')
    return JsonResponse({
        "success": False,
        "message": f"Endpoint not found: {path}",
        "error": {
            "code": "NOT_FOUND",
            "message": "The requested API resource does not exist.",
            "fields": {},
        }
    }, status=404)


def bad_request_400(request, exception=None):
    return JsonResponse({
        "success": False,
        "message": "Bad request. Please verify your request parameters.",
        "error": {
            "code": "BAD_REQUEST",
            "message": str(exception) if exception else "Invalid request data.",
            "fields": {},
        }
    }, status=400)


def permission_denied_403(request, exception=None):
    return JsonResponse({
        "success": False,
        "message": "Permission denied. You do not have permission to access this resource.",
        "error": {
            "code": "FORBIDDEN",
            "message": "Access denied.",
            "fields": {},
        }
    }, status=403)
