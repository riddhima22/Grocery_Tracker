from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import ScanCandidateViewSet, ScanSessionViewSet

router = DefaultRouter()
router.register(r'sessions', ScanSessionViewSet, basename='scan_session')
router.register(r'candidates', ScanCandidateViewSet, basename='scan_candidate')

# Standardize path mapping
urlpatterns = [
    path('', include(router.urls)),
]
