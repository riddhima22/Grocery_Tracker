import 'package:flutter/material.dart';
import '../core/extensions/responsive_context_extension.dart';
import 'app_dimensions.dart';

class AppRadius {
  AppRadius._();

  static double card(BuildContext context) =>
      context.scaleRadius(AppDimensions.radiusCard);

  static double panel(BuildContext context) =>
      context.scaleRadius(AppDimensions.radiusPanel);

  static double chip(BuildContext context) =>
      context.scaleRadius(AppDimensions.radiusChip);
}
