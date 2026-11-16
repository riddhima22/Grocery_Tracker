import json
import logging
import os

from django.conf import settings

from .models import DeviceToken

logger = logging.getLogger('freshtrack.notifications')

_firebase_app_initialized = False

def get_or_initialize_firebase():
    """
    Safely initialize Firebase Admin SDK singleton.
    Supports GOOGLE_APPLICATION_CREDENTIALS, FIREBASE_CREDENTIALS_JSON, or default Google Cloud credentials.
    Returns True if initialized, False otherwise.
    """
    global _firebase_app_initialized
    try:
        import firebase_admin
        from firebase_admin import credentials

        if firebase_admin._apps:
            _firebase_app_initialized = True
            return True

        cred_json_str = getattr(settings, 'FIREBASE_CREDENTIALS_JSON', None) or os.environ.get('FIREBASE_CREDENTIALS_JSON')
        cred_path = (
            getattr(settings, 'GOOGLE_APPLICATION_CREDENTIALS', None)
            or getattr(settings, 'FIREBASE_CREDENTIALS_PATH', None)
            or os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')
            or os.environ.get('FIREBASE_CREDENTIALS_PATH')
        )

        if cred_json_str:
            try:
                cred_dict = json.loads(cred_json_str)
                cred = credentials.Certificate(cred_dict)
                firebase_admin.initialize_app(cred)
                _firebase_app_initialized = True
                logger.info("Firebase Admin initialized from FIREBASE_CREDENTIALS_JSON")
                return True
            except Exception as e:
                logger.warning(f"Failed to initialize Firebase Admin from JSON env: {e}")

        if cred_path and os.path.exists(cred_path):
            try:
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
                _firebase_app_initialized = True
                logger.info("Firebase Admin initialized from credentials file")
                return True
            except Exception as e:
                logger.warning(f"Failed to initialize Firebase Admin from credentials file {cred_path}: {e}")

        # Attempt default credentials
        try:
            firebase_admin.initialize_app()
            _firebase_app_initialized = True
            logger.info("Firebase Admin initialized from application default credentials")
            return True
        except Exception as e:
            logger.warning(f"Firebase Admin default initialization skipped or unavailable: {e}")
            return False

    except ImportError:
        logger.warning("firebase-admin package is not installed. Push notifications will be simulated.")
        return False


class FCMNotificationService:
    """
    Production-grade service for sending Firebase Cloud Messaging push notifications.
    Supports user-level dispatch, multi-device delivery, automatic invalid token pruning,
    and structured payload transmission.
    """

    @classmethod
    def send_to_user(cls, user, title, body, data=None):
        """
        Sends an FCM notification to all active device tokens belonging to a user.
        """
        active_tokens = list(
            DeviceToken.objects.filter(user=user, is_active=True).values_list('token', flat=True)
        )
        if not active_tokens:
            logger.info(f"Notification skipped for user {user.email}: No active device tokens.")
            return {"sent": 0, "failed": 0, "cleaned": 0}

        return cls.send_to_tokens(active_tokens, title, body, data=data)

    @classmethod
    def send_to_tokens(cls, tokens, title, body, data=None):
        """
        Sends an FCM notification to a list of tokens.
        Handles invalid / unregistered tokens by removing or deactivating them.
        """
        if not tokens:
            return {"sent": 0, "failed": 0, "cleaned": 0}

        is_initialized = get_or_initialize_firebase()
        if not is_initialized:
            logger.info(f"[SIMULATED PUSH] Title='{title}', Body='{body}', Data={data} to {len(tokens)} token(s)")
            return {"sent": len(tokens), "failed": 0, "cleaned": 0, "simulated": True}

        try:
            from firebase_admin import messaging

            # Ensure all data values are strings (FCM requirement for data payload)
            clean_data = {}
            if data and isinstance(data, dict):
                for k, v in data.items():
                    clean_data[str(k)] = str(v) if v is not None else ""

            sent_count = 0
            failed_count = 0
            invalid_tokens = []

            for token_str in tokens:
                try:
                    message = messaging.Message(
                        notification=messaging.Notification(
                            title=title,
                            body=body,
                        ),
                        data=clean_data,
                        token=token_str,
                        android=messaging.AndroidConfig(
                            priority='high',
                            notification=messaging.AndroidNotification(
                                channel_id='grocery_notifications',
                                sound='default',
                                default_vibrate_timings=True,
                            ),
                        ),
                        apns=messaging.APNSConfig(
                            payload=messaging.APNSPayload(
                                aps=messaging.Aps(
                                    alert=messaging.ApsAlert(
                                        title=title,
                                        body=body,
                                    ),
                                    sound='default',
                                    badge=1,
                                ),
                            ),
                        ),
                    )

                    messaging.send(message)
                    sent_count += 1
                except messaging.UnregisteredError:
                    logger.warning(f"FCM token {token_str[:16]}... is unregistered. Flagging for removal.")
                    invalid_tokens.append(token_str)
                    failed_count += 1
                except Exception as ex:
                    ex_str = str(ex).lower()
                    if any(term in ex_str for term in ['not-registered', 'invalid-registration', 'mismatched-credential', 'sender-id-mismatch']):
                        logger.warning(f"FCM token {token_str[:16]}... invalid ({ex}). Flagging for removal.")
                        invalid_tokens.append(token_str)
                    else:
                        logger.error(f"FCM send error for token {token_str[:16]}...: {ex}")
                    failed_count += 1

            cleaned_count = 0
            if invalid_tokens:
                cleaned_count, _ = DeviceToken.objects.filter(token__in=invalid_tokens).delete()
                logger.info(f"Cleaned up {cleaned_count} invalid FCM tokens from database.")

            return {
                "sent": sent_count,
                "failed": failed_count,
                "cleaned": cleaned_count,
            }

        except Exception as e:
            logger.error(f"Unexpected error in FCMNotificationService.send_to_tokens: {e}", exc_info=True)
            return {"sent": 0, "failed": len(tokens), "cleaned": 0, "error": str(e)}
