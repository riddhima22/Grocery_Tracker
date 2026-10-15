import 'package:flutter/material.dart';
import '../core/extensions/responsive_context_extension.dart';
import 'app_dimensions.dart';

class AppSpacing {
  AppSpacing._();

  static double xxs(BuildContext context) =>
      context.scaleWidth(AppDimensions.spacingXxs);

  static double xs(BuildContext context) =>
      context.scaleWidth(AppDimensions.spacingXs);

  static double sm(BuildContext context) =>
      context.scaleWidth(AppDimensions.spacingSm);

  static double md(BuildContext context) =>
      context.scaleWidth(AppDimensions.spacingMd);

  static double lg(BuildContext context) =>
      context.scaleWidth(AppDimensions.spacingLg);

  static double xl(BuildContext context) =>
      context.scaleWidth(AppDimensions.spacingXl);

  static double xxl(BuildContext context) =>
      context.scaleWidth(AppDimensions.spacingXxl);

  static double pageHorizontal(BuildContext context) => context.responsiveValue(
    compactPhone: context.scaleWidth(AppDimensions.pagePaddingCompact),
    phone: context.scaleWidth(AppDimensions.pagePaddingPhone),
    tablet: context.scaleWidth(AppDimensions.pagePaddingTablet),
    largeTablet: context.scaleWidth(AppDimensions.pagePaddingLargeTablet),
  );

  static double pageVertical(BuildContext context) => context.responsiveValue(
    compactPhone: context.scaleWidth(AppDimensions.pagePaddingCompact),
    phone: context.scaleWidth(AppDimensions.pagePaddingPhone),
    tablet: context.scaleWidth(AppDimensions.pagePaddingTablet),
    largeTablet: context.scaleWidth(AppDimensions.pagePaddingLargeTablet),
  );
}

class AppGap extends StatelessWidget {
  final double size;

  const AppGap({super.key, required this.size});

  factory AppGap.xxs(BuildContext context, {Key? key}) =>
      AppGap(key: key, size: AppSpacing.xxs(context));

  factory AppGap.xs(BuildContext context, {Key? key}) =>
      AppGap(key: key, size: AppSpacing.xs(context));

  factory AppGap.sm(BuildContext context, {Key? key}) =>
      AppGap(key: key, size: AppSpacing.sm(context));

  factory AppGap.md(BuildContext context, {Key? key}) =>
      AppGap(key: key, size: AppSpacing.md(context));

  factory AppGap.lg(BuildContext context, {Key? key}) =>
      AppGap(key: key, size: AppSpacing.lg(context));

  factory AppGap.xl(BuildContext context, {Key? key}) =>
      AppGap(key: key, size: AppSpacing.xl(context));

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size);
  }
}
