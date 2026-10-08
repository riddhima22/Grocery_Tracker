import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_navigation.dart';
import '../../config/app_routes.dart';
import '../../features/home/views/home_shell.dart';
import '../../features/kitchen/views/kitchen_item_detail_view.dart';
import '../../features/kitchen/providers/kitchen_provider.dart';
import '../../features/kitchen/repository/grocery_repository.dart';
import '../../data/models/grocery_model.dart';
import '../utils/app_logger.dart';
import 'notification_constants.dart';

class NotificationRouter {
  static Map<String, dynamic>? _pendingNotificationData;

  /// Centralized routing entry-point for foreground taps, background taps,
  /// and cold-start launched notifications.
  static void handleNotificationTap(Map<String, dynamic>? rawData) {
    if (rawData == null || rawData.isEmpty) return;

    AppLogger.info('NotificationRouter handling tap with payload: $rawData');

    final navState = AppNavigation.navigatorKey.currentState;
    if (navState == null) {
      AppLogger.info('Navigator not ready yet. Storing notification payload as pending.');
      _pendingNotificationData = rawData;
      return;
    }

    _executeRouting(rawData);
  }

  /// Checks and flushes any pending notification that arrived before the navigator mounted.
  static void processPendingNotification() {
    if (_pendingNotificationData != null) {
      final data = _pendingNotificationData!;
      _pendingNotificationData = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _executeRouting(data);
      });
    }
  }

  static void _executeRouting(Map<String, dynamic> data) {
    try {
      final type = data['type']?.toString() ?? NotificationConstants.typeGeneral;
      final groceryId = data['grocery_id']?.toString() ?? data['id']?.toString();
      final listId = data['list_id']?.toString();

      switch (type) {
        case NotificationConstants.typeExpiryReminder:
        case NotificationConstants.typeLowStock:
        case NotificationConstants.typeGroceryUpdated:
          if (groceryId != null && groceryId.isNotEmpty) {
            _navigateToGroceryDetail(groceryId);
          } else {
            _navigateToHomeTab(1); // Kitchen tab
          }
          break;

        case NotificationConstants.typeShoppingReminder:
        case NotificationConstants.typeSharedList:
          if (listId != null && listId.isNotEmpty) {
            AppLogger.info('Routing to Grocery List tab for list: $listId');
          }
          _navigateToHomeTab(3); // Grocery List tab
          break;

        case NotificationConstants.typeGeneral:
        default:
          _navigateToHomeTab(0); // Dashboard tab
          break;
      }
    } catch (e, stack) {
      AppLogger.error('Failed to route notification', e, stack);
    }
  }

  static void _navigateToHomeTab(int tabIndex) {
    final navState = AppNavigation.navigatorKey.currentState;
    if (navState != null) {
      // If we are nested in subpages, pop back to home shell first
      navState.popUntil((route) => route.isFirst || route.settings.name == AppRoutes.home);
      HomeShell.switchTab(tabIndex);
    }
  }

  static Future<void> _navigateToGroceryDetail(String groceryId) async {
    final navState = AppNavigation.navigatorKey.currentState;
    if (navState == null) return;

    // Pop back to home shell base first
    navState.popUntil((route) => route.isFirst || route.settings.name == AppRoutes.home);

    // 1. Check if item is already loaded in KitchenProvider in memory
    GroceryModel? targetItem;
    try {
      final context = AppNavigation.context;
      final kitchenProvider = Provider.of<KitchenProvider>(context, listen: false);
      targetItem = kitchenProvider.items.cast<GroceryModel?>().firstWhere(
        (item) => item?.id == groceryId,
        orElse: () => null,
      );
    } catch (_) {}

    // 2. If not found in memory, fetch directly from backend API
    if (targetItem == null) {
      try {
        final repo = GroceryRepository();
        targetItem = await repo.getGrocery(groceryId);
      } catch (e) {
        AppLogger.warning('Could not fetch grocery detail for id $groceryId, opening Kitchen tab: $e');
        HomeShell.switchTab(1); // Switch to kitchen tab
        return;
      }
    }

    // 3. Push the KitchenItemDetailView
    navState.push(
      MaterialPageRoute(
        builder: (_) => KitchenItemDetailView(item: targetItem!),
      ),
    );
  }
}
