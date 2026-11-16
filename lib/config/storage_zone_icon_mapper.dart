import 'package:flutter/material.dart';
import 'app_icons.dart';

class StorageZoneIconMapper {
  StorageZoneIconMapper._();

  static IconData fromKey(String? key) {
    if (key == null) return Icons.kitchen_rounded;
    final normalized = key.toLowerCase().trim();
    switch (normalized) {
      case AppIconKeys.fridge:
        return Icons.kitchen_rounded;
      case AppIconKeys.freezer:
        return Icons.ac_unit_rounded;
      case AppIconKeys.pantry:
        return Icons.all_inbox_rounded; // shelves or kitchen
      case AppIconKeys.counter:
        return Icons.table_restaurant_rounded;
      case AppIconKeys.cabinet:
        return Icons.door_sliding_rounded;
      case AppIconKeys.basket:
        return Icons.shopping_basket_rounded;
      default:
        return Icons.kitchen_rounded;
    }
  }
}
