# Strict JSON schemas for Gemini model structured responses

GROCERY_SCAN_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "items": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "name": {"type": "STRING"},
                    "brand": {"type": "STRING", "nullable": True},
                    "description": {"type": "STRING", "nullable": True},
                    "category": {"type": "STRING"},
                    "icon_key": {"type": "STRING"},
                    "quantity": {"type": "NUMBER"},
                    "unit": {
                        "type": "STRING",
                        "enum": ["kg", "g", "l", "L", "ml", "pcs", "pack", "bottle", "box", "dozen", "bunch", "packet"]
                    },
                    "expiry_date": {"type": "STRING", "nullable": True}, # YYYY-MM-DD format
                    "estimated_consumption_date": {"type": "STRING", "nullable": True}, # YYYY-MM-DD format
                    "is_expiry_estimated": {"type": "BOOLEAN"},
                    "manufacturing_date": {"type": "STRING", "nullable": True}, # YYYY-MM-DD format
                    "packed_date": {"type": "STRING", "nullable": True}, # YYYY-MM-DD format
                    "best_before_date": {"type": "STRING", "nullable": True}, # YYYY-MM-DD format
                    "date_type": {
                        "type": "STRING",
                        "enum": ["expiry", "best_before", "use_by", "manufacturing", "packed", "estimated", "unknown"]
                    },
                    "date_source": {
                        "type": "STRING",
                        "enum": ["ocr_verified", "vision_detected", "calculated_from_packaging", "calculated_shelf_life", "user_entered", "unknown"]
                    },
                    "raw_date_text": {"type": "STRING", "nullable": True},
                    "storage_zone": {
                        "type": "STRING",
                        "enum": ["fridge", "freezer", "pantry", "counter", "cabinet", "basket", "spice"]
                    },
                    "storage_reason": {"type": "STRING", "nullable": True},
                    "shelf_life_guidance": {"type": "STRING", "nullable": True},
                    "confidence": {
                        "type": "STRING",
                        "enum": ["High", "Medium", "Low"]
                    },
                    "date_confidence": {
                        "type": "STRING",
                        "enum": ["High", "Medium", "Low"]
                    },
                    "source_image_index": {"type": "INTEGER"},
                    "warnings": {
                        "type": "ARRAY",
                        "items": {"type": "STRING"}
                    }
                },
                "required": ["name", "category", "icon_key", "quantity", "unit", "storage_zone", "confidence", "warnings"]
            }
        }
    },
    "required": ["items"]
}

RECIPE_GENERATION_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "recipes": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "name": {"type": "STRING"},
                    "icon_key": {"type": "STRING"},
                    "cuisine": {"type": "STRING"},
                    "diet_type": {"type": "STRING", "enum": ["veg", "non-veg"]},
                    "prep_time_mins": {"type": "INTEGER"},
                    "servings": {"type": "INTEGER"},
                    "calories_per_serving": {"type": "INTEGER"},
                    "ingredients_used": {
                        "type": "ARRAY",
                        "items": {
                            "type": "OBJECT",
                            "properties": {
                                "pantry_item_id": {"type": "STRING"},
                                "name": {"type": "STRING"},
                                "quantity": {"type": "NUMBER"},
                                "unit": {"type": "STRING"}
                            },
                            "required": ["name", "quantity", "unit"]
                        }
                    },
                    "other_ingredients": {
                        "type": "ARRAY",
                        "items": {"type": "STRING"}
                    },
                    "allergens": {
                        "type": "ARRAY",
                        "items": {"type": "STRING"}
                    },
                    "steps": {
                        "type": "ARRAY",
                        "items": {"type": "STRING"}
                    },
                    "nutrition": {
                        "type": "OBJECT",
                        "properties": {
                            "protein_g": {"type": "INTEGER"},
                            "carbs_g": {"type": "INTEGER"},
                            "fat_g": {"type": "INTEGER"},
                            "fiber_g": {"type": "INTEGER"}
                        },
                        "required": ["protein_g", "carbs_g", "fat_g", "fiber_g"]
                    },
                    "tip": {"type": "STRING"}
                },
                "required": ["name", "icon_key", "cuisine", "diet_type", "prep_time_mins", "servings", "calories_per_serving", "ingredients_used", "other_ingredients", "allergens", "steps", "nutrition", "tip"]
            }
        }
    },
    "required": ["recipes"]
}

MEAL_INFERENCE_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "meal_name": {"type": "STRING"},
        "description": {"type": "STRING"},
        "ingredients": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "pantry_item_id": {"type": "STRING"},
                    "name": {"type": "STRING"},
                    "estimated_quantity": {"type": "NUMBER"},
                    "unit": {
                        "type": "STRING",
                        "enum": ["kg", "g", "L", "ml", "pcs", "pack", "bottle", "box", "dozen", "bunch", "packet"]
                    },
                    "confidence": {
                        "type": "STRING",
                        "enum": ["High", "Medium", "Low"]
                    }
                },
                "required": ["name", "estimated_quantity", "unit", "confidence"]
            }
        }
    },
    "required": ["meal_name", "description", "ingredients"]
}
