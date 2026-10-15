import '../../../core/utils/date_helpers.dart';
import '../../../core/services/unit_classification_service.dart';

class GroceryModel {
  final String id;
  final String name;
  final String brand;
  final String description;
  final String iconKey;
  final String category;
  final double quantity;
  final String unit;
  final String unitCategory;
  final String packageType;
  final double? netContentValue;
  final String netContentUnit;
  final int? packageCount;
  final String identificationSource;
  final String unitConfidence;

  final String storageZone;
  final DateTime? expiryDate;
  final DateTime? estimatedConsumptionDate;
  final bool isExpiryEstimated;
  final String dateType;
  final String dateSource;
  final String dateConfidence;
  final String? scanSessionId;
  final DateTime purchaseDate;
  final String _rawStatus;

  /// Dynamic client-side status derived strictly from calendar days difference.
  String get status {
    if (_rawStatus == 'consumed' || _rawStatus == 'wasted') return _rawStatus;
    final exp = effectiveExpiryDate;
    if (exp == null) return _rawStatus.isNotEmpty ? _rawStatus : 'fresh';
    final diff = DateHelpers.calendarDaysDifference(exp);
    if (diff < 0) return 'expired';
    if (diff <= 3) return 'expiring';
    return 'fresh';
  }

  final int? caloriesPer100g;
  final List<String> allergens;
  final bool aiDetected;
  final String? aiConfidence;

  // AI predictions & parameters
  final String ripeness;
  final double temperature;
  final double humidity;
  final bool isOpened;
  final int freshnessScore;
  final DateTime? predictedExpiry;
  final DateTime? recommendedConsumptionDate;
  final double confidenceScore;
  final String storageRecommendationWhy;
  final String storageRecommendationHow;
  final String storageRecommendationShelfLife;
  final String aiExplanation;

  const GroceryModel({
    required this.id,
    required this.name,
    this.brand = '',
    this.description = '',
    this.iconKey = 'grocery',
    this.category = 'Uncategorized',
    required this.quantity,
    required this.unit,
    this.unitCategory = 'count',
    this.packageType = '',
    this.netContentValue,
    this.netContentUnit = '',
    this.packageCount,
    this.identificationSource = 'manual',
    this.unitConfidence = 'High',
    required this.storageZone,
    this.expiryDate,
    this.estimatedConsumptionDate,
    this.isExpiryEstimated = false,
    this.dateType = 'unknown',
    this.dateSource = 'unknown',
    this.dateConfidence = 'Low',
    this.scanSessionId,
    required this.purchaseDate,
    String status = 'fresh',
    this.caloriesPer100g,
    this.allergens = const [],
    this.aiDetected = false,
    this.aiConfidence,
    this.ripeness = 'not_applicable',
    this.temperature = 20.0,
    this.humidity = 50.0,
    this.isOpened = false,
    this.freshnessScore = 100,
    this.predictedExpiry,
    this.recommendedConsumptionDate,
    this.confidenceScore = 1.0,
    this.storageRecommendationWhy = '',
    this.storageRecommendationHow = '',
    this.storageRecommendationShelfLife = '',
    this.aiExplanation = '',
  }) : _rawStatus = status;

  /// Semantic date helper: returns printed expiryDate if detected,
  /// otherwise returns estimated consumption or predicted shelf-life date.
  DateTime? get effectiveExpiryDate => expiryDate ?? estimatedConsumptionDate ?? predictedExpiry;

  /// Formatted quantity representation (e.g. "1 packet (50 g)", "1 bottle (1 L)", "500 g")
  String get displayQuantityText {
    final qtyStr = quantity % 1 == 0 ? quantity.toInt().toString() : quantity.toString();
    final pType = packageType.isNotEmpty ? packageType : unit;
    if (netContentValue != null && netContentUnit.isNotEmpty) {
      final netStr = netContentValue! % 1 == 0 ? netContentValue!.toInt().toString() : netContentValue!.toString();
      return '$qtyStr $pType ($netStr $netContentUnit)';
    }
    return '$qtyStr $unit';
  }

  factory GroceryModel.fromJson(Map<String, dynamic> json) {
    final DateTime? parsedExpiry =
        json['expiry_date'] != null ? DateTime.tryParse(json['expiry_date']) : null;
    final DateTime? parsedEstimated = json['estimated_consumption_date'] != null
        ? DateTime.tryParse(json['estimated_consumption_date'])
        : null;
    final bool isEstimated;
    if (json['is_expiry_estimated'] != null) {
      isEstimated = json['is_expiry_estimated'] == true;
    } else if (parsedEstimated != null) {
      isEstimated = true;
    } else {
      isEstimated = false;
    }

    final name = json['name'] ?? '';
    final category = json['category'] ?? 'Uncategorized';
    final rawUnit = json['unit'];

    // Smart unit classification fallback if unit is missing or legacy pcs default
    String resolvedUnit = rawUnit?.toString() ?? '';
    String resolvedCategory = json['unit_category']?.toString() ?? '';
    String resolvedPackageType = json['package_type']?.toString() ?? '';
    double? resolvedNetVal = double.tryParse(json['net_content_value']?.toString() ?? '');
    String resolvedNetUnit = json['net_content_unit']?.toString() ?? '';
    int? resolvedPackCount = int.tryParse(json['package_count']?.toString() ?? '');
    String resolvedUnitConf = json['unit_confidence']?.toString() ?? 'High';

    if (resolvedUnit.isEmpty || (resolvedUnit == 'pcs' && resolvedCategory.isEmpty)) {
      final classified = UnitClassificationService.classifyProduct(
        productName: name,
        category: category,
        aiPredictedUnit: rawUnit?.toString(),
        source: 'database',
      );
      resolvedUnit = classified.unit;
      resolvedCategory = classified.unitCategory;
      resolvedPackageType = classified.packageType;
      resolvedNetVal = classified.netContentValue;
      resolvedNetUnit = classified.netContentUnit;
      resolvedPackCount = classified.packageCount;
      resolvedUnitConf = classified.unitConfidence;
    }

    final rawQty = double.tryParse(json['quantity']?.toString() ?? '');
    final double finalQty = rawQty != null && rawQty > 0 ? rawQty : 1.0;

    return GroceryModel(
      id: json['id'] ?? '',
      name: name,
      brand: json['brand'] ?? '',
      description: json['description'] ?? '',
      iconKey: json['icon_key'] ?? 'grocery',
      category: category,
      quantity: finalQty,
      unit: resolvedUnit,
      unitCategory: resolvedCategory,
      packageType: resolvedPackageType,
      netContentValue: resolvedNetVal,
      netContentUnit: resolvedNetUnit,
      packageCount: resolvedPackCount,
      identificationSource: json['identification_source'] ?? 'manual',
      unitConfidence: resolvedUnitConf,
      storageZone: json['storage_zone'] ?? 'pantry',
      expiryDate: parsedExpiry,
      estimatedConsumptionDate: parsedEstimated,
      isExpiryEstimated: isEstimated,
      dateType: json['date_type'] ?? (isEstimated ? 'estimated' : 'expiry'),
      dateSource: json['date_source'] ?? (isEstimated ? 'calculated_shelf_life' : 'ocr_verified'),
      dateConfidence: json['date_confidence'] ?? 'Low',
      scanSessionId: json['scan_session']?.toString(),
      purchaseDate: json['purchase_date'] != null
          ? DateTime.parse(json['purchase_date'])
          : DateTime.now(),
      status: json['status'] ?? 'fresh',
      caloriesPer100g: json['calories_per_100g'],
      allergens: List<String>.from(json['allergens'] ?? []),
      aiDetected: json['ai_detected'] ?? false,
      aiConfidence: json['ai_confidence'],
      ripeness: json['ripeness'] ?? 'not_applicable',
      temperature: double.tryParse(json['temperature']?.toString() ?? '20.0') ?? 20.0,
      humidity: double.tryParse(json['humidity']?.toString() ?? '50.0') ?? 50.0,
      isOpened: json['is_opened'] ?? false,
      freshnessScore: json['freshness_score'] ?? 100,
      predictedExpiry: json['predicted_expiry'] != null
          ? DateTime.tryParse(json['predicted_expiry'])
          : null,
      recommendedConsumptionDate: json['recommended_consumption_date'] != null
          ? DateTime.tryParse(json['recommended_consumption_date'])
          : null,
      confidenceScore: double.tryParse(json['confidence_score']?.toString() ?? '1.0') ?? 1.0,
      storageRecommendationWhy: json['storage_recommendation_why'] ?? '',
      storageRecommendationHow: json['storage_recommendation_how'] ?? '',
      storageRecommendationShelfLife: json['storage_recommendation_shelf_life'] ?? '',
      aiExplanation: json['ai_explanation'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'brand': brand,
    'description': description,
    'icon_key': iconKey,
    'category': category,
    'quantity': quantity,
    'unit': unit,
    'unit_category': unitCategory,
    'package_type': packageType,
    'net_content_value': netContentValue,
    'net_content_unit': netContentUnit,
    'package_count': packageCount,
    'identification_source': identificationSource,
    'unit_confidence': unitConfidence,
    'storage_zone': storageZone,
    'expiry_date': expiryDate?.toIso8601String().substring(0, 10),
    'estimated_consumption_date': estimatedConsumptionDate?.toIso8601String().substring(0, 10),
    'is_expiry_estimated': isExpiryEstimated,
    'date_type': dateType,
    'date_source': dateSource,
    'purchase_date': purchaseDate.toIso8601String().substring(0, 10),
    'status': status,
    'calories_per_100g': caloriesPer100g,
    'allergens': allergens,
    'ripeness': ripeness,
    'temperature': temperature,
    'humidity': humidity,
    'is_opened': isOpened,
    'freshness_score': freshnessScore,
    'predicted_expiry': predictedExpiry?.toIso8601String().substring(0, 10),
    'recommended_consumption_date':
        recommendedConsumptionDate?.toIso8601String().substring(0, 10),
    'confidence_score': confidenceScore,
    'storage_recommendation_why': storageRecommendationWhy,
    'storage_recommendation_how': storageRecommendationHow,
    'storage_recommendation_shelf_life': storageRecommendationShelfLife,
    'ai_explanation': aiExplanation,
  };

  GroceryModel copyWith({
    String? name,
    String? brand,
    String? description,
    String? iconKey,
    String? category,
    double? quantity,
    String? unit,
    String? unitCategory,
    String? packageType,
    double? netContentValue,
    String? netContentUnit,
    int? packageCount,
    String? identificationSource,
    String? unitConfidence,
    String? storageZone,
    DateTime? expiryDate,
    DateTime? estimatedConsumptionDate,
    bool? isExpiryEstimated,
    DateTime? purchaseDate,
    String? status,
  }) {
    return GroceryModel(
      id: id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      description: description ?? this.description,
      iconKey: iconKey ?? this.iconKey,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      unitCategory: unitCategory ?? this.unitCategory,
      packageType: packageType ?? this.packageType,
      netContentValue: netContentValue ?? this.netContentValue,
      netContentUnit: netContentUnit ?? this.netContentUnit,
      packageCount: packageCount ?? this.packageCount,
      identificationSource: identificationSource ?? this.identificationSource,
      unitConfidence: unitConfidence ?? this.unitConfidence,
      storageZone: storageZone ?? this.storageZone,
      expiryDate: expiryDate ?? this.expiryDate,
      estimatedConsumptionDate: estimatedConsumptionDate ?? this.estimatedConsumptionDate,
      isExpiryEstimated: isExpiryEstimated ?? this.isExpiryEstimated,
      dateType: dateType,
      dateSource: dateSource,
      dateConfidence: dateConfidence,
      scanSessionId: scanSessionId,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      status: status ?? this.status,
      caloriesPer100g: caloriesPer100g,
      allergens: allergens,
      aiDetected: aiDetected,
      aiConfidence: aiConfidence,
      ripeness: ripeness,
      temperature: temperature,
      humidity: humidity,
      isOpened: isOpened,
      freshnessScore: freshnessScore,
      predictedExpiry: predictedExpiry,
      recommendedConsumptionDate: recommendedConsumptionDate,
      confidenceScore: confidenceScore,
      storageRecommendationWhy: storageRecommendationWhy,
      storageRecommendationHow: storageRecommendationHow,
      storageRecommendationShelfLife: storageRecommendationShelfLife,
      aiExplanation: aiExplanation,
    );
  }
}
