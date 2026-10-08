import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/app_radius.dart';
import '../../core/extensions/responsive_context_extension.dart';
import '../utils/date_helpers.dart';

class ExpiryBadge extends StatelessWidget {
  final DateTime? expiryDate;
  final DateTime? estimatedDate;
  final bool isEstimated;

  const ExpiryBadge({
    super.key,
    this.expiryDate,
    this.estimatedDate,
    this.isEstimated = false,
  });

  @override
  Widget build(BuildContext context) {
    final double paddingH = context.scaleWidth(8.0);
    final double paddingV = context.scaleHeight(4.0);

    final effectiveDate = expiryDate ?? estimatedDate;
    final bool estimated = isEstimated || (expiryDate == null && estimatedDate != null);

    if (effectiveDate == null) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadius.chip(context)),
        ),
        child: Text(
          'No Expiry',
          style: AppTextStyles.caption(context).copyWith(
            color: AppColors.info,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    final badgeInfo = DateHelpers.formatExpiryBadge(effectiveDate, isEstimated: estimated);
    final badgeColor = badgeInfo.color;
    final label = badgeInfo.label;

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
