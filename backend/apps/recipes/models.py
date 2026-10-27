import uuid

from django.conf import settings
from django.db import models


class Recipe(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='recipes')

    name = models.CharField(max_length=150)
    icon_key = models.CharField(max_length=50, default='restaurant')
    cuisine = models.CharField(max_length=100, blank=True)
    diet_type = models.CharField(max_length=50, default='veg')

    prep_time_mins = models.PositiveIntegerField(default=30)
    calories_per_serving = models.PositiveIntegerField(default=200)
    servings = models.PositiveIntegerField(default=2)

    ingredients_used = models.JSONField(default=list)
    other_ingredients = models.JSONField(default=list)
    allergens = models.JSONField(default=list)
    steps = models.JSONField(default=list)
    nutrition = models.JSONField(default=dict)

    tip = models.TextField(blank=True)
    allergen_warning = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    is_cooked = models.BooleanField(default=False)
    cooked_at = models.DateTimeField(null=True, blank=True)
    cooking_result = models.JSONField(default=dict, blank=True)

    def __str__(self):
        return self.name


class CookEvent(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    recipe = models.ForeignKey(Recipe, on_delete=models.CASCADE, related_name='cook_events')
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='cook_events')
    idempotency_key = models.CharField(max_length=128, blank=True, null=True, db_index=True)
    deduction_summary = models.JSONField(default=list)
    deduction_errors = models.JSONField(default=list)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=['user', 'idempotency_key'],
                condition=models.Q(idempotency_key__isnull=False),
                name='unique_user_recipe_cook_idempotency'
            )
        ]

    def __str__(self):
        return f"CookEvent for {self.recipe.name} by {self.user.email} at {self.created_at}"
