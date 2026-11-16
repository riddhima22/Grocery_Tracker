import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/extensions/responsive_context_extension.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static TextStyle _baseStyle(BuildContext context) => GoogleFonts.outfit();

  static TextStyle displayLarge(BuildContext context) =>
      _baseStyle(context).copyWith(
        fontSize: context.scaleFont(32.0),
        fontWeight: FontWeight.w800, // ExtraBold
        color: AppColors.textPrimary,
        height: 1.2,
        letterSpacing: -0.5,
      );

  static TextStyle displayMedium(BuildContext context) =>
      _baseStyle(context).copyWith(
        fontSize: context.scaleFont(28.0),
        fontWeight: FontWeight.w700, // Bold
        color: AppColors.textPrimary,
        height: 1.2,
        letterSpacing: -0.4,
      );

  static TextStyle headingLarge(BuildContext context) =>
      _baseStyle(context).copyWith(
        fontSize: context.scaleFont(24.0),
        fontWeight: FontWeight.w700, // Bold
        color: AppColors.textPrimary,
        height: 1.2,
        letterSpacing: -0.3,
      );

  static TextStyle headingMedium(BuildContext context) =>
      _baseStyle(context).copyWith(
        fontSize: context.scaleFont(20.0),
        fontWeight: FontWeight.w600, // SemiBold
        color: AppColors.textPrimary,
        height: 1.2,
      );

  static TextStyle headingSmall(BuildContext context) =>
      _baseStyle(context).copyWith(
        fontSize: context.scaleFont(18.0),
        fontWeight: FontWeight.w600, // SemiBold
        color: AppColors.textPrimary,
        height: 1.2,
      );

  static TextStyle bodyLarge(BuildContext context) =>
      _baseStyle(context).copyWith(
        fontSize: context.scaleFont(16.0),
        fontWeight: FontWeight.w400, // Regular
        color: AppColors.textPrimary,
        height: 1.6,
      );

  static TextStyle bodyMedium(BuildContext context) =>
      _baseStyle(context).copyWith(
        fontSize: context.scaleFont(14.0),
        fontWeight: FontWeight.w400, // Regular
        color: AppColors.textSecondary,
        height: 1.6,
      );

  static TextStyle bodySmall(BuildContext context) =>
      _baseStyle(context).copyWith(
        fontSize: context.scaleFont(12.0),
        fontWeight: FontWeight.w400, // Regular
        color: AppColors.textSecondary,
        height: 1.6,
      );

  static TextStyle labelLarge(BuildContext context) =>
      _baseStyle(context).copyWith(
        fontSize: context.scaleFont(16.0),
        fontWeight: FontWeight.w600, // SemiBold
        color: AppColors.textPrimary,
      );

  static TextStyle labelMedium(BuildContext context) =>
      _baseStyle(context).copyWith(
        fontSize: context.scaleFont(14.0),
        fontWeight: FontWeight.w600, // SemiBold
        color: AppColors.textPrimary,
      );

  static TextStyle caption(BuildContext context) =>
      _baseStyle(context).copyWith(
        fontSize: context.scaleFont(11.0),
        fontWeight: FontWeight.w500, // Medium
        color: AppColors.textHint,
      );
}
