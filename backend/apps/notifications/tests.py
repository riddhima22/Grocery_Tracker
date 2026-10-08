from rest_framework.test import APITestCase
from django.contrib.auth import get_user_model
from django.utils import timezone
from apps.groceries.models import GroceryItem
from apps.grocery_lists.models import GroceryList, GroceryListItem
from .models import DeviceToken
from .tasks import (
    send_expiry_alerts_task,
    send_low_stock_alerts_task,
    send_shopping_reminder_task,
    _send_push_notification,
)
from unittest.mock import patch, MagicMock
import datetime

User = get_user_model()

class NotificationTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email="notif_user@example.com",
            password="StrongPassword123!",
            display_name="Notif User"
        )
        self.client.force_authenticate(user=self.user)

    def test_register_device_token(self):
        url = "/api/v1/notifications/device-token/"
        payload = {
            "token": "fcm_test_token_12345",
            "platform": "android",
            "device_id": "device_xyz_99"
        }
        res = self.client.post(url, payload, format="json")
        self.assertEqual(res.status_code, 201)
        record = DeviceToken.objects.filter(user=self.user, token="fcm_test_token_12345").first()
        self.assertIsNotNone(record)
        self.assertEqual(record.platform, "android")
        self.assertEqual(record.device_id, "device_xyz_99")
        self.assertTrue(record.is_active)

    def test_register_duplicate_device_token_is_idempotent(self):
        url = "/api/v1/notifications/device-token/"
        res1 = self.client.post(url, {"token": "fcm_test_token_dup", "platform": "android"}, format="json")
        self.assertEqual(res1.status_code, 201)
        res2 = self.client.post(url, {"token": "fcm_test_token_dup", "platform": "android"}, format="json")
        self.assertEqual(res2.status_code, 200)
        self.assertEqual(DeviceToken.objects.filter(token="fcm_test_token_dup").count(), 1)

    def test_delete_device_token_on_logout(self):
        url = "/api/v1/notifications/device-token/"
        DeviceToken.objects.create(user=self.user, token="fcm_logout_token", platform="android", device_id="dev_1")
        
        # Test delete by token
        res = self.client.delete(url, {"token": "fcm_logout_token"}, format="json")
        self.assertEqual(res.status_code, 200)
        self.assertFalse(DeviceToken.objects.filter(token="fcm_logout_token").exists())

    def test_update_notification_preferences(self):
        url = "/api/v1/notifications/preferences/"
        res = self.client.patch(url, {
            "notify_3_days": False,
            "notify_1_day": True,
            "notify_daily_recipe": False
        }, format="json")
        self.assertEqual(res.status_code, 200)
        self.user.refresh_from_db()
        self.assertFalse(self.user.notify_3_days)
        self.assertTrue(self.user.notify_1_day)
        self.assertFalse(self.user.notify_daily_recipe)

    def test_send_expiry_alerts_semantic_dates(self):
        today = timezone.localdate()
        # Item with printed expiry in 3 days
        item_printed = GroceryItem.objects.create(
            user=self.user,
            name="Milk Carton",
            expiry_date=today + datetime.timedelta(days=3),
            is_expiry_estimated=False,
            quantity=1.0
        )
        # Item with estimated consumption in 1 day
        item_estimated = GroceryItem.objects.create(
            user=self.user,
            name="Fresh Tomatoes",
            expiry_date=None,
            estimated_consumption_date=today + datetime.timedelta(days=1),
            is_expiry_estimated=True,
            quantity=2.0
        )
        # Expired item past date
        item_past = GroceryItem.objects.create(
            user=self.user,
            name="Old Bread",
            expiry_date=today - datetime.timedelta(days=1),
            quantity=1.0,
            status='fresh'
        )

        DeviceToken.objects.create(user=self.user, token="test_token_for_alert")

        with patch('apps.notifications.tasks._send_push_notification') as mock_push:
            send_expiry_alerts_task()
            self.assertEqual(mock_push.call_count, 2)

        item_printed.refresh_from_db()
        item_estimated.refresh_from_db()
        item_past.refresh_from_db()

        self.assertTrue(item_printed.notified_3d)
        self.assertTrue(item_estimated.notified_1d)
        self.assertEqual(item_past.status, 'expired')

    def test_send_low_stock_alerts_task(self):
        GroceryItem.objects.create(
            user=self.user,
            name="Sugar",
            quantity=0.5,
            unit="kg",
            status='fresh'
        )
        DeviceToken.objects.create(user=self.user, token="test_token_low_stock")

        with patch('apps.notifications.tasks._send_push_notification') as mock_push:
            send_low_stock_alerts_task()
            self.assertEqual(mock_push.call_count, 1)
            # Verify payload type
            _, kwargs = mock_push.call_args
            data = kwargs.get('data') or mock_push.call_args[0][3]
            self.assertEqual(data.get('type'), 'low_stock')

    def test_send_shopping_reminder_task(self):
        g_list = GroceryList.objects.create(user=self.user, status=GroceryList.Statuses.ACTIVE)
        GroceryListItem.objects.create(grocery_list=g_list, name="Apples", quantity=4, purchased=False)
        DeviceToken.objects.create(user=self.user, token="test_token_shopping")

        with patch('apps.notifications.tasks._send_push_notification') as mock_push:
            send_shopping_reminder_task()
            self.assertEqual(mock_push.call_count, 1)
            _, kwargs = mock_push.call_args
            data = kwargs.get('data') or mock_push.call_args[0][3]
            self.assertEqual(data.get('type'), 'shopping_reminder')

    def test_fcm_unregistered_token_cleanup(self):
        token_obj = DeviceToken.objects.create(user=self.user, token="unregistered_fcm_token_xyz")
        
        # Test token cleanup using mock
        with patch('firebase_admin.messaging.send') as mock_send, \
             patch('firebase_admin._apps', True):
            from firebase_admin.messaging import UnregisteredError
            mock_send.side_effect = UnregisteredError("Token is unregistered")
            _send_push_notification(self.user, "Alert", "Body")

        # Confirm token was cleaned up
        self.assertFalse(DeviceToken.objects.filter(id=token_obj.id).exists())
