from rest_framework import serializers

from .models import MealIngredientCandidate, MealLog


class MealIngredientCandidateSerializer(serializers.ModelSerializer):
    class Meta:
        model = MealIngredientCandidate
        fields = ['id', 'pantry_item', 'name', 'estimated_quantity', 'deduct_quantity', 'unit', 'confidence', 'confirmed']

class MealLogSerializer(serializers.ModelSerializer):
    candidates = MealIngredientCandidateSerializer(many=True, read_only=True)

    class Meta:
        model = MealLog
        fields = ['id', 'user', 'image', 'name', 'description', 'status', 'created_at', 'updated_at', 'candidates']
        read_only_fields = ['id', 'user', 'status', 'created_at', 'updated_at']
