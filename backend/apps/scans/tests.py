from django.test import TestCase
from django.utils import timezone
import datetime
from integrations.ocr.text_parser import parse_absolute_date, OCRDateParser
from integrations.ai.model_router import ModelRouter

class OCRTextParserTests(TestCase):
    def test_parse_absolute_dates(self):
        # Test standard formats
        self.assertEqual(parse_absolute_date("18/07/2026"), datetime.date(2026, 7, 18))
        self.assertEqual(parse_absolute_date("15-05-2025"), datetime.date(2025, 5, 15))
        self.assertEqual(parse_absolute_date("01.12.2024"), datetime.date(2024, 12, 1))
        
        # Test month name formats
        self.assertEqual(parse_absolute_date("15-JUL-2026"), datetime.date(2026, 7, 15))
        self.assertEqual(parse_absolute_date("20-October-2027"), datetime.date(2027, 10, 20))
        
        # Test partial formats (MM/YYYY)
        self.assertEqual(parse_absolute_date("08/2026"), datetime.date(2026, 8, 1))

    def test_relative_date_parsing_months(self):
        # Mock packaging text
        text = "PKD: 10/01/2026\nBEST BEFORE 6 MONTHS FROM PACKING\n"
        res = OCRDateParser.extract_dates(text)
        
        # 10th Jan 2026 + 6 months (180 days) = 9th July 2026
        self.assertIsNotNone(res["expiry_date"])
        self.assertEqual(res["date_type"], "best_before")
        self.assertEqual(res["date_source"], "calculated_from_packaging")
        self.assertEqual(res["expiry_date"].year, 2026)
        self.assertEqual(res["expiry_date"].month, 7)

    def test_relative_date_parsing_days(self):
        text = "MFD: 15-07-2026\nBEST BEFORE 15 DAYS\n"
        res = OCRDateParser.extract_dates(text)
        
        self.assertEqual(res["expiry_date"], datetime.date(2026, 7, 30))
        self.assertEqual(res["date_type"], "best_before")
        self.assertEqual(res["date_source"], "calculated_from_packaging")

    def test_absolute_ocr_extraction(self):
        text = "EXPIRY DATE: 18/12/2026\nLOT 18273"
        res = OCRDateParser.extract_dates(text)
        
        self.assertEqual(res["expiry_date"], datetime.date(2026, 12, 18))
        self.assertEqual(res["date_type"], "use_by")
        self.assertEqual(res["date_source"], "ocr_verified")

class ModelRouterQualityTests(TestCase):
    def test_quality_checks_nonexistent_files(self):
        router = ModelRouter()
        errors, warnings, unique = router.run_image_quality_checks(["nonexistent.png"])
        self.assertTrue(any("does not exist" in err for err in errors))
        self.assertEqual(len(unique), 0)


class ScanTaskRetryTests(TestCase):
    def test_is_transient_error_detection(self):
        from apps.scans.tasks import is_transient_error
        from integrations.ai.gemini_client import AIContentBlockedError

        # Transient errors
        self.assertTrue(is_transient_error(Exception("429 Too Many Requests: Rate limit exceeded")))
        self.assertTrue(is_transient_error(Exception("503 Service Unavailable")))
        self.assertTrue(is_transient_error(TimeoutError("Request timed out")))
        self.assertTrue(is_transient_error(ConnectionError("Connection reset by peer")))
        self.assertTrue(is_transient_error(Exception("ResourceExhausted: Quota exceeded for model")))

        # Permanent errors
        self.assertFalse(is_transient_error(AIContentBlockedError("Safety blocked")))
        self.assertFalse(is_transient_error(Exception("Image corrupted or unreadable")))
        self.assertFalse(is_transient_error(Exception("Image resolution is too low")))
        self.assertFalse(is_transient_error(Exception("Invalid argument: JSONDecodeError")))


from rest_framework.test import APITestCase
from django.contrib.auth import get_user_model
from apps.scans.models import ScanSession, ScanCandidate
from apps.groceries.models import GroceryItem
from apps.groceries.serializers import GroceryItemSerializer

User = get_user_model()

class ScanConfirmationDateRegressionTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email="scanner_test@example.com",
            password="StrongPassword123!",
            display_name="Scan Tester"
        )
        self.client.force_authenticate(user=self.user)
        self.session = ScanSession.objects.create(
            user=self.user,
            status=ScanSession.Statuses.COMPLETED
        )

    def test_confirm_scan_with_explicit_dates(self):
        candidate = ScanCandidate.objects.create(
            scan_session=self.session,
            name="Organic Milk",
            category="Dairy",
            storage_zone="fridge",
            quantity=2.0,
            unit="pack",
            expiry_date=datetime.date(2026, 10, 15),
            best_before_date=datetime.date(2026, 10, 15),
            manufacturing_date=datetime.date(2026, 9, 1),
            packed_date=datetime.date(2026, 9, 2),
            date_type="best_before",
            date_source="ocr_verified",
            date_confidence="High",
            confidence="High"
        )

        url = f"/api/v1/scans/sessions/{self.session.id}/confirm/"
        response = self.client.post(url, {"candidate_ids": [str(candidate.id)]}, format='json')

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data["success"])
        items = response.data["data"]
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["name"], "Organic Milk")
        self.assertEqual(items[0]["expiry_date"], "2026-10-15")
        self.assertEqual(items[0]["best_before_date"], "2026-10-15")
        self.assertEqual(items[0]["manufacturing_date"], "2026-09-01")
        self.assertEqual(items[0]["packed_date"], "2026-09-02")
        self.assertIsInstance(items[0]["purchase_date"], str)

    def test_confirm_scan_with_datetime_object_coercion(self):
        candidate = ScanCandidate.objects.create(
            scan_session=self.session,
            name="Fresh Apples",
            category="Fruits",
            storage_zone="counter",
            quantity=1.0,
            unit="kg",
            expiry_date=datetime.date(2026, 11, 1),
        )
        candidate.expiry_date = datetime.datetime(2026, 11, 1, 12, 0, 0, tzinfo=datetime.timezone.utc)
        candidate.save()

        url = f"/api/v1/scans/sessions/{self.session.id}/confirm/"
        response = self.client.post(url, {}, format='json')

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data["success"])
        items = response.data["data"]
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["name"], "Fresh Apples")
        self.assertEqual(items[0]["expiry_date"], "2026-11-01")

    def test_grocery_item_default_purchase_date_is_pure_date(self):
        item = GroceryItem.objects.create(
            user=self.user,
            name="Greek Yogurt",
            category="Dairy",
            storage_zone="fridge",
            expiry_date=datetime.date(2026, 10, 5)
        )
        self.assertIs(type(item.purchase_date), datetime.date)
        serializer = GroceryItemSerializer(item)
        self.assertEqual(serializer.data["purchase_date"], timezone.localdate().isoformat())


class ScanUploadValidationTests(TestCase):
    def test_scan_upload_rejects_corrupted_or_mismatched_image(self):
        from rest_framework.test import APIClient
        from django.core.files.uploadedfile import SimpleUploadedFile
        from django.contrib.auth import get_user_model
        import io
        from PIL import Image

        user = get_user_model().objects.create_user(
            email='scan_validator@example.com',
            password='Password123!',
            display_name='Scan Validator'
        )
        client = APIClient()
        client.force_authenticate(user=user)

        # Corrupted / fake image
        bad_file = SimpleUploadedFile("scan.png", b"not-a-real-png-bytes", content_type="image/png")
        res = client.post('/api/v1/scans/sessions/', {'images': [bad_file]}, format='multipart')
        self.assertEqual(res.status_code, 400)
        self.assertFalse(res.data['success'])

        # Format mismatch (JPEG binary pretending to be PNG)
        buf = io.BytesIO()
        Image.new('RGB', (10, 10), color='blue').save(buf, format='JPEG')
        buf.seek(0)
        mismatch_file = SimpleUploadedFile("scan.png", buf.read(), content_type="image/png")
        res = client.post('/api/v1/scans/sessions/', {'images': [mismatch_file]}, format='multipart')
        self.assertEqual(res.status_code, 400)
        self.assertFalse(res.data['success'])


