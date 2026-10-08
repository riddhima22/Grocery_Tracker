from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from django.http import JsonResponse
import logging
from apps.accounts.views import MeView, DeleteAccountView

logger = logging.getLogger('freshtrack.health')

def health_check(request):
    is_healthy = True
    db_status = "connected"

    try:
        from django.db import connection
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1;")
    except Exception as e:
        is_healthy = False
        db_status = "unreachable"
        logger.error(f"Health check database failure: {e}", exc_info=True)
        try:
            from django.db import connection
            connection.close()
        except Exception:
            pass

    response_data = {
        "status": "healthy" if is_healthy else "unhealthy",
        "service": "grocery-tracker-backend",
        "database": db_status,
    }
    status_code = 200 if is_healthy else 503
    return JsonResponse(response_data, status=status_code)

profile_patterns = [
    path('', MeView.as_view(), name='profile_detail'),
    path('account/', DeleteAccountView.as_view(), name='profile_account_delete'),
]

v1_patterns = [
    path('health/', health_check, name='v1_health_check'),
    path('auth/', include('apps.accounts.urls')),
    path('profile/', include(profile_patterns)),
    path('groceries/', include('apps.groceries.urls')),
    path('scans/', include('apps.scans.urls')),
    path('recipes/', include('apps.recipes.urls')),
    path('grocery-lists/', include('apps.grocery_lists.urls')),
    path('notifications/', include('apps.notifications.urls')),
    path('meals/', include('apps.meals.urls')),
]

urlpatterns = [
    path('health/', health_check, name='root_health_check'),
    path('admin/', admin.site.urls),
    path('api/v1/', include(v1_patterns)),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
