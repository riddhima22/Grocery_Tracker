import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/kitchen_provider.dart';
import '../widgets/storage_zone_panel.dart';
import '../widgets/kitchen_category_section.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_icon_sizes.dart';
import '../../../config/app_constraints.dart';
import '../../../config/app_text_styles.dart';
import '../../../config/kitchen_scene_layout.dart';
import '../../../config/storage_zone_icon_mapper.dart';
import '../../../core/extensions/responsive_context_extension.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/grocery_item_card.dart';
import '../../../core/services/ai_search_service.dart';
import 'kitchen_item_detail_view.dart';
import '../../meals/views/meal_log_view.dart';

class KitchenView extends StatefulWidget {
  const KitchenView({super.key});

  @override
  State<KitchenView> createState() => _KitchenViewState();
}

class _KitchenViewState extends State<KitchenView> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<KitchenProvider>().fetchKitchenItems();
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _openZoneSheet(String zone) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StorageZonePanel(zone: zone),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kitchen = context.watch<KitchenProvider>();
    final double aspect = AppConstraints.kitchenAspectRatio(context);

    return AppScaffold(
      body: Column(
        children: [
          // Top bar
          _buildTopBar(kitchen),

          // Search Box
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md(context)),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(
                  AppRadius.card(context) * 0.8,
                ),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search kitchen items... (e.g. "fruits")',
                  prefixIcon: const Icon(
                    Icons.psychology_outlined,
                    color: AppColors.primary,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchDebounceTimer?.cancel();
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                style: AppTextStyles.bodyMedium(context),
                onChanged: (val) {
                  _searchDebounceTimer?.cancel();
                  _searchDebounceTimer = Timer(
                    const Duration(milliseconds: 250),
                    () {
                      if (mounted) {
                        setState(() {
                          _searchQuery = val;
                        });
                      }
                    },
                  );
                },
              ),
            ),
          ),
          AppGap.sm(context),

          if (_searchQuery.isNotEmpty)
            Expanded(
              child: Builder(
                builder: (context) {
                  final filtered = AISearchService.filter(
                    kitchen.items,
                    _searchQuery,
                  );
                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        'No matching groceries found.',
                        style: AppTextStyles.bodyMedium(
                          context,
                        ).copyWith(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: EdgeInsets.all(AppSpacing.md(context)),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, index) {
                      final item = filtered[index];
                      return GroceryItemCard(
                        item: item,
                        onTap: () {
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
                  );
                },
              ),
            )
          else
            Expanded(
              child: CustomScrollView(
                slivers: [
                  // Canvas stacked kitchen scene inside AspectRatio
                  SliverToBoxAdapter(
                    child: AspectRatio(
                      aspectRatio: aspect,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final double W = constraints.maxWidth;
                          final double H = constraints.maxHeight;

                          return Stack(
                            children: [
                              _buildWallBackground(),
                              _buildWallTiles(H),
                              _buildFloor(H),
                              _buildCountertop(H),

                              // FRIDGE Compartment
                              Positioned(
                                left: W * KitchenSceneLayout.fridgeLeft,
                                top: H * KitchenSceneLayout.fridgeTop,
                                width: W * KitchenSceneLayout.fridgeWidth,
                                height: H * KitchenSceneLayout.fridgeHeight,
                                child: GestureDetector(
                                  onTap: () => _openZoneSheet('fridge'),
                                  child: _FridgeWidget(
                                    count: kitchen.fridgeItems.length,
                                    iconKeys: kitchen.fridgeItems
                                        .map((i) => i.iconKey)
                                        .toList(),
                                    height: H * KitchenSceneLayout.fridgeHeight,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: W * KitchenSceneLayout.fridgePillLeft,
                                top: H * KitchenSceneLayout.fridgePillTop,
                                child: _ZonePill(
                                  icon: Icons.ac_unit_rounded,
                                  label: 'Fridge',
                                  count: kitchen.fridgeItems.length,
                                  onTap: () => _openZoneSheet('fridge'),
                                ),
                              ),

                              // SPICES cabinet
                              Positioned(
                                left: W * KitchenSceneLayout.spicesLeft,
                                top: H * KitchenSceneLayout.spicesTop,
                                width: W * KitchenSceneLayout.spicesWidth,
                                height: H * KitchenSceneLayout.spicesHeight,
                                child: GestureDetector(
                                  onTap: () => _openZoneSheet('spice'),
                                  child: _SpicesCabinet(
                                    count: kitchen.spiceItems.length,
                                    iconKeys: kitchen.spiceItems
                                        .map((i) => i.iconKey)
                                        .toList(),
                                  ),
                                ),
                              ),

                              // PANTRY shelves
                              Positioned(
                                left: W * KitchenSceneLayout.pantryLeft,
                                top: H * KitchenSceneLayout.pantryTop,
                                width: W * KitchenSceneLayout.pantryWidth,
                                height: H * KitchenSceneLayout.pantryHeight,
                                child: GestureDetector(
                                  onTap: () => _openZoneSheet('pantry'),
                                  child: _PantryShelf(
                                    count: kitchen.pantryItems.length,
                                    iconKeys: kitchen.pantryItems
                                        .map((i) => i.iconKey)
                                        .toList(),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: W * KitchenSceneLayout.pantryPillLeft,
                                top: H * KitchenSceneLayout.pantryPillTop,
                                child: _ZonePill(
                                  icon: Icons.all_inbox_rounded,
                                  label: 'Pantry',
                                  count: kitchen.pantryItems.length,
                                  onTap: () => _openZoneSheet('pantry'),
                                ),
                              ),

                              // CABINET doors
                              Positioned(
                                right: W * KitchenSceneLayout.cabinetRight,
                                top: H * KitchenSceneLayout.cabinetTop,
                                width: W * KitchenSceneLayout.cabinetWidth,
                                height: H * KitchenSceneLayout.cabinetHeight,
                                child: GestureDetector(
                                  onTap: () => _openZoneSheet('cabinet'),
                                  child: _CabinetWidget(
                                    count: kitchen.cabinetItems.length,
                                    iconKeys: kitchen.cabinetItems
                                        .map((i) => i.iconKey)
                                        .toList(),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: W * KitchenSceneLayout.cabinetPillRight,
                                top: H * KitchenSceneLayout.cabinetPillTop,
                                child: _ZonePill(
                                  icon: Icons.door_sliding_rounded,
                                  label: 'Cabinet',
                                  count: kitchen.cabinetItems.length,
                                  onTap: () => _openZoneSheet('cabinet'),
                                ),
                              ),

                              // BASKET woven container
                              Positioned(
                                right: W * KitchenSceneLayout.basketRight,
                                bottom: H * KitchenSceneLayout.basketBottom,
                                width: W * KitchenSceneLayout.basketWidth,
                                height: H * KitchenSceneLayout.basketHeight,
                                child: GestureDetector(
                                  onTap: () => _openZoneSheet('basket'),
                                  child: _BasketWidget(
                                    count: kitchen.basketItems.length,
                                    iconKeys: kitchen.basketItems
                                        .map((i) => i.iconKey)
                                        .toList(),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: W * KitchenSceneLayout.basketPillRight,
                                bottom: H * KitchenSceneLayout.basketPillBottom,
                                child: _ZonePill(
                                  icon: Icons.shopping_basket_rounded,
                                  label: 'Basket',
                                  count: kitchen.basketItems.length,
                                  onTap: () => _openZoneSheet('basket'),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                  // Redesigned Modern Kitchen Category Grid Section
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: AppSpacing.sm(context),
                        bottom: AppSpacing.xl(context),
                      ),
                      child: KitchenCategorySection(
                        kitchen: kitchen,
                        onCategoryTap: _openZoneSheet,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar(KitchenProvider kitchen) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md(context),
        vertical: AppSpacing.sm(context),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Storage Management',
                  style: AppTextStyles.headingLarge(context),
                ),
                const SizedBox(height: 2),
                Text(
                  '${kitchen.totalItems} items total • ${kitchen.expiringCount} expiring soon',
                  style: AppTextStyles.caption(
                    context,
                  ).copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MealLogView()),
                  );
                },
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm(context),
                    vertical: AppSpacing.xs(context),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryDark,
                    borderRadius: BorderRadius.circular(
                      AppRadius.chip(context),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.restaurant_menu,
                        size: AppIconSizes.sm(context),
                        color: AppColors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Log Meal',
                        style: AppTextStyles.labelMedium(context).copyWith(
                          color: AppColors.white,
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
    );
  }

  Widget _buildWallBackground() => Positioned.fill(
    child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.35, 0.351, 1.0],
          colors: [
            AppColors.wallTop,
            Color(0xFFE0C898),
            Color(0xFFC8A865),
            AppColors.wallBottom,
          ],
        ),
      ),
    ),
  );

  Widget _buildWallTiles(double H) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: SizedBox(
      height: H * 0.35,
      child: CustomPaint(painter: _TileGridPainter()),
    ),
  );

  Widget _buildFloor(double H) => Positioned(
    bottom: 0,
    left: 0,
    right: 0,
    child: Container(
      height: H * 0.32,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.floorTop, AppColors.floorBottom],
        ),
      ),
      child: CustomPaint(painter: _TileGridPainter(isFloor: true)),
    ),
  );

  Widget _buildCountertop(double H) => Positioned(
    bottom: H * 0.32 - 2.0,
    left: 0,
    right: 0,
    child: Container(
      height: H * 0.08,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.countertopTop, AppColors.countertopBottom],
        ),
        border: Border.symmetric(
          horizontal: BorderSide(color: Color(0xFFF5F0E8), width: 2.0),
        ),
      ),
    ),
  );
}

// Tile painter
class _TileGridPainter extends CustomPainter {
  final bool isFloor;
  _TileGridPainter({this.isFloor = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    final hSpace = isFloor ? 48.0 : 60.0;
    final vSpace = isFloor ? 32.0 : 48.0;
    for (double x = 0; x <= size.width; x += hSpace) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += vSpace) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// Widget components
class _FridgeWidget extends StatelessWidget {
  final int count;
  final List<String> iconKeys;
  final double height;

  const _FridgeWidget({
    required this.count,
    required this.iconKeys,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.fridgeTop, AppColors.fridgeBottom],
        ),
        borderRadius: BorderRadius.circular(AppRadius.card(context) * 0.6),
        border: Border.all(color: AppColors.fridgeBorder, width: 2.0),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(2, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Handle
          Positioned(
            right: context.scaleWidth(6.0),
            top: context.scaleHeight(20.0),
            child: Container(
              width: context.scaleWidth(5.0),
              height: context.scaleHeight(32.0),
              color: AppColors.fridgeHandle,
            ),
          ),

          // Icons strip
          Positioned(
            top: context.scaleHeight(16.0),
            left: context.scaleWidth(8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: iconKeys
                  .take(3)
                  .map(
                    (key) => Padding(
                      padding: const EdgeInsets.only(right: 2.0),
                      child: Icon(
                        StorageZoneIconMapper.fromKey(key),
                        size: AppIconSizes.sm(context) * 0.7,
                        color: AppColors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),

          // Freezer Divider
          Positioned(
            top: height * 0.45,
            left: 0,
            right: 0,
            child: Container(height: 2.0, color: AppColors.fridgeDivider),
          ),

          // Freezer Handle
          Positioned(
            right: context.scaleWidth(6.0),
            top: height * 0.52,
            child: Container(
              width: context.scaleWidth(5.0),
              height: context.scaleHeight(22.0),
              color: AppColors.fridgeHandle,
            ),
          ),

          Positioned(
            bottom: context.scaleHeight(8.0),
            left: 0,
            right: 0,
            child: Text(
              'FRIDGE',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: context.scaleFont(8.0),
                fontWeight: FontWeight.bold,
                color: AppColors.fridgeLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpicesCabinet extends StatelessWidget {
  final int count;
  final List<String> iconKeys;

  const _SpicesCabinet({required this.count, required this.iconKeys});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.woodTop, AppColors.woodBottom],
        ),
        borderRadius: BorderRadius.circular(AppRadius.chip(context) * 0.75),
        border: Border.all(color: AppColors.woodBorder, width: 2.0),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(2, 4)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: iconKeys
                .take(3)
                .map(
                  (key) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.0),
                    child: Icon(
                      StorageZoneIconMapper.fromKey(key),
                      size: AppIconSizes.sm(context) * 0.6,
                      color: AppColors.white.withValues(alpha: 0.9),
                    ),
                  ),
                )
                .toList(),
          ),
          AppGap.xs(context),
          Text(
            'SPICES',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: context.scaleFont(8.0),
              color: AppColors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PantryShelf extends StatelessWidget {
  final int count;
  final List<String> iconKeys;

  const _PantryShelf({required this.count, required this.iconKeys});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        // Shelf wood board
        Container(height: 6.0, color: AppColors.woodBottom),
        Positioned(
          bottom: 6.0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: iconKeys
                .take(3)
                .map(
                  (key) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: Icon(
                      StorageZoneIconMapper.fromKey(key),
                      size: AppIconSizes.sm(context) * 0.8,
                      color: AppColors.woodBorder,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _CabinetWidget extends StatelessWidget {
  final int count;
  final List<String> iconKeys;

  const _CabinetWidget({required this.count, required this.iconKeys});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.woodTop, AppColors.woodBottom],
        ),
        borderRadius: BorderRadius.circular(AppRadius.chip(context) * 0.75),
        border: Border.all(color: AppColors.woodBorder, width: 2.0),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(-2, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.door_sliding_outlined,
              size: AppIconSizes.md(context),
              color: AppColors.white.withValues(alpha: 0.9),
            ),
            AppGap.xs(context),
            Text(
              'CABINET',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: context.scaleFont(8.0),
                color: AppColors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BasketWidget extends StatelessWidget {
  final int count;
  final List<String> iconKeys;

  const _BasketWidget({required this.count, required this.iconKeys});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFC8A04A), Color(0xFFA07828)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(8.0)),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: iconKeys
              .take(3)
              .map(
                (key) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: Icon(
                    StorageZoneIconMapper.fromKey(key),
                    size: AppIconSizes.sm(context) * 0.7,
                    color: AppColors.white.withValues(alpha: 0.9),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _ZonePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  const _ZonePill({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double paddingH = context.scaleWidth(8.0);
    final double paddingV = context.scaleHeight(3.0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
        decoration: BoxDecoration(
          color: AppColors.zonePillBg,
          borderRadius: BorderRadius.circular(AppRadius.chip(context) * 1.2),
          border: Border.all(color: AppColors.zonePillBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: AppIconSizes.sm(context) * 0.6,
              color: AppColors.zonePillText,
            ),
            const SizedBox(width: 4),
            Text(
              '$label ($count)',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: context.scaleFont(9.0),
                fontWeight: FontWeight.bold,
                color: AppColors.zonePillText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
