import datetime
import io
import logging
from unittest.mock import MagicMock, patch

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.utils import timezone
from kombu.exceptions import OperationalError
from PIL import Image
from rest_framework.test import APITestCase

from apps.groceries.models import GroceryItem
from apps.groceries.serializers import GroceryItemSerializer
from apps.scans import views as scan_views
from apps.scans.models import ScanCandidate, ScanImage, ScanSession
from integrations.ai.model_router import ModelRouter
from integrations.ocr.text_parser import OCRDateParser, parse_absolute_date

User = get_user_model()


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
        candidate.expiry_date = datetime.datetime(2026, 11, 1, 12, 0, 0, tzinfo=datetime.UTC)
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
        import io

        from django.contrib.auth import get_user_model
        from django.core.files.uploadedfile import SimpleUploadedFile
        from PIL import Image
        from rest_framework.test import APIClient

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


class ScanCandidateExpirySemanticsTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email="expiry_test@example.com",
            password="StrongPassword123!",
            display_name="Expiry Tester"
        )
        self.session = ScanSession.objects.create(
            user=self.user,
            status=ScanSession.Statuses.COMPLETED
        )

    def test_case_1_expiry_estimated_yields_true(self):
        """When expiry is estimated from shelf life, is_expiry_estimated must be True."""
        candidate = ScanCandidate.objects.create(
            scan_session=self.session,
            name="Bananas",
            category="Fruits",
            storage_zone="counter",
            estimated_consumption_date=datetime.date(2026, 10, 14),
            date_type="estimated",
            date_source="calculated_shelf_life",
            is_expiry_estimated=None,  # explicitly testing None input
        )
        self.assertIs(candidate.is_expiry_estimated, True)
        self.assertIsNone(candidate.expiry_date)
        self.assertEqual(candidate.estimated_consumption_date, datetime.date(2026, 10, 14))

    def test_case_2_expiry_explicitly_known_yields_false(self):
        """When expiry is explicitly printed / known, is_expiry_estimated must be False."""
        candidate = ScanCandidate.objects.create(
            scan_session=self.session,
            name="Cheddar Cheese",
            category="Dairy",
            storage_zone="fridge",
            expiry_date=datetime.date(2026, 11, 20),
            date_type="expiry",
            date_source="ocr_verified",
            is_expiry_estimated=None,  # explicitly testing None input
        )
        self.assertIs(candidate.is_expiry_estimated, False)
        self.assertEqual(candidate.expiry_date, datetime.date(2026, 11, 20))
        self.assertIsNone(candidate.estimated_consumption_date)

    def test_case_3_calculation_returns_null_safely_resolves_to_false(self):
        """When both expiry and shelf-life are NULL, safely resolve is_expiry_estimated to False."""
        candidate = ScanCandidate.objects.create(
            scan_session=self.session,
            name="Unknown Bulk Item",
            category="Other",
            storage_zone="pantry",
            expiry_date=None,
            estimated_consumption_date=None,
            is_expiry_estimated=None,  # explicitly testing None input
        )
        self.assertIs(candidate.is_expiry_estimated, False)
        self.assertIsNone(candidate.expiry_date)
        self.assertIsNone(candidate.estimated_consumption_date)

    def test_case_4_red_onion_scan_from_screenshot_succeeds(self):
        """
        Simulate the exact payload from the failed Red Onion scan:
        Red Onion with AI calculated shelf life date passed in expiry_date,
        date_type='estimated', date_source='calculated_shelf_life', is_expiry_estimated=None.
        Must succeed, not throw NOT NULL error, shift estimated date, and set is_expiry_estimated=True.
        """
        from apps.scans.serializers import ScanCandidateSerializer

        # Test 1: Direct model creation
        candidate = ScanCandidate.objects.create(
            scan_session=self.session,
            name="Red Onion",
            brand="",
            description="Fresh whole red onions piled together, suitable for cooking and ...",
            icon_key="vegetables",
            category="Vegetables",
            quantity=15.00,
            unit="pcs",
            storage_zone="basket",
            expiry_date=datetime.date(2026, 11, 7),
            date_type="estimated",
            date_source="calculated_shelf_life",
            date_confidence="Medium",
            raw_date_text="Estimated based on item shelf life",
            shelf_life_guidance="Keep away from direct sunlight and potatoes. Stored properly, th...",
            storage_reason="Store in a cool, dark, and well-ventilated basket to prevent spr...",
            confidence="High",
            is_expiry_estimated=None,
        )
        self.assertIsNotNone(candidate.id)
        self.assertIs(candidate.is_expiry_estimated, True)
        self.assertIsNone(candidate.expiry_date)
        self.assertEqual(candidate.estimated_consumption_date, datetime.date(2026, 11, 7))

        # Test 2: Via Serializer
        serializer = ScanCandidateSerializer(data={
            "name": "Red Onion 2",
            "category": "Vegetables",
            "quantity": 5.0,
            "unit": "pcs",
            "storage_zone": "basket",
            "expiry_date": None,
            "estimated_consumption_date": "2026-11-07",
            "date_type": "estimated",
            "date_source": "calculated_shelf_life",
            "is_expiry_estimated": None,
        })
        self.assertTrue(serializer.is_valid(), serializer.errors)
        self.assertIs(serializer.validated_data["is_expiry_estimated"], True)

    def test_tasks_processing_with_red_onion_item_data(self):
        """Simulate task processing loop with the exact AI dictionary for Red Onion."""
        from unittest.mock import patch

        from apps.scans.tasks import process_scan_session_task

        mock_router_result = {
            "success": True,
            "items": [
                {
                    "name": "Red Onion",
                    "brand": "",
                    "description": "Fresh whole red onions piled together, suitable for cooking and ...",
                    "category": "Vegetables",
                    "icon_key": "vegetables",
                    "quantity": 15.0,
                    "unit": "pcs",
                    "storage_zone": "basket",
                    "expiry_date": "2026-11-07",
                    "estimated_consumption_date": None,
                    "is_expiry_estimated": None,
                    "date_type": "estimated",
                    "date_source": "calculated_shelf_life",
                    "date_confidence": "Medium",
                    "raw_date_text": "Estimated based on item shelf life",
                    "storage_reason": "Store in a cool, dark, and well-ventilated basket to prevent spr...",
                    "shelf_life_guidance": "Keep away from direct sunlight and potatoes. Stored properly, th...",
                    "confidence": "High",
                }
            ]
        }

        with patch("apps.scans.tasks.ModelRouter") as MockRouter:
            mock_instance = MagicMock()
            mock_instance.process_scan.return_value = mock_router_result
            MockRouter.return_value = mock_instance

            # Create pending image for session
            from django.core.files.uploadedfile import SimpleUploadedFile

            from apps.scans.models import ScanImage
            img_file = SimpleUploadedFile("onion.jpg", b"fake-jpg", content_type="image/jpeg")
            ScanImage.objects.create(scan_session=self.session, image=img_file, status=ScanImage.Statuses.PENDING)

            success = process_scan_session_task(str(self.session.id))
            self.assertTrue(success)

            created_candidate = self.session.candidates.filter(name="Red Onion").first()
            self.assertIsNotNone(created_candidate)
            self.assertIs(created_candidate.is_expiry_estimated, True)
            self.assertIsNone(created_candidate.expiry_date)
            self.assertEqual(created_candidate.estimated_consumption_date, datetime.date(2026, 11, 7))


class ScanFlowAsyncAndPollingTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email="async_scan_user@example.com",
            password="StrongPassword123!",
            display_name="Async Scan Tester"
        )
        self.client.force_authenticate(user=self.user)

    def _create_dummy_image_file(self, filename="groceries.jpg"):
        import io

        from django.core.files.uploadedfile import SimpleUploadedFile
        from PIL import Image

        buf = io.BytesIO()
        img = Image.new("RGB", (300, 300), color="green")
        img.save(buf, format="JPEG")
        buf.seek(0)
        return SimpleUploadedFile(filename, buf.read(), content_type="image/jpeg")

    def test_post_scan_session_returns_201_or_202_and_queued_status(self):
        """
        POST /api/v1/scans/sessions/ returns HTTP 201/202 immediately
        with session ID and queued status, without blocking the web worker.
        """
        from unittest.mock import patch

        image_file = self._create_dummy_image_file()

        with patch("apps.scans.views.process_scan_session_task.delay") as mock_delay:
            mock_delay.return_value = None
            response = self.client.post(
                "/api/v1/scans/sessions/",
                {"images": [image_file]},
                format="multipart"
            )

        self.assertIn(response.status_code, [201, 202])
        self.assertTrue(response.data.get("success"))
        data = response.data.get("data", {})
        session_id = data.get("id")
        self.assertIsNotNone(session_id)
        self.assertIn(data.get("status"), ["pending", "processing"])

        # Verify session in database is in pending/processing status
        session = ScanSession.objects.get(id=session_id)
        self.assertIn(session.status, [ScanSession.Statuses.PENDING, ScanSession.Statuses.PROCESSING])
        self.assertEqual(session.image_count, 1)

    def test_polling_get_scan_session_endpoint(self):
        """
        GET /api/v1/scans/sessions/{id}/ returns session details in standard envelope.
        """
        session = ScanSession.objects.create(
            user=self.user,
            status=ScanSession.Statuses.PROCESSING,
            image_count=1
        )

        response = self.client.get(f"/api/v1/scans/sessions/{session.id}/")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data.get("success"))
        data = response.data.get("data", {})
        self.assertEqual(data.get("id"), str(session.id))
        self.assertEqual(data.get("status"), "processing")
        self.assertEqual(data.get("error_message"), "")

    def test_scan_task_failure_path_sets_failed_status_and_error_message(self):
        """
        When the AI/OCR pipeline encounters an unrecoverable failure,
        the task sets session status='failed' and records error_message.
        """
        from unittest.mock import patch

        from apps.scans.models import ScanImage
        from apps.scans.tasks import process_scan_session_task

        session = ScanSession.objects.create(
            user=self.user,
            status=ScanSession.Statuses.PROCESSING,
            image_count=1
        )
        image_file = self._create_dummy_image_file()
        ScanImage.objects.create(
            scan_session=session,
            image=image_file,
            status=ScanImage.Statuses.PENDING
        )

        with patch("apps.scans.tasks.ModelRouter") as MockRouter:
            mock_instance = MagicMock()
            mock_instance.process_scan.return_value = {
                "success": False,
                "error": "Image resolution too low or corrupted."
            }
            MockRouter.return_value = mock_instance

            # Execute task directly with mocked AI/OCR
            process_scan_session_task(str(session.id))

        session.refresh_from_db()
        self.assertEqual(session.status, ScanSession.Statuses.FAILED)
        self.assertIn("Image resolution too low or corrupted.", session.error_message)

        # Polling endpoint reflects failed status and error message
        response = self.client.get(f"/api/v1/scans/sessions/{session.id}/")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data.get("success"))
        data = response.data.get("data", {})
        self.assertEqual(data.get("status"), "failed")
        self.assertIn("Image resolution too low or corrupted.", data.get("error_message"))

    def test_gemini_timeout_falls_back_to_openai(self):
        """
        When Gemini raises a TimeoutError / deadline exceeded, AIService
        falls back to OpenAI and returns candidates successfully.
        """
        from integrations.ai.ai_service import AIService

        class TimeoutGeminiProvider:
            def analyze_grocery_images(self, *args, **kwargs):
                raise TimeoutError("Gemini request timed out after 45s")

        class SuccessfulOpenAIProvider:
            def analyze_grocery_images(self, *args, **kwargs):
                return {
                    "items": [
                        {
                            "name": "Organic Whole Milk",
                            "quantity": 1.0,
                            "unit": "bottle",
                            "confidence": "High",
                            "storage_zone": "fridge",
                        }
                    ]
                }

        service = AIService(
            provider_order=["gemini", "openai"],
            provider_instances={
                "gemini": TimeoutGeminiProvider(),
                "openai": SuccessfulOpenAIProvider(),
            }
        )

        res = service.analyze_grocery_images(["/dummy/path.jpg"])
        self.assertIn("items", res)
        self.assertEqual(res["items"][0]["name"], "Organic Whole Milk")

    def test_health_check_endpoints_return_200(self):
        """Verify /health, /health/, and /api/v1/health/ all return 200 OK."""
        for path in ["/health", "/health/", "/api/v1/health/"]:
            res = self.client.get(path)
            self.assertEqual(res.status_code, 200, f"Failed for {path}")
            self.assertEqual(res.json().get("status"), "healthy")






def create_test_image(filename="scan_test.jpg"):
    buf = io.BytesIO()
    img = Image.new("RGB", (50, 50), color="blue")
    img.save(buf, format="JPEG")
    return SimpleUploadedFile(filename, buf.getvalue(), content_type="image/jpeg")


class ScanDispatchAndLoggerTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email="celery_test_user@example.com",
            password="StrongPassword123!",
            display_name="Celery Tester"
        )
        self.client.force_authenticate(user=self.user)

    def test_logger_is_initialized_in_views(self):
        """Task 1: Verify logger is correctly initialized at module level in scans/views.py."""
        self.assertTrue(hasattr(scan_views, 'logger'))
        self.assertIsInstance(scan_views.logger, logging.Logger)
        self.assertEqual(scan_views.logger.name, 'freshtrack.scans.views')

    @patch("apps.scans.views.process_scan_session_task.delay")
    def test_successful_scan_upload_dispatches_async_task(self, mock_delay):
        """Task 5 & 8: Verify successful scan upload queues process_scan_session_task asynchronously."""
        img = create_test_image("produce.jpg")
        response = self.client.post(
            "/api/v1/scans/sessions/",
            {"images": [img]},
            format="multipart"
        )

        self.assertEqual(response.status_code, 201)
        self.assertTrue(response.data["success"])
        session_id = response.data["data"]["id"]

        session = ScanSession.objects.get(id=session_id)
        self.assertEqual(session.status, ScanSession.Statuses.PENDING)
        self.assertEqual(session.image_count, 1)

        mock_delay.assert_called_once_with(str(session_id))

    @patch("apps.scans.views.process_scan_session_task.apply")
    @patch("apps.scans.views.process_scan_session_task.delay")
    def test_celery_broker_failure_marks_session_failed_and_does_not_run_sync(self, mock_delay, mock_apply):
        """
        Tasks 6, 7 & 9:
        When Celery fails to queue (e.g. Kombu broker OperationalError),
        the session and images MUST be marked as FAILED (not permanently stuck in PENDING),
        synchronous apply() MUST NOT be called, and an HTTP 503 error is returned.
        """
        broker_err = OperationalError("Error 111 connecting to redis:6379. Connection refused.")
        mock_delay.side_effect = broker_err

        with self.assertLogs(scan_views.logger, level="ERROR") as log_capture:
            img = create_test_image("receipt.jpg")
            response = self.client.post(
                "/api/v1/scans/sessions/",
                {"images": [img]},
                format="multipart"
            )

        # 1. API returns 503 Service Unavailable
        self.assertEqual(response.status_code, 503)
        self.assertFalse(response.data["success"])
        self.assertEqual(response.data["error"]["code"], "TASK_DISPATCH_FAILED")
        self.assertIn("Connection refused", response.data["error"]["details"])

        session_id = response.data["error"]["session_id"]
        session = ScanSession.objects.get(id=session_id)

        # 2. Session is NOT stuck in PENDING
        self.assertEqual(session.status, ScanSession.Statuses.FAILED)
        self.assertIsNotNone(session.completed_at)

        # 3. ScanImage records are marked FAILED
        scan_image = session.images.first()
        self.assertIsNotNone(scan_image)
        self.assertEqual(scan_image.status, ScanImage.Statuses.FAILED)
        self.assertIn("Failed to enqueue", scan_image.error_message)

        # 4. Synchronous fallback (apply) was NEVER called
        mock_apply.assert_not_called()

        # 5. Error was logged with exception details
        self.assertTrue(any("Celery task dispatch failed" in msg for msg in log_capture.output))


class CeleryBrokerConfigRegistrationTests(TestCase):
    def test_task_registered_in_celery_registry(self):
        """Task 5: Ensure process_scan_session_task is registered in Celery app registry."""
        import apps.scans.tasks  # noqa: F401
        from config.celery import app as celery_app

        task_name = "apps.scans.tasks.process_scan_session_task"
        self.assertIn(task_name, celery_app.tasks)

    def test_packaging_dependency_imported_by_kombu_redis(self):
        """Verify packaging is installed and kombu.transport.redis can resolve version check."""
        import packaging
        import packaging.version
        from kombu.transport.redis import Transport

        self.assertIsNotNone(packaging.__version__)
        self.assertTrue(hasattr(Transport, 'driver_version'))

    def test_check_packaging_installed_for_kombu(self):
        """Verify the Django deploy check for packaging passes in production environment."""
        from config.checks import check_packaging_installed_for_kombu
        errors = check_packaging_installed_for_kombu(None)
        self.assertEqual(errors, [])
