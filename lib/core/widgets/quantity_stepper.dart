import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/app_spacing.dart';
import '../../config/app_radius.dart';
import '../../config/app_icon_sizes.dart';
import '../../core/extensions/responsive_context_extension.dart';

class QuantityStepper extends StatelessWidget {
  final double quantity;
  final String unit;
  final ValueChanged<double> onChanged;
  final double step;
  final double min;
  final double max;

  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.unit,
    required this.onChanged,
    this.step = 0.5,
    this.min = 0.5,
    this.max = 999.0,
  });

  @override
  Widget build(BuildContext context) {
    final double paddingH = context.scaleWidth(10.0);
    final double paddingV = context.scaleHeight(4.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: quantity <= min
                ? null
                : () {
                    final val = (quantity - step).clamp(min, max);
                    onChanged(double.parse(val.toStringAsFixed(2)));
                  },
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: Icon(
                Icons.remove_circle_outline, 
                size: AppIconSizes.md(context),
                color: quantity <= min ? AppColors.textHint : AppColors.primary,
              ),
            ),
          ),
        ),
        AppGap.xs(context),
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.chip(context) * 0.75),
          onTap: () => _showManualInputDialog(context),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.chip(context) * 0.75),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Text(
              '$quantity $unit',
              style: AppTextStyles.labelMedium(context).copyWith(color: AppColors.textPrimary),
            ),
          ),
        ),
        AppGap.xs(context),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: quantity >= max
                ? null
                : () {
                    final val = (quantity + step).clamp(min, max);
                    onChanged(double.parse(val.toStringAsFixed(2)));
                  },
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: Icon(
                Icons.add_circle_outline, 
                size: AppIconSizes.md(context),
                color: quantity >= max ? AppColors.textHint : AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showManualInputDialog(BuildContext context) {
    final controller = TextEditingController(text: quantity.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card(ctx)),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        title: Text('Enter Quantity ($unit)', style: AppTextStyles.headingMedium(ctx)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. 2.5',
          ),
          style: AppTextStyles.bodyLarge(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppTextStyles.labelMedium(ctx).copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final double? val = double.tryParse(controller.text);
              if (val != null && val >= min && val <= max) {
                onChanged(double.parse(val.toStringAsFixed(2)));
              }
              Navigator.pop(ctx);
            },
            child: Text('Confirm', style: AppTextStyles.labelMedium(ctx).copyWith(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}
