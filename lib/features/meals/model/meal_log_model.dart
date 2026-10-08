import 'meal_ingredient_candidate_model.dart';

class MealLogModel {
  final String id;
  final String name;
  final String description;
  final String? imageUrl;
  final String status;
  final List<MealIngredientCandidateModel> candidates;
  final DateTime createdAt;

  MealLogModel({
    required this.id,
    required this.name,
    required this.description,
    this.imageUrl,
    required this.status,
    required this.candidates,
    required this.createdAt,
  });

  factory MealLogModel.fromJson(Map<String, dynamic> json) {
    return MealLogModel(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Logged Meal',
      description: json['description'] ?? '',
      imageUrl: json['image'],
      status: json['status'] ?? 'pending_confirmation',
      candidates: (json['candidates'] as List?)
              ?.map((c) => MealIngredientCandidateModel.fromJson(c))
              .toList() ??
          const [],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }
}
