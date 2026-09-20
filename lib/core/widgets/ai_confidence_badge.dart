import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/app_radius.dart';
import '../../config/app_icon_sizes.dart';
import '../../core/extensions/responsive_context_extension.dart';

class AIConfidenceBadge extends StatelessWidget {
  final String confidence;

  const AIConfidenceBadge({super.key, required this.confidence});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (confidence.toLowerCase()) {
      case 'high':
        color = AppColors.success;
        break;
      case 'medium':
        color = AppColors.warning;
        break;
      case 'low':
      default:
        color = AppColors.danger;
        break;
    }

    final double paddingH = context.scaleWidth(8.0);
    final double paddingV = context.scaleHeight(4.0);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      decoration: BoxDecoration(
        color: color.withValues(alpha :0.12),
        borderRadius: BorderRadius.circular(AppRadius.chip(context)),
        border: Border.all(color: color.withValues(alpha :0.3), width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: AppIconSizes.sm(context) * 0.6, color: color),
          const SizedBox(width: 4), // small relative spacing
          Text(
            confidence,
            style: AppTextStyles.caption(context).copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
