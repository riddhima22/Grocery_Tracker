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

  factory ScanCandidateModel.fromJson(Map<String, dynamic> json) {
    DateTime? parsedExpiry;
    if (json['expiry_date'] != null && json['expiry_date'].toString().isNotEmpty) {
      parsedExpiry = DateTime.tryParse(json['expiry_date'].toString());
    }

    DateTime? parsedEstimated;
    if (json['estimated_consumption_date'] != null &&
        json['estimated_consumption_date'].toString().isNotEmpty) {
      parsedEstimated = DateTime.tryParse(json['estimated_consumption_date'].toString());
    }

    final bool isEstimated;
    if (json['is_expiry_estimated'] != null) {
      isEstimated = json['is_expiry_estimated'] == true;
    } else if (parsedEstimated != null) {
      isEstimated = true;
    } else {
      isEstimated = false;
    }

    return ScanCandidateModel(
      id: json['id'] ?? '',
      scanSession: json['scan_session'] ?? '',
      name: json['name'] ?? '',
      brand: json['brand'] ?? '',
      description: json['description'] ?? '',
      iconKey: json['icon_key'] ?? 'grocery',
      category: json['category'] ?? 'Vegetables',
      quantity: double.tryParse(json['quantity']?.toString() ?? '1.0') ?? 1.0,
      unit: json['unit'] ?? 'pcs',
      storageZone: json['storage_zone'] ?? 'pantry',
      expiryDate: parsedExpiry,
      estimatedConsumptionDate: parsedEstimated,
      isExpiryEstimated: isEstimated,
      dateType: json['date_type'] ?? (isEstimated ? 'estimated' : 'expiry'),
      dateSource: json['date_source'] ?? (isEstimated ? 'calculated_shelf_life' : 'ocr_verified'),
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
    'storage_zone': storageZone,
    'expiry_date': expiryDate?.toIso8601String().substring(0, 10),
    'estimated_consumption_date': estimatedConsumptionDate?.toIso8601String().substring(0, 10),
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
      storageZone: storageZone ?? this.storageZone,
      expiryDate: expiryDate ?? this.expiryDate,
      estimatedConsumptionDate: estimatedConsumptionDate ?? this.estimatedConsumptionDate,
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
