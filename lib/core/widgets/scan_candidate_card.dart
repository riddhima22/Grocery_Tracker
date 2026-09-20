import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/app_spacing.dart';
import '../../config/app_radius.dart';
import '../../config/app_icon_sizes.dart';
import '../../config/category_icon_mapper.dart';
import '../../data/models/scan_candidate_model.dart';
import 'ai_confidence_badge.dart';
import 'quantity_stepper.dart';

class ScanCandidateCard extends StatelessWidget {
  final ScanCandidateModel candidate;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectedChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final ValueChanged<double>? onQuantityChanged;

  const ScanCandidateCard({
    super.key,
    required this.candidate,
    required this.isSelected,
    this.onSelectedChanged,
    this.onEdit,
    this.onRemove,
    this.onQuantityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final double cardPadding = AppSpacing.sm(context);

    return Card(
      color: isSelected ? AppColors.card : AppColors.card.withValues(alpha: 0.4),
      margin: EdgeInsets.symmetric(
        vertical: AppSpacing.xxs(context),
        horizontal: AppSpacing.xxs(context) * 0.5,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        side: BorderSide(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.5) : AppColors.cardBorder,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: isSelected,
                  onChanged: onSelectedChanged,
                  activeColor: AppColors.primary,
                ),
                Container(
                  width: AppSpacing.xxl(context) * 0.85,
                  height: AppSpacing.xxl(context) * 0.85,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card(context) * 0.6),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Center(
                    child: Icon(
                      CategoryIconMapper.fromKey(candidate.iconKey),
                      size: AppIconSizes.md(context),
                      color: AppColors.primary,
                    ),
                  ),
                ),
                AppGap.sm(context),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.name,
                        style: AppTextStyles.labelMedium(context).copyWith(fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (candidate.brand.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          candidate.brand,
                          style: AppTextStyles.bodySmall(context).copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                AppGap.xs(context),
                AIConfidenceBadge(confidence: candidate.confidence),
              ],
            ),
            if (candidate.description.isNotEmpty) ...[
              AppGap.xs(context),
              Text(
                candidate.description,
                style: AppTextStyles.bodyMedium(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            AppGap.sm(context),
            const Divider(),
            AppGap.xxs(context),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Storage: ${candidate.storageZone.toUpperCase()}',
                      style: AppTextStyles.caption(context).copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Expiry: ${candidate.expiryDate != null ? candidate.expiryDate.toString().substring(0, 10) : "Not Visible"}',
                      style: AppTextStyles.caption(context).copyWith(
                        color: candidate.expiryDate != null ? AppColors.textPrimary : AppColors.warning,
                      ),
                    ),
                  ],
                ),
                if (onQuantityChanged != null)
                  QuantityStepper(
                    quantity: candidate.quantity,
                    unit: candidate.unit,
                    onChanged: onQuantityChanged!,
                    step: candidate.unit.toLowerCase() == 'pcs' ? 1.0 : 0.5,
                    min: candidate.unit.toLowerCase() == 'pcs' ? 1.0 : 0.1,
                  ),
              ],
            ),
            AppGap.xs(context),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onEdit != null)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: Icon(Icons.edit_outlined, size: AppIconSizes.sm(context), color: AppColors.primary),
                    label: Text('Edit', style: AppTextStyles.caption(context).copyWith(color: AppColors.primary)),
                  ),
                if (onRemove != null)
                  TextButton.icon(
                    onPressed: onRemove,
                    icon: Icon(Icons.delete_outline, size: AppIconSizes.sm(context), color: AppColors.danger),
                    label: Text('Remove', style: AppTextStyles.caption(context).copyWith(color: AppColors.danger)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
