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
        
        # Save or update token
        device_token, created = DeviceToken.objects.update_or_create(
            token=token,
            defaults={"user": request.user}
        )
        
        return Response({
            "success": True,
            "data": {"token": token},
            "message": "Device push token registered successfully."
        }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)

    def delete(self, request):
        token = request.data.get('token')
        if not token:
            return Response({"success": False, "error": "Token field is required."}, status=400)
            
        DeviceToken.objects.filter(user=request.user, token=token).delete()
        return Response({
            "success": True,
            "data": {},
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

