import 'package:flutter/material.dart';
import '../../config/app_breakpoints.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width >= AppBreakpoints.desktop && desktop != null) {
      return desktop!;
    } else if (width >= AppBreakpoints.tablet && tablet != null) {
      return tablet!;
    } else {
      return mobile;
    }
  }
}
