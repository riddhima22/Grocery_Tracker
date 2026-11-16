from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import MealLogViewSet

router = DefaultRouter()
router.register(r'', MealLogViewSet, basename='meal-log')

urlpatterns = [
    path('', include(router.urls)),
]
