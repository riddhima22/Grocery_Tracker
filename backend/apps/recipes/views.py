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
        today = timezone.localdate() if hasattr(timezone, 'localdate') else timezone.now().date()
        
        # 1. Fetch available active groceries (name + expiry info)
        groceries = GroceryItem.objects.filter(user=user, quantity__gt=0).exclude(status='expired')
        grocery_data = []
        for g in groceries:
            days_left = None
            if g.expiry_date:
                days_left = (g.expiry_date - today).days
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

        # 2. Proactively filter out any grocery items matching user allergies
        raw_allergies = request.data.get('allergies')
        if hasattr(request.data, 'getlist') and hasattr(request.data, '_getlist') and 'allergies' in request.data:
            gl = request.data.getlist('allergies')
            user_allergies = gl if len(gl) > 1 else (gl[0] if len(gl) == 1 else [])
        else:
            user_allergies = raw_allergies

        if user_allergies is None:
            user_allergies = list(user.allergies or [])
        elif isinstance(user_allergies, str):
            user_allergies = [a.strip() for a in user_allergies.split(',') if a.strip()]
        elif not isinstance(user_allergies, list):
            user_allergies = list(user_allergies)

        if user_allergies:
            allergen_keywords = set()
            for a in user_allergies:
                if isinstance(a, str) and a.strip():
                    cleaned = a.lower().strip()
                    allergen_keywords.add(cleaned)
                    if cleaned.endswith('s') and len(cleaned) > 3:
                        allergen_keywords.add(cleaned[:-1])
                    else:
                        allergen_keywords.add(cleaned + 's')

            safe_groceries = []
            for item in grocery_data:
                item_name_lower = item['name'].lower()
                is_allergic = any(
                    kw in item_name_lower 
                    for kw in allergen_keywords
                )
                if not is_allergic:
                    safe_groceries.append(item)
            if safe_groceries:
                grocery_data = safe_groceries
            else:
                logger.warning(f"All available groceries matched user allergies: {user_allergies}")

        # 3. Sort so expiring items (lowest days) are prioritized first
        grocery_data.sort(key=lambda x: x["days_to_expiry"])

        # 4. Handle expiring_only mode
        expiring_only = bool(request.data.get('expiring_only', False))
        if expiring_only:
            # Prioritize items expiring within 7 days or marked expiring_soon
            near_expiry_items = [
                item for item in grocery_data 
                if item["days_to_expiry"] <= 7 or item["status"] == 'expiring_soon'
            ]
            if near_expiry_items:
                # Use near-expiry items as primary, but keep up to 4 other pantry items as complement
                complement_items = [item for item in grocery_data if item not in near_expiry_items][:4]
                grocery_data = near_expiry_items + complement_items

        # 5. Extract preferences with fitness goal and strict pantry constraint
        fitness_goal = request.data.get('fitness_goal') or getattr(user, 'fitness_goal', 'Balanced')
        strict_pantry_only = request.data.get('strict_pantry_only', True)

        preferences = {
            "diet_type": request.data.get('diet_type', user.diet_type),
            "cuisine_pref": request.data.get('cuisine_pref', user.cuisine_pref or "Indian"),
            "allergies": user_allergies,
            "fitness_goal": fitness_goal,
            "strict_pantry_only": strict_pantry_only,
            "expiring_only": expiring_only,
            "household_size": int(request.data.get('household_size', user.household_size)),
            "max_prep_time_mins": int(request.data.get('max_prep_time_mins', 60)),
            "meal_type": request.data.get('meal_type', 'any')
        }

        # 6. Call AI service securely through multi-provider fallback wrapper
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

        # 7. Create and sanitize recipes
        ALLOWED_STAPLES = {'water', 'salt', 'black pepper', 'pepper', 'cooking oil', 'oil', 'sugar'}
        created_recipes = []
        with transaction.atomic():
            for r in recipes_data:
                # Validate allergy checks against user recorded allergies
                allergens_list = r.get('allergens', [])
                warning = ""
                matched_allergies = [
                    a for a in allergens_list 
                    if a.lower() in [ua.lower() for ua in preferences['allergies']]
                ]
                if matched_allergies:
                    warning = f"ALLERGY WARNING: Contains ingredients related to your allergy to {', '.join(matched_allergies)}."

                # If strict pantry only, sanitize other_ingredients so no external grocery materials are forced
                other_ing = r.get('other_ingredients', [])
                if strict_pantry_only and isinstance(other_ing, list):
                    other_ing = [
                        ing for ing in other_ing 
                        if isinstance(ing, str) and any(staple in ing.lower() for staple in ALLOWED_STAPLES)
                    ]

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
                    other_ingredients=other_ing,
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
            "message": f"Successfully generated {len(created_recipes)} zero-waste recipes."
        })

    @action(detail=True, methods=['post'], url_path='mark-cooked')
    def mark_cooked(self, request, pk=None):
        recipe_obj = self.get_object()
        user = request.user
        idempotency_key = request.data.get('idempotency_key') or request.headers.get('X-Idempotency-Key')
        
        with transaction.atomic():
            # Row lock recipe to prevent concurrent double-cooking
            recipe = Recipe.objects.select_for_update().get(pk=recipe_obj.pk)

            # Check if this idempotency key was already processed
            if idempotency_key:
                from .models import CookEvent
                existing_event = CookEvent.objects.filter(user=user, idempotency_key=idempotency_key).first()
                if existing_event:
                    return Response({
                        "success": True,
                        "data": {
                            "recipes_cooked": user.recipes_cooked,
                            "deduction_summary": existing_event.deduction_summary,
                            "deduction_errors": existing_event.deduction_errors,
                            "is_idempotent_replay": True
                        },
                        "message": f"Recipe '{recipe.name}' was already marked as cooked (idempotent replay)."
                    })

            # Check if recipe is already cooked
            if recipe.is_cooked:
                cached_res = recipe.cooking_result or {}
                return Response({
                    "success": True,
                    "data": {
                        "recipes_cooked": user.recipes_cooked,
                        "deduction_summary": cached_res.get('deduction_summary', []),
                        "deduction_errors": cached_res.get('deduction_errors', []),
                        "already_cooked": True
                    },
                    "message": f"Recipe '{recipe.name}' was already marked as cooked."
                })

            # Deduct items from pantry
            summary, errors = deduct_pantry_items_bulk(user, recipe.ingredients_used, activity_source='recipe_cooked')

            # Mark recipe as cooked and cache result
            recipe.is_cooked = True
            recipe.cooked_at = timezone.now()
            recipe.cooking_result = {
                "deduction_summary": summary,
                "deduction_errors": errors
            }
            recipe.save(update_fields=['is_cooked', 'cooked_at', 'cooking_result'])

            user.recipes_cooked += 1
            user.save(update_fields=['recipes_cooked'])

            if idempotency_key:
                from .models import CookEvent
                CookEvent.objects.create(
                    recipe=recipe,
                    user=user,
                    idempotency_key=idempotency_key,
                    deduction_summary=summary,
                    deduction_errors=errors
                )

            return Response({
                "success": True,
                "data": {
                    "recipes_cooked": user.recipes_cooked,
                    "deduction_summary": summary,
                    "deduction_errors": errors
                },
                "message": f"Recipe '{recipe.name}' marked as cooked!"
            })
