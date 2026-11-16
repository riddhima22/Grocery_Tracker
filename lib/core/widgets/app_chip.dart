import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/app_radius.dart';
import '../../core/extensions/responsive_context_extension.dart';

class AppChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final void Function(bool)? onSelected;

  const AppChip({
    super.key,
    required this.label,
    required this.isSelected,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      labelStyle: AppTextStyles.labelMedium(context).copyWith(
        color: isSelected ? AppColors.white : AppColors.textSecondary,
        fontSize: context.scaleFont(13.0),
      ),
      backgroundColor: AppColors.card,
      selectedColor: AppColors.primary,
      checkmarkColor: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip(context) * 2.0),
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.cardBorder,
        ),
      ),
    );
  }
}
