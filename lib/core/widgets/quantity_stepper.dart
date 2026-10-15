import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/app_spacing.dart';
import '../../config/app_radius.dart';
import '../../config/app_icon_sizes.dart';
import '../../core/extensions/responsive_context_extension.dart';
import '../services/unit_classification_service.dart';

class QuantityStepper extends StatelessWidget {
  final double quantity;
  final String unit;
  final ValueChanged<double> onChanged;
  final ValueChanged<String>? onUnitChanged;
  final double? step;
  final double? min;
  final double max;

  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.unit,
    required this.onChanged,
    this.onUnitChanged,
    this.step,
    this.min,
    this.max = 9999.0,
  });

  double get _resolvedStep {
    if (step != null) return step!;
    final u = UnitClassificationService.normalizeUnit(unit);
    if (u == 'g' || u == 'ml') return 50.0;
    if (u == 'pcs' || UnitClassificationService.unitCategories[u] == UnitClassificationService.categoryPackage) return 1.0;
    return 0.5;
  }

  double get _resolvedMin {
    if (min != null) return min!;
    final u = UnitClassificationService.normalizeUnit(unit);
    if (u == 'g' || u == 'ml') return 10.0;
    if (u == 'pcs' || UnitClassificationService.unitCategories[u] == UnitClassificationService.categoryPackage) return 1.0;
    return 0.1;
  }

  @override
  Widget build(BuildContext context) {
    final double paddingH = context.scaleWidth(10.0);
    final double paddingV = context.scaleHeight(4.0);
    final currentStep = _resolvedStep;
    final currentMin = _resolvedMin;

    final qtyDisplay = quantity % 1 == 0 ? quantity.toInt().toString() : quantity.toString();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: quantity <= currentMin
                ? null
                : () {
                    final val = (quantity - currentStep).clamp(currentMin, max);
                    onChanged(double.parse(val.toStringAsFixed(2)));
                  },
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: Icon(
                Icons.remove_circle_outline, 
                size: AppIconSizes.md(context),
                color: quantity <= currentMin ? AppColors.textHint : AppColors.primary,
              ),
            ),
          ),
        ),
        AppGap.xs(context),
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.chip(context) * 0.75),
          onTap: () => _showQuantityAndUnitDialog(context),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.chip(context) * 0.75),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$qtyDisplay $unit',
                  style: AppTextStyles.labelMedium(context).copyWith(color: AppColors.textPrimary),
                ),
                if (onUnitChanged != null) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.textSecondary),
                ],
              ],
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
                    final val = (quantity + currentStep).clamp(currentMin, max);
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

  void _showQuantityAndUnitDialog(BuildContext context) {
    final controller = TextEditingController(
      text: quantity % 1 == 0 ? quantity.toInt().toString() : quantity.toString(),
    );
    String selectedUnit = unit;
    final compatibleUnits = UnitClassificationService.getCompatibleUnits(unit);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card(ctx)),
            side: const BorderSide(color: AppColors.cardBorder),
          ),
          title: Text('Edit Quantity & Unit', style: AppTextStyles.headingMedium(ctx)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quantity Value', style: AppTextStyles.caption(ctx).copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'e.g. 500 or 1.5',
                  ),
                  style: AppTextStyles.bodyLarge(ctx),
                ),
                if (onUnitChanged != null) ...[
                  const SizedBox(height: 16),
                  Text('Unit of Measurement', style: AppTextStyles.caption(ctx).copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: compatibleUnits.map((u) {
                      final isSel = u.toLowerCase() == selectedUnit.toLowerCase();
                      return ChoiceChip(
                        label: Text(u),
                        selected: isSel,
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.card,
                        labelStyle: TextStyle(
                          color: isSel ? Colors.white : AppColors.textPrimary,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (val) {
                          if (val && u != selectedUnit) {
                            // Smart conversion of the input number if compatible
                            final currentNum = double.tryParse(controller.text);
                            if (currentNum != null) {
                              final converted = UnitClassificationService.convertQuantity(currentNum, selectedUnit, u);
                              if (converted != null) {
                                controller.text = converted % 1 == 0 ? converted.toInt().toString() : converted.toString();
                              }
                            }
                            setModalState(() {
                              selectedUnit = u;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: AppTextStyles.labelMedium(ctx).copyWith(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                final double? val = double.tryParse(controller.text);
                if (val != null && val >= _resolvedMin && val <= max) {
                  onChanged(double.parse(val.toStringAsFixed(3)));
                  if (onUnitChanged != null && selectedUnit != unit) {
                    onUnitChanged!(selectedUnit);
                  }
                }
                Navigator.pop(ctx);
              },
              child: Text('Confirm', style: AppTextStyles.labelMedium(ctx).copyWith(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
  }
}
