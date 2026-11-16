import base64
import json
import logging
import os

from django.conf import settings
from django.utils import timezone

try:
    from openai import AuthenticationError, OpenAI
    OPENAI_AVAILABLE = True
except ImportError:
    OpenAI = None
    AuthenticationError = None
    OPENAI_AVAILABLE = False

from .base import GroceryVisionService, MealInferenceService, RecipeGenerationService
from .prompts import (
    GROCERY_SCAN_PROMPT,
    MEAL_INFERENCE_PROMPT,
    RECIPE_GENERATION_PROMPT,
    SYSTEM_INSTRUCTION,
)

logger = logging.getLogger('freshtrack.ai.openai')


class OpenAIAuthenticationError(Exception):
    """
    Raised when the OpenAI API rejects credentials (HTTP 401).
    Classified as a permanent configuration failure, not a transient error.
    """
    status_code = 401
    is_configuration_error = True


def is_openai_auth_error(exc: Exception) -> bool:
    """Detects whether an exception is an OpenAI 401 authentication/key error."""
    if AuthenticationError and isinstance(exc, AuthenticationError):
        return True
    if getattr(exc, 'status_code', None) == 401 or getattr(exc, 'code', None) == 401:
        return True
    msg = str(exc).lower()
    return '401' in msg and ('api key' in msg or 'authentication' in msg or 'unauthorized' in msg or 'incorrect' in msg)


class OpenAIClient(GroceryVisionService, RecipeGenerationService, MealInferenceService):
    def __init__(self, api_key: str = None):
        # Prefer direct argument or fresh os.environ over cached settings
        raw_key = api_key if api_key is not None else (
            os.environ.get('OPENAI_API_KEY') or getattr(settings, 'OPENAI_API_KEY', '')
        )
        self.api_key = raw_key.strip().strip('\'"') if isinstance(raw_key, str) else ''
        self.enabled = bool(self.api_key and OPENAI_AVAILABLE)

        raw_model = getattr(settings, 'OPENAI_MODEL_NAME', 'gpt-4o-mini')
        self.model_name = raw_model.strip().strip('\'"') if isinstance(raw_model, str) else 'gpt-4o-mini'

        raw_project = os.environ.get('OPENAI_PROJECT_ID') or getattr(settings, 'OPENAI_PROJECT_ID', None)
        self.project = raw_project.strip().strip('\'"') if isinstance(raw_project, str) and raw_project.strip() else None

        raw_org = os.environ.get('OPENAI_ORG_ID') or getattr(settings, 'OPENAI_ORG_ID', None)
        self.organization = raw_org.strip().strip('\'"') if isinstance(raw_org, str) and raw_org.strip() else None

        raw_base_url = os.environ.get('OPENAI_BASE_URL') or getattr(settings, 'OPENAI_BASE_URL', None)
        self.base_url = raw_base_url.strip().strip('\'"') if isinstance(raw_base_url, str) and raw_base_url.strip() else None

        self.client = None
        if self.enabled:
            try:
                timeout_sec = getattr(settings, 'AI_REQUEST_TIMEOUT_SECONDS', 22)
                client_kwargs = {
                    'api_key': self.api_key,
                    'timeout': float(timeout_sec),
                    'max_retries': 1,
                }
                if self.project:
                    client_kwargs['project'] = self.project
                if self.organization:
                    client_kwargs['organization'] = self.organization
                if self.base_url:
                    client_kwargs['base_url'] = self.base_url
                self.client = OpenAI(**client_kwargs)
                logger.info(
                    "OpenAI client initialized safely. "
                    "Key configured: True, Model: %s, Project: %s, Org: %s",
                    self.model_name,
                    "configured" if self.project else "default",
                    "configured" if self.organization else "default",
                )
            except Exception as e:
                logger.warning(f"Failed to initialize OpenAI client: {e}")
                self.enabled = False
        else:
            logger.info(
                "OpenAI client is disabled. Key configured: %s, OpenAI SDK available: %s",
                bool(self.api_key),
                OPENAI_AVAILABLE,
            )

    def _encode_image_to_base64(self, image_path: str) -> str:
        with open(image_path, "rb") as img_file:
            return base64.b64encode(img_file.read()).decode('utf-8')

    def _clean_json_text(self, text: str) -> str:
        text = text.strip()
        if text.startswith('```'):
            lines = text.splitlines()
            if lines[0].startswith('```json') or lines[0].startswith('```'):
                text = '\n'.join(lines[1:-1])
        return text.strip()

    def analyze_grocery_images(self, image_paths: list, ocr_context: str = None, correlation_id: str = None) -> dict:
        if not self.enabled:
            logger.warning("OpenAI Client is disabled. Returning empty results.")
            return {"items": []}

        import time
        t_start = time.time()
        corr_tag = f"CorrelationID={correlation_id} " if correlation_id else ""

        try:
            current_date_str = timezone.now().date().isoformat()
            prompt = GROCERY_SCAN_PROMPT.format(
                ocr_text=ocr_context or "No packaging text extracted.",
                current_date=current_date_str
            )

            content = [{"type": "text", "text": prompt}]

            for path in image_paths:
                b64_img = self._encode_image_to_base64(path)
                content.append({
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:image/jpeg;base64,{b64_img}"
                    }
                })

            timeout_sec = getattr(settings, 'AI_REQUEST_TIMEOUT_SECONDS', 22)
            logger.info(f"[openai_started] {corr_tag}Calling OpenAI ({self.model_name}) timeout={timeout_sec}s images={len(image_paths)}")
            response = self.client.chat.completions.create(
                model=self.model_name,
                messages=[
                    {"role": "system", "content": SYSTEM_INSTRUCTION},
                    {"role": "user", "content": content}
                ],
                response_format={"type": "json_object"},
                max_tokens=1500,
                timeout=float(timeout_sec)
            )

            t_openai = time.time() - t_start
            text_response = response.choices[0].message.content
            cleaned = self._clean_json_text(text_response)
            data = json.loads(cleaned)
            items = data.get('items', [])
            logger.info(
                f"[openai_completed] {corr_tag}model={self.model_name} elapsed_ms={int(t_openai * 1000)} items={len(items)}"
            )
            return data

        except Exception as e:
            t_openai = time.time() - t_start
            logger.warning(
                f"[openai_failed] {corr_tag}model={self.model_name} elapsed_ms={int(t_openai * 1000)} error={e}"
            )
            if is_openai_auth_error(e):
                self.enabled = False
                logger.critical(
                    "OpenAI API authentication failed (HTTP 401: Incorrect API key provided). "
                    "This is a permanent configuration failure. Please verify the OPENAI_API_KEY "
                    "environment variable in your Render Web Service and Celery Worker settings."
                )
                raise OpenAIAuthenticationError(
                    "OpenAI API authentication failed (401 Incorrect API key provided). "
                    "Please configure a valid OPENAI_API_KEY in Render."
                ) from e
            logger.error(f"OpenAI scan analysis failed: {e}", exc_info=True)
            raise e

    def generate_recipes(self, available_items: list, preferences: dict) -> dict:
        if not self.enabled:
            logger.warning("OpenAI Client is disabled. Recipe generation skipped.")
            return {"recipes": []}

        try:
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

            logger.info(f"Calling OpenAI ({self.model_name}) for recipe generation...")
            response = self.client.chat.completions.create(
                model=self.model_name,
                messages=[
                    {"role": "system", "content": SYSTEM_INSTRUCTION},
                    {"role": "user", "content": prompt}
                ],
                response_format={"type": "json_object"}
            )

            text_response = response.choices[0].message.content
            cleaned = self._clean_json_text(text_response)
            data = json.loads(cleaned)
            logger.info(f"OpenAI successfully generated {len(data.get('recipes', []))} recipes.")
            return data

        except Exception as e:
            if is_openai_auth_error(e):
                self.enabled = False
                logger.critical(
                    "OpenAI API authentication failed (HTTP 401: Incorrect API key provided). "
                    "This is a permanent configuration failure. Please verify the OPENAI_API_KEY "
                    "environment variable in your Render Web Service and Celery Worker settings."
                )
                raise OpenAIAuthenticationError(
                    "OpenAI API authentication failed (401 Incorrect API key provided). "
                    "Please configure a valid OPENAI_API_KEY in Render."
                ) from e
            logger.error(f"OpenAI recipe generation failed: {e}", exc_info=True)
            raise e

    def infer_meal_ingredients(self, image_path: str, text_description: str, available_pantry_items: list) -> dict:
        if not self.enabled:
            logger.warning("OpenAI Client is disabled. Meal inference skipped.")
            return {"meal_name": "Unknown", "description": "", "ingredients": []}

        try:
            items_str = json.dumps(available_pantry_items, indent=2)
            prompt = MEAL_INFERENCE_PROMPT.format(
                available_items=items_str,
                text_description=text_description or "None"
            )

            content = [{"type": "text", "text": prompt}]
            if image_path:
                logger.info(f"Encoding image for OpenAI Meal Inference: {image_path}")
                b64_img = self._encode_image_to_base64(image_path)
                content.append({
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:image/jpeg;base64,{b64_img}"
                    }
                })

            logger.info(f"Calling OpenAI ({self.model_name}) for meal inference...")
            response = self.client.chat.completions.create(
                model=self.model_name,
                messages=[
                    {"role": "system", "content": SYSTEM_INSTRUCTION},
                    {"role": "user", "content": content}
                ],
                response_format={"type": "json_object"}
            )

            text_response = response.choices[0].message.content
            cleaned = self._clean_json_text(text_response)
            data = json.loads(cleaned)
            logger.info(f"OpenAI successfully inferred {len(data.get('ingredients', []))} ingredients.")
            return data

        except Exception as e:
            if is_openai_auth_error(e):
                self.enabled = False
                logger.critical(
                    "OpenAI API authentication failed (HTTP 401: Incorrect API key provided). "
                    "This is a permanent configuration failure. Please verify the OPENAI_API_KEY "
                    "environment variable in your Render Web Service and Celery Worker settings."
                )
                raise OpenAIAuthenticationError(
                    "OpenAI API authentication failed (401 Incorrect API key provided). "
                    "Please configure a valid OPENAI_API_KEY in Render."
                ) from e
            logger.error(f"OpenAI meal inference failed: {e}", exc_info=True)
            raise e
