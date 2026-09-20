import 'package:flutter/material.dart';
import 'app_button.dart';
import '../../config/app_text_styles.dart';
import '../../config/app_spacing.dart';
import '../../config/app_icon_sizes.dart';

class AppRetryState extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  const AppRetryState({
    super.key,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg(context)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: AppIconSizes.lg(context) * 2.0,
              color: Colors.redAccent,
            ),
            AppGap.md(context),
            Text(
              'Oops! Load Failed',
              style: AppTextStyles.headingLarge(context),
              textAlign: TextAlign.center,
            ),
            AppGap.xs(context),
            Text(
              errorMessage,
              style: AppTextStyles.bodyMedium(context),
              textAlign: TextAlign.center,
            ),
            AppGap.lg(context),
            AppButton(
              text: 'Retry Attempt',
              onPressed: onRetry,
              style: AppButtonStyle.outline,
            ),
          ],
        ),
      ),
    );
  }
}
