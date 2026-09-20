from decimal import Decimal
from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase
import datetime

from apps.groceries.models import GroceryItem
from apps.groceries.services import deduct_pantry_items_bulk
from apps.grocery_lists.models import GroceryList, GroceryListItem
from apps.grocery_lists.services import add_to_active_grocery_list

User = get_user_model()


class SmartGroceryListTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='smart_list_user@example.com',
            password='Password123!',
            display_name='Smart List User'
        )
        self.client.force_authenticate(user=self.user)
        self.generate_url = '/api/v1/grocery-lists/generate/'
        self.current_url = '/api/v1/grocery-lists/current/'

    def test_generate_suggestions_with_empty_history_returns_200(self):
        """Even if user has 0 activities or history, generate must return 200 with suggestions."""
        response = self.client.post(self.generate_url, {})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['success'])
        self.assertGreater(len(response.data['data']['items']), 0)

    def test_generate_suggestions_picks_up_finished_pantry_items(self):
        """Items that are finished (quantity <= 0) must be prioritized and added to the list."""
        GroceryItem.objects.create(
            user=self.user,
            name='Fresh Milk',
            quantity=Decimal('0'),
            unit='L',
            storage_zone='fridge'
        )

        response = self.client.post(self.generate_url, {})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['success'])
        
        items = response.data['data']['items']
        item_names = [i['name'] for i in items]
        self.assertIn('Fresh Milk', item_names)

    def test_consume_to_zero_automatically_adds_to_grocery_list(self):
        """When an item is consumed down to 0, it must automatically appear in the active smart grocery list."""
        item = GroceryItem.objects.create(
            user=self.user,
            name='Whole Wheat Bread',
            quantity=Decimal('1.0'),
            unit='pack',
            storage_zone='counter'
        )

        consume_url = f'/api/v1/groceries/{item.id}/consume/'
        response = self.client.post(consume_url, {'quantity': 1.0})
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        # Verify active grocery list now has Whole Wheat Bread
        active_list = GroceryList.objects.filter(user=self.user, status=GroceryList.Statuses.ACTIVE).first()
        self.assertIsNotNone(active_list)
        list_item = active_list.items.filter(name='Whole Wheat Bread').first()
        self.assertIsNotNone(list_item)
        self.assertEqual(list_item.unit, 'pack')
        self.assertIn('Finished in your kitchen', list_item.reason)

    def test_deduct_bulk_to_zero_adds_to_grocery_list(self):
        """When an item is depleted via recipe cooking, it must automatically appear in the grocery list."""
        item = GroceryItem.objects.create(
            user=self.user,
            name='Coriander Seeds',
            quantity=Decimal('100'),
            unit='g',
            storage_zone='spice'
        )

        summary, errors = deduct_pantry_items_bulk(
            user=self.user,
            items_to_deduct=[{'pantry_item_id': str(item.id), 'name': 'Coriander Seeds', 'quantity': 100}]
        )
        self.assertEqual(len(errors), 0)

        # Verify grocery list item created
        active_list = GroceryList.objects.filter(user=self.user, status=GroceryList.Statuses.ACTIVE).first()
        self.assertIsNotNone(active_list)
        list_item = active_list.items.filter(name='Coriander Seeds').first()
        self.assertIsNotNone(list_item)
        self.assertIn('Finished during cooking', list_item.reason)
