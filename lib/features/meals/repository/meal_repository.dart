import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../model/meal_log_model.dart';

class MealRepository {
  final ApiClient _apiClient = ApiClient();

  Future<MealLogModel> createMealLog({XFile? image, String? description}) async {
    final Map<String, dynamic> formMap = {};
    if (description != null && description.isNotEmpty) {
      formMap['description'] = description;
    }
    if (image != null) {
      final bytes = await image.readAsBytes();
      formMap['image'] = MultipartFile.fromBytes(bytes, filename: image.name);
    }

    final formData = FormData.fromMap(formMap);
    final response = await _apiClient.post(
      ApiEndpoints.meals,
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );

    return MealLogModel.fromJson(response.data['data']);
  }

  Future<MealLogModel> getMealLog(String id) async {
    final response = await _apiClient.get(ApiEndpoints.mealDetail(id));
    return MealLogModel.fromJson(response.data['data']);
  }

  Future<List<MealLogModel>> getMealLogs() async {
    final response = await _apiClient.get(ApiEndpoints.meals);
    final list = response.data['data'] as List?;
    return list?.map((m) => MealLogModel.fromJson(m)).toList() ?? const [];
  }

  Future<MealLogModel> confirmDeduction(String mealId, List<Map<String, dynamic>> deductions) async {
    final response = await _apiClient.post(
      ApiEndpoints.confirmMealDeduction(mealId),
      data: {'candidate_deductions': deductions},
    );
    return MealLogModel.fromJson(response.data['data']);
  }
}
