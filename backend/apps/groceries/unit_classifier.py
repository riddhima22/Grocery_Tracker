"""
Centralized Unit Classification and Conversion Service for FreshTrack.
Shared across barcode/API scanning, camera AI/ML detection, and manual grocery operations.
"""
import re
from decimal import Decimal
from typing import Any


class UnitCategory:
    WEIGHT = 'weight'
    VOLUME = 'volume'
    COUNT = 'count'
    PACKAGE = 'package'


# Allowed canonical units
CANONICAL_UNITS = {
    'kg': UnitCategory.WEIGHT,
    'g': UnitCategory.WEIGHT,
    'L': UnitCategory.VOLUME,
    'ml': UnitCategory.VOLUME,
    'pcs': UnitCategory.COUNT,
    'dozen': UnitCategory.COUNT,
    'pack': UnitCategory.PACKAGE,
    'packet': UnitCategory.PACKAGE,
    'bottle': UnitCategory.PACKAGE,
    'box': UnitCategory.PACKAGE,
    'jar': UnitCategory.PACKAGE,
    'pouch': UnitCategory.PACKAGE,
    'can': UnitCategory.PACKAGE,
}

# Unit conversion factors within compatible categories
UNIT_CONVERSIONS = {
    ('kg', 'g'): Decimal(1000),
    ('g', 'kg'): Decimal('0.001'),
    ('L', 'ml'): Decimal(1000),
    ('ml', 'L'): Decimal('0.001'),
    ('l', 'ml'): Decimal(1000),
    ('ml', 'l'): Decimal('0.001'),
    ('dozen', 'pcs'): Decimal(12),
    ('pcs', 'dozen'): Decimal('0.083333'),
}

# Products that are sold by count rather than weight even in produce
COUNT_PRODUCE_KEYWORDS = [
    'coconut', 'watermelon', 'pineapple', 'pumpkin', 'cabbage',
    'cauliflower', 'lemon', 'lime', 'avocado', 'melon', 'papaya',
    'lettuce', 'cucumber'
]

# Produce with smaller default weights (in grams)
SMALL_WEIGHT_PRODUCE_KEYWORDS = [
    'spinach', 'coriander', 'cilantro', 'mint', 'chilli', 'chili',
    'ginger', 'garlic', 'berry', 'berries', 'strawberry', 'blueberry',
    'mushroom', 'green chilli', 'curry leaves'
]

# Bulk produce default weights (in kg or g)
PRODUCE_DEFAULT_WEIGHTS = {
    'potato': (1.0, 'kg'),
    'potatoes': (1.0, 'kg'),
    'onion': (500.0, 'g'),
    'onions': (500.0, 'g'),
    'tomato': (500.0, 'g'),
    'tomatoes': (500.0, 'g'),
    'apple': (1.0, 'kg'),
    'apples': (1.0, 'kg'),
    'banana': (1.0, 'kg'),
    'bananas': (1.0, 'kg'),
    'carrot': (500.0, 'g'),
    'carrots': (500.0, 'g'),
}

# Pulses & Grains defaults
GRAIN_DEFAULTS = {
    'dal': (250.0, 'g'),
    'lentil': (250.0, 'g'),
    'lentils': (250.0, 'g'),
    'rice': (1.0, 'kg'),
    'wheat': (1.0, 'kg'),
    'flour': (1.0, 'kg'),
    'atta': (1.0, 'kg'),
    'chickpeas': (500.0, 'g'),
    'rajma': (500.0, 'g'),
}

# Packaged snacks keywords
SNACK_KEYWORDS = [
    'chip', 'chips', 'biscuit', 'biscuits', 'cookie', 'cookies',
    'chocolate', 'chocolates', 'noodle', 'noodles', 'maggi', 'cracker',
    'popcorn', 'wafer', 'wafers', 'candy', 'snack', 'snacks'
]

# Liquid / Oil / Milk keywords
LIQUID_KEYWORDS = [
    'oil', 'cooking oil', 'olive oil', 'sunflower oil', 'mustard oil',
    'milk', 'juice', 'water', 'vinegar', 'syrup', 'soda', 'coke', 'pepsi',
    'sprite', 'drink', 'beverage', 'sauce', 'soya sauce', 'soy sauce'
]

# Specific container hints
PACKAGE_TYPE_KEYWORDS = {
    'bottle': ['bottle', 'btl', 'flask'],
    'packet': ['packet', 'pack', 'pkt', 'pouch', 'sachet', 'bag'],
    'box': ['box', 'carton', 'case'],
    'jar': ['jar', 'pot'],
    'can': ['can', 'tin'],
}


def parse_quantity_string(quantity_str: str) -> dict[str, Any] | None:
    """
    Parses Open Food Facts quantity strings or text descriptions such as:
    - "50 g", "50g", "1 kg", "2.5kg", "500 ml", "1 L", "1.5 l", "6 x 330 ml", "1 bottle (1 L)"
    """
    if not quantity_str or not isinstance(quantity_str, str):
        return None

    raw = quantity_str.strip()
    if not raw:
        return None

    # Check for multi-pack pattern e.g. "6 x 330 ml" or "4 x 50g"
    multi_match = re.search(r'(\d+)\s*[xX*]\s*([0-9.]+)\s*(kg|g|gm|gms|l|litre|liter|litres|liters|ml|cl|oz|pcs|pc)', raw, re.IGNORECASE)
    if multi_match:
        pack_count = int(multi_match.group(1))
        content_val = float(multi_match.group(2))
        unit_raw = multi_match.group(3).lower()
        norm_unit = 'L' if unit_raw in ('l', 'litre', 'liter', 'litres', 'liters') else ('g' if unit_raw in ('g', 'gm', 'gms') else unit_raw)
        return {
            'package_count': pack_count,
            'net_content_value': content_val,
            'net_content_unit': norm_unit,
            'raw_text': raw,
        }

    # Match single quantity e.g. "50 g", "1.5 L", "500ml"
    single_match = re.search(r'([0-9.]+)\s*(kg|kilogram|kilograms|kgs|g|gram|grams|gm|gms|l|litre|liter|litres|liters|ml|milliliter|millilitre|milliliters|millilitres|pcs|pc|piece|pieces|bar|bars)\b', raw, re.IGNORECASE)
    if single_match:
        val = float(single_match.group(1))
        u_raw = single_match.group(2).lower()
        if u_raw in ('kg', 'kilogram', 'kilograms', 'kgs'):
            unit = 'kg'
            category = UnitCategory.WEIGHT
        elif u_raw in ('g', 'gram', 'grams', 'gm', 'gms'):
            unit = 'g'
            category = UnitCategory.WEIGHT
        elif u_raw in ('l', 'litre', 'liter', 'litres', 'liters'):
            unit = 'L'
            category = UnitCategory.VOLUME
        elif u_raw in ('ml', 'milliliter', 'millilitre', 'milliliters', 'millilitres'):
            unit = 'ml'
            category = UnitCategory.VOLUME
        else:
            unit = 'pcs'
            category = UnitCategory.COUNT

        return {
            'net_content_value': val,
            'net_content_unit': unit,
            'unit_category': category,
            'raw_text': raw,
        }

    return None


def detect_package_type_from_text(text: str) -> str | None:
    """Detects packaging container type from string."""
    if not text:
        return None
    lower = text.lower()
    for ptype, keywords in PACKAGE_TYPE_KEYWORDS.items():
        if any(re.search(r'\b' + re.escape(k) + r'\b', lower) for k in keywords):
            return ptype
    return None


def convert_quantity_units(quantity: Decimal, from_unit: str, to_unit: str) -> tuple[Decimal | None, bool]:
    """
    Safely converts between compatible measurement units.
    Rejects incompatible conversions (e.g. weight to volume or count).
    """
    f = (from_unit or '').strip()
    t = (to_unit or '').strip()
    f_norm = 'L' if f.lower() == 'l' else f.lower()
    t_norm = 'L' if t.lower() == 'l' else t.lower()

    if not f_norm or not t_norm or f_norm == t_norm:
        return quantity, True

    # Lookup conversion
    key = (f_norm, t_norm)
    if key in UNIT_CONVERSIONS:
        factor = UNIT_CONVERSIONS[key]
        return (quantity * factor).quantize(Decimal('0.001')), True

    # Check reverse or uppercase variations
    key_rev = (f_norm.lower(), t_norm.lower())
    if key_rev in [('l', 'ml'), ('ml', 'l')]:
        factor = Decimal(1000) if key_rev == ('l', 'ml') else Decimal('0.001')
        return (quantity * factor).quantize(Decimal('0.001')), True

    return None, False


def classify_product_unit(
    product_name: str,
    category: str = 'Other',
    explicit_quantity_str: str = '',
    ai_predicted_unit: str = '',
    ai_confidence: str = 'High',
    source: str = 'barcode'
) -> dict[str, Any]:
    res = _classify_product_unit_internal(
        product_name=product_name,
        category=category,
        explicit_quantity_str=explicit_quantity_str,
        ai_predicted_unit=ai_predicted_unit,
        ai_confidence=ai_confidence,
        source=source,
    )
    if (ai_confidence or '').lower() == 'low':
        res['is_uncertain'] = True
        res['unit_confidence'] = 'Low'
    return res


def _classify_product_unit_internal(
    product_name: str,
    category: str = 'Other',
    explicit_quantity_str: str = '',
    ai_predicted_unit: str = '',
    ai_confidence: str = 'High',
    source: str = 'barcode'
) -> dict[str, Any]:
    """
    Central classification engine following strict priority rules:
    1. Explicit product metadata / package size.
    2. Verified net weight/volume from product information.
    3. Category and product-name classification rules.
    4. AI/ML prediction when appropriate.
    5. Safe fallback with uncertain flag.

    Never defaults every scanned product to 'pcs'.
    """
    name_clean = (product_name or '').strip()
    name_lower = name_clean.lower()
    cat_lower = (category or 'Other').lower()

    package_type = detect_package_type_from_text(name_clean) or detect_package_type_from_text(explicit_quantity_str)
    parsed_meta = parse_quantity_string(explicit_quantity_str) or parse_quantity_string(name_clean)

    # 1 & 2. Metadata / Package information
    if parsed_meta:
        net_val = parsed_meta.get('net_content_value')
        net_u = parsed_meta.get('net_content_unit')
        pack_count = parsed_meta.get('package_count', 1)

        # Countable snacks or liquids in bottles/packets
        if any(k in name_lower for k in SNACK_KEYWORDS):
            p_type = package_type or 'packet'
            return {
                'quantity': float(pack_count),
                'unit': p_type,
                'unit_category': UnitCategory.PACKAGE,
                'package_type': p_type,
                'net_content_value': net_val,
                'net_content_unit': net_u,
                'package_count': pack_count,
                'unit_confidence': 'High',
                'is_uncertain': False,
            }

        if any(k in name_lower for k in LIQUID_KEYWORDS) or cat_lower in ('beverages', 'beverage'):
            p_type = package_type or ('can' if re.search(r'\b(can|cans|tin)\b', name_lower) else 'bottle')
            return {
                'quantity': float(pack_count),
                'unit': p_type,
                'unit_category': UnitCategory.PACKAGE,
                'package_type': p_type,
                'net_content_value': net_val,
                'net_content_unit': net_u,
                'package_count': pack_count,
                'unit_confidence': 'High',
                'is_uncertain': False,
            }

        # If it's a pulse, grain, or produce sold packaged
        if net_val is not None and net_u:
            if package_type:
                return {
                    'quantity': float(pack_count),
                    'unit': package_type,
                    'unit_category': UnitCategory.PACKAGE,
                    'package_type': package_type,
                    'net_content_value': net_val,
                    'net_content_unit': net_u,
                    'package_count': pack_count,
                    'unit_confidence': 'High',
                    'is_uncertain': False,
                }
            # Sold as loose weight/volume/count
            return {
                'quantity': float(net_val),
                'unit': net_u,
                'unit_category': UnitCategory.WEIGHT if net_u in ('kg', 'g') else (UnitCategory.VOLUME if net_u in ('L', 'ml') else UnitCategory.COUNT),
                'package_type': '',
                'net_content_value': net_val,
                'net_content_unit': net_u,
                'package_count': 1,
                'unit_confidence': 'High',
                'is_uncertain': False,
            }

    # 3. Product Category and Name Classification Rules

    # Eggs (can be Dairy, Produce, or Breakfast)
    if 'egg' in name_lower:
        egg_count = 6.0
        # Check if count mentioned e.g. "12 eggs", "6 eggs", "dozen eggs"
        num_match = re.search(r'\b(\d+)\s*(eggs|egg|pcs|pc)\b', name_lower)
        if num_match:
            egg_count = float(num_match.group(1))
        return {
            'quantity': egg_count,
            'unit': 'pcs',
            'unit_category': UnitCategory.COUNT,
            'package_type': '',
            'net_content_value': None,
            'net_content_unit': '',
            'package_count': int(egg_count),
            'unit_confidence': 'High',
            'is_uncertain': False,
        }

    # A. Fruits and Vegetables
    if cat_lower in ('vegetables', 'fruits', 'produce') or any(k in name_lower for k in [
        'potato', 'onion', 'tomato', 'carrot', 'spinach', 'apple', 'banana',
        'cabbage', 'ginger', 'garlic', 'chilli', 'cucumber', 'lemon'
    ]):

        # Check countable produce
        if any(re.search(r'\b' + re.escape(k) + r'\b', name_lower) for k in COUNT_PRODUCE_KEYWORDS):
            # Can be pcs or weight; default to pcs with weight alternative
            return {
                'quantity': 1.0,
                'unit': 'pcs',
                'unit_category': UnitCategory.COUNT,
                'package_type': '',
                'net_content_value': None,
                'net_content_unit': '',
                'package_count': 1,
                'unit_confidence': 'High',
                'is_uncertain': False,
            }

        # Produce with smaller default weights (g)
        if any(re.search(r'\b' + re.escape(k) + r'\b', name_lower) for k in SMALL_WEIGHT_PRODUCE_KEYWORDS):
            return {
                'quantity': 250.0,
                'unit': 'g',
                'unit_category': UnitCategory.WEIGHT,
                'package_type': '',
                'net_content_value': 250.0,
                'net_content_unit': 'g',
                'package_count': 1,
                'unit_confidence': 'High',
                'is_uncertain': False,
            }

        # Standard produce weight lookups (potato -> 1 kg, onion -> 500 g)
        for keyword, (def_qty, def_unit) in PRODUCE_DEFAULT_WEIGHTS.items():
            if re.search(r'\b' + re.escape(keyword) + r'\b', name_lower):
                return {
                    'quantity': def_qty,
                    'unit': def_unit,
                    'unit_category': UnitCategory.WEIGHT,
                    'package_type': '',
                    'net_content_value': def_qty,
                    'net_content_unit': def_unit,
                    'package_count': 1,
                    'unit_confidence': 'High',
                    'is_uncertain': False,
                }

        # General loose produce: default weight 1 kg
        return {
            'quantity': 1.0,
            'unit': 'kg',
            'unit_category': UnitCategory.WEIGHT,
            'package_type': '',
            'net_content_value': 1.0,
            'net_content_unit': 'kg',
            'package_count': 1,
            'unit_confidence': 'High',
            'is_uncertain': False,
        }

    # B. Pulses, Grains, Flour & Loose Spices
    if cat_lower in ('grains', 'spices') or any(k in name_lower for k in [
        'dal', 'lentil', 'rice', 'wheat', 'flour', 'atta', 'chickpea', 'rajma',
        'cumin', 'turmeric', 'coriander powder', 'chilli powder', 'salt', 'pepper'
    ]):
        for keyword, (def_qty, def_unit) in GRAIN_DEFAULTS.items():
            if re.search(r'\b' + re.escape(keyword) + r'\b', name_lower):
                return {
                    'quantity': def_qty,
                    'unit': def_unit,
                    'unit_category': UnitCategory.WEIGHT,
                    'package_type': package_type or '',
                    'net_content_value': def_qty,
                    'net_content_unit': def_unit,
                    'package_count': 1,
                    'unit_confidence': 'High',
                    'is_uncertain': False,
                }
        # Loose spices default to grams
        if cat_lower == 'spices' or any(k in name_lower for k in ['powder', 'masala', 'spice', 'pepper', 'salt', 'cumin']):
            return {
                'quantity': 100.0,
                'unit': 'g',
                'unit_category': UnitCategory.WEIGHT,
                'package_type': package_type or '',
                'net_content_value': 100.0,
                'net_content_unit': 'g',
                'package_count': 1,
                'unit_confidence': 'High',
                'is_uncertain': False,
            }
        # General grain
        return {
            'quantity': 1.0,
            'unit': 'kg',
            'unit_category': UnitCategory.WEIGHT,
            'package_type': package_type or '',
            'net_content_value': 1.0,
            'net_content_unit': 'kg',
            'package_count': 1,
            'unit_confidence': 'High',
            'is_uncertain': False,
        }

    # C. Packaged Snacks & Countable Grocery Items
    if cat_lower == 'snacks' or any(k in name_lower for k in SNACK_KEYWORDS):
        p_type = package_type or 'packet'
        # Check if biscuit packet count e.g. "2 biscuit packets" or "two packets"
        qty = 1.0
        qty_match = re.search(r'\b(\d+)\s*(packet|packets|pack|packs|bars|bar|box|boxes)\b', name_lower)
        if qty_match:
            qty = float(qty_match.group(1))

        # Check for net weight mention in product name e.g. "50 g chips" or "100g chocolate"
        weight_match = re.search(r'(\d+)\s*(g|gm|gms|kg)\b', name_lower)
        net_val = float(weight_match.group(1)) if weight_match else None
        net_u = 'g' if weight_match else ''

        return {
            'quantity': qty,
            'unit': p_type,
            'unit_category': UnitCategory.PACKAGE,
            'package_type': p_type,
            'net_content_value': net_val,
            'net_content_unit': net_u,
            'package_count': int(qty),
            'unit_confidence': 'High',
            'is_uncertain': False,
        }

    # D. Oils, Milk & Liquids
    if cat_lower in ('beverages', 'beverage') or any(k in name_lower for k in LIQUID_KEYWORDS):
        p_type = package_type or 'bottle'
        # Default volume: 1 L (or 1 bottle containing 1 L)
        vol_match = re.search(r'(\d+)\s*(l|litre|liter|ml)\b', name_lower)
        if vol_match:
            val = float(vol_match.group(1))
            u = 'L' if vol_match.group(2).lower() in ('l', 'litre', 'liter') else 'ml'
        else:
            val = 1.0
            u = 'L'

        return {
            'quantity': 1.0,
            'unit': p_type,
            'unit_category': UnitCategory.PACKAGE,
            'package_type': p_type,
            'net_content_value': val,
            'net_content_unit': u,
            'package_count': 1,
            'unit_confidence': 'High',
            'is_uncertain': False,
        }

    # E. Other Configurable Categories (Bakery, Cleaning, Dairy, etc.)
    if cat_lower == 'bakery' or any(k in name_lower for k in ['bread', 'loaf', 'bun', 'buns', 'toast', 'croissant']):
        unit = 'loaf' if 'bread' in name_lower else (package_type or 'packet')
        return {
            'quantity': 1.0,
            'unit': unit,
            'unit_category': UnitCategory.PACKAGE,
            'package_type': unit,
            'net_content_value': None,
            'net_content_unit': '',
            'package_count': 1,
            'unit_confidence': 'High',
            'is_uncertain': False,
        }

    if cat_lower == 'dairy' or any(k in name_lower for k in ['cheese', 'butter', 'paneer', 'yogurt', 'curd']):
        if 'milk' in name_lower:
            return {
                'quantity': 1.0,
                'unit': 'bottle' if package_type == 'bottle' else 'packet',
                'unit_category': UnitCategory.PACKAGE,
                'package_type': package_type or 'packet',
                'net_content_value': 500.0,
                'net_content_unit': 'ml',
                'package_count': 1,
                'unit_confidence': 'High',
                'is_uncertain': False,
            }
        return {
            'quantity': 200.0,
            'unit': 'g',
            'unit_category': UnitCategory.WEIGHT,
            'package_type': package_type or 'packet',
            'net_content_value': 200.0,
            'net_content_unit': 'g',
            'package_count': 1,
            'unit_confidence': 'High',
            'is_uncertain': False,
        }

    # 4. AI Prediction Fallback (if valid and not raw pcs for unverified items)
    if ai_predicted_unit and ai_predicted_unit in CANONICAL_UNITS and ai_predicted_unit != 'pcs':
        return {
            'quantity': 1.0,
            'unit': ai_predicted_unit,
            'unit_category': CANONICAL_UNITS[ai_predicted_unit],
            'package_type': package_type or '',
            'net_content_value': None,
            'net_content_unit': '',
            'package_count': 1,
            'unit_confidence': ai_confidence,
            'is_uncertain': ai_confidence.lower() == 'low',
        }

    # 5. Safe Fallback with uncertain flag
    is_uncertain = True
    return {
        'quantity': 1.0,
        'unit': 'pcs',
        'unit_category': UnitCategory.COUNT,
        'package_type': package_type or '',
        'net_content_value': None,
        'net_content_unit': '',
        'package_count': 1,
        'unit_confidence': 'uncertain',
        'is_uncertain': is_uncertain,
    }
