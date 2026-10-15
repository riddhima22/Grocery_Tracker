/// Centralized Unit Classification & Conversion Service for FreshTrack.
/// Shared by barcode/API scanning, camera AI/ML detection, manual adding, and smart grocery lists.
class UnitClassificationResult {
  final double quantity;
  final String unit;
  final String unitCategory; // 'weight', 'volume', 'count', 'package'
  final String packageType; // 'packet', 'bottle', 'box', 'jar', 'can', 'pouch'
  final double? netContentValue;
  final String netContentUnit;
  final int? packageCount;
  final String unitConfidence; // 'High', 'Medium', 'Low', 'uncertain'
  final bool isUncertain;

  const UnitClassificationResult({
    required this.quantity,
    required this.unit,
    required this.unitCategory,
    this.packageType = '',
    this.netContentValue,
    this.netContentUnit = '',
    this.packageCount,
    this.unitConfidence = 'High',
    this.isUncertain = false,
  });

  /// Formatted display string e.g.:
  /// "Potato — 1 kg"
  /// "Onion — 500 g"
  /// "Dal — 250 g"
  /// "Chips — 1 packet (50 g)"
  /// "Cooking oil — 1 bottle (1 L)"
  /// "Eggs — 6 pcs"
  String get displayQuantityText {
    final qtyStr = quantity % 1 == 0 ? quantity.toInt().toString() : quantity.toString();
    if (packageType.isNotEmpty && netContentValue != null && netContentUnit.isNotEmpty) {
      final netValStr = netContentValue! % 1 == 0 ? netContentValue!.toInt().toString() : netContentValue!.toString();
      return '$qtyStr $unit ($netValStr $netContentUnit)';
    }
    return '$qtyStr $unit';
  }

  UnitClassificationResult copyWith({
    double? quantity,
    String? unit,
    String? unitCategory,
    String? packageType,
    double? netContentValue,
    String? netContentUnit,
    int? packageCount,
    String? unitConfidence,
    bool? isUncertain,
  }) {
    return UnitClassificationResult(
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      unitCategory: unitCategory ?? this.unitCategory,
      packageType: packageType ?? this.packageType,
      netContentValue: netContentValue ?? this.netContentValue,
      netContentUnit: netContentUnit ?? this.netContentUnit,
      packageCount: packageCount ?? this.packageCount,
      unitConfidence: unitConfidence ?? this.unitConfidence,
      isUncertain: isUncertain ?? this.isUncertain,
    );
  }

  /// Formatted display string e.g.:
  /// "Potato — 1 kg"
  /// "Onion — 500 g"
  /// "Dal — 250 g"
  /// "Chips — 1 packet (50 g)"
  /// "Cooking oil — 1 bottle (1 L)"
  /// "Eggs — 6 pcs"
  String formatDisplay(String productName) {
    return '$productName — $displayQuantityText';
  }
}

class UnitClassificationService {
  static const String categoryWeight = 'weight';
  static const String categoryVolume = 'volume';
  static const String categoryCount = 'count';
  static const String categoryPackage = 'package';

  static const List<String> allUnits = [
    'kg', 'g', 'L', 'ml', 'pcs', 'dozen', 'packet', 'pack', 'bottle', 'box', 'jar', 'pouch', 'can'
  ];

  static const Map<String, String> unitCategories = {
    'kg': categoryWeight,
    'g': categoryWeight,
    'L': categoryVolume,
    'ml': categoryVolume,
    'pcs': categoryCount,
    'dozen': categoryCount,
    'packet': categoryPackage,
    'pack': categoryPackage,
    'bottle': categoryPackage,
    'box': categoryPackage,
    'jar': categoryPackage,
    'pouch': categoryPackage,
    'can': categoryPackage,
  };

  /// Returns units that can be converted to/from the given unit.
  static List<String> getCompatibleUnits(String unit) {
    final u = normalizeUnit(unit);
    final cat = unitCategories[u] ?? categoryCount;
    switch (cat) {
      case categoryWeight:
        return ['kg', 'g'];
      case categoryVolume:
        return ['L', 'ml'];
      case categoryCount:
        return ['pcs', 'dozen'];
      case categoryPackage:
        return ['packet', 'bottle', 'box', 'jar', 'pouch', 'can', 'pack'];
      default:
        return [unit];
    }
  }

  /// Normalizes unit strings (e.g. 'l' -> 'L', 'grams' -> 'g')
  static String normalizeUnit(String unit) {
    final lower = unit.trim().toLowerCase();
    if (lower == 'l' || lower == 'liter' || lower == 'litre' || lower == 'liters' || lower == 'litres') {
      return 'L';
    }
    if (lower == 'ml' || lower == 'milliliter' || lower == 'millilitre') {
      return 'ml';
    }
    if (lower == 'kg' || lower == 'kilogram' || lower == 'kilograms' || lower == 'kgs') {
      return 'kg';
    }
    if (lower == 'g' || lower == 'gram' || lower == 'grams' || lower == 'gm' || lower == 'gms') {
      return 'g';
    }
    if (lower == 'pc' || lower == 'pcs' || lower == 'piece' || lower == 'pieces') {
      return 'pcs';
    }
    if (lower == 'pack' || lower == 'packet' || lower == 'packets' || lower == 'pkt') {
      return 'packet';
    }
    if (lower == 'bottle' || lower == 'bottles' || lower == 'btl') {
      return 'bottle';
    }
    if (lower == 'box' || lower == 'boxes') {
      return 'box';
    }
    if (lower == 'jar' || lower == 'jars') {
      return 'jar';
    }
    if (lower == 'pouch' || lower == 'pouches') {
      return 'pouch';
    }
    if (lower == 'can' || lower == 'cans' || lower == 'tin') {
      return 'can';
    }
    if (lower == 'dozen' || lower == 'dozens') {
      return 'dozen';
    }
    return unit.trim();
  }

  /// Checks whether two units can be mathematically converted between each other.
  static bool areUnitsCompatible(String fromUnit, String toUnit) {
    final f = normalizeUnit(fromUnit);
    final t = normalizeUnit(toUnit);
    if (f == t) return true;
    final catF = unitCategories[f];
    final catT = unitCategories[t];
    if (catF == null || catT == null) return false;
    // Disallow cross-category conversion (e.g. weight to volume or count)
    return catF == catT;
  }

  /// Converts quantity between compatible units.
  /// Returns null if units are incompatible.
  static double? convertQuantity(double quantity, String fromUnit, String toUnit) {
    final f = normalizeUnit(fromUnit);
    final t = normalizeUnit(toUnit);
    if (f == t) return quantity;

    // Weight conversions: kg <-> g
    if (f == 'kg' && t == 'g') return double.parse((quantity * 1000).toStringAsFixed(3));
    if (f == 'g' && t == 'kg') return double.parse((quantity / 1000).toStringAsFixed(3));

    // Volume conversions: L <-> ml
    if (f == 'L' && t == 'ml') return double.parse((quantity * 1000).toStringAsFixed(3));
    if (f == 'ml' && t == 'L') return double.parse((quantity / 1000).toStringAsFixed(3));

    // Count conversions: dozen <-> pcs
    if (f == 'dozen' && t == 'pcs') return double.parse((quantity * 12).toStringAsFixed(3));
    if (f == 'pcs' && t == 'dozen') return double.parse((quantity / 12).toStringAsFixed(3));

    // Packages conversion preserves count if converting between package types
    if (unitCategories[f] == categoryPackage && unitCategories[t] == categoryPackage) {
      return quantity;
    }

    return null;
  }

  /// Format quantity with package details
  static String formatQuantityWithPackage({
    required double quantity,
    required String unit,
    String? packageType,
    double? netContentValue,
    String? netContentUnit,
  }) {
    final qtyStr = quantity % 1 == 0 ? quantity.toInt().toString() : quantity.toString();
    final pType = (packageType != null && packageType.isNotEmpty) ? packageType : unit;
    if (netContentValue != null && netContentUnit != null && netContentUnit.isNotEmpty) {
      final netStr = netContentValue % 1 == 0 ? netContentValue.toInt().toString() : netContentValue.toString();
      return '$qtyStr $pType ($netStr $netContentUnit)';
    }
    return '$qtyStr $unit';
  }

  /// Primary centralized classification method.
  /// Follows strict priority order:
  /// 1. Explicit product metadata / package size
  /// 2. Verified net weight/volume from product information
  /// 3. Product category and product-name classification
  /// 4. AI/ML prediction when appropriate
  /// 5. Safe fallback asking user confirmation
  static UnitClassificationResult classifyProduct({
    required String productName,
    String category = 'Other',
    String? explicitQuantityStr,
    String? aiPredictedUnit,
    String aiConfidence = 'High',
    String source = 'barcode',
  }) {
    final res = _classifyProductInternal(
      productName: productName,
      category: category,
      explicitQuantityStr: explicitQuantityStr,
      aiPredictedUnit: aiPredictedUnit,
      aiConfidence: aiConfidence,
      source: source,
    );
    if (aiConfidence.toLowerCase() == 'low') {
      return res.copyWith(unitConfidence: 'Low', isUncertain: true);
    }
    return res;
  }

  static UnitClassificationResult _classifyProductInternal({
    required String productName,
    String category = 'Other',
    String? explicitQuantityStr,
    String? aiPredictedUnit,
    String aiConfidence = 'High',
    String source = 'barcode',
  }) {
    final nameClean = productName.trim();
    final nameLower = nameClean.toLowerCase();
    final catLower = category.trim().toLowerCase();

    final packageType = _detectPackageType(nameClean) ?? _detectPackageType(explicitQuantityStr ?? '');
    final parsedMeta = _parseQuantityString(explicitQuantityStr) ?? _parseQuantityString(nameClean);

    // Priority 1 & 2: Explicit metadata and package size
    if (parsedMeta != null) {
      final netVal = parsedMeta['netContentValue'] as double?;
      final netU = parsedMeta['netContentUnit'] as String? ?? '';
      final packCount = parsedMeta['packageCount'] as int? ?? 1;

      // Packaged snacks
      if (_isSnack(nameLower, catLower)) {
        final pType = packageType ?? 'packet';
        return UnitClassificationResult(
          quantity: packCount.toDouble(),
          unit: pType,
          unitCategory: categoryPackage,
          packageType: pType,
          netContentValue: netVal,
          netContentUnit: netU,
          packageCount: packCount,
          unitConfidence: 'High',
        );
      }

      // Liquids and oils
      if (_isLiquid(nameLower, catLower)) {
        final pType = packageType ?? (nameLower.contains('can') ? 'can' : 'bottle');
        return UnitClassificationResult(
          quantity: packCount.toDouble(),
          unit: pType,
          unitCategory: categoryPackage,
          packageType: pType,
          netContentValue: netVal,
          netContentUnit: netU,
          packageCount: packCount,
          unitConfidence: 'High',
        );
      }

      // Packaged produce or grains
      if (netVal != null && netU.isNotEmpty) {
        if (packageType != null) {
          return UnitClassificationResult(
            quantity: packCount.toDouble(),
            unit: packageType,
            unitCategory: categoryPackage,
            packageType: packageType,
            netContentValue: netVal,
            netContentUnit: netU,
            packageCount: packCount,
            unitConfidence: 'High',
          );
        }
        return UnitClassificationResult(
          quantity: netVal,
          unit: netU,
          unitCategory: unitCategories[netU] ?? categoryCount,
          packageType: '',
          netContentValue: netVal,
          netContentUnit: netU,
          packageCount: 1,
          unitConfidence: 'High',
        );
      }
    }

    // Priority 3: Product Classification Rules

    // Eggs (can be placed under Dairy, Breakfast, Produce, or Other)
    if (nameLower.contains('egg')) {
      double eggCount = 6.0;
      final numMatch = RegExp(r'\b(\d+)\s*(eggs|egg|pcs|pc)\b').firstMatch(nameLower);
      if (numMatch != null) {
        eggCount = double.tryParse(numMatch.group(1)!) ?? 6.0;
      }
      return UnitClassificationResult(
        quantity: eggCount,
        unit: 'pcs',
        unitCategory: categoryCount,
        packageCount: eggCount.toInt(),
        unitConfidence: 'High',
      );
    }

    // A. Fruits and Vegetables
    if (catLower == 'vegetables' || catLower == 'fruits' || catLower == 'produce' || _isProduce(nameLower)) {
      // Countable produce (coconut, watermelon, pumpkin, pineapple, lemon, cabbage, etc.)
      if (_isCountableProduce(nameLower)) {
        return const UnitClassificationResult(
          quantity: 1.0,
          unit: 'pcs',
          unitCategory: categoryCount,
          packageCount: 1,
          unitConfidence: 'High',
        );
      }

      // Smaller produce (spinach, herbs, ginger, garlic, berries) -> grams
      if (_isSmallWeightProduce(nameLower)) {
        return const UnitClassificationResult(
          quantity: 250.0,
          unit: 'g',
          unitCategory: categoryWeight,
          netContentValue: 250.0,
          netContentUnit: 'g',
          packageCount: 1,
          unitConfidence: 'High',
        );
      }

      // Bulk loose produce (potato -> 1 kg, onion -> 500 g, etc.)
      if (nameLower.contains('potato')) {
        return const UnitClassificationResult(
          quantity: 1.0,
          unit: 'kg',
          unitCategory: categoryWeight,
          netContentValue: 1.0,
          netContentUnit: 'kg',
          unitConfidence: 'High',
        );
      }
      if (nameLower.contains('onion') || nameLower.contains('tomato') || nameLower.contains('carrot')) {
        return const UnitClassificationResult(
          quantity: 500.0,
          unit: 'g',
          unitCategory: categoryWeight,
          netContentValue: 500.0,
          netContentUnit: 'g',
          unitConfidence: 'High',
        );
      }

      // Default loose produce is 1 kg
      return const UnitClassificationResult(
        quantity: 1.0,
        unit: 'kg',
        unitCategory: categoryWeight,
        netContentValue: 1.0,
        netContentUnit: 'kg',
        unitConfidence: 'High',
      );
    }

    // B. Pulses, Grains, Flour & Loose Spices
    if (catLower == 'grains' || catLower == 'spices' || _isGrainOrSpice(nameLower)) {
      if (nameLower.contains('dal') || nameLower.contains('lentil')) {
        return UnitClassificationResult(
          quantity: 250.0,
          unit: 'g',
          unitCategory: categoryWeight,
          packageType: packageType ?? '',
          netContentValue: 250.0,
          netContentUnit: 'g',
          unitConfidence: 'High',
        );
      }
      if (nameLower.contains('rice') || nameLower.contains('wheat') || nameLower.contains('flour') || nameLower.contains('atta')) {
        return UnitClassificationResult(
          quantity: 1.0,
          unit: 'kg',
          unitCategory: categoryWeight,
          packageType: packageType ?? '',
          netContentValue: 1.0,
          netContentUnit: 'kg',
          unitConfidence: 'High',
        );
      }
      if (catLower == 'spices' || nameLower.contains('powder') || nameLower.contains('masala') || nameLower.contains('cumin') || nameLower.contains('turmeric')) {
        return UnitClassificationResult(
          quantity: 100.0,
          unit: 'g',
          unitCategory: categoryWeight,
          packageType: packageType ?? '',
          netContentValue: 100.0,
          netContentUnit: 'g',
          unitConfidence: 'High',
        );
      }
      return UnitClassificationResult(
        quantity: 1.0,
        unit: 'kg',
        unitCategory: categoryWeight,
        packageType: packageType ?? '',
        netContentValue: 1.0,
        netContentUnit: 'kg',
        unitConfidence: 'High',
      );
    }

    // C. Packaged Snacks & Countable Grocery Items
    if (catLower == 'snacks' || _isSnack(nameLower, catLower)) {
      final pType = packageType ?? 'packet';
      double qty = 1.0;
      final qtyMatch = RegExp(r'\b(\d+)\s*(packet|packets|pack|packs|bars|bar|box|boxes)\b').firstMatch(nameLower);
      if (qtyMatch != null) {
        qty = double.tryParse(qtyMatch.group(1)!) ?? 1.0;
      }
      final weightMatch = RegExp(r'(\d+)\s*(g|gm|gms|kg)\b').firstMatch(nameLower);
      final netVal = weightMatch != null ? double.tryParse(weightMatch.group(1)!) : null;
      final netU = weightMatch != null ? 'g' : '';

      return UnitClassificationResult(
        quantity: qty,
        unit: pType,
        unitCategory: categoryPackage,
        packageType: pType,
        netContentValue: netVal,
        netContentUnit: netU,
        packageCount: qty.toInt(),
        unitConfidence: 'High',
      );
    }

    // D. Oils, Milk & Liquids
    if (catLower == 'beverages' || catLower == 'beverage' || _isLiquid(nameLower, catLower)) {
      final pType = packageType ?? 'bottle';
      double volVal = 1.0;
      String volUnit = 'L';
      final volMatch = RegExp(r'(\d+)\s*(l|litre|liter|ml)\b').firstMatch(nameLower);
      if (volMatch != null) {
        volVal = double.tryParse(volMatch.group(1)!) ?? 1.0;
        volUnit = volMatch.group(2)!.toLowerCase().startsWith('l') ? 'L' : 'ml';
      }
      return UnitClassificationResult(
        quantity: 1.0,
        unit: pType,
        unitCategory: categoryPackage,
        packageType: pType,
        netContentValue: volVal,
        netContentUnit: volUnit,
        packageCount: 1,
        unitConfidence: 'High',
      );
    }

    // E. Other Configurable Categories (Bakery, Dairy, etc.)
    if (catLower == 'bakery' || nameLower.contains('bread') || nameLower.contains('bun') || nameLower.contains('cake')) {
      final pType = nameLower.contains('bread') ? 'loaf' : (packageType ?? 'packet');
      return UnitClassificationResult(
        quantity: 1.0,
        unit: pType,
        unitCategory: categoryPackage,
        packageType: pType,
        unitConfidence: 'High',
      );
    }

    if (catLower == 'dairy') {
      if (nameLower.contains('milk')) {
        final pType = packageType ?? 'bottle';
        return UnitClassificationResult(
          quantity: 1.0,
          unit: pType,
          unitCategory: categoryPackage,
          packageType: pType,
          netContentValue: 1.0,
          netContentUnit: 'L',
          unitConfidence: 'High',
        );
      }
      return UnitClassificationResult(
        quantity: 200.0,
        unit: 'g',
        unitCategory: categoryWeight,
        packageType: packageType ?? 'packet',
        netContentValue: 200.0,
        netContentUnit: 'g',
        unitConfidence: 'High',
      );
    }

    // Priority 4: AI Prediction fallback (if not generic pcs)
    if (aiPredictedUnit != null && aiPredictedUnit.isNotEmpty) {
      final normAI = normalizeUnit(aiPredictedUnit);
      if (normAI != 'pcs' && allUnits.contains(normAI)) {
        return UnitClassificationResult(
          quantity: 1.0,
          unit: normAI,
          unitCategory: unitCategories[normAI] ?? categoryCount,
          packageType: packageType ?? '',
          unitConfidence: aiConfidence,
          isUncertain: aiConfidence.toLowerCase() == 'low',
        );
      }
    }

    // Priority 5: Safe Fallback with uncertain flag
    return UnitClassificationResult(
      quantity: 1.0,
      unit: 'pcs',
      unitCategory: categoryCount,
      packageType: packageType ?? '',
      unitConfidence: 'uncertain',
      isUncertain: true,
    );
  }

  /// Parses raw net weight/volume strings (e.g. '500 g', '1.5 L')
  static Map<String, dynamic>? parseNetContentString(String? text) => _parseQuantityString(text);

  /// Parses raw net weight/volume strings
  static Map<String, dynamic>? parseQuantityString(String? text) => _parseQuantityString(text);

  // --- Helpers ---

  static String? _detectPackageType(String text) {
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (RegExp(r'\b(bottle|bottles|btl)\b').hasMatch(lower)) return 'bottle';
    if (RegExp(r'\b(packet|packets|pack|packs|pkt|bag|pouch)\b').hasMatch(lower)) return 'packet';
    if (RegExp(r'\b(box|boxes|carton)\b').hasMatch(lower)) return 'box';
    if (RegExp(r'\b(jar|jars|pot)\b').hasMatch(lower)) return 'jar';
    if (RegExp(r'\b(can|cans|tin)\b').hasMatch(lower)) return 'can';
    return null;
  }

  static Map<String, dynamic>? _parseQuantityString(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final raw = text.trim();

    // Multi-pack: "6 x 330 ml"
    final multi = RegExp(r'(\d+)\s*[xX*]\s*([0-9.]+)\s*(kg|g|gm|gms|l|litre|liter|ml)\b', caseSensitive: false).firstMatch(raw);
    if (multi != null) {
      final count = int.tryParse(multi.group(1)!) ?? 1;
      final val = double.tryParse(multi.group(2)!) ?? 1.0;
      final u = normalizeUnit(multi.group(3)!);
      return {
        'packageCount': count,
        'netContentValue': val,
        'netContentUnit': u,
      };
    }

    // Single quantity: "50 g", "1.5 L", "500ml"
    final single = RegExp(r'([0-9.]+)\s*(kg|kilogram|g|gram|gm|gms|l|litre|liter|ml|pcs|piece)\b', caseSensitive: false).firstMatch(raw);
    if (single != null) {
      final val = double.tryParse(single.group(1)!) ?? 1.0;
      final u = normalizeUnit(single.group(2)!);
      return {
        'netContentValue': val,
        'netContentUnit': u,
      };
    }

    return null;
  }

  static bool _isProduce(String name) {
    return [
      'potato', 'onion', 'tomato', 'carrot', 'spinach', 'apple', 'banana',
      'cabbage', 'ginger', 'garlic', 'chilli', 'cucumber', 'lemon',
      'orange', 'mango', 'grape', 'beetroot', 'cauliflower', 'broccoli'
    ].any((k) => name.contains(k));
  }

  static bool _isCountableProduce(String name) {
    return [
      'coconut', 'watermelon', 'pineapple', 'pumpkin', 'cabbage',
      'cauliflower', 'lemon', 'lime', 'avocado', 'melon', 'papaya',
      'lettuce', 'cucumber'
    ].any((k) => name.contains(k));
  }

  static bool _isSmallWeightProduce(String name) {
    return [
      'spinach', 'coriander', 'cilantro', 'mint', 'chilli', 'chili',
      'ginger', 'garlic', 'berry', 'berries', 'strawberry', 'curry leaves'
    ].any((k) => name.contains(k));
  }

  static bool _isGrainOrSpice(String name) {
    return [
      'dal', 'lentil', 'rice', 'wheat', 'flour', 'atta', 'chickpea', 'rajma',
      'cumin', 'turmeric', 'coriander powder', 'chilli powder', 'salt', 'pepper', 'masala'
    ].any((k) => name.contains(k));
  }

  static bool _isSnack(String name, String cat) {
    if (cat == 'snacks') return true;
    return [
      'chip', 'chips', 'biscuit', 'biscuits', 'cookie', 'cookies',
      'chocolate', 'chocolates', 'noodle', 'noodles', 'maggi', 'cracker',
      'popcorn', 'wafer', 'wafers', 'candy', 'snack'
    ].any((k) => name.contains(k));
  }

  static bool _isLiquid(String name, String cat) {
    if (cat == 'beverages' || cat == 'beverage') return true;
    return [
      'oil', 'cooking oil', 'olive oil', 'sunflower oil', 'mustard oil',
      'milk', 'juice', 'water', 'vinegar', 'syrup', 'soda', 'coke', 'pepsi',
      'sprite', 'drink', 'beverage', 'sauce'
    ].any((k) => name.contains(k));
  }
}
