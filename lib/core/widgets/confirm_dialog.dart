import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/app_radius.dart';

class ConfirmDialog extends StatelessWidget {
  final String title;
  final String content;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback? onConfirm;
  final bool isDestructive;

  const ConfirmDialog({
    super.key,
    required this.title,
    required this.content,
    required this.confirmLabel,
    required this.cancelLabel,
    this.onConfirm,
    this.isDestructive = false,
  });

  /// Displays the confirmation dialog and returns true ONLY if user confirmed.
  /// Returns false on cancel or dismissal.
  static Future<bool> show({
    required BuildContext context,
    String title = 'Delete Confirmation',
    String content =
        'Are you sure you want to delete this item? This action cannot be undone.',
    String confirmLabel = 'Delete',
    String cancelLabel = 'Cancel',
    bool isDestructive = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ConfirmDialog(
        title: title,
        content: content,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        isDestructive: isDestructive,
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      title: Text(title, style: AppTextStyles.headingMedium(context)),
      content: Text(
        content,
        style: AppTextStyles.bodyMedium(
          context,
        ).copyWith(color: AppColors.textPrimary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            cancelLabel,
            style: AppTextStyles.labelMedium(
              context,
            ).copyWith(color: AppColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context, true);
            onConfirm?.call();
          },
          child: Text(
            confirmLabel,
            style: AppTextStyles.labelMedium(context).copyWith(
              color: isDestructive ? AppColors.danger : AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
