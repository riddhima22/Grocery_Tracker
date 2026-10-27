import json
import logging
import os
import time
import warnings

from django.conf import settings
from django.utils import timezone
from PIL import Image, ImageOps

# Force REST transport across all Google API calls to avoid gRPC socket hangs
os.environ['GOOGLE_API_USE_REST'] = '1'

try:
    from google import genai
    from google.genai import types
    GENAI_NEW_SDK = True
except ImportError:
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            import google.generativeai as genai
        types = None
        GENAI_NEW_SDK = False
    except ImportError:
        genai = None
        types = None
        GENAI_NEW_SDK = False

from .base import GroceryVisionService, MealInferenceService, RecipeGenerationService
from .prompts import (
    GROCERY_SCAN_PROMPT,
    MEAL_INFERENCE_PROMPT,
    RECIPE_GENERATION_PROMPT,
    SYSTEM_INSTRUCTION,
)
from .schemas import (
    GROCERY_SCAN_SCHEMA,
    MEAL_INFERENCE_SCHEMA,
    RECIPE_GENERATION_SCHEMA,
)

logger = logging.getLogger('freshtrack.ai.gemini')

class AIContentBlockedError(Exception):
    """Raised when Gemini response is empty or blocked by safety/recitation/content filters."""


def translate_gemini_error(exc: Exception, raw_text: str = None, stage_name: str = "operation") -> str:
    """
    Translates underlying Gemini / Google API / network / parsing errors into
    clear, actionable, user-facing error messages with appropriate logging hints.
    """
    if isinstance(exc, AIContentBlockedError):
        return "The image couldn't be analyzed — try a clearer photo or a different angle."

    # Malformed / unparseable JSON response
    if isinstance(exc, json.JSONDecodeError):
        preview = (raw_text[:500] + '...') if raw_text and len(raw_text) > 500 else (raw_text or 'Empty')
        logger.warning(
            f"Malformed/unparseable JSON response returned by Gemini during {stage_name}. "
            f"Raw response preview (first 500 chars): {preview}"
        )
        return "AI service returned an unparseable response. Please try again."

    # Google API Core exception classes
    try:
        from google.api_core import exceptions as google_exceptions
        if isinstance(exc, (google_exceptions.PermissionDenied, google_exceptions.Unauthenticated)):
            logger.error(
                f"Gemini API authentication failed during {stage_name}: {exc}. "
                f"Check that GEMINI_API_KEY is configured correctly and has valid permissions."
            )
            return "AI service is not configured correctly. Contact support."
        if isinstance(exc, google_exceptions.ResourceExhausted):
            logger.warning(f"Gemini rate limit / quota exceeded during {stage_name}: {exc}.")
            return "Too many requests right now, try again in a minute."
        if isinstance(exc, (google_exceptions.DeadlineExceeded, google_exceptions.ServiceUnavailable,
                            google_exceptions.BadGateway, google_exceptions.GatewayTimeout)):
            logger.warning(f"Gemini network / timeout error during {stage_name}: {exc}.")
            return "Couldn't reach the AI service. Check your connection and try again."
    except ImportError:
        pass

    # Built-in network / timeout errors
    if isinstance(exc, (TimeoutError, ConnectionError)):
        logger.warning(f"Network error during {stage_name}: {exc}.")
        return "Couldn't reach the AI service. Check your connection and try again."

    msg = str(exc).lower()

    # API key / Permission errors
    if any(k in msg for k in ['api_key_invalid', 'api key not valid', 'permissiondenied', 'unauthenticated', 'invalid api key', '403', '401', 'api_key']):
        logger.error(
            f"Gemini API key / permission error during {stage_name}: {exc}. "
            f"Check that GEMINI_API_KEY is valid and configured."
        )
        return "AI service is not configured correctly. Contact support."

    # Rate limit / Quota errors
    if any(k in msg for k in ['429', 'resource_exhausted', 'resourceexhausted', 'quota exceeded', 'rate limit', 'too many requests']):
        logger.warning(f"Gemini rate limit exceeded during {stage_name}: {exc}.")
        return "Too many requests right now, try again in a minute."

    # Network / Timeout errors
    if any(k in msg for k in ['timeout', 'timed out', 'deadline exceeded', 'connection error', 'connection reset', '503', '502', '504', 'service unavailable']):
        logger.warning(f"Gemini connection error during {stage_name}: {exc}.")
        return "Couldn't reach the AI service. Check your connection and try again."

    return f"AI service failed: {exc}"


class GeminiClient(GroceryVisionService, RecipeGenerationService, MealInferenceService):
    def __init__(self):
        self.api_key = getattr(settings, 'GEMINI_API_KEY', '')
        self.enabled = bool(self.api_key and genai is not None)

        self.scan_model_name = getattr(settings, 'GEMINI_MODEL_NAME', 'gemini-3.5-flash-lite')
        self.recipe_model_name = getattr(settings, 'GEMINI_RECIPE_MODEL_NAME', 'gemini-3.5-flash-lite')
        self.fallback_models = getattr(
            settings,
            'GEMINI_FALLBACK_MODELS',
            ['gemini-3.5-flash-lite', 'gemini-3.6-flash', 'gemini-3.5-flash', 'gemini-3.8-flash']
        )
        self.timeout_seconds = getattr(settings, 'GEMINI_TIMEOUT_SECONDS', 25)

        self.client = None
        if self.enabled:
            try:
                os.environ['GOOGLE_API_USE_REST'] = '1'
                if GENAI_NEW_SDK and hasattr(genai, 'Client'):
                    client_kwargs = {'api_key': self.api_key}
                    if types and hasattr(types, 'HttpOptions'):
                        client_kwargs['http_options'] = types.HttpOptions(timeout=self.timeout_seconds * 1000)
                    self.client = genai.Client(**client_kwargs)
                else:
                    try:
                        genai.configure(api_key=self.api_key, transport='rest')
                    except TypeError:
                        genai.configure(api_key=self.api_key)
            except Exception as e:
                logger.warning(f"Failed to initialize Gemini client: {e}")
                self.enabled = False
        else:
            logger.warning("GEMINI_API_KEY is missing or genai package not available. Gemini client disabled.")

    def _prepare_image(self, image_or_path, max_dim: int = 1568) -> Image.Image:
        """
        Loads, auto-orients (EXIF), and downscales an image if its longest side exceeds max_dim,
        maintaining aspect ratio with Image.LANCZOS resampling.
        Ensures dimensions never fall below the 150x150 minimum.
        """
        if isinstance(image_or_path, str):
            img = Image.open(image_or_path)
        else:
            img = image_or_path.copy()

        try:
            img = ImageOps.exif_transpose(img)
        except Exception:
            pass

        if img.mode not in ('RGB', 'L'):
            img = img.convert('RGB')

        img.load()
        width, height = img.size
        longest = max(width, height)

        if longest > max_dim:
            scale = max_dim / float(longest)
            new_w = max(150, int(round(width * scale)))
            new_h = max(150, int(round(height * scale)))
            img = img.resize((new_w, new_h), resample=Image.LANCZOS)

        return img

    def _validate_response(self, response, stage_name: str) -> str:
        """
        Validates that response contains valid candidates and was not blocked
        by safety, recitation, or content filters. Returns response text.
        """
        if response is None:
            raise AIContentBlockedError(f"Gemini {stage_name} returned no response.")

        # Check prompt-level blocking
        prompt_feedback = getattr(response, 'prompt_feedback', None)
        if prompt_feedback:
            block_reason = getattr(prompt_feedback, 'block_reason', None)
            if block_reason:
                raise AIContentBlockedError(
                    f"Gemini {stage_name} was blocked at prompt level (block_reason: {block_reason})."
                )

        candidates = getattr(response, 'candidates', None)
        if not candidates or len(candidates) == 0:
            raise AIContentBlockedError(
                f"Gemini {stage_name} returned an empty response with no candidates."
            )

        first_candidate = candidates[0]
        finish_reason = getattr(first_candidate, 'finish_reason', None)

        reason_str = ""
        if finish_reason is not None:
            if hasattr(finish_reason, 'name'):
                reason_str = finish_reason.name.upper()
            else:
                reason_str = str(finish_reason).upper()

        blocked_indicators = ['SAFETY', 'RECITATION', 'BLOCKLIST', 'PROHIBITED', 'SPII', 'IMAGE_SAFETY', 'OTHER']
        if any(b in reason_str for b in blocked_indicators):
            raise AIContentBlockedError(
                f"Gemini {stage_name} was blocked by content filters (finish_reason: {reason_str or finish_reason})."
            )

        try:
            text = response.text
        except Exception as e:
            raise AIContentBlockedError(
                f"Gemini {stage_name} response text could not be extracted (finish_reason: {reason_str or finish_reason}): {e}"
            )

        if not text or not text.strip():
            raise AIContentBlockedError(
                f"Gemini {stage_name} returned empty text content (finish_reason: {reason_str or finish_reason})."
            )

        return text

    def _clean_json_text(self, text: str) -> str:
        text = text.strip()
        if text.startswith('```'):
            lines = text.splitlines()
            if lines[0].startswith('```json') or lines[0].startswith('```'):
                text = '\n'.join(lines[1:-1])
        return text.strip()

    def _get_candidate_models(self, primary_model: str) -> list:
        """Constructs ordered list of models: primary model first, followed by fallbacks without duplicates."""
        models = [primary_model]
        for m in self.fallback_models:
            if m not in models:
                models.append(m)
        return models

    def analyze_grocery_images(self, image_paths: list, ocr_context: str = None) -> dict:
        if not self.enabled:
            logger.warning("Gemini Client is disabled. Returning empty results.")
            return {"items": []}

        images = []
        for path in image_paths:
            size_kb = (os.path.getsize(path) / 1024) if os.path.exists(path) else 0
            logger.info(f"Loading and preparing image for Gemini: {path} ({size_kb:.1f} KB)")
            images.append(self._prepare_image(path))

        current_date_str = timezone.now().date().isoformat()
        prompt = GROCERY_SCAN_PROMPT.format(
            ocr_text=ocr_context or "No packaging text extracted.",
            current_date=current_date_str
        )
        contents = [prompt] + images

        candidate_models = self._get_candidate_models(self.scan_model_name)
        overall_start = time.time()
        last_exception = None
        raw_text = None

        for model_name in candidate_models:
            attempt_start = time.time()
            logger.info(f"AI analysis started with Gemini model '{model_name}'...")
            try:
                if self.client:
                    config_kwargs = {
                        "system_instruction": SYSTEM_INSTRUCTION,
                        "response_mime_type": "application/json",
                        "response_schema": GROCERY_SCAN_SCHEMA,
                    }
                    if types and hasattr(types, 'HttpOptions'):
                        config_kwargs["http_options"] = types.HttpOptions(timeout=self.timeout_seconds * 1000)

                    config = types.GenerateContentConfig(**config_kwargs) if types else config_kwargs
                    response = self.client.models.generate_content(
                        model=model_name,
                        contents=contents,
                        config=config
                    )
                else:
                    model = genai.GenerativeModel(
                        model_name=model_name,
                        system_instruction=SYSTEM_INSTRUCTION
                    )
                    response = model.generate_content(
                        contents,
                        generation_config={
                            "response_mime_type": "application/json",
                            "response_schema": GROCERY_SCAN_SCHEMA
                        }
                    )

                raw_text = self._validate_response(response, f"scan analysis ({model_name})")
                text_response = self._clean_json_text(raw_text)
                data = json.loads(text_response)
                items = data.get('items', [])

                attempt_elapsed = time.time() - attempt_start
                total_elapsed = time.time() - overall_start
                logger.info(
                    f"AI analysis completed with model '{model_name}' in {attempt_elapsed:.2f}s "
                    f"(total elapsed: {total_elapsed:.2f}s). Detected {len(items)} items."
                )
                return data

            except AIContentBlockedError as blocked_err:
                logger.warning(f"Gemini model '{model_name}' content blocked: {blocked_err}")
                raise
            except Exception as e:
                attempt_elapsed = time.time() - attempt_start
                last_exception = e
                logger.warning(
                    f"Gemini model '{model_name}' failed after {attempt_elapsed:.2f}s: {e}. "
                    f"Attempting fallback model..."
                )

        total_elapsed = time.time() - overall_start
        msg = translate_gemini_error(last_exception, raw_text=raw_text, stage_name="scan analysis")
        logger.error(
            f"All Gemini scan models {candidate_models} failed after {total_elapsed:.2f}s. "
            f"Last error: {last_exception} -> {msg}",
            exc_info=True
        )
        raise RuntimeError(msg) from last_exception

    def generate_recipes(self, available_items: list, preferences: dict) -> dict:
        if not self.enabled:
            logger.warning("Gemini Client is disabled. Recipe generation skipped.")
            return {"recipes": []}

        items_str = json.dumps(available_items, indent=2)
        prompt = RECIPE_GENERATION_PROMPT.format(
            available_items=items_str,
            diet_type=preferences.get('diet_type', 'any'),
            cuisine_pref=preferences.get('cuisine_pref', 'Indian'),
            allergens=json.dumps(preferences.get('allergies', [])),
            fitness_goal=preferences.get('fitness_goal', 'Balanced'),
            household_size=preferences.get('household_size', 1),
            max_prep_time_mins=preferences.get('max_prep_time_mins', 60),
            meal_type=preferences.get('meal_type', 'any')
        )

        candidate_models = self._get_candidate_models(self.recipe_model_name)
        overall_start = time.time()
        last_exception = None
        raw_text = None

        for model_name in candidate_models:
            attempt_start = time.time()
            logger.info(f"Recipe generation started with Gemini model '{model_name}'...")
            try:
                if self.client:
                    config_kwargs = {
                        "system_instruction": SYSTEM_INSTRUCTION,
                        "response_mime_type": "application/json",
                        "response_schema": RECIPE_GENERATION_SCHEMA,
                    }
                    if types and hasattr(types, 'HttpOptions'):
                        config_kwargs["http_options"] = types.HttpOptions(timeout=self.timeout_seconds * 1000)

                    config = types.GenerateContentConfig(**config_kwargs) if types else config_kwargs
                    response = self.client.models.generate_content(
                        model=model_name,
                        contents=prompt,
                        config=config
                    )
                else:
                    model = genai.GenerativeModel(
                        model_name=model_name,
                        system_instruction=SYSTEM_INSTRUCTION
                    )
                    response = model.generate_content(
                        prompt,
                        generation_config={
                            "response_mime_type": "application/json",
                            "response_schema": RECIPE_GENERATION_SCHEMA
                        }
                    )

                raw_text = self._validate_response(response, f"recipe generation ({model_name})")
                text_response = self._clean_json_text(raw_text)
                data = json.loads(text_response)
                recipes = data.get('recipes', [])

                attempt_elapsed = time.time() - attempt_start
                logger.info(f"Gemini successfully generated {len(recipes)} recipes with '{model_name}' in {attempt_elapsed:.2f}s.")
                return data

            except AIContentBlockedError as blocked_err:
                logger.warning(f"Gemini recipe generation blocked with '{model_name}': {blocked_err}")
                raise
            except Exception as e:
                attempt_elapsed = time.time() - attempt_start
                last_exception = e
                logger.warning(f"Gemini model '{model_name}' failed recipe generation after {attempt_elapsed:.2f}s: {e}")

        total_elapsed = time.time() - overall_start
        msg = translate_gemini_error(last_exception, raw_text=raw_text, stage_name="recipe generation")
        logger.error(f"All Gemini recipe models failed after {total_elapsed:.2f}s: {last_exception} -> {msg}")
        raise RuntimeError(msg) from last_exception

    def infer_meal_ingredients(self, image_path: str, text_description: str, available_pantry_items: list) -> dict:
        if not self.enabled:
            logger.warning("Gemini Client is disabled. Meal inference skipped.")
            return {"meal_name": "Unknown", "description": "", "ingredients": []}

        items_str = json.dumps(available_pantry_items, indent=2)
        prompt = MEAL_INFERENCE_PROMPT.format(
            available_items=items_str,
            text_description=text_description or "None"
        )
        contents = [prompt]
        if image_path:
            size_kb = (os.path.getsize(image_path) / 1024) if os.path.exists(image_path) else 0
            logger.info(f"Loading and preparing image for Gemini Meal Inference: {image_path} ({size_kb:.1f} KB)")
            contents.append(self._prepare_image(image_path))

        candidate_models = self._get_candidate_models(self.scan_model_name)
        overall_start = time.time()
        last_exception = None
        raw_text = None

        for model_name in candidate_models:
            attempt_start = time.time()
            logger.info(f"Meal inference started with Gemini model '{model_name}'...")
            try:
                if self.client:
                    config_kwargs = {
                        "system_instruction": SYSTEM_INSTRUCTION,
                        "response_mime_type": "application/json",
                        "response_schema": MEAL_INFERENCE_SCHEMA,
                    }
                    if types and hasattr(types, 'HttpOptions'):
                        config_kwargs["http_options"] = types.HttpOptions(timeout=self.timeout_seconds * 1000)

                    config = types.GenerateContentConfig(**config_kwargs) if types else config_kwargs
                    response = self.client.models.generate_content(
                        model=model_name,
                        contents=contents,
                        config=config
                    )
                else:
                    model = genai.GenerativeModel(
                        model_name=model_name,
                        system_instruction=SYSTEM_INSTRUCTION
                    )
                    response = model.generate_content(
                        contents,
                        generation_config={
                            "response_mime_type": "application/json",
                            "response_schema": MEAL_INFERENCE_SCHEMA
                        }
                    )

                raw_text = self._validate_response(response, f"meal inference ({model_name})")
                text_response = self._clean_json_text(raw_text)
                data = json.loads(text_response)
                ingredients = data.get('ingredients', [])

                attempt_elapsed = time.time() - attempt_start
                logger.info(f"Gemini successfully inferred {len(ingredients)} ingredients with '{model_name}' in {attempt_elapsed:.2f}s.")
                return data

            except AIContentBlockedError as blocked_err:
                logger.warning(f"Gemini meal inference blocked with '{model_name}': {blocked_err}")
                raise
            except Exception as e:
                attempt_elapsed = time.time() - attempt_start
                last_exception = e
                logger.warning(f"Gemini model '{model_name}' failed meal inference after {attempt_elapsed:.2f}s: {e}")

        total_elapsed = time.time() - overall_start
        msg = translate_gemini_error(last_exception, raw_text=raw_text, stage_name="meal inference")
        logger.error(f"All Gemini meal inference models failed after {total_elapsed:.2f}s: {last_exception} -> {msg}")
        raise RuntimeError(msg) from last_exception

