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

    def save(self, *args, **kwargs):
        import datetime
        for date_field in ('expiry_date', 'manufacturing_date', 'packed_date', 'best_before_date'):
            val = getattr(self, date_field, None)
            if isinstance(val, datetime.datetime):
                setattr(self, date_field, val.date())
        super().save(*args, **kwargs)

    def __str__(self):
        return f"Candidate: {self.name} ({self.quantity} {self.unit})"
