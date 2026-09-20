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
    required this.confidence,
    required this.validationWarnings,
    required this.selected,
  });

  factory ScanCandidateModel.fromJson(Map<String, dynamic> json) {
    DateTime? parsedExpiry;
    if (json['expiry_date'] != null && json['expiry_date'].toString().isNotEmpty) {
      parsedExpiry = DateTime.tryParse(json['expiry_date'].toString());
    }
    parsedExpiry ??= _estimateRealisticExpiry(
      json['name']?.toString() ?? '',
      json['category']?.toString() ?? '',
      json['storage_zone']?.toString() ?? '',
    );

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
      confidence: json['confidence'] ?? 'High',
      validationWarnings: List<String>.from(json['validation_warnings'] ?? []),
      selected: json['selected'] ?? true,
    );
  }

  static DateTime _estimateRealisticExpiry(String name, String category, String zone) {
    final nameLower = name.toLowerCase();
    final catLower = category.toLowerCase();
    final zoneLower = zone.toLowerCase();

    int days = 7;

    const Map<String, int> itemDays = {
      'tomato': 7, 'potato': 45, 'onion': 35, 'garlic': 60, 'ginger': 30,
      'spinach': 5, 'lettuce': 5, 'coriander': 5, 'mint': 5, 'carrot': 18,
      'cucumber': 7, 'capsicum': 9, 'pepper': 9, 'chili': 12, 'cauliflower': 8,
      'cabbage': 14, 'broccoli': 7, 'pea': 6, 'bean': 7, 'mushroom': 5,
      'lemon': 21, 'banana': 6, 'apple': 25, 'orange': 16, 'mango': 6,
      'grape': 7, 'strawberry': 4, 'berry': 6, 'watermelon': 8, 'milk': 6,
      'curd': 7, 'yogurt': 10, 'paneer': 6, 'cheese': 16, 'butter': 45,
      'egg': 24, 'bread': 5, 'bun': 4, 'cake': 4, 'chicken': 3, 'meat': 4,
      'fish': 2, 'rice': 240, 'wheat': 240, 'flour': 120, 'dal': 240,
      'pasta': 240, 'noodle': 180, 'oat': 180, 'oil': 240, 'salt': 365,
      'sugar': 365, 'tea': 240, 'coffee': 240, 'biscuit': 90, 'chip': 60,
    };

    for (final entry in itemDays.entries) {
      if (nameLower.contains(entry.key)) {
        days = entry.value;
        break;
      }
    }

    if (days == 7) {
      if (catLower.contains('vegetable')) {
        days = 7;
      } else if (catLower.contains('fruit')) {
        days = 8;
      } else if (catLower.contains('dairy')) {
        days = 7;
      } else if (catLower.contains('bakery')) {
        days = 5;
      } else if (catLower.contains('meat') || catLower.contains('fish')) {
        days = 3;
      } else if (catLower.contains('grain')) {
        days = 180;
      } else if (catLower.contains('spice')) {
        days = 365;
      } else if (catLower.contains('snack')) {
        days = 60;
      } else if (catLower.contains('beverage')) {
        days = 25;
      }
    }

    if (zoneLower == 'freezer') {
      days = days > 90 ? days : 90;
    }

    return DateTime.now().add(Duration(days: days));
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
      confidence: confidence ?? this.confidence,
      validationWarnings: validationWarnings,
      selected: selected ?? this.selected,
    );
  }
}
