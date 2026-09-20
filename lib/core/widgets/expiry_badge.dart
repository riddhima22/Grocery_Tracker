import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/app_radius.dart';
import '../../core/extensions/responsive_context_extension.dart';

class ExpiryBadge extends StatelessWidget {
  final DateTime? expiryDate;

  const ExpiryBadge({super.key, this.expiryDate});

  @override
  Widget build(BuildContext context) {
    final double paddingH = context.scaleWidth(8.0);
    final double paddingV = context.scaleHeight(4.0);

    if (expiryDate == null) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadius.chip(context)),
        ),
        child: Text(
          'No Expiry',
          style: AppTextStyles.caption(context).copyWith(color: AppColors.info, fontWeight: FontWeight.bold),
        ),
      );
    }

    final difference = expiryDate!.difference(DateTime.now()).inDays;
    Color badgeColor;
    String label;

    if (difference < 0) {
      badgeColor = AppColors.danger;
      label = 'Expired';
    } else if (difference <= 3) {
      badgeColor = AppColors.warning;
      label = '${difference}d left';
    } else {
      badgeColor = AppColors.success;
      label = '${difference}d left';
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.chip(context)),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3), width: 1.0),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption(context).copyWith(
          color: badgeColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
