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

                item_name = safe_str(item_data.get('name'), 'Unknown Item')[:150]
                item_category = safe_str(item_data.get('category'), 'Vegetables')[:100]

                # Intelligent storage zone placement: Carbonated drinks & beverages MUST be in fridge
                is_beverage_or_carbonated = (
                    item_category.lower() in ['beverages', 'beverage'] or
                    any(k in item_name.lower() for k in [
                        'carbonated', 'soda', 'coke', 'coca-cola', 'pepsi', 'sprite',
                        'fanta', 'thums up', 'limca', 'mountain dew', '7up', 'dr pepper',
                        'cold drink', 'soft drink', 'sparkling water', 'tonic water',
                        'energy drink', 'red bull', 'sting', 'monster', 'beer'
                    ])
                )
                if is_beverage_or_carbonated:
                    if item_category.lower() not in ['beverages', 'beverage']:
                        item_category = 'Beverages'
                    zone = 'fridge'
                    icon_key = 'beverage'

                # Resolve expiry date semantics: distinguish printed date from estimated consumption
                expiry_dt = parse_date_str(item_data.get('expiry_date'))
                estimated_dt = parse_date_str(item_data.get('estimated_consumption_date'))
                raw_is_estimated = item_data.get('is_expiry_estimated')
                date_type_val = safe_str(item_data.get('date_type'), 'unknown')[:30]
                date_src_val = safe_str(item_data.get('date_source'), 'unknown')[:30]
                raw_date_val = safe_str(item_data.get('raw_date_text'), '')
                date_conf_val = safe_str(item_data.get('date_confidence'), 'Low')[:20]
                shelf_guidance_val = safe_str(item_data.get('shelf_life_guidance'), '')

                is_flagged_estimated = (
                    date_type_val == 'estimated' or
                    date_src_val == 'calculated_shelf_life' or
                    raw_is_estimated is True
                )

                if is_flagged_estimated:
                    is_estimated = True
                    if estimated_dt is None and expiry_dt is not None:
                        estimated_dt = expiry_dt
                        expiry_dt = None
                    date_type_val = 'estimated'
                    date_src_val = 'calculated_shelf_life'
                    if estimated_dt is None:
                        from apps.groceries.prediction_engine import calculate_item_shelf_life
                        real_shelf_days = calculate_item_shelf_life(item_name, item_category, zone)
                        if real_shelf_days:
                            estimated_dt = timezone.now().date() + datetime.timedelta(days=real_shelf_days)
                            raw_date_val = raw_date_val or f"Estimated ~{real_shelf_days} days shelf life ({zone})"
                            if not shelf_guidance_val:
                                shelf_guidance_val = f"Estimated {real_shelf_days} days shelf life based on optimal {zone} storage."
                        else:
                            estimated_dt = None
                            is_estimated = False
                elif expiry_dt is not None:
                    # Packaging has a printed expiry date
                    is_estimated = False
                    estimated_dt = None
                    if date_src_val == 'unknown':
                        date_src_val = 'ocr_verified'
                else:
                    # No printed packaging date exists -> compute estimated shelf life
                    from apps.groceries.prediction_engine import calculate_item_shelf_life
                    real_shelf_days = calculate_item_shelf_life(item_name, item_category, zone)
                    if real_shelf_days:
                        is_estimated = True
                        expiry_dt = None
                        estimated_dt = timezone.now().date() + datetime.timedelta(days=real_shelf_days)
                        date_type_val = 'estimated'
                        date_src_val = 'calculated_shelf_life'
                        date_conf_val = 'Medium'
                        raw_date_val = raw_date_val or f"Estimated ~{real_shelf_days} days shelf life ({zone})"
                        if not shelf_guidance_val:
                            shelf_guidance_val = f"Estimated {real_shelf_days} days shelf life based on optimal {zone} storage."
                    else:
                        is_estimated = False
                        expiry_dt = None
                        estimated_dt = None

                is_estimated = bool(is_estimated)

                ScanCandidate.objects.create(
                    scan_session=session,
                    source_image=source_image,
                    name=item_name,
                    brand=safe_str(item_data.get('brand'), '')[:100],
                    description=safe_str(item_data.get('description'), '') or f"Fresh {item_name} stored in {zone}.",
                    icon_key=icon_key[:50],
                    category=item_category,
                    quantity=quantity,
                    unit=unit[:20],
                    storage_zone=zone[:20],
                    expiry_date=expiry_dt,
                    estimated_consumption_date=estimated_dt,
                    is_expiry_estimated=is_estimated,
                    manufacturing_date=parse_date_str(item_data.get('manufacturing_date')),
                    packed_date=parse_date_str(item_data.get('packed_date')),
                    best_before_date=parse_date_str(item_data.get('best_before_date')),
                    date_type=date_type_val,
                    date_source=date_src_val,
                    date_confidence=date_conf_val,
                    raw_date_text=raw_date_val,
                    storage_reason=safe_str(item_data.get('storage_reason'), '') or (
                        "Keep chilled in refrigerator to preserve carbonation and refreshing fizz."
                        if is_beverage_or_carbonated else ""
                    ),
                    shelf_life_guidance=shelf_guidance_val or (
                        "Store upright in refrigerator at 2-5°C. Never freeze carbonated cans or glass bottles."
                        if is_beverage_or_carbonated else ""
                    ),
                    confidence=safe_str(item_data.get('confidence'), 'High')[:20],
                )
                candidate_count += 1


            # Mark all processed images as completed
            for scan_image in images:
                scan_image.status = ScanImage.Statuses.COMPLETED
                scan_image.save(update_fields=['status'])
                successful_count += 1

    except Exception as e:
        retries = getattr(getattr(self, 'request', None), 'retries', 0)
        max_retries = getattr(self, 'max_retries', 3)
        if is_transient_error(e) and retries < max_retries and hasattr(self, 'retry'):
            countdown = (2 ** retries) * 10
            logger.warning(
                f"Transient error for scan session {session_id} (attempt {retries + 1}/{max_retries}): {e}. "
                f"Retrying in {countdown}s with exponential backoff..."
            )
            connection.close_if_unusable_or_obsolete()
            raise self.retry(exc=e, countdown=countdown)

        logger.error(f"Permanent error or max retries exceeded for session {session_id}: {str(e)}", exc_info=True)
        # Directly mark images failed and record error message
        for scan_image in images:
            scan_image.status = ScanImage.Statuses.FAILED
            scan_image.error_message = str(e)
            scan_image.save(update_fields=['status', 'error_message'])
            failed_count += 1

    finally:
        # If task is retrying, don't finalize the session as failed
        import sys
        exc_type, _, _ = sys.exc_info()
        if exc_type is not None and issubclass(exc_type, Retry):
            logger.info(f"Task for session {session_id} scheduled for retry. Preserving status {session.status}.")
            connection.close_if_unusable_or_obsolete()
        else:
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
