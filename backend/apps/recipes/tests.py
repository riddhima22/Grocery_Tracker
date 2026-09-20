from unittest.mock import patch
from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase
import datetime
from decimal import Decimal

from apps.groceries.models import GroceryItem
from apps.recipes.models import Recipe

User = get_user_model()


class RecipeAPITests(APITestCase):
    def setUp(self):
        self.user1 = User.objects.create_user(
            email='user1_recipe@example.com',
            password='Password123!',
            display_name='Recipe User 1',
            allergies=['dairy', 'peanuts']
        )
        self.user2 = User.objects.create_user(
            email='user2_recipe@example.com',
            password='Password123!',
            display_name='Recipe User 2'
        )

        self.pantry_tomato = GroceryItem.objects.create(
            user=self.user1,
            name='Tomato',
            quantity=Decimal('3.0'),
            unit='kg',
            storage_zone='fridge',
            expiry_date=timezone.now().date() + datetime.timedelta(days=2)
        )

        self.pantry_paneer = GroceryItem.objects.create(
            user=self.user1,
            name='Paneer',
            quantity=Decimal('0.5'),
            unit='kg',
            storage_zone='fridge',
            expiry_date=timezone.now().date() + datetime.timedelta(days=1)
        )

        self.client.force_authenticate(user=self.user1)
        self.generate_url = '/api/v1/recipes/generate/'

    @patch('apps.recipes.views.AIService')
    def test_generate_recipes_success(self, MockAIService):
        mock_service = MockAIService.return_value
        mock_service.generate_recipes.return_value = {
            "recipes": [
                {
                    "name": "Paneer Tomato Curry",
                    "icon_key": "restaurant",
                    "cuisine": "North Indian",
                    "diet_type": "veg",
                    "prep_time_mins": 20,
                    "servings": 2,
                    "calories_per_serving": 300,
                    "ingredients_used": [
                        {"pantry_item_id": str(self.pantry_tomato.id), "name": "Tomato", "quantity": 1.0, "unit": "kg"},
                        {"pantry_item_id": str(self.pantry_paneer.id), "name": "Paneer", "quantity": 0.2, "unit": "kg"}
                    ],
                    "other_ingredients": ["Garlic", "Spices"],
                    "allergens": ["dairy"],
                    "steps": ["Chop tomatoes and paneer", "Cook together with spices"],
                    "nutrition": {"protein_g": 15, "carbs_g": 20, "fat_g": 12, "fiber_g": 4},
                    "tip": "Garnish with cilantro"
                }
            ]
        }

        response = self.client.post(self.generate_url, {})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['success'])
        self.assertEqual(len(response.data['data']), 1)
        self.assertIn("ALLERGY WARNING", response.data['data'][0]['allergen_warning'])

    @patch('apps.recipes.views.AIService')
    def test_generate_recipes_fallback_path(self, MockAIService):
        """Simulate primary provider failure with OpenAI fallback success."""
        mock_service = MockAIService.return_value
        mock_service.generate_recipes.return_value = {
            "recipes": [
                {
                    "name": "Fallback Tomato Soup",
                    "icon_key": "beverage",
                    "cuisine": "Continental",
                    "diet_type": "veg",
                    "prep_time_mins": 15,
                    "servings": 2,
                    "calories_per_serving": 150,
                    "ingredients_used": [
                        {"pantry_item_id": str(self.pantry_tomato.id), "name": "Tomato", "quantity": 1.0, "unit": "kg"}
                    ],
                    "other_ingredients": ["Salt", "Pepper"],
                    "allergens": [],
                    "steps": ["Boil tomatoes", "Puree"],
                    "nutrition": {"protein_g": 3, "carbs_g": 10, "fat_g": 1, "fiber_g": 2},
                    "tip": "Serve warm"
                }
            ]
        }

        response = self.client.post(self.generate_url, {})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['data'][0]['name'], "Fallback Tomato Soup")

    @patch('apps.recipes.views.AIService')
    def test_generate_recipes_all_providers_fail(self, MockAIService):
        mock_service = MockAIService.return_value
        mock_service.generate_recipes.side_effect = RuntimeError("All AI providers unavailable")

        response = self.client.post(self.generate_url, {})
        self.assertEqual(response.status_code, status.HTTP_502_BAD_GATEWAY)
        self.assertFalse(response.data['success'])

    def test_generate_recipes_empty_pantry(self):
        # Remove all groceries for user 1
        GroceryItem.objects.filter(user=self.user1).delete()

        response = self.client.post(self.generate_url, {})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(response.data['success'])

    def test_mark_cooked_deducts_pantry_and_increments_stat(self):
        recipe = Recipe.objects.create(
            user=self.user1,
            name="Tomato Salad",
            ingredients_used=[
                {"pantry_item_id": str(self.pantry_tomato.id), "name": "Tomato", "quantity": 1.0, "unit": "kg"}
            ]
        )

        mark_url = f'/api/v1/recipes/{recipe.id}/mark-cooked/'
        response = self.client.post(mark_url, {})

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['success'])

        # Verify quantity deducted in DB
        self.pantry_tomato.refresh_from_db()
        self.assertEqual(self.pantry_tomato.quantity, Decimal('2.0'))

        # Verify user recipes_cooked incremented
        self.user1.refresh_from_db()
        self.assertEqual(self.user1.recipes_cooked, 1)

    def test_idor_protection(self):
        recipe = Recipe.objects.create(
            user=self.user1,
            name="User 1 Secret Recipe"
        )

        # Authenticate as User 2
        self.client.force_authenticate(user=self.user2)

        # Retrieve should fail
        response = self.client.get(f'/api/v1/recipes/{recipe.id}/')
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

        # Mark cooked should fail
        response = self.client.post(f'/api/v1/recipes/{recipe.id}/mark-cooked/', {})
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
