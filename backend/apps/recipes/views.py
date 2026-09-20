from rest_framework import viewsets, status
from rest_framework.response import Response
from rest_framework.decorators import action
from django.db import transaction
from django.utils import timezone
from .models import Recipe
from .serializers import RecipeSerializer
from apps.groceries.models import GroceryItem
from apps.groceries.services import deduct_pantry_items_bulk
from integrations.ai.ai_service import AIService
from integrations.ai.gemini_client import AIContentBlockedError
from common.exceptions import ResourceNotFoundException, ForbiddenException
import logging
import datetime

logger = logging.getLogger('freshtrack.recipes')

class RecipeViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = RecipeSerializer

    def get_queryset(self):
        # Scoped to request.user to prevent IDOR
        return Recipe.objects.filter(user=self.request.user).order_by('-created_at')

    @action(detail=False, methods=['post'])
    def generate(self, request):
        user = request.user
        
        # 1. Fetch available active groceries (name + expiry info), prioritizing near-expiry
        groceries = GroceryItem.objects.filter(user=user, quantity__gt=0).exclude(status='expired')
        grocery_data = []
        for g in groceries:
            days_left = None
            if g.expiry_date:
                days_left = (g.expiry_date - timezone.now().date()).days
            grocery_data.append({
                "pantry_item_id": str(g.id),
                "name": g.name,
                "quantity": float(g.quantity),
                "unit": g.unit,
                "days_to_expiry": days_left if days_left is not None else 999,
                "status": g.status
            })
            
        if not grocery_data:
            return Response({
                "success": False, 
                "error": "You do not have any active fresh/expiring items in your kitchen to generate recipes from."
            }, status=400)

        # Sort so expiring items (lowest days) are prioritized
        grocery_data.sort(key=lambda x: x["days_to_expiry"])

        # 2. Extract preferences with request overrides
        preferences = {
            "diet_type": request.data.get('diet_type', user.diet_type),
            "cuisine_pref": request.data.get('cuisine_pref', user.cuisine_pref or "Indian"),
            "allergies": request.data.get('allergies', user.allergies or []),
            "household_size": int(request.data.get('household_size', user.household_size)),
            "max_prep_time_mins": int(request.data.get('max_prep_time_mins', 60)),
            "meal_type": request.data.get('meal_type', 'any')
        }

        # 3. Call AI service securely through multi-provider fallback wrapper
        ai_service = AIService()
        try:
            ai_output = ai_service.generate_recipes(grocery_data, preferences)
            recipes_data = ai_output.get('recipes', [])
        except AIContentBlockedError as e:
            logger.warning(f"Recipe generation content blocked: {e}")
            return Response({"success": False, "error": "The recipe request couldn't be processed — try adjusting your preferences or ingredients."}, status=400)
        except Exception as e:
            logger.error(f"Recipe generation failed: {str(e)}", exc_info=True)
            return Response({"success": False, "error": "AI recipe generator is temporarily unavailable."}, status=502)

        created_recipes = []
        with transaction.atomic():
            for r in recipes_data:
                # Validate allergy checks against user recorded allergies
                allergens_list = r.get('allergens', [])
                warning = ""
                matched_allergies = [a for a in allergens_list if a.lower() in [ua.lower() for ua in preferences['allergies']]]
                if matched_allergies:
                    warning = f"ALLERGY WARNING: Contains ingredients related to your allergy to {', '.join(matched_allergies)}."

                recipe = Recipe.objects.create(
                    user=user,
                    name=r.get('name', 'Pantry Stew'),
                    icon_key=r.get('icon_key', 'restaurant'),
                    cuisine=r.get('cuisine', 'Mixed'),
                    diet_type=r.get('diet_type', 'veg'),
                    prep_time_mins=r.get('prep_time_mins', 25),
                    calories_per_serving=r.get('calories_per_serving', 200),
                    servings=r.get('servings', 2),
                    ingredients_used=r.get('ingredients_used', []),
                    other_ingredients=r.get('other_ingredients', []),
                    allergens=allergens_list,
                    steps=r.get('steps', []),
                    nutrition=r.get('nutrition', {}),
                    tip=r.get('tip', ''),
                    allergen_warning=warning or r.get('allergen_warning', '')
                )
                created_recipes.append(recipe)

        serializer = RecipeSerializer(created_recipes, many=True)
        return Response({
            "success": True,
            "data": serializer.data,
            "message": f"Successfully generated {len(created_recipes)} recipes."
        })

    @action(detail=True, methods=['post'], url_path='mark-cooked')
    def mark_cooked(self, request, pk=None):
        recipe = self.get_object()
        
        with transaction.atomic():
            user = request.user
            
            # Deduct items
            summary, errors = deduct_pantry_items_bulk(user, recipe.ingredients_used, activity_source='recipe_cooked')
            
            user.recipes_cooked += 1
            user.save(update_fields=['recipes_cooked'])
            
            return Response({
                "success": True,
                "data": {
                    "recipes_cooked": user.recipes_cooked,
                    "deduction_summary": summary,
                    "deduction_errors": errors
                },
                "message": f"Recipe '{recipe.name}' marked as cooked!"
            })
