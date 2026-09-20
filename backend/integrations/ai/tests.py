from unittest.mock import MagicMock, patch
from django.test import TestCase
from django.test.utils import override_settings

from integrations.ai.ai_service import AIService
from integrations.ai.base import GroceryVisionService, RecipeGenerationService, MealInferenceService


class DummyProvider(GroceryVisionService, RecipeGenerationService, MealInferenceService):
    def __init__(self, name="dummy", fail=False, return_val=None):
        self.name = name
        self.fail = fail
        self.return_val = return_val or {}

    def analyze_grocery_images(self, image_paths: list, ocr_context: str = None) -> dict:
        if self.fail:
            raise RuntimeError(f"Provider {self.name} failed analyze_grocery_images")
        return self.return_val or {"items": [{"name": f"Item from {self.name}"}]}

    def generate_recipes(self, available_items: list, preferences: dict) -> dict:
        if self.fail:
            raise RuntimeError(f"Provider {self.name} failed generate_recipes")
        return self.return_val or {"recipes": [{"name": f"Recipe from {self.name}"}]}

    def infer_meal_ingredients(self, image_path: str, text_description: str, available_pantry_items: list) -> dict:
        if self.fail:
            raise RuntimeError(f"Provider {self.name} failed infer_meal_ingredients")
        return self.return_val or {
            "meal_name": f"Meal from {self.name}",
            "description": "Test meal",
            "ingredients": [{"name": "Ingredient 1", "estimated_quantity": 1, "unit": "pcs", "confidence": "High"}]
        }


class AIServiceFallbackTests(TestCase):
    def test_gemini_primary_success(self):
        gemini = DummyProvider(name="gemini", return_val={"items": [{"name": "Gemini Milk"}]})
        openai = DummyProvider(name="openai", return_val={"items": [{"name": "OpenAI Milk"}]})
        
        service = AIService(
            provider_order=["gemini", "openai"],
            provider_instances={"gemini": gemini, "openai": openai}
        )

        res = service.analyze_grocery_images(["/fake/path.jpg"])
        self.assertEqual(res["items"][0]["name"], "Gemini Milk")

    def test_fallback_to_openai_when_gemini_fails(self):
        gemini = DummyProvider(name="gemini", fail=True)
        openai = DummyProvider(name="openai", return_val={"recipes": [{"name": "OpenAI Stew"}]})

        service = AIService(
            provider_order=["gemini", "openai"],
            provider_instances={"gemini": gemini, "openai": openai}
        )

        res = service.generate_recipes([], {})
        self.assertEqual(res["recipes"][0]["name"], "OpenAI Stew")

    def test_infer_meal_ingredients_fallback(self):
        gemini = DummyProvider(name="gemini", fail=True)
        openai = DummyProvider(name="openai", return_val={
            "meal_name": "OpenAI Curry",
            "description": "Delish curry",
            "ingredients": [{"name": "Paneer", "estimated_quantity": 200, "unit": "g", "confidence": "High"}]
        })

        service = AIService(
            provider_order=["gemini", "openai"],
            provider_instances={"gemini": gemini, "openai": openai}
        )

        res = service.infer_meal_ingredients(None, "Paneer Curry", [])
        self.assertEqual(res["meal_name"], "OpenAI Curry")
        self.assertEqual(len(res["ingredients"]), 1)

    def test_all_providers_failed_raises_exception(self):
        gemini = DummyProvider(name="gemini", fail=True)
        openai = DummyProvider(name="openai", fail=True)

        service = AIService(
            provider_order=["gemini", "openai"],
            provider_instances={"gemini": gemini, "openai": openai}
        )

        with self.assertRaises(RuntimeError):
            service.analyze_grocery_images(["/fake/path.jpg"])

        with self.assertRaises(RuntimeError):
            service.generate_recipes([], {})

        with self.assertRaises(RuntimeError):
            service.infer_meal_ingredients(None, "test", [])

    @override_settings(AI_PROVIDER_ORDER=["openai", "gemini"])
    def test_custom_provider_order_from_settings(self):
        gemini = DummyProvider(name="gemini", return_val={"items": [{"name": "Gemini Item"}]})
        openai = DummyProvider(name="openai", return_val={"items": [{"name": "OpenAI Item"}]})

        service = AIService(
            provider_instances={"gemini": gemini, "openai": openai}
        )

        res = service.analyze_grocery_images(["/fake/path.jpg"])
        self.assertEqual(res["items"][0]["name"], "OpenAI Item")


class GeminiHardeningTests(TestCase):
    def test_image_downscaling_large_image(self):
        from PIL import Image
        from integrations.ai.gemini_client import GeminiClient
        client = GeminiClient()

        # Create a large 3000x1500 test image in memory
        large_img = Image.new('RGB', (3000, 1500), color='green')
        prepared = client._prepare_image(large_img, max_dim=1568)
        
        self.assertEqual(prepared.size[0], 1568)
        self.assertEqual(prepared.size[1], 784)

    def test_image_downscaling_portrait_image(self):
        from PIL import Image
        from integrations.ai.gemini_client import GeminiClient
        client = GeminiClient()

        # Create a large 2000x4000 test image in memory
        portrait_img = Image.new('RGB', (2000, 4000), color='blue')
        prepared = client._prepare_image(portrait_img, max_dim=1568)
        
        self.assertEqual(prepared.size[1], 1568)
        self.assertEqual(prepared.size[0], 784)

    def test_image_downscaling_small_image_untouched(self):
        from PIL import Image
        from integrations.ai.gemini_client import GeminiClient
        client = GeminiClient()

        small_img = Image.new('RGB', (800, 600), color='red')
        prepared = client._prepare_image(small_img, max_dim=1568)
        
        self.assertEqual(prepared.size, (800, 600))

    def test_validate_response_empty_candidates_raises_blocked_error(self):
        from integrations.ai.gemini_client import GeminiClient, AIContentBlockedError
        client = GeminiClient()

        mock_resp = MagicMock()
        mock_resp.candidates = []
        mock_resp.prompt_feedback = None

        with self.assertRaises(AIContentBlockedError) as ctx:
            client._validate_response(mock_resp, "scan")
        self.assertIn("empty response with no candidates", str(ctx.exception))

    def test_validate_response_safety_finish_reason_raises_blocked_error(self):
        from integrations.ai.gemini_client import GeminiClient, AIContentBlockedError
        client = GeminiClient()

        mock_candidate = MagicMock()
        mock_candidate.finish_reason = "SAFETY"
        mock_resp = MagicMock()
        mock_resp.candidates = [mock_candidate]
        mock_resp.prompt_feedback = None

        with self.assertRaises(AIContentBlockedError) as ctx:
            client._validate_response(mock_resp, "recipe generation")
        self.assertIn("blocked by content filters", str(ctx.exception))

    def test_validate_response_recitation_finish_reason_raises_blocked_error(self):
        from integrations.ai.gemini_client import GeminiClient, AIContentBlockedError
        client = GeminiClient()

        mock_candidate = MagicMock()
        mock_candidate.finish_reason = "RECITATION"
        mock_resp = MagicMock()
        mock_resp.candidates = [mock_candidate]
        mock_resp.prompt_feedback = None

        with self.assertRaises(AIContentBlockedError) as ctx:
            client._validate_response(mock_resp, "meal inference")
        self.assertIn("blocked by content filters", str(ctx.exception))

    def test_model_router_catches_ai_content_blocked_error(self):
        from integrations.ai.model_router import ModelRouter
        from integrations.ai.gemini_client import AIContentBlockedError

        router = ModelRouter()
        with patch.object(router, 'run_image_quality_checks', return_value=([], [], ["/fake/valid.jpg"])):
            with patch.object(router.ai_client, 'analyze_grocery_images', side_effect=AIContentBlockedError("Safety blocked")):
                result = router.process_scan(["/fake/valid.jpg"])
                self.assertFalse(result["success"])
                self.assertEqual(result["error"], "The image couldn't be analyzed — try a clearer photo or a different angle.")

    def test_settings_gemini_model_defaults(self):
        from django.conf import settings
        self.assertEqual(settings.GEMINI_MODEL_NAME, 'gemini-3.6-flash')
        self.assertEqual(settings.GEMINI_RECIPE_MODEL_NAME, 'gemini-3.6-flash')

    def test_translate_gemini_error_auth_error(self):
        from integrations.ai.gemini_client import translate_gemini_error
        msg = translate_gemini_error(Exception("API_KEY_INVALID: API key not valid"))
        self.assertEqual(msg, "AI service is not configured correctly. Contact support.")

    def test_translate_gemini_error_rate_limit(self):
        from integrations.ai.gemini_client import translate_gemini_error
        msg = translate_gemini_error(Exception("429 ResourceExhausted: Quota exceeded"))
        self.assertEqual(msg, "Too many requests right now, try again in a minute.")

    def test_translate_gemini_error_timeout(self):
        from integrations.ai.gemini_client import translate_gemini_error
        msg = translate_gemini_error(TimeoutError("Request timed out"))
        self.assertEqual(msg, "Couldn't reach the AI service. Check your connection and try again.")

    def test_translate_gemini_error_json_decode_error(self):
        import json
        from integrations.ai.gemini_client import translate_gemini_error
        try:
            json.loads("invalid json text here")
        except json.JSONDecodeError as e:
            msg = translate_gemini_error(e, raw_text="invalid json text here", stage_name="scan")
            self.assertEqual(msg, "AI service returned an unparseable response. Please try again.")

    def test_opencv_laplacian_blur_detection(self):
        import tempfile
        import os
        from PIL import Image, ImageFilter
        from integrations.ai.model_router import ModelRouter

        router = ModelRouter()

        # Create a sharp image with high-contrast checkerboard
        sharp_img = Image.new('RGB', (200, 200), color='white')
        for x in range(0, 200, 20):
            for y in range(0, 200, 20):
                if (x // 20 + y // 20) % 2 == 0:
                    sharp_img.paste(Image.new('RGB', (20, 20), color='black'), (x, y))

        with tempfile.NamedTemporaryFile(suffix='.jpg', delete=False) as f:
            sharp_path = f.name
            sharp_img.save(sharp_path)

        # Create a heavily blurred image
        blurred_img = sharp_img.filter(ImageFilter.GaussianBlur(radius=15))
        with tempfile.NamedTemporaryFile(suffix='.jpg', delete=False) as f:
            blurred_path = f.name
            blurred_img.save(blurred_path)

        try:
            _, sharp_warnings, _ = router.run_image_quality_checks([sharp_path])
            self.assertFalse(any("might be blurry" in w for w in sharp_warnings))

            _, blur_warnings, _ = router.run_image_quality_checks([blurred_path])
            self.assertTrue(any("might be blurry" in w for w in blur_warnings))
        finally:
            if os.path.exists(sharp_path):
                os.remove(sharp_path)
            if os.path.exists(blurred_path):
                os.remove(blurred_path)

    def test_dark_image_clahe_preprocessing(self):
        import tempfile
        import os
        from PIL import Image
        from integrations.ai.model_router import ModelRouter

        router = ModelRouter()

        # Create very dark image
        dark_img = Image.new('RGB', (300, 300), color=(10, 10, 10))
        with tempfile.NamedTemporaryFile(suffix='.jpg', delete=False) as f:
            dark_path = f.name
            dark_img.save(dark_path)

        try:
            prep_path, is_temp = router._preprocess_image_for_ai(dark_path, is_dark=True)
            self.assertTrue(is_temp)
            self.assertTrue(os.path.exists(prep_path))
            self.assertNotEqual(prep_path, dark_path)
            
            # Clean up temp prep file
            if os.path.exists(prep_path):
                os.remove(prep_path)
        finally:
            if os.path.exists(dark_path):
                os.remove(dark_path)


