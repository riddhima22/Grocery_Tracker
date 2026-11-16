import 'package:flutter/material.dart';
import '../../config/app_breakpoints.dart';
import '../../config/app_dimensions.dart';

enum DeviceType { compactPhone, phone, largePhone, tablet, largeTablet }

extension ResponsiveContext on BuildContext {
  Size get screenSize => MediaQuery.sizeOf(this);

  double get availableWidth => screenSize.width;

  double get availableHeight =>
      screenSize.height -
      MediaQuery.paddingOf(this).vertical -
      MediaQuery.viewInsetsOf(this).bottom;

  bool get isLandscape =>
      MediaQuery.orientationOf(this) == Orientation.landscape;

  /// Maximum width for content to prevent excessive stretching on wide screens.
  double get contentWidth => availableWidth.clamp(0.0, 600.0);

  DeviceType get deviceType {
    final width = screenSize.width;
    if (width <= AppBreakpoints.compactPhoneMax) {
      return DeviceType.compactPhone;
    } else if (width <= AppBreakpoints.phoneMax) {
      return DeviceType.phone;
    } else if (width <= AppBreakpoints.largePhoneMax) {
      return DeviceType.largePhone;
    } else if (width <= AppBreakpoints.tabletMax) {
      return DeviceType.tablet;
    } else {
      return DeviceType.largeTablet;
    }
  }

  /// Scale a design-time width value to the current screen.
  /// On phones (<=600px), scales proportionally to baseWidth (390px).
  /// On wider screens, caps at 1.0x to prevent bloating.
  double scaleWidth(double designValue) {
    final double effectiveWidth = availableWidth <= AppBreakpoints.phoneMax
        ? availableWidth.clamp(320.0, AppBreakpoints.phoneMax)
        : AppDimensions
              .baseWidth; // Use 1:1 on tablets (content is constrained)
    final scale = effectiveWidth / AppDimensions.baseWidth;
    return designValue * scale;
  }

  /// Scale a design-time height value to the current screen.
  double scaleHeight(double designValue) {
    final double height = availableHeight.clamp(480.0, 900.0);
    final scale = height / AppDimensions.baseHeight;
    return designValue * scale;
  }

  /// Scale a font size value with min/max clamping.
  double scaleFont(double designValue) {
    final double effectiveWidth = availableWidth <= AppBreakpoints.phoneMax
        ? availableWidth.clamp(320.0, AppBreakpoints.phoneMax)
        : AppDimensions.baseWidth;
    final scale = effectiveWidth / AppDimensions.baseWidth;
    final scaled = designValue * scale;
    return scaled.clamp(
      designValue * AppDimensions.minimumFontScale,
      designValue * AppDimensions.maximumFontScale,
    );
  }

  /// Scale a border radius value.
  double scaleRadius(double designValue) {
    final double effectiveWidth = availableWidth <= AppBreakpoints.phoneMax
        ? availableWidth.clamp(320.0, AppBreakpoints.phoneMax)
        : AppDimensions.baseWidth;
    final scale = effectiveWidth / AppDimensions.baseWidth;
    return designValue * scale;
  }

  /// Return a value based on the current device type.
  double responsiveValue({
    required double compactPhone,
    required double phone,
    required double tablet,
    required double largeTablet,
  }) {
    switch (deviceType) {
      case DeviceType.compactPhone:
        return compactPhone;
      case DeviceType.phone:
      case DeviceType.largePhone:
        return phone;
      case DeviceType.tablet:
        return tablet;
      case DeviceType.largeTablet:
        return largeTablet;
    }
  }
}
