from celery import shared_task
from celery.exceptions import MaxRetriesExceededError, Retry
from django.utils import timezone
from django.db import transaction
from .models import ScanSession, ScanImage, ScanCandidate
from integrations.ai.model_router import ModelRouter
from integrations.ai.gemini_client import AIContentBlockedError
import logging
import datetime

logger = logging.getLogger('freshtrack.scans.tasks')


def is_transient_error(exc: Exception) -> bool:
    """
    Distinguishes transient/retryable errors (rate limits, 429, 5xx, network timeouts,
    retryable google.api_core exceptions) from permanent errors (bad image, schema violation,
    safety block).
    """
    if isinstance(exc, AIContentBlockedError):
        return False

    # Check for google-api-core retryable exceptions
    try:
        from google.api_core import exceptions as google_exceptions
        retryable_google = (
            google_exceptions.ResourceExhausted,      # 429
            google_exceptions.ServiceUnavailable,     # 503
            google_exceptions.DeadlineExceeded,       # 504 / timeout
            google_exceptions.InternalServerError,    # 500
            google_exceptions.BadGateway,             # 502
            google_exceptions.GatewayTimeout,
        )
        if isinstance(exc, retryable_google):
            return True
        non_retryable_google = (
            google_exceptions.InvalidArgument,        # 400
            google_exceptions.PermissionDenied,       # 403
            google_exceptions.Unauthenticated,        # 401
            google_exceptions.NotFound,               # 404
        )
        if isinstance(exc, non_retryable_google):
            return False
    except ImportError:
        pass

    # Built-in network / timeout exceptions
    if isinstance(exc, (TimeoutError, ConnectionError)):
        return True

    status_code = getattr(exc, 'status_code', None) or getattr(exc, 'code', None)
    if status_code in (429, 500, 502, 503, 504):
        return True
    if status_code in (400, 401, 403, 404):
        return False

    msg = str(exc).lower()

    # Permanent failure indicators (do not retry)
    permanent_indicators = [
        'blocked by safety', 'blocked by content', 'content filters',
        'corrupted', 'unreadable', 'resolution is too low', 'exceeds size limit',
        'duplicate image', 'no valid images', 'image file does not exist',
        'invalid argument', 'schema validation', 'jsondecodeerror'
    ]
    if any(ind in msg for ind in permanent_indicators):
        return False

    transient_indicators = [
        '429', 'rate limit', 'quota', 'resource_exhausted', 'resource exhausted',
        'timeout', 'timed out', 'deadline exceeded', '503', '502', '500',
        'service unavailable', 'temporarily unavailable', 'connection error',
        'connection reset', 'try again', 'server error'
    ]
    if any(ind in msg for ind in transient_indicators):
        return True

    return False


@shared_task(bind=True, max_retries=3, default_retry_delay=10)
def process_scan_session_task(self, session_id=None):
    # Support both task.delay(session_id) and direct thread execution
    if session_id is None and isinstance(self, (str, int)):
        session_id = self

    import time
    from django.db import connection

    # Ensure clean database connection in thread context
    connection.close_if_unusable_or_obsolete()

    start_time = time.time()
    logger.info(f"Starting scan processing task for session {session_id}")
    try:
        session = ScanSession.objects.get(id=session_id)
    except ScanSession.DoesNotExist:
        logger.error(f"Scan session {session_id} does not exist.")
        return False

    session.status = ScanSession.Statuses.PROCESSING
    session.save(update_fields=['status'])

    images = session.images.filter(status=ScanImage.Statuses.PENDING)
    if not images.exists():
        logger.info("No pending images found for session.")
        session.status = ScanSession.Statuses.COMPLETED
        session.completed_at = timezone.now()
        session.save(update_fields=['status', 'completed_at'])
        return True

    # 1. Instantiate the AI / OCR pipeline orchestrator
    router = ModelRouter()
    image_paths = [img.image.path for img in images]

    successful_count = 0
    failed_count = 0
    candidate_count = 0

    try:
        # 2. Process all images through the router pipeline
        result = router.process_scan(image_paths)

        if not result.get("success"):
            raise Exception(result.get("error", "Scan processing failed."))

        items = result.get("items", [])

        # 3. Create ScanCandidate objects inside a transaction
        with transaction.atomic():
            def safe_str(val, default=''):
                if val is None:
                    return default
                return str(val).strip()

            def parse_date_str(d_str):
                if not d_str:
                    return None
                d_str = str(d_str).strip()
                for fmt in ('%Y-%m-%d', '%d/%m/%Y', '%d-%m-%Y', '%m/%d/%Y', '%Y/%m/%d'):
                    try:
                        return datetime.datetime.strptime(d_str[:10], fmt).date()
                    except (ValueError, TypeError):
                        pass
                try:
                    from dateutil import parser as date_parser
                    return date_parser.parse(d_str).date()
                except Exception:
                    return None

            # Map items to source images. The AI may return a 'source_image_index'
            # field per item. If not present, distribute items evenly across images.
            image_list = list(images)  # Materialize queryset for index access
            for idx, item_data in enumerate(items):
                # Use AI-provided source_image_index if available, else distribute evenly
                source_idx = item_data.get('source_image_index')
                if source_idx is not None and isinstance(source_idx, int) and 0 <= source_idx < len(image_list):
                    source_image = image_list[source_idx]
                elif len(image_list) == 1:
                    source_image = image_list[0]
                else:
                    # Distribute items across images proportionally
                    source_image = image_list[min(idx, len(image_list) - 1)]
                
                # Normalize enums and bounds
                quantity = 1.0
                try:
                    quantity = float(item_data.get('quantity', 1.0))
                    if quantity <= 0:
                        quantity = 1.0
                except (ValueError, TypeError):
                    pass

                unit = safe_str(item_data.get('unit'), 'pcs').lower()
                allowed_units = ['kg', 'g', 'l', 'ml', 'pcs', 'pack', 'bottle', 'box', 'dozen', 'bunch', 'packet']
                if unit not in allowed_units:
                    if unit in ('liter', 'liters', 'l'):
                        unit = 'l'
                    elif unit in ('gram', 'grams', 'g'):
                        unit = 'g'
                    else:
                        unit = 'pcs'

                zone = safe_str(item_data.get('storage_zone'), 'pantry').lower()
                allowed_zones = ['fridge', 'freezer', 'pantry', 'counter', 'cabinet', 'basket', 'spice']
                if zone not in allowed_zones:
                    zone = 'pantry'

                raw_icon = safe_str(item_data.get('icon_key'), 'grocery').lower()
                allowed_icons = ['vegetables', 'fruits', 'dairy', 'grains', 'beverage', 'spices', 'grocery']
                icon_key = raw_icon if raw_icon in allowed_icons else 'grocery'

                warnings_list = item_data.get('warnings')
                if not isinstance(warnings_list, list):
                    warnings_list = []

                ScanCandidate.objects.create(
                    scan_session=session,
                    source_image=source_image,
                    name=safe_str(item_data.get('name'), 'Unknown Item')[:150],
                    brand=safe_str(item_data.get('brand'), '')[:100],
                    description=safe_str(item_data.get('description'), ''),
                    icon_key=icon_key[:50],
                    category=safe_str(item_data.get('category'), 'Vegetables')[:100],
                    quantity=quantity,
                    unit=unit[:20],
                    storage_zone=zone[:20],
                    expiry_date=parse_date_str(item_data.get('expiry_date')),
                    manufacturing_date=parse_date_str(item_data.get('manufacturing_date')),
                    packed_date=parse_date_str(item_data.get('packed_date')),
                    best_before_date=parse_date_str(item_data.get('best_before_date')),
                    date_type=safe_str(item_data.get('date_type'), 'unknown')[:30],
                    date_source=safe_str(item_data.get('date_source'), 'unknown')[:30],
                    date_confidence=safe_str(item_data.get('date_confidence'), 'Low')[:20],
                    raw_date_text=safe_str(item_data.get('raw_date_text'), ''),
                    storage_reason=safe_str(item_data.get('storage_reason'), ''),
                    shelf_life_guidance=safe_str(item_data.get('shelf_life_guidance'), ''),
                    confidence=safe_str(item_data.get('confidence'), 'High')[:20],
                )
                candidate_count += 1

            # Mark all processed images as completed
            for scan_image in images:
                scan_image.status = ScanImage.Statuses.COMPLETED
                scan_image.save(update_fields=['status'])
                successful_count += 1

    except Exception as e:
        logger.error(f"Error processing images for session {session_id}: {str(e)}", exc_info=True)
        # Directly mark images failed and record error message so client receives error immediately
        for scan_image in images:
            scan_image.status = ScanImage.Statuses.FAILED
            scan_image.error_message = str(e)
            scan_image.save(update_fields=['status', 'error_message'])
            failed_count += 1

    finally:
        # Update session status
        session.successful_image_count = successful_count
        session.failed_image_count = failed_count
        session.candidate_count = candidate_count
        
        if failed_count == 0 and successful_count > 0:
            session.status = ScanSession.Statuses.COMPLETED
        elif successful_count > 0 and failed_count > 0:
            session.status = ScanSession.Statuses.PARTIAL
        else:
            session.status = ScanSession.Statuses.FAILED
            
        session.completed_at = timezone.now()
        session.save(update_fields=['status', 'successful_image_count', 'failed_image_count', 'candidate_count', 'completed_at'])
        
        elapsed = time.time() - start_time
        logger.info(
            f"Completed scan processing task for session {session_id} in {elapsed:.2f}s: "
            f"status={session.status}, candidates={candidate_count}, failed_images={failed_count}"
        )
        connection.close_if_unusable_or_obsolete()

    return True
