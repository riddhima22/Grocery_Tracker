from rest_framework import viewsets, status
from rest_framework.response import Response
from rest_framework.decorators import action
from django.db import transaction
from django.utils import timezone
from .models import ScanSession, ScanImage, ScanCandidate
from .serializers import ScanSessionSerializer, ScanCandidateSerializer
from .tasks import process_scan_session_task
from apps.groceries.models import GroceryItem, GroceryActivity
from apps.groceries.serializers import GroceryItemSerializer
from common.exceptions import ResourceNotFoundException, ForbiddenException
import uuid
import os

class ScanSessionViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = ScanSessionSerializer

    def get_queryset(self):
        # Scoped to request.user to prevent IDOR
        return ScanSession.objects.filter(user=self.request.user)

    def create(self, request, *args, **kwargs):
        images_files = request.FILES.getlist('images')
        
        if not images_files:
            return Response({"success": False, "error": "No images provided."}, status=400)
            
        if len(images_files) > 10:
            return Response({"success": False, "error": "Maximum 10 images allowed per scan session."}, status=400)

        # Validate total request size
        total_size = sum(img.size for img in images_files)
        import logging
        logging.getLogger('freshtrack.scans.views').info(
            f"Received scan upload request with {len(images_files)} image(s) ({total_size / 1024:.1f} KB total) from user {request.user}"
        )
        if total_size > 20 * 1024 * 1024: # 20MB limit
            return Response({"success": False, "error": "Total upload size exceeds 20MB limit."}, status=400)

        # Validate file sizes, content types, and duplicate files by hash
        import hashlib
        seen_request_hashes = set()

        from PIL import Image
        ALLOWED_IMAGE_FORMATS = {
            '.jpg': 'JPEG',
            '.jpeg': 'JPEG',
            '.png': 'PNG',
            '.webp': 'WEBP',
        }

        for img in images_files:
            if img.size > 5 * 1024 * 1024: # 5MB limit
                return Response({"success": False, "error": f"Image {img.name} exceeds 5MB size limit."}, status=400)
            
            ext = os.path.splitext(img.name)[1].lower()
            if ext not in ALLOWED_IMAGE_FORMATS:
                return Response({"success": False, "error": f"Unsupported file type: {ext}."}, status=400)

            # Validate real image content using Pillow
            try:
                img.seek(0)
                with Image.open(img) as pil_img:
                    pil_img.verify()
                    actual_format = pil_img.format
                if actual_format != ALLOWED_IMAGE_FORMATS[ext]:
                    return Response({
                        "success": False,
                        "error": f"Image format mismatch for {img.name}: file is {actual_format}, but extension is {ext}."
                    }, status=400)
            except Exception:
                return Response({"success": False, "error": f"File {img.name} is not a valid image."}, status=400)
            finally:
                img.seek(0)

            # Check duplicate content hashes
            hasher = hashlib.md5()
            for chunk in img.chunks():
                hasher.update(chunk)
            img.seek(0)
            img_hash = hasher.hexdigest()
            if img_hash in seen_request_hashes:
                return Response({"success": False, "error": f"Duplicate image uploaded: {img.name}."}, status=400)
            seen_request_hashes.add(img_hash)

        with transaction.atomic():
            session = ScanSession.objects.create(
                user=request.user,
                status=ScanSession.Statuses.PENDING,
                image_count=len(images_files)
            )
            for file in images_files:
                ScanImage.objects.create(
                    scan_session=session,
                    image=file,
                    status=ScanImage.Statuses.PENDING
                )

        # Enqueue background processing via Celery
        try:
            process_scan_session_task.delay(str(session.id))
        except Exception as queue_err:
            logger.warning(f"Celery delay failed, executing task synchronously as fallback: {queue_err}")
            process_scan_session_task.apply(args=(str(session.id),))

        return Response({
            "success": True,
            "data": ScanSessionSerializer(session).data,
            "message": "Images uploaded and AI processing queued."
        }, status=status.HTTP_201_CREATED)


    @action(detail=True, methods=['get'])
    def candidates(self, request, pk=None):
        session = self.get_object()
        candidates = session.candidates.all()
        return Response({
            "success": True,
            "data": ScanCandidateSerializer(candidates, many=True).data
        })

    @action(detail=True, methods=['post'])
    def confirm(self, request, pk=None):
        session = self.get_object()
        idempotency_key = request.data.get('idempotency_key')
        session_obj = session

        with transaction.atomic():
            # Acquire row lock to ensure concurrency safety
            session = ScanSession.objects.select_for_update().get(pk=session_obj.pk)

            # Verify idempotency key if provided
            if idempotency_key:
                try:
                    key_uuid = uuid.UUID(str(idempotency_key))
                    if session.idempotency_key == key_uuid or session.created_groceries.exists():
                        confirmed_items = session.created_groceries.all()
                        return Response({
                            "success": True,
                            "data": GroceryItemSerializer(confirmed_items, many=True).data,
                            "message": "Scan already confirmed previously (idempotent)."
                        })
                except ValueError:
                    return Response({"success": False, "error": "Invalid idempotency key format."}, status=400)

            if session.created_groceries.exists():
                confirmed_items = session.created_groceries.all()
                return Response({
                    "success": True,
                    "data": GroceryItemSerializer(confirmed_items, many=True).data,
                    "message": "Scan session has already been confirmed."
                })

            # Get candidates to add (fallback to all candidates if selected_ids is empty)
            selected_ids = request.data.get('candidate_ids', [])
            if selected_ids:
                candidates = session.candidates.filter(id__in=selected_ids)
            else:
                candidates = session.candidates.all()

            if not candidates.exists():
                return Response({"success": False, "error": "Selected candidates not found or already processed."}, status=400)

            created_groceries = []

            def sanitize_unit(u):
                if not u: return 'pcs'
                u_str = str(u).lower().strip()
                if u_str in ['kg', 'g', 'l', 'ml', 'pcs', 'pack', 'bottle', 'box', 'dozen']:
                    return 'L' if u_str == 'l' else u_str
                if u_str in ['packet', 'packets', 'pkt']: return 'pack'
                if u_str in ['piece', 'pieces', 'pc']: return 'pcs'
                if u_str in ['bunch', 'bunches']: return 'pcs'
                if u_str in ['liter', 'liters', 'litre', 'litres']: return 'L'
                if u_str in ['gram', 'grams', 'gm']: return 'g'
                return 'pcs'

            def sanitize_zone(z):
                if not z: return 'pantry'
                z_str = str(z).lower().strip()
                if z_str in ['fridge', 'freezer', 'pantry', 'counter', 'cabinet', 'basket', 'spice']:
                    return z_str
                if 'fridge' in z_str or 'refrigerator' in z_str or 'chiller' in z_str: return 'fridge'
                if 'freezer' in z_str: return 'freezer'
                if 'basket' in z_str: return 'basket'
                if 'spice' in z_str: return 'spice'
                if 'counter' in z_str: return 'counter'
                return 'pantry'

            def sanitize_confidence(c):
                if not c: return 'Low'
                c_str = str(c).strip().capitalize()
                if c_str in ['High', 'Medium', 'Low']: return c_str
                return 'Low'

            from apps.groceries.prediction_engine import calculate_item_shelf_life
            import datetime

            def to_calendar_date(val):
                if val is None:
                    return None
                if isinstance(val, datetime.datetime):
                    return val.date()
                if isinstance(val, datetime.date):
                    return val
                if isinstance(val, str):
                    val = val.strip()
                    if not val:
                        return None
                    try:
                        return datetime.date.fromisoformat(val[:10])
                    except Exception:
                        pass
                    try:
                        from dateutil import parser
                        return parser.parse(val).date()
                    except Exception:
                        return None
                return None

            user = request.user
            for candidate in candidates:
                # Semantic Expiry Rule:
                # If package had a printed date, expiry_date is set and is_expiry_estimated is False.
                # If no printed date, expiry_date remains None, estimated_consumption_date is populated.
                is_estimated = candidate.is_expiry_estimated or (candidate.expiry_date is None)
                if is_estimated:
                    exp_date = None
                    est_date = to_calendar_date(candidate.estimated_consumption_date)
                    if not est_date:
                        days = calculate_item_shelf_life(candidate.name, candidate.category, candidate.storage_zone)
                        est_date = timezone.localdate() + datetime.timedelta(days=days)
                else:
                    exp_date = to_calendar_date(candidate.expiry_date)
                    est_date = None

                unit_val = sanitize_unit(candidate.unit)
                zone_val = sanitize_zone(candidate.storage_zone)
                conf_val = sanitize_confidence(candidate.confidence)
                date_conf_val = sanitize_confidence(candidate.date_confidence)

                mfg_date = to_calendar_date(candidate.manufacturing_date)
                pck_date = to_calendar_date(candidate.packed_date)
                bb_date = to_calendar_date(candidate.best_before_date)
                purch_date = timezone.localdate()

                # Add item with explicit relationship to this scan session
                item = GroceryItem.objects.create(
                    user=request.user,
                    scan_session=session,
                    name=candidate.name,
                    brand=candidate.brand,
                    description=candidate.description or f"Fresh {candidate.name} stored in {zone_val.capitalize()}.",
                    icon_key=candidate.icon_key,
                    category=candidate.category,
                    quantity=candidate.quantity,
                    unit=unit_val,
                    storage_zone=zone_val,
                    expiry_date=exp_date,
                    estimated_consumption_date=est_date,
                    is_expiry_estimated=is_estimated,
                    predicted_expiry=est_date or exp_date,
                    recommended_consumption_date=est_date or exp_date,
                    manufacturing_date=mfg_date,
                    packed_date=pck_date,
                    best_before_date=bb_date,
                    purchase_date=purch_date,
                    date_type=candidate.date_type or ('estimated' if is_estimated else 'expiry'),
                    date_source=candidate.date_source or ('calculated_shelf_life' if is_estimated else 'ocr_verified'),
                    date_confidence=date_conf_val,
                    raw_date_text=candidate.raw_date_text,
                    storage_reason=candidate.storage_reason,
                    shelf_life_guidance=candidate.shelf_life_guidance,
                    ai_detected=True,
                    ai_confidence=conf_val
                )

                # Record Activity
                GroceryActivity.objects.create(
                    user=request.user,
                    grocery_item=item,
                    activity_type=GroceryActivity.ActivityTypes.SCAN_CONFIRMED,
                    new_quantity=item.quantity,
                    unit=item.unit
                )

                user.total_tracked += 1
                created_groceries.append(item)

            user.save(update_fields=['total_tracked'])


            # Set session completed & save key
            if idempotency_key:
                try:
                    session.idempotency_key = uuid.UUID(str(idempotency_key))
                except Exception:
                    pass
            session.status = ScanSession.Statuses.COMPLETED
            session.save()

            # Remove candidate items from session reviews
            candidates.delete()

        # Safely clean up local temporary images
        for scan_image in session.images.all():
            try:
                if scan_image.image and hasattr(scan_image.image, 'path') and os.path.exists(scan_image.image.path):
                    os.remove(scan_image.image.path)
            except Exception:
                pass

        return Response({
            "success": True,
            "data": GroceryItemSerializer(created_groceries, many=True).data,
            "message": f"Successfully added {len(created_groceries)} items to your kitchen."
        })


class ScanCandidateViewSet(viewsets.ModelViewSet):
    serializer_class = ScanCandidateSerializer
    
    def get_queryset(self):
        # Prevent IDOR: candidates scoped to session owned by request.user
        return ScanCandidate.objects.filter(scan_session__user=self.request.user)

    def perform_update(self, serializer):
        serializer.save()

    def perform_destroy(self, instance):
        instance.delete()
