from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import GroceryListViewSet

router = DefaultRouter()
router.register(r'', GroceryListViewSet, basename='grocery_list')

urlpatterns = [
    path('', include(router.urls)),
]
