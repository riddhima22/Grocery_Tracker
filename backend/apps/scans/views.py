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
        if total_size > 20 * 1024 * 1024: # 20MB limit
            return Response({"success": False, "error": "Total upload size exceeds 20MB limit."}, status=400)

        # Validate file sizes, content types, and duplicate files by hash
        import hashlib
        seen_request_hashes = set()

        for img in images_files:
            if img.size > 5 * 1024 * 1024: # 5MB limit
                return Response({"success": False, "error": f"Image {img.name} exceeds 5MB size limit."}, status=400)
            
            ext = os.path.splitext(img.name)[1].lower()
            if ext not in ['.jpg', '.jpeg', '.png', '.webp']:
                return Response({"success": False, "error": f"Unsupported file type: {ext}."}, status=400)

            # Check duplicate content hashes
            hasher = hashlib.md5()
            for chunk in img.chunks():
                hasher.update(chunk)
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

        # Spawn background task.
        # Uses Celery if available, and gracefully falls back to a daemon thread
        import threading
        import logging
        from django.conf import settings
        
        task_logger = logging.getLogger('freshtrack.scans.views')

        if getattr(settings, 'CELERY_TASK_ALWAYS_EAGER', False):
            threading.Thread(
                target=process_scan_session_task,
                args=(str(session.id),),
                daemon=True
            ).start()
        else:
            try:
                process_scan_session_task.delay(str(session.id))
            except Exception as celery_err:
                task_logger.warning(
                    f"Celery queue unavailable ({celery_err}). Falling back to daemon thread for scan session {session.id}."
                )
                threading.Thread(
                    target=process_scan_session_task,
                    args=(str(session.id),),
                    daemon=True
                ).start()

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
        
        # Verify idempotency key if provided
        if idempotency_key:
            try:
                key_uuid = uuid.UUID(str(idempotency_key))
                if session.idempotency_key == key_uuid:
                    # Already confirmed, return success idempotently
                    confirmed_items = GroceryItem.objects.filter(user=request.user, ai_detected=True, created_at__gte=session.created_at)
                    return Response({
                        "success": True,
                        "data": GroceryItemSerializer(confirmed_items, many=True).data,
                        "message": "Scan already confirmed previously (idempotent)."
                    })
            except ValueError:
                return Response({"success": False, "error": "Invalid idempotency key format."}, status=400)

        # Get candidates to add
        selected_ids = request.data.get('candidate_ids', [])
        if not selected_ids:
            return Response({"success": False, "error": "No candidates selected for saving."}, status=400)

        candidates = session.candidates.filter(id__in=selected_ids)
        if not candidates.exists():
            return Response({"success": False, "error": "Selected candidates not found or already processed."}, status=400)

        created_groceries = []

        with transaction.atomic():
            # Update user stats
            user = request.user
            
            for candidate in candidates:
                # Add item to user kitchen/grocery list
                item = GroceryItem.objects.create(
                    user=request.user,
                    name=candidate.name,
                    brand=candidate.brand,
                    description=candidate.description,
                    icon_key=candidate.icon_key,
                    category=candidate.category,
                    quantity=candidate.quantity,
                    unit=candidate.unit,
                    storage_zone=candidate.storage_zone,
                    expiry_date=candidate.expiry_date,
                    manufacturing_date=candidate.manufacturing_date,
                    packed_date=candidate.packed_date,
                    best_before_date=candidate.best_before_date,
                    date_type=candidate.date_type,
                    date_source=candidate.date_source,
                    date_confidence=candidate.date_confidence,
                    raw_date_text=candidate.raw_date_text,
                    storage_reason=candidate.storage_reason,
                    shelf_life_guidance=candidate.shelf_life_guidance,
                    ai_detected=True,
                    ai_confidence=candidate.confidence
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
                session.idempotency_key = uuid.UUID(str(idempotency_key))
            session.status = ScanSession.Statuses.COMPLETED
            session.save()

            # Remove candidate items from session reviews
            candidates.delete()

        # Safely clean up local temporary images
        for scan_image in session.images.all():
            if scan_image.image and os.path.exists(scan_image.image.path):
                try:
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
