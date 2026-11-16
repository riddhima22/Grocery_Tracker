import '../../../core/services/unit_classification_service.dart';

class ScanCandidateModel {
  final String id;
  final String scanSession;

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
  final bool isUncertain;

  final String storageZone;

  final DateTime? expiryDate;
  final DateTime? estimatedConsumptionDate;
  final bool isExpiryEstimated;
  final String dateType;
  final String dateSource;
  final String dateConfidence;
  final String rawDateText;
  final String storageReason;
  final String shelfLifeGuidance;

  final String confidence;
  final List<String> validationWarnings;
  final bool selected;

  const ScanCandidateModel({
    required this.id,
    required this.scanSession,
    required this.name,
    required this.brand,
    required this.description,
    this.iconKey = 'grocery',
    required this.category,
    required this.quantity,
    required this.unit,
    this.unitCategory = 'count',
    this.packageType = '',
    this.netContentValue,
    this.netContentUnit = '',
    this.packageCount,
    this.identificationSource = 'camera_ai',
    this.unitConfidence = 'High',
    this.isUncertain = false,
    required this.storageZone,
    this.expiryDate,
    this.estimatedConsumptionDate,
    this.isExpiryEstimated = false,
    this.dateType = 'unknown',
    this.dateSource = 'unknown',
    this.dateConfidence = 'Low',
    this.rawDateText = '',
    this.storageReason = '',
    this.shelfLifeGuidance = '',
    required this.confidence,
    required this.validationWarnings,
    required this.selected,
  });

  /// Semantic date helper: returns printed expiryDate if detected,
  /// otherwise returns estimatedConsumptionDate.
  DateTime? get effectiveExpiryDate => expiryDate ?? estimatedConsumptionDate;

  /// Display string with package details (e.g. "Chips — 1 packet (50 g)")
  String get displayQuantityText {
    final qtyStr = quantity % 1 == 0
        ? quantity.toInt().toString()
        : quantity.toString();
    final pType = packageType.isNotEmpty ? packageType : unit;
    if (netContentValue != null && netContentUnit.isNotEmpty) {
      final netStr = netContentValue! % 1 == 0
          ? netContentValue!.toInt().toString()
          : netContentValue!.toString();
      return '$qtyStr $pType ($netStr $netContentUnit)';
    }
    return '$qtyStr $unit';
  }

  factory ScanCandidateModel.fromJson(Map<String, dynamic> json) {
    DateTime? parsedExpiry;
    if (json['expiry_date'] != null &&
        json['expiry_date'].toString().isNotEmpty) {
      parsedExpiry = DateTime.tryParse(json['expiry_date'].toString());
    }

    DateTime? parsedEstimated;
    if (json['estimated_consumption_date'] != null &&
        json['estimated_consumption_date'].toString().isNotEmpty) {
      parsedEstimated = DateTime.tryParse(
        json['estimated_consumption_date'].toString(),
      );
    }

    final bool isEstimated;
    if (json['is_expiry_estimated'] != null) {
      isEstimated = json['is_expiry_estimated'] == true;
    } else if (parsedEstimated != null) {
      isEstimated = true;
    } else {
      isEstimated = false;
    }

    final name = json['name'] ?? '';
    final category = json['category'] ?? 'Vegetables';
    final rawUnit = json['unit'];

    // Smart unit classification fallback if unit is empty or default 'pcs'
    String resolvedUnit = rawUnit?.toString() ?? '';
    String resolvedCategory = json['unit_category']?.toString() ?? '';
    String resolvedPackageType = json['package_type']?.toString() ?? '';
    double? resolvedNetVal = double.tryParse(
      json['net_content_value']?.toString() ?? '',
    );
    String resolvedNetUnit = json['net_content_unit']?.toString() ?? '';
    int? resolvedPackCount = int.tryParse(
      json['package_count']?.toString() ?? '',
    );
    String resolvedUnitConf = json['unit_confidence']?.toString() ?? 'High';
    bool resolvedUncertain =
        json['is_uncertain'] == true ||
        resolvedUnitConf.toLowerCase() == 'uncertain';

    if (resolvedUnit.isEmpty ||
        (resolvedUnit == 'pcs' && resolvedCategory.isEmpty)) {
      final classified = UnitClassificationService.classifyProduct(
        productName: name,
        category: category,
        aiPredictedUnit: rawUnit?.toString(),
        aiConfidence: json['confidence'] ?? 'High',
        source: 'camera_ai',
      );
      resolvedUnit = classified.unit;
      resolvedCategory = classified.unitCategory;
      resolvedPackageType = classified.packageType;
      resolvedNetVal = classified.netContentValue;
      resolvedNetUnit = classified.netContentUnit;
      resolvedPackCount = classified.packageCount;
      resolvedUnitConf = classified.unitConfidence;
      resolvedUncertain = classified.isUncertain;
    }

    final rawQty = double.tryParse(json['quantity']?.toString() ?? '');
    final double finalQty = rawQty != null && rawQty > 0 ? rawQty : 1.0;

    return ScanCandidateModel(
      id: json['id'] ?? '',
      scanSession: json['scan_session'] ?? '',
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
      identificationSource: json['identification_source'] ?? 'camera_ai',
      unitConfidence: resolvedUnitConf,
      isUncertain: resolvedUncertain,
      storageZone: json['storage_zone'] ?? 'pantry',
      expiryDate: parsedExpiry,
      estimatedConsumptionDate: parsedEstimated,
      isExpiryEstimated: isEstimated,
      dateType: json['date_type'] ?? (isEstimated ? 'estimated' : 'expiry'),
      dateSource:
          json['date_source'] ??
          (isEstimated ? 'calculated_shelf_life' : 'ocr_verified'),
      dateConfidence: json['date_confidence'] ?? 'Low',
      rawDateText: json['raw_date_text'] ?? '',
      storageReason: json['storage_reason'] ?? '',
      shelfLifeGuidance: json['shelf_life_guidance'] ?? '',
      confidence: json['confidence'] ?? 'High',
      validationWarnings: List<String>.from(json['validation_warnings'] ?? []),
      selected: json['selected'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
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
    'is_uncertain': isUncertain,
    'storage_zone': storageZone,
    'expiry_date': expiryDate?.toIso8601String().substring(0, 10),
    'estimated_consumption_date': estimatedConsumptionDate
        ?.toIso8601String()
        .substring(0, 10),
    'is_expiry_estimated': isExpiryEstimated,
    'date_type': dateType,
    'date_source': dateSource,
    'date_confidence': dateConfidence,
    'raw_date_text': rawDateText,
    'storage_reason': storageReason,
    'shelf_life_guidance': shelfLifeGuidance,
    'confidence': confidence,
    'selected': selected,
  };

  ScanCandidateModel copyWith({
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
    bool? isUncertain,
    String? storageZone,
    DateTime? expiryDate,
    DateTime? estimatedConsumptionDate,
    bool? isExpiryEstimated,
    String? dateType,
    String? dateSource,
    String? dateConfidence,
    String? rawDateText,
    String? storageReason,
    String? shelfLifeGuidance,
    String? confidence,
    bool? selected,
  }) {
    return ScanCandidateModel(
      id: id,
      scanSession: scanSession,
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
      isUncertain: isUncertain ?? this.isUncertain,
      storageZone: storageZone ?? this.storageZone,
      expiryDate: expiryDate ?? this.expiryDate,
      estimatedConsumptionDate:
          estimatedConsumptionDate ?? this.estimatedConsumptionDate,
      isExpiryEstimated: isExpiryEstimated ?? this.isExpiryEstimated,
      dateType: dateType ?? this.dateType,
      dateSource: dateSource ?? this.dateSource,
      dateConfidence: dateConfidence ?? this.dateConfidence,
      rawDateText: rawDateText ?? this.rawDateText,
      storageReason: storageReason ?? this.storageReason,
      shelfLifeGuidance: shelfLifeGuidance ?? this.shelfLifeGuidance,
      confidence: confidence ?? this.confidence,
      validationWarnings: validationWarnings,
      selected: selected ?? this.selected,
    );
  }
}
