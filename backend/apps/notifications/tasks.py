from celery import shared_task
from django.utils import timezone
from django.db import transaction, models
from django.contrib.auth import get_user_model
from apps.groceries.models import GroceryItem
from apps.grocery_lists.models import GroceryList
from .models import DeviceToken
from .services import FCMNotificationService
import logging
import datetime

logger = logging.getLogger('freshtrack.notifications.tasks')
User = get_user_model()

@shared_task
def send_expiry_alerts_task():
    """
    Periodic task to check and send expiry reminders via FCM.
    Supports printed expiry and AI-estimated shelf-life dates.
    """
    logger.info("Executing periodic expiry check alerts task...")
    today = timezone.localdate() if hasattr(timezone, 'localdate') else timezone.now().date()
    
    target_3d = today + datetime.timedelta(days=3)
    target_1d = today + datetime.timedelta(days=1)

    # 1. Query active items that reach effective expiry in 3 days
    items_3d = GroceryItem.objects.filter(
        models.Q(expiry_date=target_3d) | 
        (models.Q(expiry_date__isnull=True) & models.Q(estimated_consumption_date=target_3d)),
        notified_3d=False,
        quantity__gt=0
    ).exclude(status='expired').select_related('user')

    # 2. Query active items that reach effective expiry tomorrow (1 day)
    items_1d = GroceryItem.objects.filter(
        models.Q(expiry_date=target_1d) | 
        (models.Q(expiry_date__isnull=True) & models.Q(estimated_consumption_date=target_1d)),
        notified_1d=False,
        quantity__gt=0
    ).exclude(status='expired').select_related('user')

    # 3. Process 3-day alerts
    for item in items_3d:
        user = item.user
        if getattr(user, 'notify_3_days', True):
            if item.is_expiry_estimated:
                body = f"Your {item.name} has an estimated consumption window ending in 3 days! Plan a recipe to cook it soon."
            else:
                body = f"Your {item.name} printed expiry date is in 3 days! Plan a recipe to cook it soon."
            
            payload_data = {
                "type": "expiry_reminder",
                "grocery_id": str(item.id),
                "title": f"🥦 {item.name} expires in 3 days",
            }
            _send_push_notification(user, f"Grocery Expiry Alert: {item.name}", body, data=payload_data)
            item.notified_3d = True
            item.save(update_fields=['notified_3d'])

    # 4. Process 1-day alerts
    for item in items_1d:
        user = item.user
        if getattr(user, 'notify_1_day', True):
            if item.is_expiry_estimated:
                body = f"Urgent: Your {item.name} is estimated to spoil tomorrow! Cook it today to avoid waste."
            else:
                body = f"Urgent: Your {item.name} printed expiry date is tomorrow! Cook it today to avoid waste."
            
            payload_data = {
                "type": "expiry_reminder",
                "grocery_id": str(item.id),
                "title": f"⚠️ {item.name} expires tomorrow",
            }
            _send_push_notification(user, f"Urgent Expiry Alert: {item.name}", body, data=payload_data)
            item.notified_1d = True
            item.save(update_fields=['notified_1d'])

    # 5. Auto-update expired statuses daily based on effective date
    expired_items = GroceryItem.objects.filter(
        models.Q(expiry_date__lt=today) | 
        (models.Q(expiry_date__isnull=True) & models.Q(estimated_consumption_date__lt=today)),
        quantity__gt=0
    ).exclude(status='expired')
    for item in expired_items:
        item.status = 'expired'
        item.save(update_fields=['status'])

    return True


@shared_task
def send_low_stock_alerts_task():
    """
    Checks active pantry and fridge items running low on stock and sends reminders.
    """
    logger.info("Executing periodic low stock alerts task...")
    low_stock_items = GroceryItem.objects.filter(
        quantity__gt=0,
        quantity__lte=1,
    ).exclude(status='expired').select_related('user')

    for item in low_stock_items:
        user = item.user
        title = "Low stock reminder"
        body = f"{item.name} is running low ({item.quantity} {item.unit} left). Consider adding it to your shopping list."
        payload_data = {
            "type": "low_stock",
            "grocery_id": str(item.id),
        }
        _send_push_notification(user, title, body, data=payload_data)

    return True


@shared_task
def send_shopping_reminder_task():
    """
    Sends shopping reminders to users with unpurchased items on active grocery lists.
    """
    logger.info("Executing periodic shopping reminder task...")
    active_lists = GroceryList.objects.filter(
        status=GroceryList.Statuses.ACTIVE
    ).select_related('user')

    for g_list in active_lists:
        unpurchased_count = g_list.items.filter(purchased=False).count()
        if unpurchased_count > 0:
            user = g_list.user
            title = "🛒 Shopping reminder"
            body = f"You have {unpurchased_count} item(s) on your shopping list."
            payload_data = {
                "type": "shopping_reminder",
                "list_id": str(g_list.id),
            }
            _send_push_notification(user, title, body, data=payload_data)

    return True


def _send_push_notification(user, title, body, data=None):
    """
    Helper function for backward-compatibility with tests and internal tasks.
    Delegates to FCMNotificationService.
    """
    return FCMNotificationService.send_to_user(user, title, body, data=data)
