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
import '../utils/date_helpers.dart';

class ScanCandidateCard extends StatelessWidget {
  final ScanCandidateModel candidate;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectedChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final ValueChanged<double>? onQuantityChanged;
  final ValueChanged<DateTime>? onExpiryChanged;

  const ScanCandidateCard({
    super.key,
    required this.candidate,
    required this.isSelected,
    this.onSelectedChanged,
    this.onEdit,
    this.onRemove,
    this.onQuantityChanged,
    this.onExpiryChanged,
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
            AppGap.xs(context),
            Text(
              candidate.description.isNotEmpty
                  ? candidate.description
                  : 'Detected ${candidate.category.toLowerCase()} item for ${candidate.storageZone.toLowerCase()} storage.',
              style: AppTextStyles.bodyMedium(context).copyWith(
                color: candidate.description.isNotEmpty ? AppColors.textPrimary : AppColors.textSecondary,
                fontStyle: candidate.description.isNotEmpty ? FontStyle.normal : FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            AppGap.sm(context),
            const Divider(),
            AppGap.xxs(context),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Storage: ${candidate.storageZone.toUpperCase()}',
                        style: AppTextStyles.caption(context).copyWith(color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () async {
                          final initial = candidate.effectiveExpiryDate ?? DateTime.now().add(const Duration(days: 7));
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: initial,
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                          );
                          if (picked != null && onExpiryChanged != null) {
                            onExpiryChanged!(picked);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today_outlined, 
                                size: 13, 
                                color: candidate.effectiveExpiryDate != null ? AppColors.primary : AppColors.warning,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Builder(
                                  builder: (context) {
                                    final effective = candidate.effectiveExpiryDate;
                                    if (effective == null) {
                                      return Text(
                                        'Date: Set Date',
                                        style: AppTextStyles.caption(context).copyWith(
                                          color: AppColors.warning,
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      );
                                    }
                                    final bool isEstimated = candidate.isExpiryEstimated || candidate.expiryDate == null;
                                    final shelfText = DateHelpers.formatCandidateShelfText(effective, isEstimated: isEstimated);
                                    final String labelPrefix = isEstimated ? 'Est. Consume' : 'Expiry';
                                    return Text(
                                      '$labelPrefix: ${effective.toString().substring(0, 10)} ($shelfText)',
                                      style: AppTextStyles.caption(context).copyWith(
                                        color: isEstimated ? AppColors.textSecondary : AppColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline,
                                        decorationColor: AppColors.primary.withValues(alpha: 0.5),
                                      ),
                                      maxLines: 2,
                                      softWrap: true,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    ],
                  ),
                ),
                AppGap.xs(context),
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
