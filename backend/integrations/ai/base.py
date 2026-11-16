class GroceryVisionService:
    def analyze_grocery_images(self, image_paths: list, ocr_context: str = None) -> dict:
        """
        Detects multiple grocery items in the provided images, optionally incorporating OCR context.
        Returns a dictionary mapping structured JSON matching the expected schema.
        """
        raise NotImplementedError("GroceryVisionService subclasses must implement analyze_grocery_images")

class RecipeGenerationService:
    def generate_recipes(self, available_items: list, preferences: dict) -> dict:
        """
        Generates structured chef recipes based on expiring pantry items and dietary preferences.
        """
        raise NotImplementedError("RecipeGenerationService subclasses must implement generate_recipes")

class MealInferenceService:
    def infer_meal_ingredients(self, image_path: str, text_description: str, available_pantry_items: list) -> dict:
        """
        Infers ingredients used in a meal from an image and/or text description, matched against pantry items.
        """
        raise NotImplementedError("MealInferenceService subclasses must implement infer_meal_ingredients")
