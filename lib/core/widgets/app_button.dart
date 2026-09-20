import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/app_spacing.dart';
import '../../config/app_radius.dart';
import '../../config/app_icon_sizes.dart';
import '../../config/app_dimensions.dart';
import '../../core/extensions/responsive_context_extension.dart';

enum AppButtonStyle { primary, secondary, danger, outline }

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final AppButtonStyle style;
  final IconData? icon;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.style = AppButtonStyle.primary,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null || isLoading;
    final double buttonH = context.scaleHeight(AppDimensions.buttonHeight).clamp(46.0, 56.0);
    final double radius = AppRadius.card(context);
    final EdgeInsets buttonPadding = EdgeInsets.symmetric(
      horizontal: AppSpacing.sm(context),
      vertical: AppSpacing.xs(context),
    );

    switch (style) {
      case AppButtonStyle.outline:
        return SizedBox(
          width: double.infinity,
          height: buttonH,
          child: OutlinedButton(
            onPressed: disabled ? null : onPressed,
            style: OutlinedButton.styleFrom(
              padding: buttonPadding,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(
                color: disabled
                    ? AppColors.cardBorder.withValues(alpha: 0.5)
                    : AppColors.cardBorder,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
              ),
            ),
            child: _buildChild(context, AppColors.textPrimary),
          ),
        );
      case AppButtonStyle.danger:
        return SizedBox(
          width: double.infinity,
          height: buttonH,
          child: ElevatedButton(
            onPressed: disabled ? null : onPressed,
            style: ElevatedButton.styleFrom(
              padding: buttonPadding,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: disabled
                  ? AppColors.danger.withValues(alpha: 0.5)
                  : AppColors.danger,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
              ),
            ),
            child: _buildChild(context, AppColors.white),
          ),
        );
      case AppButtonStyle.secondary:
        return SizedBox(
          width: double.infinity,
          height: buttonH,
          child: ElevatedButton(
            onPressed: disabled ? null : onPressed,
            style: ElevatedButton.styleFrom(
              padding: buttonPadding,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: disabled
                  ? AppColors.card.withValues(alpha: 0.5)
                  : AppColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
                side: const BorderSide(color: AppColors.cardBorder),
              ),
            ),
            child: _buildChild(context, AppColors.textPrimary),
          ),
        );
      case AppButtonStyle.primary:
        return Container(
          width: double.infinity,
          height: buttonH,
          decoration: BoxDecoration(
            gradient: disabled ? null : AppColors.primaryGradient,
            color: disabled ? AppColors.primary.withValues(alpha: 0.5) : null,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: ElevatedButton(
            onPressed: disabled ? null : onPressed,
            style: ElevatedButton.styleFrom(
              padding: buttonPadding,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
              ),
            ),
            child: _buildChild(context, AppColors.white),
          ),
        );
    }
  }

  Widget _buildChild(BuildContext context, Color textColor) {
    if (isLoading) {
      return SizedBox(
        width: AppSpacing.lg(context),
        height: AppSpacing.lg(context),
        child: CircularProgressIndicator(strokeWidth: 2.5, color: textColor),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: AppIconSizes.md(context), color: textColor),
              SizedBox(width: AppSpacing.xs(context)),
            ],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelMedium(
                    context,
                  ).copyWith(
                    color: textColor,
                    fontSize: context.scaleFont(15.0),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
