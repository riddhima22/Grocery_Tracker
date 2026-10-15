import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/app_spacing.dart';
import '../../config/app_radius.dart';

class AppLoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final String? message;
  final Widget child;

  const AppLoadingOverlay({
    super.key,
    required this.isLoading,
    this.message,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: AppColors.overlay,
            child: Center(
              child: Card(
                color: AppColors.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card(context)),
                  side: const BorderSide(color: AppColors.cardBorder),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg(context),
                    vertical: AppSpacing.md(context),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppColors.primary),
                      if (message != null) ...[
                        AppGap.md(context),
                        Text(
                          message!,
                          style: AppTextStyles.labelMedium(context),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
