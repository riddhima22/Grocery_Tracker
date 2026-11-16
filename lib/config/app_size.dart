import 'package:flutter/material.dart';

class R {
  static const double _baseW = 390.0;
  static const double _baseH = 844.0;

  static double screenWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;
  static double screenHeight(BuildContext context) =>
      MediaQuery.of(context).size.height;

  static double w(BuildContext context, double value) =>
      value * (screenWidth(context) / _baseW);
  static double h(BuildContext context, double value) =>
      value * (screenHeight(context) / _baseH);
  static double r(BuildContext context, double value) =>
      value * (screenWidth(context) / _baseW);
  static double fs(BuildContext context, double value) =>
      (value * (screenWidth(context) / _baseW)).clamp(
        value * 0.85,
        value * 1.25,
      );

  static bool isSmall(BuildContext context) => screenWidth(context) < 360;
  static bool isTablet(BuildContext context) => screenWidth(context) >= 600;
  static bool isDesktop(BuildContext context) => screenWidth(context) >= 1024;

  static EdgeInsets pagePadding(BuildContext context) =>
      EdgeInsets.symmetric(horizontal: w(context, 20));
  static EdgeInsets cardPadding(BuildContext context) =>
      EdgeInsets.all(r(context, 16));
}
