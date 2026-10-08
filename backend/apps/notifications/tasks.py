from celery import shared_task
from django.utils import timezone
from django.db import transaction, models
from django.contrib.auth import get_user_model
from apps.groceries.models import GroceryItem
from .models import DeviceToken
import logging
import datetime

logger = logging.getLogger('freshtrack.notifications.tasks')
User = get_user_model()

@shared_task
def send_expiry_alerts_task():
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
    ).exclude(status='expired')

    # 2. Query active items that reach effective expiry tomorrow (1 day)
    items_1d = GroceryItem.objects.filter(
        models.Q(expiry_date=target_1d) | 
        (models.Q(expiry_date__isnull=True) & models.Q(estimated_consumption_date=target_1d)),
        notified_1d=False,
        quantity__gt=0
    ).exclude(status='expired')

    # 3. Process 3-day alerts
    for item in items_3d:
        user = item.user
        if getattr(user, 'notify_3_days', True):
            if item.is_expiry_estimated:
                message_body = f"Your {item.name} has an estimated consumption window ending in 3 days! Plan a recipe to cook it soon."
            else:
                message_body = f"Your {item.name} printed expiry date is in 3 days! Plan a recipe to cook it soon."
            _send_push_notification(user, "Grocery Expiry Alert 🥦", message_body)
            item.notified_3d = True
            item.save(update_fields=['notified_3d'])

    # 4. Process 1-day alerts
    for item in items_1d:
        user = item.user
        if getattr(user, 'notify_1_day', True):
            if item.is_expiry_estimated:
                message_body = f"Urgent: Your {item.name} is estimated to spoil tomorrow! Cook it today to avoid waste."
            else:
                message_body = f"Urgent: Your {item.name} printed expiry date is tomorrow! Cook it today to avoid waste."
            _send_push_notification(user, "Urgent Expiry Alert ⚠️", message_body)
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

def _send_push_notification(user, title, body):
    # Retrieve all tokens registered for this user
    tokens = DeviceToken.objects.filter(user=user)
    if not tokens.exists():
        logger.info(f"Notification skipped for {user.email}: No device tokens registered")
        return

    logger.info(f"Sending Push Alert to {user.email}: Title='{title}', Body='{body}' across {tokens.count()} devices.")
    
    # Try sending via Firebase Admin SDK if initialized
    try:
        import firebase_admin
        from firebase_admin import messaging
        from firebase_admin.exceptions import FirebaseError
        
        if firebase_admin._apps:
            tokens_to_delete = []
            for token_obj in tokens:
                try:
                    msg = messaging.Message(
                        notification=messaging.Notification(
                            title=title,
                            body=body,
                        ),
                        token=token_obj.token,
                    )
                    messaging.send(msg)
                    logger.info(f"FCM Notification sent successfully to token {token_obj.token[:15]}...")
                except messaging.UnregisteredError:
                    logger.warning(f"FCM token {token_obj.token[:15]} is unregistered. Marking for cleanup.")
                    tokens_to_delete.append(token_obj.id)
                except Exception as token_err:
                    err_str = str(token_err).lower()
                    if 'not-registered' in err_str or 'invalid-registration' in err_str or 'mismatched-credential' in err_str:
                        logger.warning(f"FCM token {token_obj.token[:15]} invalid ({token_err}). Marking for cleanup.")
                        tokens_to_delete.append(token_obj.id)
                    else:
                        logger.warning(f"Failed to send FCM to token {token_obj.token[:15]}: {str(token_err)}")
            
            if tokens_to_delete:
                DeviceToken.objects.filter(id__in=tokens_to_delete).delete()
                logger.info(f"Cleaned up {len(tokens_to_delete)} stale/unregistered FCM device tokens.")
        else:
            logger.info(f"Firebase Admin not initialized. Simulated push: Title='{title}', Body='{body}'")
    except ImportError:
        logger.info(f"firebase-admin module not available. Simulated push: Title='{title}', Body='{body}'")

