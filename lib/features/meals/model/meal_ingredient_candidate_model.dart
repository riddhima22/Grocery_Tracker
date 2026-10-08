class MealIngredientCandidateModel {
  final String id;
  final String? pantryItemId;
  final String name;
  final double estimatedQuantity;
  final double deductQuantity;
  final String unit;
  final String confidence;
  final bool confirmed;

  MealIngredientCandidateModel({
    required this.id,
    this.pantryItemId,
    required this.name,
    required this.estimatedQuantity,
    required this.deductQuantity,
    required this.unit,
    required this.confidence,
    this.confirmed = true,
  });

  factory MealIngredientCandidateModel.fromJson(Map<String, dynamic> json) {
    return MealIngredientCandidateModel(
      id: json['id'] ?? '',
      pantryItemId: json['pantry_item'],
      name: json['name'] ?? '',
      estimatedQuantity: double.tryParse(json['estimated_quantity']?.toString() ?? '1.0') ?? 1.0,
      deductQuantity: double.tryParse(json['deduct_quantity']?.toString() ?? '1.0') ?? 1.0,
      unit: json['unit'] ?? 'pcs',
      confidence: json['confidence'] ?? 'Medium',
      confirmed: json['confirmed'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'pantry_item': pantryItemId,
    'name': name,
    'estimated_quantity': estimatedQuantity,
    'deduct_quantity': deductQuantity,
    'unit': unit,
    'confidence': confidence,
    'confirmed': confirmed,
  };
}
