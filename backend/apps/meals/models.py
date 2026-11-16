import os
import uuid

from django.conf import settings
from django.db import models

from apps.groceries.models import GroceryItem


def get_meal_log_image_path(instance, filename):
    ext = filename.split('.')[-1]
    name = f"{uuid.uuid4()}.{ext}"
    return os.path.join('meal_logs', name)

class MealLog(models.Model):
    class StatusChoices(models.TextChoices):
        PENDING_CONFIRMATION = 'pending_confirmation', 'Pending Confirmation'
        CONFIRMED = 'confirmed', 'Confirmed'
        CANCELLED = 'cancelled', 'Cancelled'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='meal_logs')
    image = models.ImageField(upload_to=get_meal_log_image_path, null=True, blank=True)
    name = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    status = models.CharField(max_length=50, choices=StatusChoices.choices, default=StatusChoices.PENDING_CONFIRMATION)
    confirmed_at = models.DateTimeField(null=True, blank=True)
    deduction_result = models.JSONField(default=dict, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.name} by {self.user.email}"

class MealIngredientCandidate(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    meal_log = models.ForeignKey(MealLog, on_delete=models.CASCADE, related_name='candidates')
    pantry_item = models.ForeignKey(GroceryItem, on_delete=models.SET_NULL, null=True, blank=True)
    name = models.CharField(max_length=255)
    estimated_quantity = models.DecimalField(max_digits=7, decimal_places=2)
    deduct_quantity = models.DecimalField(max_digits=7, decimal_places=2, default=0.0)
    unit = models.CharField(max_length=50)
    confidence = models.CharField(max_length=50)
    confirmed = models.BooleanField(default=True)

    def __str__(self):
        return f"{self.name} for {self.meal_log.name}"
