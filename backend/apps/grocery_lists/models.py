import uuid

from django.conf import settings
from django.db import models


class GroceryList(models.Model):
    class Statuses(models.TextChoices):
        ACTIVE = 'active', 'Active'
        COMPLETED = 'completed', 'Completed'
        ARCHIVED = 'archived', 'Archived'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='grocery_lists')

    status = models.CharField(max_length=30, choices=Statuses.choices, default=Statuses.ACTIVE)
    generation_reason = models.CharField(max_length=200, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Grocery List {self.id} ({self.status})"


class GroceryListItem(models.Model):
    class Feedbacks(models.TextChoices):
        PENDING = 'pending', 'Pending'
        ACCEPTED = 'accepted', 'Accepted'
        EDITED = 'edited_then_accepted', 'Edited then Accepted'
        REJECTED = 'rejected', 'Rejected'
        IGNORED = 'ignored', 'Ignored'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    grocery_list = models.ForeignKey(GroceryList, on_delete=models.CASCADE, related_name='items')

    name = models.CharField(max_length=150)
    suggested_quantity = models.DecimalField(max_digits=7, decimal_places=2, default=1.0)
    quantity = models.DecimalField(max_digits=7, decimal_places=2, default=1.0)
    unit = models.CharField(max_length=20, default='pcs')

    reason = models.CharField(max_length=255, blank=True)
    confidence = models.CharField(max_length=20, default='Medium')
    source_signal = models.CharField(max_length=100, blank=True)

    feedback = models.CharField(max_length=30, choices=Feedbacks.choices, default=Feedbacks.PENDING)
    purchased = models.BooleanField(default=False)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.name} - {self.quantity} {self.unit} ({self.feedback})"
