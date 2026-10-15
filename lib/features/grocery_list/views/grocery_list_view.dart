import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/grocery_list_provider.dart';
import '../../kitchen/providers/kitchen_provider.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_icon_sizes.dart';
import '../../../config/app_text_styles.dart';
import '../../../config/app_routes.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_retry_state.dart';
import '../../../core/services/unit_classification_service.dart';
import '../../../core/extensions/responsive_context_extension.dart';

class GroceryListView extends StatefulWidget {
  const GroceryListView({super.key});

  @override
  State<GroceryListView> createState() => _GroceryListViewState();
}

class _GroceryListViewState extends State<GroceryListView> {
  final _addItemController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GroceryListProvider>().fetchCurrentList();
    });
  }

  @override
  void dispose() {
    _addItemController.dispose();
    super.dispose();
  }

  Future<void> _addManualItem() async {
    final name = _addItemController.text.trim();
    if (name.isEmpty) return;

    final classified = UnitClassificationService.classifyProduct(
      productName: name,
    );
    final provider = context.read<GroceryListProvider>();
    final success = await provider.addItem(
      name,
      classified.quantity,
      classified.unit,
    );
    if (!mounted) return;
    if (success) {
      _addItemController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final listProvider = context.watch<GroceryListProvider>();

    return AppScaffold(
      isLoading: listProvider.isLoading,
      appBar: AppBar(
        title: Text(
          'Smart Grocery List',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.bold,
            fontSize: context.scaleFont(20.0),
          ),
        ),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Smart Restock Finished Items',
            color: AppColors.primary,
            onPressed: () async {
              await listProvider.generateSuggestions();
              if (context.mounted && listProvider.errorMessage == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Smart grocery list updated with restock items!',
                    ),
                    backgroundColor: AppColors.primary,
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.restaurant_menu_rounded),
            tooltip: 'Expiring Soon Recipes',
            color: AppColors.primary,
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.recipes,
                arguments: {'expiring_only': true},
              );
            },
          ),
        ],
      ),
      body: listProvider.errorMessage != null
          ? AppRetryState(
              errorMessage: listProvider.errorMessage!,
              onRetry: () => listProvider.fetchCurrentList(),
            )
          : Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  children: [
                    // Zero-Waste Recipe Banner (cook from expiring food)
                    _buildZeroWasteBanner(),

                    // Quick Manual Add Bar
                    _buildQuickAddBar(),
                    const Divider(),

                    // Grocery Items lists
                    Expanded(
                      child:
                          listProvider.currentList == null ||
                              listProvider.currentList!.items.isEmpty
                          ? _buildEmptyState(listProvider)
                          : ListView.builder(
                              padding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.md(context),
                                vertical: AppSpacing.sm(context),
                              ),
                              itemCount: listProvider.currentList!.items.length,
                              itemBuilder: (ctx, index) {
                                final item =
                                    listProvider.currentList!.items[index];
                                return _buildShoppingItemCard(
                                  item,
                                  listProvider,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildZeroWasteBanner() {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: AppSpacing.md(context),
        vertical: AppSpacing.xs(context),
      ),
      padding: EdgeInsets.all(AppSpacing.md(context)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.12),
            AppColors.primaryDeep.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.restaurant_menu_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Zero-Waste Recipes',
                        style: AppTextStyles.labelLarge(context).copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'EXPIRING SOON',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: context.scaleFont(8.0),
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Cook with kitchen items near expiry. No extra shopping!',
                  style: AppTextStyles.caption(
                    context,
                  ).copyWith(color: AppColors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.recipes,
                arguments: {'expiring_only': true},
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              visualDensity: VisualDensity.compact,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Cook',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: context.scaleFont(11.0),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_forward_rounded, size: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAddBar() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md(context),
        vertical: AppSpacing.xs(context),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _addItemController,
              decoration: const InputDecoration(
                hintText: 'Quick add item... (e.g. Eggs)',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              style: AppTextStyles.bodyLarge(context),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addManualItem(),
            ),
          ),
          AppGap.sm(context),
          IconButton(
            icon: Icon(
              Icons.add_circle,
              color: AppColors.primary,
              size: AppIconSizes.lg(context) * 1.2,
            ),
            onPressed: _addManualItem,
          ),
        ],
      ),
    );
  }

  Widget _buildShoppingItemCard(dynamic item, GroceryListProvider provider) {
    final double currentQty = item.quantity;
    final bool isSuggested =
        item.reason.isNotEmpty && item.reason != "Added manually";

    return Card(
      color: AppColors.card,
      margin: EdgeInsets.symmetric(vertical: AppSpacing.xxs(context)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card(context) * 0.85),
        side: BorderSide(
          color: item.feedback == 'rejected'
              ? AppColors.danger.withValues(alpha: 0.3)
              : AppColors.cardBorder,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.sm(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: AppTextStyles.headingMedium(context).copyWith(
                          fontSize: 16.0,
                          decoration: item.purchased
                              ? TextDecoration.lineThrough
                              : null,
                          color: item.purchased
                              ? AppColors.textHint
                              : AppColors.textPrimary,
                        ),
                      ),
                      if (isSuggested) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.reason,
                          style: AppTextStyles.caption(
                            context,
                          ).copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),

                // Stepper quantity controls
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (currentQty > 0.5) {
                          provider.updateItemQuantity(
                            item.id,
                            currentQty - 0.5,
                          );
                        }
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10.0,
                          vertical: 8.0,
                        ),
                        child: Icon(
                          Icons.remove_circle_outline,
                          size: AppIconSizes.sm(context),
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$currentQty ${item.unit}',
                      style: AppTextStyles.labelMedium(
                        context,
                      ).copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        provider.updateItemQuantity(item.id, currentQty + 0.5);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10.0,
                          vertical: 8.0,
                        ),
                        child: Icon(
                          Icons.add_circle_outline,
                          size: AppIconSizes.sm(context),
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Suggestion Feedback row (using Wrap to prevent overflow on small screens)
            if (isSuggested && item.feedback == 'pending') ...[
              AppGap.sm(context),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  Text(
                    'Replenish Suggestion? ',
                    style: AppTextStyles.caption(
                      context,
                    ).copyWith(color: AppColors.textHint),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: () =>
                            provider.setItemFeedback(item.id, 'rejected'),
                        icon: Icon(
                          Icons.close,
                          size: AppIconSizes.sm(context) * 0.8,
                          color: AppColors.danger,
                        ),
                        label: Text(
                          'Reject',
                          style: AppTextStyles.caption(
                            context,
                          ).copyWith(color: AppColors.danger),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () =>
                            provider.setItemFeedback(item.id, 'accepted'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check,
                                size: AppIconSizes.sm(context) * 0.8,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Accept',
                                style: AppTextStyles.caption(context).copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],

            // Mark Purchased Action
            if (item.feedback != 'rejected') ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final success = await provider.markItemPurchased(item.id);
                    if (success && mounted) {
                      // refresh kitchen inventory list in background
                      context.read<KitchenProvider>().fetchKitchenItems();
                    }
                  },
                  icon: Icon(
                    Icons.shopping_cart_checkout,
                    size: AppIconSizes.sm(context),
                    color: AppColors.primary,
                  ),
                  label: Text(
                    'Mark Purchased',
                    style: AppTextStyles.labelMedium(
                      context,
                    ).copyWith(color: AppColors.primary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(GroceryListProvider provider) {
    return Padding(
      padding: EdgeInsets.all(AppSpacing.xl(context)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: AppIconSizes.lg(context) * 2.0,
            color: AppColors.textSecondary,
          ),
          AppGap.md(context),
          Text(
            'Your Shopping List is Empty',
            style: AppTextStyles.headingMedium(context),
          ),
          AppGap.xs(context),
          Text(
            'We can analyze your pantry history to suggest replenishment items.',
            style: AppTextStyles.bodyMedium(context),
            textAlign: TextAlign.center,
          ),
          AppGap.lg(context),
          SizedBox(
            width: context.scaleWidth(290.0),
            child: AppButton(
              text: 'Generate Suggestions',
              onPressed: () => provider.generateSuggestions(),
            ),
          ),
        ],
      ),
    );
  }
}
