import 'package:flutter/material.dart';
import '../core/extensions/responsive_context_extension.dart';
import 'app_dimensions.dart';

class AppConstraints {
  AppConstraints._();

  static double get formMaxWidth => AppDimensions.formMaxWidth;
  static double get dialogMaxWidth => AppDimensions.dialogMaxWidth;

  static double dashboardCardMaxExtent(BuildContext context) =>
      context.scaleWidth(AppDimensions.dashboardCardMaxExtent);

  static double dashboardCardAspectRatio(BuildContext context) {
    // Return different ratios for different form factors
    if (context.deviceType == DeviceType.largeTablet) {
      return 1.4;
    } else if (context.deviceType == DeviceType.tablet) {
      return 1.5;
    } else {
      return 1.6;
    }
  }

  static double kitchenAspectRatio(BuildContext context) {
    // Kitchen scene standard aspect ratio (width / height)
    return context.isLandscape ? 2.1 : 1.35;
  }
}
