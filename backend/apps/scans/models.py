from django.db import models
from django.conf import settings
import uuid
import os

def get_temp_image_path(instance, filename):
    ext = filename.split('.')[-1]
    name = f"{uuid.uuid4()}.{ext}"
    return os.path.join('temp_scans', str(instance.scan_session.id), name)

class ScanSession(models.Model):
    class Statuses(models.TextChoices):
        PENDING = 'pending', 'Pending'
        PROCESSING = 'processing', 'Processing'
        COMPLETED = 'completed', 'Completed'
        PARTIAL = 'partial_success', 'Partial Success'
        FAILED = 'failed', 'Failed'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='scan_sessions')
    
    status = models.CharField(max_length=30, choices=Statuses.choices, default=Statuses.PENDING)
    image_count = models.PositiveIntegerField(default=0)
    successful_image_count = models.PositiveIntegerField(default=0)
    failed_image_count = models.PositiveIntegerField(default=0)
    candidate_count = models.PositiveIntegerField(default=0)
    
    idempotency_key = models.UUIDField(null=True, blank=True, unique=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Scan Session {self.id} - {self.status}"


class ScanImage(models.Model):
    class Statuses(models.TextChoices):
        PENDING = 'pending', 'Pending'
        COMPLETED = 'completed', 'Completed'
        FAILED = 'failed', 'Failed'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    scan_session = models.ForeignKey(ScanSession, on_delete=models.CASCADE, related_name='images')
    
    image = models.ImageField(upload_to=get_temp_image_path)
    status = models.CharField(max_length=20, choices=Statuses.choices, default=Statuses.PENDING)
    error_message = models.TextField(blank=True)
    
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Scan Image {self.id} - {self.status}"


class ScanCandidate(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    scan_session = models.ForeignKey(ScanSession, on_delete=models.CASCADE, related_name='candidates')
    source_image = models.ForeignKey(ScanImage, on_delete=models.SET_NULL, null=True, blank=True, related_name='candidates')
    
    name = models.CharField(max_length=150)
    brand = models.CharField(max_length=100, blank=True)
    description = models.TextField(blank=True)
    icon_key = models.CharField(max_length=50, default='grocery')
    category = models.CharField(max_length=100, default='Uncategorized')
    
    quantity = models.DecimalField(max_digits=7, decimal_places=2, default=1.0)
    unit = models.CharField(max_length=20, default='pcs')
    storage_zone = models.CharField(max_length=20, default='pantry')
    
    expiry_date = models.DateField(null=True, blank=True)
    estimated_consumption_date = models.DateField(null=True, blank=True)
    is_expiry_estimated = models.BooleanField(default=False, db_default=False)
    manufacturing_date = models.DateField(null=True, blank=True)
    packed_date = models.DateField(null=True, blank=True)
    best_before_date = models.DateField(null=True, blank=True)
    date_type = models.CharField(max_length=30, default='unknown')
    date_source = models.CharField(max_length=30, default='unknown')
    date_confidence = models.CharField(max_length=20, default='Low')
    raw_date_text = models.TextField(blank=True)
    storage_reason = models.TextField(blank=True)
    shelf_life_guidance = models.TextField(blank=True)
    confidence = models.CharField(max_length=20, default='High')
    validation_warnings = models.JSONField(default=list, blank=True)
    
    selected = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def _resolve_is_expiry_estimated(self) -> bool:
        """
        Determines whether the expiry date is estimated:
        - True when the expiry date/shelf life was estimated/calculated.
        - False when the expiry date is not estimated (explicitly known/printed).
        - False when both expiry and shelf-life are None (calculation returns NULL).
        """
        if self.expiry_date is None and self.estimated_consumption_date is None:
            return False
        if self.estimated_consumption_date is not None:
            return True
        if self.date_type == 'estimated' or self.date_source == 'calculated_shelf_life':
            return True
        return False

    def clean(self):
        super().clean()
        if self.is_expiry_estimated is None:
            self.is_expiry_estimated = self._resolve_is_expiry_estimated()
        else:
            self.is_expiry_estimated = bool(self.is_expiry_estimated)

    def save(self, *args, **kwargs):
        import datetime
        for date_field in ('expiry_date', 'estimated_consumption_date', 'manufacturing_date', 'packed_date', 'best_before_date'):
            val = getattr(self, date_field, None)
            if isinstance(val, datetime.datetime):
                setattr(self, date_field, val.date())

        # If date is estimated, ensure date is in estimated_consumption_date
        if (self.date_type == 'estimated' or self.date_source == 'calculated_shelf_life') and self.estimated_consumption_date is None and self.expiry_date is not None:
            self.estimated_consumption_date = self.expiry_date
            self.expiry_date = None

        # Guard against NULL reaching the database
        if self.is_expiry_estimated is None:
            self.is_expiry_estimated = self._resolve_is_expiry_estimated()
        else:
            self.is_expiry_estimated = bool(self.is_expiry_estimated)

        super().save(*args, **kwargs)


    def __str__(self):
        return f"Candidate: {self.name} ({self.quantity} {self.unit})"
