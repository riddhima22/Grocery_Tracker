import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/app_icon_sizes.dart';
import '../../config/app_text_styles.dart';

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.xl(context),
          vertical: AppSpacing.xxl(context),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: AppIconSizes.lg(context) * 2.0, // scale icon size
              color: AppColors.textSecondary,
            ),
            AppGap.md(context),
            Text(
              title,
              style: AppTextStyles.headingLarge(context),
              textAlign: TextAlign.center,
            ),
            AppGap.xs(context),
            Text(
              subtitle,
              style: AppTextStyles.bodyMedium(context),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[AppGap.lg(context), action!],
          ],
        ),
      ),
    );
  }
}
