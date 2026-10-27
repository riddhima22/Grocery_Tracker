import datetime
from decimal import Decimal
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.groceries.models import GroceryActivity, GroceryItem
from apps.meals.models import MealLog

User = get_user_model()


class MealLogAPITests(APITestCase):
    def setUp(self):
        self.user1 = User.objects.create_user(
            email='user1_meal@example.com',
            password='Password123!',
            display_name='Meal User 1'
        )
        self.user2 = User.objects.create_user(
            email='user2_meal@example.com',
            password='Password123!',
            display_name='Meal User 2'
        )

        self.pantry_milk = GroceryItem.objects.create(
            user=self.user1,
            name='Milk',
            quantity=Decimal('2.0'),
            unit='L',
            storage_zone='fridge',
            expiry_date=timezone.now().date() + datetime.timedelta(days=3)
        )

        self.pantry_bread = GroceryItem.objects.create(
            user=self.user1,
            name='Bread',
            quantity=Decimal('1.0'),
            unit='pcs',
            storage_zone='pantry',
            expiry_date=timezone.now().date() + datetime.timedelta(days=5)
        )

        self.client.force_authenticate(user=self.user1)
        self.list_url = '/api/v1/meals/'

    @patch('apps.meals.views.AIService')
    def test_meal_logging_success(self, MockAIService):
        mock_service = MockAIService.return_value
        mock_service.infer_meal_ingredients.return_value = {
            "meal_name": "French Toast & Milk",
            "description": "Delicious breakfast meal",
            "ingredients": [
                {
                    "pantry_item_id": str(self.pantry_milk.id),
                    "name": "Milk",
                    "estimated_quantity": 0.5,
                    "unit": "L",
                    "confidence": "High"
                },
                {
                    "pantry_item_id": str(self.pantry_bread.id),
                    "name": "Bread",
                    "estimated_quantity": 0.2,
                    "unit": "pcs",
                    "confidence": "High"
                }
            ]
        }

        response = self.client.post(self.list_url, {
            'description': 'Had french toast with a glass of milk'
        })

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['name'], 'French Toast & Milk')
        self.assertEqual(response.data['status'], MealLog.StatusChoices.PENDING_CONFIRMATION)

        # Check candidates saved
        meal_id = response.data['id']
        meal_log = MealLog.objects.get(id=meal_id)
        self.assertEqual(meal_log.candidates.count(), 2)

    @patch('apps.meals.views.AIService')
    def test_meal_logging_fallback_path(self, MockAIService):
        """Simulate primary provider fail, fallback provider succeeds via AIService."""
        mock_service = MockAIService.return_value
        mock_service.infer_meal_ingredients.return_value = {
            "meal_name": "Fallback Omelette",
            "description": "Eggs and bread inferred by fallback AI",
            "ingredients": [
                {
                    "pantry_item_id": str(self.pantry_bread.id),
                    "name": "Bread",
                    "estimated_quantity": 0.5,
                    "unit": "pcs",
                    "confidence": "Medium"
                }
            ]
        }

        response = self.client.post(self.list_url, {
            'description': 'Scrambled eggs with toast'
        })

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['name'], 'Fallback Omelette')

    @patch('apps.meals.views.AIService')
    def test_meal_logging_all_ai_providers_fail(self, MockAIService):
        """When AIService raises error, meal log deletion + 500 clean handling."""
        mock_service = MockAIService.return_value
        mock_service.infer_meal_ingredients.side_effect = RuntimeError("All AI providers unavailable")

        response = self.client.post(self.list_url, {
            'description': 'Failure test meal'
        })

        self.assertEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)
        self.assertEqual(MealLog.objects.filter(user=self.user1).count(), 0)

    @patch('apps.meals.views.AIService')
    def test_confirm_deduction_endpoint(self, MockAIService):
        mock_service = MockAIService.return_value
        mock_service.infer_meal_ingredients.return_value = {
            "meal_name": "Milk Shake",
            "description": "Cold milk shake",
            "ingredients": [
                {
                    "pantry_item_id": str(self.pantry_milk.id),
                    "name": "Milk",
                    "estimated_quantity": 0.5,
                    "unit": "L",
                    "confidence": "High"
                }
            ]
        }

        # 1. Create meal log
        create_res = self.client.post(self.list_url, {'description': 'Milk shake'})
        self.assertEqual(create_res.status_code, status.HTTP_201_CREATED)
        meal_id = create_res.data['id']
        candidate_id = create_res.data['candidates'][0]['id']

        # 2. Confirm deduction
        confirm_url = f'{self.list_url}{meal_id}/confirm-deduction/'
        confirm_res = self.client.post(confirm_url, {
            'candidate_deductions': [
                {
                    'candidate_id': candidate_id,
                    'confirmed': True,
                    'quantity': 0.5
                }
            ]
        }, format='json')

        self.assertEqual(confirm_res.status_code, status.HTTP_200_OK)
        self.assertTrue(confirm_res.data['success'])

        # 3. Verify DB quantity deducted
        self.pantry_milk.refresh_from_db()
        self.assertEqual(self.pantry_milk.quantity, Decimal('1.50'))

        # Verify activity recorded
        activities = GroceryActivity.objects.filter(grocery_item=self.pantry_milk)
        self.assertTrue(activities.exists())

    def test_idor_protection(self):
        meal_log = MealLog.objects.create(
            user=self.user1,
            name="User 1 Meal",
            status=MealLog.StatusChoices.PENDING_CONFIRMATION
        )

        # Authenticate as User 2
        self.client.force_authenticate(user=self.user2)

        # Retrieve should fail
        response = self.client.get(f'{self.list_url}{meal_log.id}/')
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

        # Confirm deduction should fail
        response = self.client.post(f'{self.list_url}{meal_log.id}/confirm-deduction/', {})
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
