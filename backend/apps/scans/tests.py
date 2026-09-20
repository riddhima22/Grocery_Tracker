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

