import 'package:flutter/material.dart';
import '../../../data/models/grocery_list_model.dart';
import '../../../data/repositories/grocery_list_repository.dart';
import '../../../core/utils/app_logger.dart';

class GroceryListProvider extends ChangeNotifier {
  final GroceryListRepository _repository = GroceryListRepository();

  GroceryListModel? _currentList;
  bool _isLoading = false;
  String? _errorMessage;

  GroceryListModel? get currentList => _currentList;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchCurrentList() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentList = await _repository.getCurrentList();
      _isLoading = false;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      AppLogger.error('Failed to load current list', e);
    }
    notifyListeners();
  }

  Future<void> generateSuggestions() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentList = await _repository.generateSuggestedList();
      _isLoading = false;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      AppLogger.error('Failed to generate suggestions', e);
    }
    notifyListeners();
  }

  Future<bool> addItem(String name, double quantity, String unit) async {
    if (_currentList == null) return false;
    try {
      final newItem = await _repository.addListItem(
        _currentList!.id,
        name,
        quantity,
        unit,
      );

      // Update local state list
      final updatedItems = List<GroceryListItemModel>.from(_currentList!.items)
        ..add(newItem);
      _currentList = GroceryListModel(
        id: _currentList!.id,
        status: _currentList!.status,
        generationReason: _currentList!.generationReason,
        createdAt: _currentList!.createdAt,
        items: updatedItems,
      );

      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.error('Failed to add list item', e);
      return false;
    }
  }

  Future<bool> updateItemQuantity(String itemId, double newQty) async {
    if (_currentList == null) return false;
    try {
      final updated = await _repository.editListItem(_currentList!.id, itemId, {
        'quantity': newQty,
      });

      final index = _currentList!.items.indexWhere((i) => i.id == itemId);
      if (index != -1) {
        final updatedItems = List<GroceryListItemModel>.from(
          _currentList!.items,
        );
        updatedItems[index] = updated;
        _currentList = GroceryListModel(
          id: _currentList!.id,
          status: _currentList!.status,
          generationReason: _currentList!.generationReason,
          createdAt: _currentList!.createdAt,
          items: updatedItems,
        );
        notifyListeners();
      }
      return true;
    } catch (e) {
      AppLogger.error('Failed to update list item quantity', e);
      return false;
    }
  }

  Future<bool> deleteItem(String itemId) async {
    if (_currentList == null) return false;
    try {
      await _repository.deleteListItem(_currentList!.id, itemId);

      final updatedItems = List<GroceryListItemModel>.from(_currentList!.items)
        ..removeWhere((i) => i.id == itemId);

      _currentList = GroceryListModel(
        id: _currentList!.id,
        status: _currentList!.status,
        generationReason: _currentList!.generationReason,
        createdAt: _currentList!.createdAt,
        items: updatedItems,
      );
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.error('Failed to delete list item', e);
      return false;
    }
  }

  Future<bool> setItemFeedback(String itemId, String feedback) async {
    if (_currentList == null) return false;
    try {
      final updated = await _repository.setItemFeedback(
        _currentList!.id,
        itemId,
        feedback,
      );

      final index = _currentList!.items.indexWhere((i) => i.id == itemId);
      if (index != -1) {
        final updatedItems = List<GroceryListItemModel>.from(
          _currentList!.items,
        );
        updatedItems[index] = updated;
        _currentList = GroceryListModel(
          id: _currentList!.id,
          status: _currentList!.status,
          generationReason: _currentList!.generationReason,
          createdAt: _currentList!.createdAt,
          items: updatedItems,
        );
        notifyListeners();
      }
      return true;
    } catch (e) {
      AppLogger.error('Failed to set item feedback', e);
      return false;
    }
  }

  Future<bool> markItemPurchased(String itemId) async {
    if (_currentList == null) return false;
    try {
      await _repository.markPurchased(_currentList!.id, itemId);

      // Remove item from active shopping list since it enters pantry
      final updatedItems = List<GroceryListItemModel>.from(_currentList!.items)
        ..removeWhere((i) => i.id == itemId);

      _currentList = GroceryListModel(
        id: _currentList!.id,
        status: _currentList!.status,
        generationReason: _currentList!.generationReason,
        createdAt: _currentList!.createdAt,
        items: updatedItems,
      );

      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.error('Failed to purchase list item', e);
      return false;
    }
  }
}
