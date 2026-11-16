import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/kitchen_provider.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_icon_sizes.dart';
import '../../../config/app_routes.dart';
import '../../../core/extensions/responsive_context_extension.dart';
import '../../../core/widgets/grocery_item_card.dart';
import '../../../core/widgets/app_button.dart';
import '../views/kitchen_item_detail_view.dart';

class StorageZonePanel extends StatelessWidget {
  final String zone;

  const StorageZonePanel({super.key, required this.zone});

  @override
  Widget build(BuildContext context) {
    final kitchen = context.watch<KitchenProvider>();
    final items = kitchen.items
        .where((i) => i.storageZone.toLowerCase() == zone.toLowerCase())
        .toList();

    // Limit width on large screens/tablets
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 550),
        height: context.screenSize.height * 0.65,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.panel(context)),
          ),
          border: const Border(
            top: BorderSide(color: AppColors.cardBorder, width: 1.5),
          ),
        ),
        child: Column(
          children: [
            // Drag handle
            AppGap.sm(context),
            Container(
              width: context.scaleWidth(40.0),
              height: 4.0,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2.0),
              ),
            ),
            AppGap.md(context),

            // Header details
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md(context)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${zone.toUpperCase()} ZONE',
                        style: AppTextStyles.headingMedium(
                          context,
                        ).copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${items.length} items total',
                        style: AppTextStyles.caption(
                          context,
                        ).copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: AppIconSizes.md(context),
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            AppGap.sm(context),
            const Divider(),

            // Scrollable grocery list
            Expanded(
              child: items.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.md(context),
                        vertical: AppSpacing.sm(context),
                      ),
                      itemCount: items.length,
                      itemBuilder: (ctx, index) {
                        final item = items[index];
                        return GroceryItemCard(
                          item: item,
                          onTap: () {
                            // Close zone panel and navigate to premium details page
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    KitchenItemDetailView(item: item),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(AppSpacing.lg(context)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_basket_outlined,
            size: AppIconSizes.lg(context) * 2.0,
            color: AppColors.textSecondary,
          ),
          AppGap.md(context),
          Text(
            'This storage zone is empty',
            style: AppTextStyles.headingSmall(context),
          ),
          AppGap.xs(context),
          Text(
            'Store items here to monitor their freshness.',
            style: AppTextStyles.bodyMedium(context),
            textAlign: TextAlign.center,
          ),
          AppGap.lg(context),
          SizedBox(
            width: context.scaleWidth(200.0),
            child: AppButton(
              text: 'Add Item to $zone',
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  AppRoutes.manualAdd,
                  arguments: zone,
                );
              },
              style: AppButtonStyle.outline,
            ),
          ),
        ],
      ),
    );
  }
}
