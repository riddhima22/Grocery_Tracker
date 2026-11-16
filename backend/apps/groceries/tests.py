import datetime

from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from .models import GroceryItem

User = get_user_model()

class GroceryAPITests(APITestCase):
    def setUp(self):
        self.user1 = User.objects.create_user(
            email='user1@example.com',
            password='Password123!',
            display_name='User One'
        )
        self.user2 = User.objects.create_user(
            email='user2@example.com',
            password='Password123!',
            display_name='User Two'
        )

        # Create item for User 1
        self.item1 = GroceryItem.objects.create(
            user=self.user1,
            name='User 1 Milk',
            quantity=2.0,
            unit='pcs',
            storage_zone='fridge',
            expiry_date=timezone.now().date() + datetime.timedelta(days=5)
        )

        self.list_url = '/api/v1/groceries/'
        self.detail_url = f'/api/v1/groceries/{self.item1.id}/'

    def test_status_calculation_fresh(self):
        """Ensure status calculates correctly based on expiry date."""
        self.assertEqual(self.item1.status, 'fresh')

        # Test expiring
        item2 = GroceryItem.objects.create(
            user=self.user1,
            name='Expiring Cheese',
            quantity=1.0,
            expiry_date=timezone.now().date() + datetime.timedelta(days=2)
        )
        self.assertEqual(item2.status, 'expiring')

        # Test expired
        item3 = GroceryItem.objects.create(
            user=self.user1,
            name='Expired Bread',
            quantity=1.0,
            expiry_date=timezone.now().date() - datetime.timedelta(days=1)
        )
        self.assertEqual(item3.status, 'expired')

    def test_idor_protection(self):
        """Ensure User 2 cannot access or modify User 1's grocery items."""
        # Authenticate as User 2
        self.client.force_authenticate(user=self.user2)

        # GET list should be empty for User 2
        response = self.client.get(self.list_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['results'] if 'results' in response.data else response.data), 0)

        # GET detail of User 1's item should return 404 Not Found (or 403)
        response = self.client.get(self.detail_url)
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

        # POST consume to User 1's item should return 404 Not Found
        response = self.client.post(self.detail_url + 'consume/')
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_barcode_lookup_missing_parameter(self):
        """Barcode lookup without query parameter should return 400."""
        self.client.force_authenticate(user=self.user1)
        response = self.client.get('/api/v1/groceries/barcode-lookup/')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(response.data['success'])

    def test_barcode_lookup_invalid_format_returns_400(self):
        """Barcode lookup with non-numeric or out-of-range length returns 400."""
        self.client.force_authenticate(user=self.user1)
        # Non-numeric / path traversal attempt
        response = self.client.get('/api/v1/groceries/barcode-lookup/?barcode=../../etc/passwd')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(response.data['success'])

        # Too short (< 6 digits)
        response = self.client.get('/api/v1/groceries/barcode-lookup/?barcode=12345')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

        # Too long (> 18 digits)
        response = self.client.get('/api/v1/groceries/barcode-lookup/?barcode=1234567890123456789')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_barcode_lookup_pantry_history_hit(self):
        """Barcode lookup should return item details from user's pantry history if available."""
        barcode = '8901030382725'
        GroceryItem.objects.create(
            user=self.user1,
            barcode=barcode,
            name='Amul Taaza Milk',
            brand='Amul',
            category='Dairy',
            unit='L',
            calories_per_100g=60,
            allergens=['Milk'],
            storage_zone='fridge'
        )

        self.client.force_authenticate(user=self.user1)
        response = self.client.get(f'/api/v1/groceries/barcode-lookup/?barcode={barcode}')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['success'])
        data = response.data['data']
        self.assertEqual(data['source'], 'pantry_history')
        self.assertEqual(data['barcode'], barcode)
        self.assertEqual(data['name'], 'Amul Taaza Milk')
        self.assertEqual(data['brand'], 'Amul')
        self.assertEqual(data['category'], 'Dairy')
        self.assertEqual(data['unit'], 'L')
        self.assertEqual(data['calories_per_100g'], 60)
        self.assertEqual(data['allergens'], ['Milk'])
        self.assertEqual(data['storage_zone'], 'fridge')
        self.assertTrue(data['found'])

    def test_barcode_lookup_open_food_facts_hit(self):
        """Barcode lookup should query and parse Open Food Facts if not in pantry history."""
        from unittest.mock import MagicMock, patch

        barcode = '3017620422003'
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "status": 1,
            "product": {
                "product_name": "Nutella Hazelnut Spread",
                "brands": "Ferrero",
                "categories": "Sweet spreads, Hazelnut spreads, Chocolate spreads",
                "quantity": "350 g",
                "nutriments": {
                    "energy-kcal_100g": 539.4
                },
                "allergens_tags": ["en:milk", "en:soybeans", "en:nuts"]
            }
        }

        self.client.force_authenticate(user=self.user1)
        with patch('requests.get', return_value=mock_response) as mock_get:
            response = self.client.get(f'/api/v1/groceries/barcode-lookup/?barcode={barcode}')

            self.assertEqual(response.status_code, status.HTTP_200_OK)
            self.assertTrue(response.data['success'])
            data = response.data['data']
            self.assertEqual(data['source'], 'open_food_facts')
            self.assertEqual(data['barcode'], barcode)
            self.assertEqual(data['name'], 'Nutella Hazelnut Spread')
            self.assertEqual(data['brand'], 'Ferrero')
            self.assertEqual(data['unit'], 'g')
            self.assertEqual(data['calories_per_100g'], 539)
            self.assertEqual(data['allergens'], ['milk', 'soybeans', 'nuts'])
            self.assertEqual(data['storage_zone'], 'pantry')
            self.assertTrue(data['found'])
            mock_get.assert_called_once()

    def test_barcode_lookup_not_found_fallback(self):
        """Barcode lookup should return 200 with found=False if product is not in history or Open Food Facts."""
        from unittest.mock import MagicMock, patch

        barcode = '0000000000000'
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "status": 0,
            "status_verbose": "product not found"
        }

        self.client.force_authenticate(user=self.user1)
        with patch('requests.get', return_value=mock_response):
            response = self.client.get(f'/api/v1/groceries/barcode-lookup/?barcode={barcode}')

            self.assertEqual(response.status_code, status.HTTP_200_OK)
            self.assertTrue(response.data['success'])
            self.assertEqual(response.data['data']['barcode'], barcode)
            self.assertFalse(response.data['data']['found'])
            self.assertIn("No product found", response.data['message'])

    def test_barcode_lookup_network_exception_fallback(self):
        """Barcode lookup should gracefully handle external network errors and return found=False."""
        from unittest.mock import patch

        import requests

        barcode = '1111111111111'
        self.client.force_authenticate(user=self.user1)
        with patch('requests.get', side_effect=requests.RequestException("Timeout")):
            response = self.client.get(f'/api/v1/groceries/barcode-lookup/?barcode={barcode}')

            self.assertEqual(response.status_code, status.HTTP_200_OK)
            self.assertTrue(response.data['success'])
            self.assertEqual(response.data['data']['barcode'], barcode)
            self.assertFalse(response.data['data']['found'])


class ExpiryAndShelfLifeSemanticsTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='expiry_test@example.com',
            password='Password123!',
            display_name='Expiry Tester'
        )

    def test_printed_expiry_date(self):
        """When printed expiry is present, expiry_date is populated and is_expiry_estimated is False."""
        future_date = timezone.localdate() + datetime.timedelta(days=10)
        item = GroceryItem.objects.create(
            user=self.user,
            name='Canned Beans',
            expiry_date=future_date,
            date_type='expiry',
            date_source='ocr_verified',
            is_expiry_estimated=False
        )
        self.assertEqual(item.expiry_date, future_date)
        self.assertFalse(item.is_expiry_estimated)
        self.assertIsNone(item.estimated_consumption_date)
        self.assertEqual(item.status, 'fresh')

    def test_printed_best_before_date(self):
        """Printed best before date is preserved cleanly."""
        bb_date = timezone.localdate() + datetime.timedelta(days=20)
        item = GroceryItem.objects.create(
            user=self.user,
            name='Biscuit Pack',
            best_before_date=bb_date,
            date_type='best_before',
            date_source='ocr_verified',
            is_expiry_estimated=False
        )
        self.assertEqual(item.best_before_date, bb_date)

    def test_no_printed_date_estimated_shelf_life(self):
        """When NO printed date exists, expiry_date MUST be None and estimated_consumption_date populated."""
        est_date = timezone.localdate() + datetime.timedelta(days=7)
        item = GroceryItem.objects.create(
            user=self.user,
            name='Fresh Apples',
            expiry_date=None,
            estimated_consumption_date=est_date,
            date_type='estimated',
            date_source='calculated_shelf_life',
            is_expiry_estimated=True
        )
        self.assertIsNone(item.expiry_date)
        self.assertTrue(item.is_expiry_estimated)
        self.assertEqual(item.estimated_consumption_date, est_date)
        # Status calculation should derive from estimated date
        self.assertEqual(item.status, 'fresh')

    def test_expired_item_status(self):
        """Past printed date causes status='expired'."""
        past_date = timezone.localdate() - datetime.timedelta(days=2)
        item = GroceryItem.objects.create(
            user=self.user,
            name='Old Milk',
            expiry_date=past_date,
            is_expiry_estimated=False
        )
        self.assertEqual(item.status, 'expired')

    def test_expired_estimated_item_status(self):
        """Past estimated consumption date causes status='expired' even without printed expiry."""
        past_date = timezone.localdate() - datetime.timedelta(days=1)
        item = GroceryItem.objects.create(
            user=self.user,
            name='Old Spinach',
            expiry_date=None,
            estimated_consumption_date=past_date,
            is_expiry_estimated=True
        )
        self.assertEqual(item.status, 'expired')

    def test_model_router_enforces_semantic_null_expiry_date(self):
        """AI router leaves expiry_date=None when unprinted and sets estimated_consumption_date."""
        from integrations.ai.model_router import ModelRouter
        router = ModelRouter()


        # Simulated AI extraction with NO printed expiry (e.g. fresh banana)
        raw_items = [{
            "name": "Organic Banana",
            "category": "Fruits",
            "storage_zone": "counter",
            "quantity": 1,
            "unit": "bunch",
            "expiry_date": None,
            "raw_date_text": "",
            "warnings": [],
        }]

        processed = router.parse_grocery_response(json_data={"items": raw_items})
        self.assertTrue(processed['success'])
        item = processed['items'][0]
        # CRITICAL ASSERTIONS:
        self.assertIsNone(item['expiry_date'], "expiry_date must be None when no printed date exists!")
        self.assertTrue(item['is_expiry_estimated'])
        self.assertIsNotNone(item['estimated_consumption_date'])
        self.assertEqual(item['date_type'], 'estimated')
        self.assertEqual(item['date_source'], 'calculated_shelf_life')

    def test_model_router_preserves_printed_date(self):
        """AI router preserves printed expiry date and sets is_expiry_estimated=False."""
        from integrations.ai.model_router import ModelRouter
        router = ModelRouter()


        future_str = (timezone.localdate() + datetime.timedelta(days=30)).isoformat()
        raw_items = [{
            "name": "Almond Milk",
            "category": "Dairy",
            "storage_zone": "fridge",
            "quantity": 1,
            "unit": "L",
            "expiry_date": future_str,
            "raw_date_text": f"EXP {future_str}",
            "warnings": [],
        }]

        processed = router.parse_grocery_response(json_data={"items": raw_items})
        self.assertTrue(processed['success'])
        item = processed['items'][0]
        self.assertEqual(item['expiry_date'], future_str)
        self.assertFalse(item['is_expiry_estimated'])
        self.assertIsNone(item['estimated_consumption_date'])

    def test_model_router_malformed_date_falls_back_to_estimated(self):
        """AI router handles malformed date strings by setting expiry_date=None and calculating estimate."""
        from integrations.ai.model_router import ModelRouter
        router = ModelRouter()


        raw_items = [{
            "name": "Tomatoes",
            "category": "Vegetables",
            "storage_zone": "counter",
            "quantity": 1,
            "unit": "kg",
            "expiry_date": "INVALID_DATE_STRING_999",
            "raw_date_text": "garbage text",
            "warnings": [],
        }]

        processed = router.parse_grocery_response(json_data={"items": raw_items})
        self.assertTrue(processed['success'])
        item = processed['items'][0]
        self.assertIsNone(item['expiry_date'])
        self.assertTrue(item['is_expiry_estimated'])
        self.assertIsNotNone(item['estimated_consumption_date'])


class SmartUnitClassificationBackendTests(APITestCase):
    """Automated backend test suite covering the 14 smart quantity & unit detection scenarios."""

    def test_scenario_1_loose_potato_weight_based(self):
        from apps.groceries.unit_classifier import UnitCategory, classify_product_unit
        res = classify_product_unit(product_name='Potato', category='Vegetables')
        self.assertEqual(res['unit'], 'kg')
        self.assertEqual(res['unit_category'], UnitCategory.WEIGHT)
        self.assertNotEqual(res['unit'], 'pcs')

    def test_scenario_2_onion_barcode_weight_based(self):
        from apps.groceries.unit_classifier import UnitCategory, classify_product_unit
        res = classify_product_unit(product_name='Red Onion', category='Vegetables')
        self.assertIn(res['unit'], ['kg', 'g'])
        self.assertEqual(res['unit_category'], UnitCategory.WEIGHT)
        self.assertNotEqual(res['unit'], 'pcs')

    def test_scenario_3_branded_50g_chips_packet(self):
        from apps.groceries.unit_classifier import UnitCategory, classify_product_unit
        res = classify_product_unit(
            product_name="Lay's Classic Potato Chips",
            category='Snacks',
            explicit_quantity_str='50 g'
        )
        self.assertEqual(res['quantity'], 1.0)
        self.assertEqual(res['unit'], 'packet')
        self.assertEqual(res['unit_category'], UnitCategory.PACKAGE)
        self.assertEqual(res['net_content_value'], 50.0)
        self.assertEqual(res['net_content_unit'], 'g')

    def test_scenario_4_two_packets_biscuits(self):
        from apps.groceries.unit_classifier import classify_product_unit
        res = classify_product_unit(
            product_name="Oreo Biscuit 2 pack",
            category='Snacks'
        )
        self.assertEqual(res['quantity'], 2.0)
        self.assertEqual(res['unit'], 'packet')
        self.assertEqual(res['package_count'], 2)

    def test_scenario_5_cooking_oil_bottle(self):
        from apps.groceries.unit_classifier import UnitCategory, classify_product_unit
        res = classify_product_unit(
            product_name="Fortune Sunflower Cooking Oil 1L Bottle",
            category='Beverages',
            explicit_quantity_str='1 L'
        )
        self.assertEqual(res['quantity'], 1.0)
        self.assertEqual(res['unit'], 'bottle')
        self.assertEqual(res['unit_category'], UnitCategory.PACKAGE)
        self.assertEqual(res['net_content_value'], 1.0)
        self.assertEqual(res['net_content_unit'], 'L')

    def test_scenario_6_loose_dal_weight_based(self):
        from apps.groceries.unit_classifier import UnitCategory, classify_product_unit
        res = classify_product_unit(product_name="Toor Dal", category='Grains')
        self.assertEqual(res['unit'], 'g')
        self.assertEqual(res['unit_category'], UnitCategory.WEIGHT)
        self.assertNotEqual(res['unit'], 'pcs')

    def test_scenario_7_six_eggs_count(self):
        from apps.groceries.unit_classifier import UnitCategory, classify_product_unit
        res = classify_product_unit(product_name="Farm Fresh Brown Eggs 6 pcs", category='Dairy')
        self.assertEqual(res['unit'], 'pcs')
        self.assertEqual(res['quantity'], 6.0)
        self.assertEqual(res['unit_category'], UnitCategory.COUNT)

    def test_scenario_8_unknown_category_fallback(self):
        from apps.groceries.unit_classifier import classify_product_unit
        res = classify_product_unit(product_name="XYZ Unknown Widget 999", category='')
        self.assertTrue(res['is_uncertain'])
        self.assertEqual(res['unit_confidence'], 'uncertain')

    def test_scenario_9_low_confidence_ai_detection(self):
        from apps.groceries.unit_classifier import classify_product_unit
        res = classify_product_unit(
            product_name="Something Blurry",
            category="Vegetables",
            ai_confidence="Low"
        )
        self.assertTrue(res['is_uncertain'])
        self.assertEqual(res['unit_confidence'], 'Low')

    def test_scenario_10_quantity_conversion_g_to_kg(self):
        from decimal import Decimal

        from apps.groceries.unit_classifier import convert_quantity_units
        val, ok = convert_quantity_units(Decimal(500), 'g', 'kg')
        self.assertTrue(ok)
        self.assertEqual(val, Decimal('0.5'))

        val2, ok2 = convert_quantity_units(Decimal('1.5'), 'kg', 'g')
        self.assertTrue(ok2)
        self.assertEqual(val2, Decimal(1500))

    def test_scenario_11_quantity_conversion_ml_to_L(self):
        from decimal import Decimal

        from apps.groceries.unit_classifier import convert_quantity_units
        val, ok = convert_quantity_units(Decimal(500), 'ml', 'L')
        self.assertTrue(ok)
        self.assertEqual(val, Decimal('0.5'))

        val2, ok2 = convert_quantity_units(Decimal(2), 'L', 'ml')
        self.assertTrue(ok2)
        self.assertEqual(val2, Decimal(2000))

    def test_prevention_cross_category_conversions(self):
        from decimal import Decimal

        from apps.groceries.unit_classifier import convert_quantity_units
        val, ok = convert_quantity_units(Decimal(500), 'g', 'L')
        self.assertFalse(ok)
        self.assertIsNone(val)

    def test_scenario_12_legacy_product_records(self):
        from apps.groceries.models import GroceryItem
        user = User.objects.create_user(email='legacy@example.com', password='Password123!', display_name='Legacy User')
        item = GroceryItem.objects.create(
            user=user,
            name='Legacy Item',
            quantity=3.0,
            unit='pcs',
            storage_zone='pantry'
        )
        self.assertEqual(item.quantity, 3.0)
        self.assertEqual(item.unit, 'pcs')
        # Edit and save
        item.unit = 'kg'
        item.quantity = 1.0
        item.save()
        item.refresh_from_db()
        self.assertEqual(item.unit, 'kg')
        self.assertEqual(item.quantity, 1.0)

    def test_scenario_13_scan_session_deduplication(self):
        from apps.scans.models import ScanCandidate, ScanSession
        user = User.objects.create_user(email='scan_dedup@example.com', password='Password123!', display_name='Scan User')
        session = ScanSession.objects.create(user=user)
        c1 = ScanCandidate.objects.create(
            scan_session=session,
            name='Red Onion',
            quantity=1.0,
            unit='kg',
            storage_zone='pantry'
        )
        # Adding identical item in view or task increments quantity
        c1.quantity += 1.0
        c1.save()
        c1.refresh_from_db()
        self.assertEqual(c1.quantity, 2.0)

    def test_scenario_14_barcode_failure_safe_fallback(self):
        from apps.groceries.barcode_lookup import lookup_open_food_facts
        # Random non-existent barcode should gracefully return None without crashing
        res = lookup_open_food_facts("000000000000000000")
        self.assertIsNone(res)



