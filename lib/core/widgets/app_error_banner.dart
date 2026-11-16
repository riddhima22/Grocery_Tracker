import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/app_spacing.dart';
import '../../config/app_radius.dart';
import '../../config/app_icon_sizes.dart';

class AppErrorBanner extends StatelessWidget {
  final String? errorMessage;
  final VoidCallback? onClose;

  const AppErrorBanner({super.key, this.errorMessage, this.onClose});

  @override
  Widget build(BuildContext context) {
    if (errorMessage == null || errorMessage!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md(context),
        vertical: AppSpacing.sm(context),
      ),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.card(context) * 0.75),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: AppIconSizes.md(context),
            color: AppColors.danger,
          ),
          AppGap.sm(context),
          Expanded(
            child: Text(
              errorMessage!,
              style: AppTextStyles.bodyMedium(
                context,
              ).copyWith(color: AppColors.textPrimary),
            ),
          ),
          if (onClose != null) ...[
            AppGap.xs(context),
            IconButton(
              icon: Icon(
                Icons.close,
                size: AppIconSizes.sm(context),
                color: AppColors.textSecondary,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onClose,
            ),
          ],
        ],
      ),
    );
  }
}
