import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../models/grocery_model.dart';

class GroceryRepository {
  final ApiClient _apiClient = ApiClient();

  Future<List<GroceryModel>> getGroceries() async {
    final response = await _apiClient.get(ApiEndpoints.groceries);
    final list = response.data['data'] as List?;
    return list?.map((i) => GroceryModel.fromJson(i)).toList() ?? const [];
  }

  Future<Map<String, dynamic>> lookupBarcode(String barcode) async {
    final response = await _apiClient.get(
      '${ApiEndpoints.groceries}barcode-lookup/',
      queryParameters: {'barcode': barcode},
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<GroceryModel> createGrocery(Map<String, dynamic> data) async {
    final response = await _apiClient.post(ApiEndpoints.groceries, data: data);
    return GroceryModel.fromJson(response.data['data']);
  }

  Future<GroceryModel> updateGrocery(String id, Map<String, dynamic> data) async {
    final response = await _apiClient.patch(ApiEndpoints.groceryDetail(id), data: data);
    return GroceryModel.fromJson(response.data['data']);
  }

  Future<void> deleteGrocery(String id) async {
    await _apiClient.delete(ApiEndpoints.groceryDetail(id));
  }

  Future<GroceryModel> adjustQuantity(String id, double adjustment) async {
    final response = await _apiClient.post(
      ApiEndpoints.adjustQuantity(id),
      data: {'adjustment': adjustment},
    );
    return GroceryModel.fromJson(response.data['data']);
  }

  Future<GroceryModel> consume(String id, {double? quantity}) async {
    final response = await _apiClient.post(
      ApiEndpoints.consume(id),
      data: quantity != null ? {'quantity': quantity} : null,
    );
    return GroceryModel.fromJson(response.data['data']);
  }

  Future<GroceryModel> waste(String id, {double? quantity}) async {
    final response = await _apiClient.post(
      ApiEndpoints.waste(id),
      data: quantity != null ? {'quantity': quantity} : null,
    );
    return GroceryModel.fromJson(response.data['data']);
  }

  Future<List<GroceryModel>> getUseFirst() async {
    final response = await _apiClient.get(ApiEndpoints.useFirst);
    final list = response.data['data'] as List?;
    return list?.map((i) => GroceryModel.fromJson(i)).toList() ?? const [];
  }

  Future<Map<String, int>> getStats() async {
    final response = await _apiClient.get(ApiEndpoints.stats);
    final stats = response.data['data'] as Map<String, dynamic>;
    return stats.map((key, value) => MapEntry(key, value as int));
  }

  Future<Map<String, int>> getZones() async {
    final response = await _apiClient.get(ApiEndpoints.zones);
    final zones = response.data['data'] as Map<String, dynamic>;
    return zones.map((key, value) => MapEntry(key, value as int));
  }
}
