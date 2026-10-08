from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated
from .models import DeviceToken
from .serializers import DeviceTokenSerializer

class DeviceTokenView(APIView):
    permission_classes = (IsAuthenticated,)

    def post(self, request):
        serializer = DeviceTokenSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        token = serializer.validated_data['token']
        platform = serializer.validated_data.get('platform', 'android')
        device_id = serializer.validated_data.get('device_id')
        
        defaults = {
            "user": request.user,
            "platform": platform,
            "is_active": True,
        }
        if device_id:
            defaults["device_id"] = device_id

        # Save or update token (handles reassigning to current user if device was previously logged in as another user)
        device_token, created = DeviceToken.objects.update_or_create(
            token=token,
            defaults=defaults
        )
        
        return Response({
            "success": True,
            "data": {
                "token": token,
                "platform": device_token.platform,
                "device_id": device_token.device_id,
            },
            "message": "Device push token registered successfully."
        }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)

    def delete(self, request):
        token = request.data.get('token') or request.query_params.get('token')
        device_id = request.data.get('device_id') or request.query_params.get('device_id')

        if not token and not device_id:
            return Response({"success": False, "error": "Token or device_id is required."}, status=400)
            
        qs = DeviceToken.objects.filter(user=request.user)
        if token:
            qs = qs.filter(token=token)
        elif device_id:
            qs = qs.filter(device_id=device_id)

        deleted_count, _ = qs.delete()
        return Response({
            "success": True,
            "data": {"deleted": deleted_count},
            "message": "Device token removed successfully."
        })


class NotificationPreferencesView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request):
        user = request.user
        return Response({
            "success": True,
            "data": {
                "notify_3_days": user.notify_3_days,
                "notify_1_day": user.notify_1_day,
                "notify_daily_recipe": user.notify_daily_recipe,
            }
        })

    def patch(self, request):
        user = request.user
        if 'notify_3_days' in request.data:
            user.notify_3_days = bool(request.data['notify_3_days'])
        if 'notify_1_day' in request.data:
            user.notify_1_day = bool(request.data['notify_1_day'])
        if 'notify_daily_recipe' in request.data:
            user.notify_daily_recipe = bool(request.data['notify_daily_recipe'])
        
        user.save(update_fields=['notify_3_days', 'notify_1_day', 'notify_daily_recipe'])

        return Response({
            "success": True,
            "data": {
                "notify_3_days": user.notify_3_days,
                "notify_1_day": user.notify_1_day,
                "notify_daily_recipe": user.notify_daily_recipe,
            },
            "message": "Notification preferences updated successfully."
        })

