import 'package:flutter/material.dart';
import 'app_icons.dart';

class GroceryIconMapper {
  GroceryIconMapper._();

  static IconData fromKey(String? key) {
    if (key == null) return Icons.inventory_2_rounded;
    final normalized = key.toLowerCase().trim();
    switch (normalized) {
      case AppIconKeys.vegetables:
        return Icons.eco_rounded;
      case AppIconKeys.fruits:
        return Icons.apple_rounded;
      case AppIconKeys.dairy:
        return Icons.local_drink_rounded;
      case AppIconKeys.grains:
        return Icons.grain_rounded;
      case AppIconKeys.beverage:
        return Icons.local_cafe_rounded;
      case AppIconKeys.spices:
        return Icons.grass_rounded;
      case AppIconKeys.grocery:
        return Icons.shopping_bag_rounded;
      case AppIconKeys.restaurant:
        return Icons.restaurant_rounded;
      default:
        return Icons.inventory_2_rounded;
    }
  }
}
