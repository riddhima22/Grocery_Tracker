from django.urls import path

from .views import DeviceTokenView, NotificationPreferencesView

urlpatterns = [
    path('device-token/', DeviceTokenView.as_view(), name='device_token'),
    path('preferences/', NotificationPreferencesView.as_view(), name='notification_preferences'),
]

