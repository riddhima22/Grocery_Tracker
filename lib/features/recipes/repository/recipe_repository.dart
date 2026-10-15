import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../model/recipe_model.dart';

class RecipeRepository {
  final ApiClient _apiClient = ApiClient();

  Future<List<RecipeModel>> getRecipes() async {
    final response = await _apiClient.get(ApiEndpoints.recipes);
    final list = response.data['data'] as List?;
    return list?.map((r) => RecipeModel.fromJson(r)).toList() ?? const [];
  }

  Future<List<RecipeModel>> generateRecipes({
    Map<String, dynamic>? preferences,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.generateRecipes,
      data: preferences ?? {},
    );
    final list = response.data['data'] as List?;
    return list?.map((r) => RecipeModel.fromJson(r)).toList() ?? const [];
  }

  Future<int> markCooked(String id) async {
    final response = await _apiClient.post(ApiEndpoints.markCooked(id));
    return response.data['data']['recipes_cooked'] as int;
  }
}
