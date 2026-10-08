import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../model/grocery_list_model.dart';
import '../../kitchen/model/grocery_model.dart';

class GroceryListRepository {
  final ApiClient _apiClient = ApiClient();

  Future<GroceryListModel> getCurrentList() async {
    final response = await _apiClient.get(ApiEndpoints.currentGroceryList);
    return GroceryListModel.fromJson(response.data['data']);
  }

  Future<GroceryListModel> generateSuggestedList() async {
    final response = await _apiClient.post(ApiEndpoints.generateGroceryList);
    return GroceryListModel.fromJson(response.data['data']);
  }

  Future<GroceryListItemModel> addListItem(String listId, String name, double quantity, String unit) async {
    final response = await _apiClient.post(
      ApiEndpoints.groceryListItems(listId),
      data: {
        'name': name,
        'quantity': quantity,
        'unit': unit,
      },
    );
    return GroceryListItemModel.fromJson(response.data['data']);
  }

  Future<GroceryListItemModel> editListItem(String listId, String itemId, Map<String, dynamic> data) async {
    final response = await _apiClient.patch(
      ApiEndpoints.groceryListItemDetail(listId, itemId),
      data: data,
    );
    return GroceryListItemModel.fromJson(response.data['data']);
  }

  Future<void> deleteListItem(String listId, String itemId) async {
    await _apiClient.delete(ApiEndpoints.groceryListItemDetail(listId, itemId));
  }

  Future<GroceryListItemModel> setItemFeedback(String listId, String itemId, String feedback) async {
    final response = await _apiClient.post(
      ApiEndpoints.itemFeedback(listId, itemId),
      data: {'feedback': feedback},
    );
    return GroceryListItemModel.fromJson(response.data['data']);
  }

  Future<GroceryModel> markPurchased(String listId, String itemId) async {
    final response = await _apiClient.post(ApiEndpoints.markPurchased(listId, itemId));
    return GroceryModel.fromJson(response.data['data']);
  }
}
