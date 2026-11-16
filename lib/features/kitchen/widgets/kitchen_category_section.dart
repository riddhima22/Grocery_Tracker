import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_text_styles.dart';
import '../providers/kitchen_provider.dart';
import 'kitchen_category_card.dart';

class _CategoryItem {
  final String key;
  final String name;
  final IconData icon;

  const _CategoryItem({
    required this.key,
    required this.name,
    required this.icon,
  });
}

class KitchenCategorySection extends StatefulWidget {
  final KitchenProvider kitchen;
  final ValueChanged<String> onCategoryTap;

  const KitchenCategorySection({
    super.key,
    required this.kitchen,
    required this.onCategoryTap,
  });

  @override
  State<KitchenCategorySection> createState() => _KitchenCategorySectionState();
}

class _KitchenCategorySectionState extends State<KitchenCategorySection> {
  bool _isExpanded = false;

  static const List<_CategoryItem> _categories = [
    _CategoryItem(key: 'fridge', name: 'Fridge', icon: Icons.kitchen_rounded),
    _CategoryItem(key: 'pantry', name: 'Pantry', icon: Icons.all_inbox_rounded),
    _CategoryItem(
      key: 'basket',
      name: 'Basket',
      icon: Icons.shopping_basket_rounded,
    ),
    _CategoryItem(key: 'spice', name: 'Spices', icon: Icons.grass_rounded),
    _CategoryItem(
      key: 'cabinet',
      name: 'Cabinet',
      icon: Icons.door_sliding_rounded,
    ),
    _CategoryItem(
      key: 'counter',
      name: 'Counter',
      icon: Icons.table_restaurant_rounded,
    ),
    _CategoryItem(key: 'freezer', name: 'Freezer', icon: Icons.ac_unit_rounded),
  ];

  CategoryStatus _resolveStatus(String zoneKey) {
    final items = widget.kitchen.items
        .where((i) => i.storageZone.toLowerCase() == zoneKey.toLowerCase())
        .toList();

    if (items.isEmpty) {
      return CategoryStatus.empty;
    }
    if (items.any((i) => i.status == 'expired')) {
      return CategoryStatus.expired;
    }
    if (items.any((i) => i.status == 'expiring')) {
      return CategoryStatus.expiringSoon;
    }
    return CategoryStatus.allGood;
  }

  int _resolveCount(String zoneKey) {
    return widget.kitchen.items
        .where((i) => i.storageZone.toLowerCase() == zoneKey.toLowerCase())
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final visibleCategories = _isExpanded
        ? _categories
        : _categories.take(2).toList();
    final remainingCount = _categories.length - 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md(context),
            vertical: AppSpacing.xs(context),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Kitchen',
                      style: AppTextStyles.headingMedium(
                        context,
                      ).copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Storage zones & freshness overview',
                      style: AppTextStyles.caption(
                        context,
                      ).copyWith(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isExpanded = !_isExpanded);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isExpanded
                            ? 'Show Less'
                            : 'View All ($remainingCount)',
                        style: AppTextStyles.labelMedium(context).copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        _isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.arrow_forward_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        AppGap.xs(context),

        // Animated Category Grid
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md(context)),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive aspect ratio around 2.1
              final cardWidth = (constraints.maxWidth - 16.0) / 2.0;
              final childAspectRatio = (cardWidth / 78.0).clamp(1.95, 2.3);

              return AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visibleCategories.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16.0,
                    mainAxisSpacing: 16.0,
                    childAspectRatio: childAspectRatio,
                  ),
                  itemBuilder: (context, index) {
                    final cat = visibleCategories[index];
                    return KitchenCategoryCard(
                      key: ValueKey(cat.key),
                      name: cat.name,
                      icon: cat.icon,
                      count: _resolveCount(cat.key),
                      status: _resolveStatus(cat.key),
                      onTap: () => widget.onCategoryTap(cat.key),
                    );
                  },
                ),
              );
            },
          ),
        ),
        AppGap.sm(context),

        // Bottom Expansion Action Pill
        Center(
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isExpanded = !_isExpanded);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6.0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isExpanded ? 'Show Less' : 'View All Categories',
                    style: AppTextStyles.labelMedium(context).copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.arrow_forward_rounded,
                    size: 15,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
