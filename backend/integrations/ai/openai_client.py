import base64
import json
import logging

from django.conf import settings
from django.utils import timezone

try:
    from openai import OpenAI
    OPENAI_AVAILABLE = True
except ImportError:
    OpenAI = None
    OPENAI_AVAILABLE = False

from .base import GroceryVisionService, MealInferenceService, RecipeGenerationService
from .prompts import (
    GROCERY_SCAN_PROMPT,
    MEAL_INFERENCE_PROMPT,
    RECIPE_GENERATION_PROMPT,
    SYSTEM_INSTRUCTION,
)

logger = logging.getLogger('freshtrack.ai.openai')

class OpenAIClient(GroceryVisionService, RecipeGenerationService, MealInferenceService):
    def __init__(self):
        self.api_key = getattr(settings, 'OPENAI_API_KEY', '')
        self.enabled = bool(self.api_key and OPENAI_AVAILABLE)
        self.model_name = getattr(settings, 'OPENAI_MODEL_NAME', 'gpt-4o-mini')

        self.client = None
        if self.enabled:
            try:
                self.client = OpenAI(api_key=self.api_key)
            except Exception as e:
                logger.warning(f"Failed to initialize OpenAI client: {e}")
                self.enabled = False
        else:
            logger.warning("OPENAI_API_KEY is missing or openai package not available. OpenAI client disabled.")

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

    def analyze_grocery_images(self, image_paths: list, ocr_context: str = None) -> dict:
        if not self.enabled:
            logger.warning("OpenAI Client is disabled. Returning empty results.")
            return {"items": []}

        try:
            current_date_str = timezone.now().date().isoformat()
            prompt = GROCERY_SCAN_PROMPT.format(
                ocr_text=ocr_context or "No packaging text extracted.",
                current_date=current_date_str
            )

            content = [{"type": "text", "text": prompt}]

            for path in image_paths:
                logger.info(f"Encoding image for OpenAI Vision: {path}")
                b64_img = self._encode_image_to_base64(path)
                content.append({
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:image/jpeg;base64,{b64_img}"
                    }
                })

            logger.info(f"Calling OpenAI ({self.model_name}) for scan analysis...")
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
            logger.info(f"OpenAI successfully scanned and returned {len(data.get('items', []))} items.")
            return data

        except Exception as e:
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
            logger.error(f"OpenAI meal inference failed: {e}", exc_info=True)
            raise e
