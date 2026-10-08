import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_text_styles.dart';
import '../../config/app_spacing.dart';
import '../../config/app_radius.dart';
import '../../config/app_icon_sizes.dart';
import '../../config/category_icon_mapper.dart';
import '../../data/models/grocery_model.dart';
import 'expiry_badge.dart';

class GroceryItemCard extends StatelessWidget {
  final GroceryModel item;
  final VoidCallback? onTap;
  final Widget? trailing;

  const GroceryItemCard({
    super.key,
    required this.item,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.card,
      margin: EdgeInsets.symmetric(vertical: AppSpacing.xxs(context)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.sm(context)),
          child: Row(
            children: [
              Container(
                width: AppSpacing.xxl(context), // use xxl (48) or similar token size
                height: AppSpacing.xxl(context),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card(context) * 0.75),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Center(
                  child: Icon(
                    CategoryIconMapper.fromKey(item.iconKey),
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
                      item.name,
                      style: AppTextStyles.labelMedium(context).copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.brand.isNotEmpty) ...[
                      const SizedBox(height: 2), // small relative spacer
                      Text(
                        item.brand,
                        style: AppTextStyles.bodySmall(context).copyWith(color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.description,
                        style: AppTextStyles.caption(context).copyWith(
                          color: AppColors.textSecondary.withValues(alpha: 0.85),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '${item.quantity} ${item.unit} • ${item.storageZone.toUpperCase()}',
                      style: AppTextStyles.bodySmall(context).copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              AppGap.xs(context),
              if (trailing != null)
                trailing!
              else
                ExpiryBadge(
                  expiryDate: item.expiryDate,
                  estimatedDate: item.estimatedConsumptionDate ?? item.predictedExpiry,
                  isEstimated: item.isExpiryEstimated,
                ),

            ],
          ),
        ),
      ),
    );
  }
}
