import logging

from django.conf import settings

from .base import GroceryVisionService, MealInferenceService, RecipeGenerationService
from .gemini_client import AIContentBlockedError, GeminiClient
from .openai_client import OpenAIClient

logger = logging.getLogger('freshtrack.ai.service')

class AIService(GroceryVisionService, RecipeGenerationService, MealInferenceService):
    def __init__(self, provider_order: list = None, provider_instances: dict = None):
        self.provider_order = provider_order or getattr(settings, 'AI_PROVIDER_ORDER', ['gemini', 'openai'])
        self.provider_instances = provider_instances

    def _get_providers(self):
        if self.provider_instances is not None:
            return [(name, self.provider_instances[name]) for name in self.provider_order if name in self.provider_instances]

        providers = []
        for name in self.provider_order:
            name_lower = name.lower().strip()
            if name_lower == 'gemini':
                client = GeminiClient()
                if client.enabled:
                    providers.append(('gemini', client))
                else:
                    logger.info("Gemini provider is disabled or missing credentials.")
            elif name_lower == 'openai':
                client = OpenAIClient()
                if client.enabled:
                    providers.append(('openai', client))
                else:
                    logger.info("OpenAI provider is disabled or missing credentials.")
            else:
                logger.warning(f"Unknown AI provider name in AI_PROVIDER_ORDER: {name}")

        return providers

    def analyze_grocery_images(self, image_paths: list, ocr_context: str = None) -> dict:
        providers = self._get_providers()
        if not providers:
            logger.error("No active AI providers available for image analysis.")
            raise RuntimeError("No active AI providers available for image analysis.")

        errors = []
        blocked_count = 0
        for name, client in providers:
            try:
                logger.info(f"Attempting grocery scan analysis with provider: {name}")
                result = client.analyze_grocery_images(image_paths, ocr_context=ocr_context)
                if result and isinstance(result, dict) and "items" in result:
                    logger.info(f"Provider '{name}' successfully processed grocery scan analysis.")
                    return result
            except AIContentBlockedError as e:
                logger.warning(f"AI provider '{name}' content blocked during grocery scan: {e}")
                errors.append(f"{name}: {e}")
                blocked_count += 1
            except Exception as e:
                logger.warning(f"AI provider '{name}' failed during grocery scan: {e}")
                errors.append(f"{name}: {e}")

        logger.error(f"All AI providers failed for analyze_grocery_images. Errors: {errors}")
        if blocked_count == len(providers):
            raise AIContentBlockedError(f"All AI providers content blocked: {', '.join(errors)}")
        raise RuntimeError(f"All AI providers failed for analyze_grocery_images: {', '.join(errors)}")

    def generate_recipes(self, available_items: list, preferences: dict) -> dict:
        providers = self._get_providers()
        if not providers:
            logger.error("No active AI providers available for recipe generation.")
            raise RuntimeError("No active AI providers available for recipe generation.")

        errors = []
        blocked_count = 0
        for name, client in providers:
            try:
                logger.info(f"Attempting recipe generation with provider: {name}")
                result = client.generate_recipes(available_items, preferences)
                if result and isinstance(result, dict) and "recipes" in result:
                    logger.info(f"Provider '{name}' successfully generated recipes.")
                    return result
            except AIContentBlockedError as e:
                logger.warning(f"AI provider '{name}' content blocked during recipe generation: {e}")
                errors.append(f"{name}: {e}")
                blocked_count += 1
            except Exception as e:
                logger.warning(f"AI provider '{name}' failed during recipe generation: {e}")
                errors.append(f"{name}: {e}")

        logger.error(f"All AI providers failed for generate_recipes. Errors: {errors}")
        if blocked_count == len(providers):
            raise AIContentBlockedError(f"All AI providers content blocked: {', '.join(errors)}")
        raise RuntimeError(f"All AI providers failed for generate_recipes: {', '.join(errors)}")

    def infer_meal_ingredients(self, image_path: str, text_description: str, available_pantry_items: list) -> dict:
        providers = self._get_providers()
        if not providers:
            logger.error("No active AI providers available for meal ingredient inference.")
            raise RuntimeError("No active AI providers available for meal ingredient inference.")

        errors = []
        blocked_count = 0
        for name, client in providers:
            try:
                logger.info(f"Attempting meal ingredient inference with provider: {name}")
                result = client.infer_meal_ingredients(image_path, text_description, available_pantry_items)
                if result and isinstance(result, dict) and "ingredients" in result:
                    logger.info(f"Provider '{name}' successfully inferred meal ingredients.")
                    return result
            except AIContentBlockedError as e:
                logger.warning(f"AI provider '{name}' content blocked during meal ingredient inference: {e}")
                errors.append(f"{name}: {e}")
                blocked_count += 1
            except Exception as e:
                logger.warning(f"AI provider '{name}' failed during meal ingredient inference: {e}")
                errors.append(f"{name}: {e}")

        logger.error(f"All AI providers failed for infer_meal_ingredients. Errors: {errors}")
        if blocked_count == len(providers):
            raise AIContentBlockedError(f"All AI providers content blocked: {', '.join(errors)}")
        raise RuntimeError(f"All AI providers failed for infer_meal_ingredients: {', '.join(errors)}")
