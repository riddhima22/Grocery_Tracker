import 'package:flutter/material.dart';
import '../../../data/models/grocery_model.dart';
import '../../../data/repositories/grocery_repository.dart';
import '../../../data/local/cache_manager.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/services/notification_service.dart';

class KitchenProvider extends ChangeNotifier {
  final GroceryRepository _groceryRepository = GroceryRepository();
  final CacheManager _cacheManager = CacheManager();

  List<GroceryModel> _items = [];
  bool _isLoading = false;
  bool _isFetching = false;
  String? _errorMessage;

  KitchenProvider() {
    _loadInitialCachedItems();
  }

  Future<void> _loadInitialCachedItems() async {
    try {
      final cached = await _cacheManager.getCachedGroceries();
      if (cached.isNotEmpty && _items.isEmpty) {
        _items = cached;
        notifyListeners();
      }
    } catch (e) {
      AppLogger.error('Failed to load initial cached groceries', e);
    }
  }

  List<GroceryModel> get items => _items;
  bool get isLoading => _isLoading;
  bool get isFetching => _isFetching;
  String? get errorMessage => _errorMessage;

  int get totalItems => _items.length;
  int get expiringCount => _items.where((i) => i.status == 'expiring').length;
  int get expiredCount => _items.where((i) => i.status == 'expired').length;

  List<GroceryModel> get expiringItems => _items.where((i) => i.status == 'expiring').toList();
  List<GroceryModel> get expiredItems => _items.where((i) => i.status == 'expired').toList();

  List<GroceryModel> get fridgeItems => _getItemsByZone('fridge');
  List<GroceryModel> get freezerItems => _getItemsByZone('freezer');
  List<GroceryModel> get pantryItems => _getItemsByZone('pantry');
  List<GroceryModel> get counterItems => _getItemsByZone('counter');
  List<GroceryModel> get cabinetItems => _getItemsByZone('cabinet');
  List<GroceryModel> get basketItems => _getItemsByZone('basket');
  List<GroceryModel> get spiceItems => _getItemsByZone('spice');

  /// Fetches kitchen items using a fast cache-first / stale-while-revalidate strategy.
  /// If cached data exists, it renders immediately (0ms) and refreshes in the background.
  Future<void> fetchKitchenItems({bool forceRefresh = false}) async {
    // 1. Immediately hydrate from cache if in-memory state is empty
    if (_items.isEmpty) {
      final cached = await _cacheManager.getCachedGroceries();
      if (cached.isNotEmpty) {
        _items = cached;
        _isLoading = false;
        notifyListeners();
      } else {
        _isLoading = true;
        _errorMessage = null;
        notifyListeners();
      }
    }

    // 2. Prevent concurrent duplicate requests
    if (_isFetching) return;

    // 3. Skip redundant network fetch if data is present and fresh (< 3 mins), unless forced
    if (!forceRefresh && _items.isNotEmpty) {
      final isStale = await _cacheManager.isGroceriesCacheStale(maxAge: const Duration(minutes: 3));
      if (!isStale) {
        return;
      }
    }

    _isFetching = true;
    try {
      final remoteItems = await _groceryRepository.getGroceries();
      _items = remoteItems;
      _errorMessage = null;
      _isLoading = false;

      // Update cache asynchronously
      _cacheManager.saveGroceries(_items);

      // Automatically schedule local notifications for expiring items
      NotificationService().scheduleExpiryAlertsForItems(_items);
    } catch (e) {
      AppLogger.error('Failed to load kitchen items from network', e);
      // If we already have items displayed from cache, do NOT block user with error screen
      if (_items.isEmpty) {
        _errorMessage = e.toString();
      }
    } finally {
      _isLoading = false;
      _isFetching = false;
      notifyListeners();
    }
  }

  List<GroceryModel> _getItemsByZone(String zone) {
    return _items.where((i) => i.storageZone.toLowerCase() == zone.toLowerCase()).toList();
  }

  Future<bool> adjustQuantity(String id, double adjustment) async {
    try {
      final updated = await _groceryRepository.adjustQuantity(id, adjustment);
      final index = _items.indexWhere((i) => i.id == id);
      if (index != -1) {
        if (updated.quantity == 0) {
          _items.removeAt(index);
        } else {
          _items[index] = updated;
        }
        _cacheManager.saveGroceries(_items);
        notifyListeners();
      }
      return true;
    } catch (e) {
      AppLogger.error('Quantity adjust failed', e);
      return false;
    }
  }

  Future<bool> consumeItem(String id, {double? quantity}) async {
    try {
      final updated = await _groceryRepository.consume(id, quantity: quantity);
      final index = _items.indexWhere((i) => i.id == id);
      if (index != -1) {
        if (updated.quantity == 0) {
          _items.removeAt(index);
        } else {
          _items[index] = updated;
        }
        _cacheManager.saveGroceries(_items);
        notifyListeners();
      }
      return true;
    } catch (e) {
      AppLogger.error('Consume failed', e);
      return false;
    }
  }

  Future<bool> wasteItem(String id, {double? quantity}) async {
    try {
      final updated = await _groceryRepository.waste(id, quantity: quantity);
      final index = _items.indexWhere((i) => i.id == id);
      if (index != -1) {
        if (updated.quantity == 0) {
          _items.removeAt(index);
        } else {
          _items[index] = updated;
        }
        _cacheManager.saveGroceries(_items);
        notifyListeners();
      }
      return true;
    } catch (e) {
      AppLogger.error('Waste logging failed', e);
      return false;
    }
  }

  Future<bool> deleteItem(String id) async {
    try {
      await _groceryRepository.deleteGrocery(id);
      _items.removeWhere((i) => i.id == id);
      _cacheManager.saveGroceries(_items);
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.error('Delete failed', e);
      return false;
    }
  }

  Future<void> addItemManually(Map<String, dynamic> data) async {
    _isLoading = true;
    notifyListeners();
    try {
      final newItem = await _groceryRepository.createGrocery(data);
      _items.add(newItem);
      _cacheManager.saveGroceries(_items);
    } catch (e) {
      _errorMessage = e.toString();
      AppLogger.error('Add manual item failed', e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateItem(String id, Map<String, dynamic> data) async {
    try {
      final updated = await _groceryRepository.updateGrocery(id, data);
      final index = _items.indexWhere((i) => i.id == id);
      if (index != -1) {
        _items[index] = updated;
        _cacheManager.saveGroceries(_items);
        notifyListeners();
      }
      return true;
    } catch (e) {
      AppLogger.error('Update item failed', e);
      return false;
    }
  }
}
