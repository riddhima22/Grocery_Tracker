import 'package:flutter/material.dart';
import 'grocery_icon_mapper.dart';

class RecipeIconMapper {
  RecipeIconMapper._();

  static IconData fromKey(String? key) {
    return GroceryIconMapper.fromKey(key);
  }
}
