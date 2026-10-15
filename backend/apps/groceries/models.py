from django.db import models
from django.conf import settings
from django.utils import timezone
import uuid

class GroceryItem(models.Model):
    class StorageZones(models.TextChoices):
        FRIDGE = 'fridge', 'Fridge'
        FREEZER = 'freezer', 'Freezer'
        PANTRY = 'pantry', 'Pantry'
        COUNTER = 'counter', 'Counter'
        CABINET = 'cabinet', 'Cabinet'
        BASKET = 'basket', 'Basket'
        SPICE = 'spice', 'Spice'

    class Units(models.TextChoices):
        KG = 'kg', 'kg'
        G = 'g', 'g'
        L = 'L', 'L'
        ML = 'ml', 'ml'
        PCS = 'pcs', 'pcs'
        PACK = 'pack', 'pack'
        BOTTLE = 'bottle', 'bottle'
        BOX = 'box', 'box'
        DOZEN = 'dozen', 'dozen'
        PACKET = 'packet', 'packet'
        JAR = 'jar', 'jar'
        CAN = 'can', 'can'
        POUCH = 'pouch', 'pouch'

    class Confidence(models.TextChoices):
        HIGH = 'High', 'High'
        MEDIUM = 'Medium', 'Medium'
        LOW = 'Low', 'Low'

    class RipenessLevels(models.TextChoices):
        UNRIPE = 'unripe', 'Unripe'
        RIPE = 'ripe', 'Ripe'
        OVERRIPE = 'overripe', 'Overripe'
        NA = 'not_applicable', 'Not Applicable'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='groceries')
    
    name = models.CharField(max_length=150)
    brand = models.CharField(max_length=100, blank=True)
    description = models.TextField(blank=True)
    icon_key = models.CharField(max_length=50, default='grocery')
    category = models.CharField(max_length=100, default='Uncategorized')
    barcode = models.CharField(max_length=50, blank=True)
    
    quantity = models.DecimalField(max_digits=7, decimal_places=2, default=1.0)
    unit = models.CharField(max_length=20, choices=Units.choices, default=Units.PCS)
    unit_category = models.CharField(max_length=30, blank=True, default='')
    package_type = models.CharField(max_length=30, blank=True, default='')
    net_content_value = models.DecimalField(max_digits=7, decimal_places=2, null=True, blank=True)
    net_content_unit = models.CharField(max_length=20, blank=True, default='')
    package_count = models.PositiveIntegerField(null=True, blank=True)
    identification_source = models.CharField(max_length=30, blank=True, default='')
    unit_confidence = models.CharField(max_length=20, blank=True, default='High')
    storage_zone = models.CharField(max_length=20, choices=StorageZones.choices, default=StorageZones.PANTRY)
    storage_notes = models.TextField(blank=True)
    scan_session = models.ForeignKey('scans.ScanSession', on_delete=models.SET_NULL, null=True, blank=True, related_name='created_groceries')
    
    expiry_date = models.DateField(null=True, blank=True)
    estimated_consumption_date = models.DateField(null=True, blank=True)
    is_expiry_estimated = models.BooleanField(default=False, db_default=False)
    manufacturing_date = models.DateField(null=True, blank=True)
    packed_date = models.DateField(null=True, blank=True)
    best_before_date = models.DateField(null=True, blank=True)
    date_type = models.CharField(max_length=30, default='unknown')
    date_source = models.CharField(max_length=30, default='unknown')
    date_confidence = models.CharField(max_length=20, choices=Confidence.choices, default=Confidence.LOW)
    raw_date_text = models.TextField(blank=True)
    storage_reason = models.TextField(blank=True)
    shelf_life_guidance = models.TextField(blank=True)
    purchase_date = models.DateField(default=timezone.localdate)
    
    # Server-side auto calculated fields
    status = models.CharField(max_length=20, default='fresh')
    
    # Metrics
    calories_per_100g = models.PositiveIntegerField(null=True, blank=True)
    allergens = models.JSONField(default=list, blank=True)
    
    # AI Predictions & Parameters
    ripeness = models.CharField(max_length=30, choices=RipenessLevels.choices, default=RipenessLevels.NA)
    temperature = models.DecimalField(max_digits=5, decimal_places=2, default=20.00)
    humidity = models.DecimalField(max_digits=5, decimal_places=2, default=50.00)
    is_opened = models.BooleanField(default=False)
    freshness_score = models.PositiveIntegerField(default=100)
    predicted_expiry = models.DateField(null=True, blank=True)
    recommended_consumption_date = models.DateField(null=True, blank=True)
    confidence_score = models.DecimalField(max_digits=4, decimal_places=3, default=1.000)
    
    storage_recommendation_why = models.TextField(blank=True)
    storage_recommendation_how = models.TextField(blank=True)
    storage_recommendation_shelf_life = models.TextField(blank=True)
    ai_explanation = models.TextField(blank=True)

    # Detections
    ai_detected = models.BooleanField(default=False)
    ai_confidence = models.CharField(max_length=20, choices=Confidence.choices, null=True, blank=True)
    
    # Alarm flags
    notified_3d = models.BooleanField(default=False)
    notified_1d = models.BooleanField(default=False)
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['user', 'status']),
            models.Index(fields=['user', 'expiry_date']),
            models.Index(fields=['user', 'storage_zone']),
            models.Index(fields=['user', 'created_at']),
        ]
        constraints = [
            models.CheckConstraint(
                check=models.Q(quantity__gte=0),
                name='grocery_quantity_non_negative'
            )
        ]

    def _resolve_is_expiry_estimated(self) -> bool:
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
        # Ensure all calendar DateFields are pure datetime.date instances (not datetime.datetime)
        for date_field in (
            'expiry_date', 'estimated_consumption_date', 'manufacturing_date', 'packed_date',
            'best_before_date', 'purchase_date', 'predicted_expiry',
            'recommended_consumption_date'
        ):
            val = getattr(self, date_field, None)
            if isinstance(val, datetime.datetime):
                setattr(self, date_field, val.date())

        # Ensure is_expiry_estimated is strictly boolean and never NULL
        if self.is_expiry_estimated is None:
            self.is_expiry_estimated = self._resolve_is_expiry_estimated()
        else:
            self.is_expiry_estimated = bool(self.is_expiry_estimated)

        # Calculate status server-side based on actual expiry date or estimated consumption date
        if self.status not in ['consumed', 'wasted']:
            effective_date = self.expiry_date or self.estimated_consumption_date or self.predicted_expiry
            if effective_date is None:
                self.status = 'fresh'
            else:
                days_left = (effective_date - timezone.localdate()).days
                if days_left < 0:
                    self.status = 'expired'
                elif days_left <= 3:
                    self.status = 'expiring'
                else:
                    self.status = 'fresh'
        super().save(*args, **kwargs)


    def __str__(self):
        return f"{self.name} ({self.quantity} {self.unit})"


class GroceryActivity(models.Model):
    class ActivityTypes(models.TextChoices):
        ITEM_ADDED = 'item_added', 'Item Added'
        SCAN_CONFIRMED = 'scan_confirmed', 'Scan Confirmed'
        QUANTITY_INCREASED = 'quantity_increased', 'Quantity Increased'
        QUANTITY_DECREASED = 'quantity_decreased', 'Quantity Decreased'
        QUANTITY_CORRECTED = 'quantity_corrected', 'Quantity Corrected'
        CONSUMED = 'consumed', 'Consumed'
        WASTED = 'wasted', 'Wasted'
        ITEM_UPDATED = 'item_updated', 'Item Updated'
        ITEM_DELETED = 'item_deleted', 'Item Deleted'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='activities')
    grocery_item = models.ForeignKey(GroceryItem, on_delete=models.SET_NULL, null=True, blank=True, related_name='activities')
    
    activity_type = models.CharField(max_length=50, choices=ActivityTypes.choices)
    previous_quantity = models.DecimalField(max_digits=7, decimal_places=2, null=True, blank=True)
    new_quantity = models.DecimalField(max_digits=7, decimal_places=2, null=True, blank=True)
    unit = models.CharField(max_length=20, blank=True)
    
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user.email} - {self.activity_type} - {self.created_at}"
