class GroceryModel {
  final String id;
  final String name;
  final String brand;
  final String description;
  final String iconKey;
  final String category;
  
  final double quantity;
  final String unit;
  final String storageZone;
  
  final DateTime? expiryDate;
  final DateTime purchaseDate;
  final String status;
  
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
    required this.storageZone,
    this.expiryDate,
    required this.purchaseDate,
    required this.status,
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
  });

  factory GroceryModel.fromJson(Map<String, dynamic> json) {
    return GroceryModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      brand: json['brand'] ?? '',
      description: json['description'] ?? '',
      iconKey: json['icon_key'] ?? 'grocery',
      category: json['category'] ?? 'Uncategorized',
      quantity: double.tryParse(json['quantity']?.toString() ?? '1.0') ?? 1.0,
      unit: json['unit'] ?? 'pcs',
      storageZone: json['storage_zone'] ?? 'pantry',
      expiryDate: json['expiry_date'] != null ? DateTime.tryParse(json['expiry_date']) : null,
      purchaseDate: json['purchase_date'] != null ? DateTime.parse(json['purchase_date']) : DateTime.now(),
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
      predictedExpiry: json['predicted_expiry'] != null ? DateTime.tryParse(json['predicted_expiry']) : null,
      recommendedConsumptionDate: json['recommended_consumption_date'] != null ? DateTime.tryParse(json['recommended_consumption_date']) : null,
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
    'storage_zone': storageZone,
    'expiry_date': expiryDate?.toIso8601String().substring(0, 10),
    'purchase_date': purchaseDate.toIso8601String().substring(0, 10),
    'calories_per_100g': caloriesPer100g,
    'allergens': allergens,
    'ripeness': ripeness,
    'temperature': temperature,
    'humidity': humidity,
    'is_opened': isOpened,
    'freshness_score': freshnessScore,
    'predicted_expiry': predictedExpiry?.toIso8601String().substring(0, 10),
    'recommended_consumption_date': recommendedConsumptionDate?.toIso8601String().substring(0, 10),
    'confidence_score': confidenceScore,
    'storage_recommendation_why': storageRecommendationWhy,
    'storage_recommendation_how': storageRecommendationHow,
    'storage_recommendation_shelf_life': storageRecommendationShelfLife,
    'ai_explanation': aiExplanation,
  };
}
