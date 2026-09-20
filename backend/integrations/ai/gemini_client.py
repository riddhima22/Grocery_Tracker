import os
import json
import logging
from django.conf import settings
from django.utils import timezone
from PIL import Image

import warnings

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

from .base import GroceryVisionService, RecipeGenerationService, MealInferenceService
from .prompts import SYSTEM_INSTRUCTION, GROCERY_SCAN_PROMPT, RECIPE_GENERATION_PROMPT, MEAL_INFERENCE_PROMPT
from .schemas import GROCERY_SCAN_SCHEMA, RECIPE_GENERATION_SCHEMA, MEAL_INFERENCE_SCHEMA

logger = logging.getLogger('freshtrack.ai.gemini')

class AIContentBlockedError(Exception):
    """Raised when Gemini response is empty or blocked by safety/recitation/content filters."""
    pass


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
        
        self.scan_model_name = getattr(settings, 'GEMINI_MODEL_NAME', 'gemini-3.6-flash')
        self.recipe_model_name = getattr(settings, 'GEMINI_RECIPE_MODEL_NAME', 'gemini-3.6-flash')

        self.client = None
        if self.enabled:
            try:
                import os
                os.environ['GOOGLE_API_USE_REST'] = '1'
                if GENAI_NEW_SDK and hasattr(genai, 'Client'):
                    self.client = genai.Client(api_key=self.api_key)
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
        Loads and downscales an image if its longest side exceeds max_dim,
        maintaining aspect ratio with Image.LANCZOS resampling.
        Ensures dimensions never fall below the 150x150 minimum.
        """
        if isinstance(image_or_path, str):
            img = Image.open(image_or_path)
        else:
            img = image_or_path.copy()

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
            if lines[0].startswith('```json'):
                text = '\n'.join(lines[1:-1])
            elif lines[0].startswith('```'):
                text = '\n'.join(lines[1:-1])
        return text.strip()

    def analyze_grocery_images(self, image_paths: list, ocr_context: str = None) -> dict:
        if not self.enabled:
            logger.warning("Gemini Client is disabled. Returning empty results.")
            return {"items": []}

        raw_text = None
        try:
            images = []
            for path in image_paths:
                logger.info(f"Loading and preparing image for Gemini: {path}")
                images.append(self._prepare_image(path))

            current_date_str = timezone.now().date().isoformat()
            prompt = GROCERY_SCAN_PROMPT.format(
                ocr_text=ocr_context or "No packaging text extracted.",
                current_date=current_date_str
            )

            logger.info(f"Calling Gemini ({self.scan_model_name}) for scan analysis...")
            contents = [prompt] + images

            if self.client:
                config = types.GenerateContentConfig(
                    system_instruction=SYSTEM_INSTRUCTION,
                    response_mime_type="application/json",
                    response_schema=GROCERY_SCAN_SCHEMA
                ) if types else {"response_mime_type": "application/json", "response_schema": GROCERY_SCAN_SCHEMA}
                response = self.client.models.generate_content(
                    model=self.scan_model_name,
                    contents=contents,
                    config=config
                )
            else:
                model = genai.GenerativeModel(
                    model_name=self.scan_model_name,
                    system_instruction=SYSTEM_INSTRUCTION
                )
                response = model.generate_content(contents, generation_config={
                    "response_mime_type": "application/json",
                    "response_schema": GROCERY_SCAN_SCHEMA
                })

            raw_text = self._validate_response(response, "scan analysis")
            text_response = self._clean_json_text(raw_text)
            data = json.loads(text_response)
            logger.info(f"Gemini successfully scanned and returned {len(data.get('items', []))} items.")
            return data

        except AIContentBlockedError:
            raise
        except Exception as e:
            msg = translate_gemini_error(e, raw_text=raw_text, stage_name="scan analysis")
            logger.error(f"Gemini scan analysis failed: {e} -> {msg}", exc_info=True)
            raise RuntimeError(msg) from e

    def generate_recipes(self, available_items: list, preferences: dict) -> dict:
        if not self.enabled:
            logger.warning("Gemini Client is disabled. Recipe generation skipped.")
            return {"recipes": []}

        raw_text = None
        try:
            items_str = json.dumps(available_items, indent=2)

            prompt = RECIPE_GENERATION_PROMPT.format(
                available_items=items_str,
                diet_type=preferences.get('diet_type', 'any'),
                cuisine_pref=preferences.get('cuisine_pref', 'Indian'),
                allergens=json.dumps(preferences.get('allergies', [])),
                household_size=preferences.get('household_size', 1),
                max_prep_time_mins=preferences.get('max_prep_time_mins', 60),
                meal_type=preferences.get('meal_type', 'any')
            )

            logger.info(f"Calling Gemini ({self.recipe_model_name}) for recipe generation...")

            if self.client:
                config = types.GenerateContentConfig(
                    system_instruction=SYSTEM_INSTRUCTION,
                    response_mime_type="application/json",
                    response_schema=RECIPE_GENERATION_SCHEMA
                ) if types else {"response_mime_type": "application/json", "response_schema": RECIPE_GENERATION_SCHEMA}
                response = self.client.models.generate_content(
                    model=self.recipe_model_name,
                    contents=prompt,
                    config=config
                )
            else:
                model = genai.GenerativeModel(
                    model_name=self.recipe_model_name,
                    system_instruction=SYSTEM_INSTRUCTION
                )
                response = model.generate_content(prompt, generation_config={
                    "response_mime_type": "application/json",
                    "response_schema": RECIPE_GENERATION_SCHEMA
                })

            raw_text = self._validate_response(response, "recipe generation")
            text_response = self._clean_json_text(raw_text)
            data = json.loads(text_response)
            logger.info(f"Gemini successfully generated {len(data.get('recipes', []))} recipes.")
            return data

        except AIContentBlockedError:
            raise
        except Exception as e:
            msg = translate_gemini_error(e, raw_text=raw_text, stage_name="recipe generation")
            logger.error(f"Gemini recipe generation failed: {e} -> {msg}", exc_info=True)
            raise RuntimeError(msg) from e

    def infer_meal_ingredients(self, image_path: str, text_description: str, available_pantry_items: list) -> dict:
        if not self.enabled:
            logger.warning("Gemini Client is disabled. Meal inference skipped.")
            return {"meal_name": "Unknown", "description": "", "ingredients": []}

        raw_text = None
        try:
            items_str = json.dumps(available_pantry_items, indent=2)
            prompt = MEAL_INFERENCE_PROMPT.format(
                available_items=items_str,
                text_description=text_description or "None"
            )

            contents = [prompt]
            if image_path:
                logger.info(f"Loading and preparing image for Gemini Meal Inference: {image_path}")
                contents.append(self._prepare_image(image_path))

            logger.info(f"Calling Gemini ({self.scan_model_name}) for meal inference...")

            if self.client:
                config = types.GenerateContentConfig(
                    system_instruction=SYSTEM_INSTRUCTION,
                    response_mime_type="application/json",
                    response_schema=MEAL_INFERENCE_SCHEMA
                ) if types else {"response_mime_type": "application/json", "response_schema": MEAL_INFERENCE_SCHEMA}
                response = self.client.models.generate_content(
                    model=self.scan_model_name,
                    contents=contents,
                    config=config
                )
            else:
                model = genai.GenerativeModel(
                    model_name=self.scan_model_name,
                    system_instruction=SYSTEM_INSTRUCTION
                )
                response = model.generate_content(contents, generation_config={
                    "response_mime_type": "application/json",
                    "response_schema": MEAL_INFERENCE_SCHEMA
                })

            raw_text = self._validate_response(response, "meal inference")
            text_response = self._clean_json_text(raw_text)
            data = json.loads(text_response)
            logger.info(f"Gemini successfully inferred {len(data.get('ingredients', []))} ingredients.")
            return data

        except AIContentBlockedError:
            raise
        except Exception as e:
            msg = translate_gemini_error(e, raw_text=raw_text, stage_name="meal inference")
            logger.error(f"Gemini meal inference failed: {e} -> {msg}", exc_info=True)
            raise RuntimeError(msg) from e

