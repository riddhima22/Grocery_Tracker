from rest_framework import serializers

from .models import DeviceToken


class DeviceTokenSerializer(serializers.ModelSerializer):
    token = serializers.CharField(max_length=512)
    platform = serializers.CharField(max_length=20, required=False, default='android')
    device_id = serializers.CharField(max_length=255, required=False, allow_blank=True, allow_null=True)

    class Meta:
        model = DeviceToken
        fields = ('token', 'platform', 'device_id')
