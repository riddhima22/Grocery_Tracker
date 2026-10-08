class RecipeModel {
  final String id;
  final String name;
  final String iconKey;
  final String cuisine;
  final String dietType;
  
  final int prepTimeMins;
  final int caloriesPerServing;
  final int servings;
  
  final List<String> ingredientsUsed;
  final List<String> otherIngredients;
  final List<String> allergens;
  final List<String> steps;
  final Map<String, String> nutrition;
  
  final String tip;
  final String allergenWarning;

  const RecipeModel({
    required this.id,
    required this.name,
    this.iconKey = 'restaurant',
    required this.cuisine,
    required this.dietType,
    required this.prepTimeMins,
    required this.caloriesPerServing,
    required this.servings,
    required this.ingredientsUsed,
    required this.otherIngredients,
    required this.allergens,
    required this.steps,
    required this.nutrition,
    required this.tip,
    required this.allergenWarning,
  });

  factory RecipeModel.fromJson(Map<String, dynamic> json) {
    return RecipeModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      iconKey: json['icon_key'] ?? 'restaurant',
      cuisine: json['cuisine'] ?? '',
      dietType: json['diet_type'] ?? 'veg',
      prepTimeMins: int.tryParse(json['prep_time_mins']?.toString() ?? '30') ?? 30,
      caloriesPerServing: int.tryParse(json['calories_per_serving']?.toString() ?? '200') ?? 200,
      servings: int.tryParse(json['servings']?.toString() ?? '2') ?? 2,
      ingredientsUsed: (json['ingredients_used'] as List?)?.map((item) {
        if (item is Map) {
          final qty = item['quantity'] ?? '';
          final unit = item['unit'] ?? '';
          final name = item['name'] ?? '';
          final parts = [
            if (qty.toString().isNotEmpty) qty,
            if (unit.toString().isNotEmpty) unit,
            name.toString(),
          ];
          return parts.join(' ').trim();
        }
        return item.toString();
      }).toList() ?? const [],
      otherIngredients: (json['other_ingredients'] as List?)?.map((item) {
        if (item is Map) {
          return (item['name'] ?? item.toString()).toString();
        }
        return item.toString();
      }).toList() ?? const [],
      allergens: (json['allergens'] as List?)?.map((item) => item.toString()).toList() ?? const [],
      steps: (json['steps'] as List?)?.map((item) => item.toString()).toList() ?? const [],
      nutrition: (json['nutrition'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
      tip: json['tip'] ?? '',
      allergenWarning: json['allergen_warning'] ?? '',
    );
  }
}