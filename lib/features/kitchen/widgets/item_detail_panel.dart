import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/kitchen_provider.dart';
import '../../../data/models/grocery_model.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_icon_sizes.dart';
import '../../../config/category_icon_mapper.dart';
import '../../../core/extensions/responsive_context_extension.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/expiry_badge.dart';

class ItemDetailPanel extends StatefulWidget {
  final GroceryModel item;

  const ItemDetailPanel({super.key, required this.item});

  @override
  State<ItemDetailPanel> createState() => _ItemDetailPanelState();
}

class _ItemDetailPanelState extends State<ItemDetailPanel> {
  late double _consumeQty;

  @override
  void initState() {
    super.initState();
    _consumeQty = widget.item.quantity;
  }

  String _getStorageTip() {
    switch (widget.item.storageZone.toLowerCase()) {
      case 'fridge':
        return 'Store in the middle shelf to maintain even temperature. Seal packaged items securely.';
      case 'freezer':
        return 'Ensure freezer temperature is below -18°C. Store in airtight freezer-safe bags.';
      case 'pantry':
        return 'Keep in a cool, dark, and dry cupboard away from direct sunlight.';
      case 'counter':
        return 'Leave uncovered on the counter. Keep away from ripening bananas.';
      case 'basket':
        return 'Excellent storage location for root vegetables like onions and potatoes. Keep separate to avoid sprouting.';
      case 'spice':
        return 'Keep sealed in airtight jars. Avoid storing above the stove steam.';
      default:
        return 'Store appropriately to maximize freshness and flavor.';
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => ConfirmDialog(
        title: 'Delete Item',
        content: 'Are you sure you want to delete ${widget.item.name} from your pantry?',
        confirmLabel: 'Delete',
        cancelLabel: 'Cancel',
        isDestructive: true,
        onConfirm: () async {
          final success = await context.read<KitchenProvider>().deleteItem(widget.item.id);
          if (success && mounted) {
            Navigator.pop(context); // close bottom sheet
          }
        },
      ),
    );
  }

  void _showConsumeQtySelector() {
    final controller = TextEditingController(text: _consumeQty.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card(ctx)),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        title: Text('Consume Quantity (${widget.item.unit})', style: AppTextStyles.headingMedium(ctx)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Max: ${widget.item.quantity}',
          ),
          style: AppTextStyles.bodyLarge(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppTextStyles.labelMedium(ctx).copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              final double? val = double.tryParse(controller.text);
              if (val != null && val > 0 && val <= widget.item.quantity) {
                Navigator.pop(ctx);
                final success = await context.read<KitchenProvider>().consumeItem(widget.item.id, quantity: val);
                if (success && mounted) {
                  Navigator.pop(context); // close bottom sheet
                }
              }
            },
            child: Text('Confirm', style: AppTextStyles.labelMedium(ctx).copyWith(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _consumeAll() async {
    final success = await context.read<KitchenProvider>().consumeItem(widget.item.id);
    if (success && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _markWasted() async {
    final success = await context.read<KitchenProvider>().wasteItem(widget.item.id);
    if (success && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveDate = widget.item.effectiveExpiryDate;
    final int? daysLeft = effectiveDate?.difference(DateTime.now()).inDays;
    final int totalDays = effectiveDate != null
        ? effectiveDate.difference(widget.item.purchaseDate).inDays
        : 0;
    final int elapsedDays = DateTime.now().difference(widget.item.purchaseDate).inDays;
    final double timelineProgress = totalDays > 0
        ? (elapsedDays / totalDays).clamp(0.0, 1.0)
        : (daysLeft != null && daysLeft <= 0 ? 1.0 : 0.0);

    return Center(


      child: Container(
        constraints: const BoxConstraints(maxWidth: 550),
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md(context),
          vertical: AppSpacing.sm(context),
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.panel(context))),
          border: const Border(top: BorderSide(color: AppColors.cardBorder, width: 1.5)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: context.scaleWidth(40.0),
                  height: 4.0,
                  decoration: BoxDecoration(
                    color: AppColors.cardBorder,
                    borderRadius: BorderRadius.circular(2.0),
                  ),
                ),
              ),
              AppGap.md(context),
              
              // Icon and details
              Row(
                children: [
                  Container(
                    width: context.scaleWidth(64.0),
                    height: context.scaleWidth(64.0),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(AppRadius.card(context)),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Center(
                      child: Icon(
                        CategoryIconMapper.fromKey(widget.item.iconKey),
                        size: AppIconSizes.lg(context),
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  AppGap.md(context),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.item.name, style: AppTextStyles.headingLarge(context)),
                        if (widget.item.brand.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.item.brand,
                            style: AppTextStyles.bodyMedium(context).copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: context.scaleWidth(8.0),
                                vertical: context.scaleHeight(4.0),
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(AppRadius.chip(context) * 0.75),
                              ),
                              child: Text(
                                widget.item.storageZone.toUpperCase(),
                                style: AppTextStyles.caption(context).copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                              ),
                            ),
                            AppGap.xs(context),
                            ExpiryBadge(
                              expiryDate: widget.item.expiryDate,
                              estimatedDate: widget.item.estimatedConsumptionDate ?? widget.item.predictedExpiry,
                              isEstimated: widget.item.isExpiryEstimated,
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                ],
              ),
              AppGap.md(context),
              const Divider(),
              AppGap.sm(context),
              
              // Description
              if (widget.item.description.isNotEmpty) ...[
                Text('Description', style: AppTextStyles.labelMedium(context)),
                const SizedBox(height: 6),
                Text(
                  widget.item.description,
                  style: AppTextStyles.bodyLarge(context).copyWith(color: AppColors.textSecondary),
                ),
                AppGap.md(context),
              ],

              // Expiry progress timeline
              if (effectiveDate != null) ...[
                Text('Freshness Timeline', style: AppTextStyles.labelMedium(context)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Purchased', style: AppTextStyles.caption(context)),
                    Text(
                      widget.item.isExpiryEstimated ? 'Estimated Date' : 'Expiry Date',
                      style: AppTextStyles.caption(context),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.chip(context) * 0.5),
                  child: LinearProgressIndicator(
                    value: timelineProgress,
                    backgroundColor: AppColors.card,
                    color: (daysLeft != null && daysLeft <= 3) ? AppColors.danger : AppColors.success,

                    minHeight: 8.0,
                  ),
                ),
                AppGap.md(context),
              ],


              // AI Storage Tips
              Container(
                padding: EdgeInsets.all(AppSpacing.sm(context)),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.card(context) * 0.75),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.tips_and_updates_outlined, color: AppColors.primary, size: AppIconSizes.md(context)),
                    AppGap.sm(context),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Storage Advice', style: AppTextStyles.labelMedium(context).copyWith(color: AppColors.primary)),
                          const SizedBox(height: 4),
                          Text(
                            _getStorageTip(),
                            style: AppTextStyles.bodySmall(context).copyWith(color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              AppGap.lg(context),
              
              // Actions
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      text: 'Consume Portion',
                      onPressed: _showConsumeQtySelector,
                      style: AppButtonStyle.outline,
                    ),
                  ),
                  AppGap.sm(context),
                  Expanded(
                    child: AppButton(
                      text: 'Mark Consumed',
                      onPressed: _consumeAll,
                    ),
                  ),
                ],
              ),
              AppGap.xs(context),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      text: 'Mark Wasted',
                      onPressed: _markWasted,
                      style: AppButtonStyle.secondary,
                    ),
                  ),
                  AppGap.sm(context),
                  Expanded(
                    child: AppButton(
                      text: 'Delete Item',
                      onPressed: _confirmDelete,
                      style: AppButtonStyle.danger,
                    ),
                  ),
                ],
              ),
              AppGap.sm(context),
            ],
          ),
        ),
      ),
    );
  }
}
