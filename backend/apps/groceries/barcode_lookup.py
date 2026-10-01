import re
import logging
import requests
from django.conf import settings
from .models import GroceryItem

logger = logging.getLogger(__name__)

# Standard categories recognized across FreshTrack
VALID_CATEGORIES = [
    'Vegetables', 'Fruits', 'Dairy', 'Bakery', 'Meat',
    'Grains', 'Snacks', 'Beverages', 'Spices', 'Other'
]

# Default storage zone mapping by category
CATEGORY_STORAGE_ZONE_MAP = {
    'Dairy': GroceryItem.StorageZones.FRIDGE,
    'Meat': GroceryItem.StorageZones.FRIDGE,
    'Vegetables': GroceryItem.StorageZones.FRIDGE,
    'Fruits': GroceryItem.StorageZones.COUNTER,
    'Beverages': GroceryItem.StorageZones.FRIDGE,
    'Bakery': GroceryItem.StorageZones.COUNTER,
    'Spices': GroceryItem.StorageZones.SPICE,
    'Grains': GroceryItem.StorageZones.PANTRY,
    'Snacks': GroceryItem.StorageZones.PANTRY,
    'Other': GroceryItem.StorageZones.PANTRY,
}


def map_category_from_text(categories_text: str) -> str:
    """
    Best-effort mapping from Open Food Facts categories text to FreshTrack category enum.
    """
    if not categories_text or not isinstance(categories_text, str):
        return 'Other'

    text = categories_text.lower()

    # Match in priority order
    if any(k in text for k in ['fruit', 'apple', 'banana', 'berry', 'citrus', 'orange', 'grape', 'mango']):
        return 'Fruits'
    if any(k in text for k in ['vegetable', 'salad', 'tomato', 'potato', 'onion', 'legume', 'greens', 'herb']):
        return 'Vegetables'
    if any(k in text for k in ['dairy', 'milk', 'cheese', 'yogurt', 'butter', 'cream', 'curd', 'paneer']):
        return 'Dairy'
    if any(k in text for k in ['bakery', 'bread', 'pastry', 'biscuit', 'cake', 'cookie', 'croissant', 'toast', 'bake']):
        return 'Bakery'
    if any(k in text for k in ['meat', 'beef', 'chicken', 'pork', 'poultry', 'fish', 'seafood', 'ham', 'sausage', 'mutton', 'lamb', 'egg']):
        return 'Meat'
    if any(k in text for k in ['beverage', 'drink', 'juice', 'soda', 'water', 'tea', 'coffee', 'syrup']):
        return 'Beverages'
    if any(k in text for k in ['snack', 'chip', 'chocolate', 'candy', 'sweet', 'crisp', 'popcorn', 'cracker', 'confectionery']):
        return 'Snacks'
    if any(k in text for k in ['grain', 'cereal', 'pasta', 'rice', 'flour', 'noodle', 'oat', 'wheat', 'lentil', 'pulse']):
        return 'Grains'
    if any(k in text for k in ['spice', 'seasoning', 'sauce', 'condiment', 'salt', 'pepper', 'curry', 'masala', 'dressing']):
        return 'Spices'

    return 'Other'


def parse_unit_from_quantity(quantity_str: str) -> str:
    """
    Extracts a supported FreshTrack unit from Open Food Facts quantity string.
    Supported units: 'kg', 'g', 'L', 'ml', 'pcs', 'pack', 'bottle', 'box', 'dozen'
    """
    if not quantity_str or not isinstance(quantity_str, str):
        return GroceryItem.Units.PCS

    q = quantity_str.strip().lower()

    # Search units in priority order
    if re.search(r'\b(kg|kilogram|kilograms|kgs)\b', q):
        return GroceryItem.Units.KG
    if re.search(r'\b(ml|milliliter|millilitre|milliliters|millilitres)\b', q):
        return GroceryItem.Units.ML
    if re.search(r'\b(g|gram|grams|gm|gms)\b', q):
        return GroceryItem.Units.G
    if re.search(r'\b(l|liter|litre|liters|litres)\b', q):
        return GroceryItem.Units.L
    if re.search(r'\b(bottle|bottles|btl)\b', q):
        return GroceryItem.Units.BOTTLE
    if re.search(r'\b(box|boxes)\b', q):
        return GroceryItem.Units.BOX
    if re.search(r'\b(dozen|dozens)\b', q):
        return GroceryItem.Units.DOZEN
    if re.search(r'\b(pack|packet|package|pkg|pkgs|packets|packs)\b', q):
        return GroceryItem.Units.PACK
    if re.search(r'\b(pc|pcs|piece|pieces)\b', q):
        return GroceryItem.Units.PCS

    return GroceryItem.Units.PCS


def parse_calories(nutriments: dict):
    """
    Extracts calories per 100g as a rounded int or None.
    """
    if not nutriments or not isinstance(nutriments, dict):
        return None

    val = nutriments.get('energy-kcal_100g')
    if val is None:
        val = nutriments.get('energy-kcal')
    if val is None:
        val = nutriments.get('energy-kcal_value')

    if val is not None:
        try:
            num = float(val)
            if num >= 0:
                return int(round(num))
        except (ValueError, TypeError):
            return None
    return None


def clean_allergens(allergens_tags) -> list:
    """
    Cleans Open Food Facts allergen tags by stripping language prefixes and formatting.
    """
    if not allergens_tags:
        return []

    if isinstance(allergens_tags, str):
        raw_list = [t.strip() for t in allergens_tags.split(',') if t.strip()]
    elif isinstance(allergens_tags, list):
        raw_list = allergens_tags
    else:
        return []

    cleaned = []
    for tag in raw_list:
        if not isinstance(tag, str):
            continue
        # Strip language prefix e.g. 'en:milk' -> 'milk'
        name = re.sub(r'^[a-z]{2}:', '', tag.strip())
        name = name.replace('-', ' ').strip()
        if name and name not in cleaned:
            cleaned.append(name)

    return cleaned


def lookup_open_food_facts(barcode: str):
    """
    Performs HTTP lookup against Open Food Facts API v2.
    Returns normalized product dictionary on success or None if not found/error.
    """
    sanitized_barcode = re.sub(r'[^\d]', '', str(barcode).strip())[:18]
    if not re.match(r'^\d{6,18}$', sanitized_barcode):
        logger.warning("Open Food Facts lookup received invalid barcode: %s", sanitized_barcode)
        return None

    base_url = getattr(settings, 'OPEN_FOOD_FACTS_BASE_URL', 'https://world.openfoodfacts.org').rstrip('/')
    url = f"{base_url}/api/v2/product/{sanitized_barcode}.json"
    params = {
        'fields': 'product_name,brands,categories,quantity,image_url,nutriments,allergens_tags'
    }
    headers = {
        'User-Agent': 'FreshTrack - Barcode Lookup Service'
    }

    try:
        response = requests.get(url, params=params, headers=headers, timeout=5)
        if response.status_code != 200:
            logger.warning("Open Food Facts returned status code %s for barcode %s", response.status_code, sanitized_barcode)
            return None

        data = response.json()
        if data.get('status') != 1 or not data.get('product'):
            return None

        product = data.get('product', {})
        product_name = (product.get('product_name') or '').strip()
        name = product_name if product_name else sanitized_barcode
        brand = (product.get('brands') or '').strip()
        category = map_category_from_text(product.get('categories') or '')
        storage_zone = CATEGORY_STORAGE_ZONE_MAP.get(category, GroceryItem.StorageZones.PANTRY)
        unit = parse_unit_from_quantity(product.get('quantity') or '')
        calories_per_100g = parse_calories(product.get('nutriments') or {})
        allergens = clean_allergens(product.get('allergens_tags') or [])

        return {
            "barcode": sanitized_barcode,
            "name": name,
            "brand": brand,
            "category": category,
            "unit": unit,
            "calories_per_100g": calories_per_100g,
            "allergens": allergens,
            "storage_zone": storage_zone,
            "source": "open_food_facts",
            "found": True,
        }

    except Exception as e:
        logger.warning("Open Food Facts lookup failed for barcode %s: %s", sanitized_barcode, str(e))
        return None
