import 'package:flutter/material.dart';
import '../core/extensions/responsive_context_extension.dart';

class AppIconSizes {
  AppIconSizes._();

  static double sm(BuildContext context) => context.scaleWidth(18.0);
  static double md(BuildContext context) => context.scaleWidth(24.0);
  static double lg(BuildContext context) => context.scaleWidth(32.0);
}
