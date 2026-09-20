import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../kitchen/providers/kitchen_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_text_styles.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_retry_state.dart';
import '../../../core/widgets/grocery_item_card.dart';
import '../../../core/extensions/responsive_context_extension.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/services/ai_search_service.dart';
import '../../../data/local/cache_manager.dart';
import '../../kitchen/views/kitchen_item_detail_view.dart';
import '../../meals/views/meal_log_view.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _chartController;
  final TextEditingController _searchController = TextEditingController();
  final IAIService _aiService = AIServiceImpl();
  final CacheManager _cacheManager = CacheManager();

  List<String> _insights = [];
  double _wasteRisk = 0.0;
  int _freshnessScore = 100;
  bool _isLoadingInsights = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _chartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _chartController.forward();
    
    // 1. Immediately hydrate cached insights (0ms)
    _loadCachedInsights();

    // 2. Proactively fetch items and remote insights in background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final kitchen = context.read<KitchenProvider>();
      // Trigger cache-first fetch for kitchen items
      kitchen.fetchKitchenItems();
      
      // If we don't have insights yet, generate instant client-side insights
      if (_insights.isEmpty) {
        _applyInstantClientInsights(kitchen);
      }
      
      // Fetch fresh remote insights in background
      _loadAIInsights();
    });
  }

  Future<void> _loadCachedInsights() async {
    try {
      final cached = await _cacheManager.getCachedAIInsights();
      if (cached != null && mounted) {
        setState(() {
          _insights = List<String>.from(cached['insights'] ?? []);
          _wasteRisk = double.tryParse(cached['waste_risk']?.toString() ?? '0.0') ?? 0.0;
          _freshnessScore = cached['freshness_score'] ?? 100;
        });
      }
    } catch (_) {}
  }

  void _applyInstantClientInsights(KitchenProvider kitchen) {
    final expiring = kitchen.expiringItems;
    final expired = kitchen.expiredItems;
    final items = kitchen.items;

    final List<String> generated = [];

    if (expiring.isNotEmpty) {
      final names = expiring.take(3).map((e) => e.name).join(', ');
      if (expiring.length > 3) {
        generated.add('You have ${expiring.length} items expiring soon, including $names, and others.');
      } else {
        generated.add('You have items expiring soon: $names.');
      }
    }

    if (expired.isNotEmpty) {
      generated.add('Warning: ${expired.length} items have expired. Please clear them to keep your kitchen fresh.');
    }

    final categories = items.map((e) => e.category.toLowerCase()).toSet();
    if (categories.contains('fruits') || categories.contains('fruit')) {
      generated.add('Keeping bananas separate from other fruits prevents ethylene gas from ripening them too quickly.');
    }
    if (categories.contains('vegetables') || categories.contains('vegetable')) {
      generated.add('Store leafy greens with a dry paper towel inside a sealed bag to absorb excess moisture.');
    }
    if (categories.contains('dairy')) {
      generated.add('Avoid storing milk in the refrigerator door; shelf temperatures are much more stable.');
    }

    if (generated.isEmpty) {
      generated.addAll([
        'Your kitchen is in healthy shape! Keep logging items to track freshness.',
        'Storage temperature control is the easiest way to prevent grocery wastage.',
        'Planning meals around expiring items saves money and reduces waste.'
      ]);
    }

    final wasteVal = expiring.length * 65.0;
    int avgScore = 100;
    if (items.isNotEmpty) {
      final sum = items.fold<int>(0, (prev, el) => prev + el.freshnessScore);
      avgScore = (sum / items.length).round();
    }

    if (mounted) {
      setState(() {
        _insights = generated;
        _wasteRisk = wasteVal;
        _freshnessScore = avgScore;
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _chartController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAIInsights({bool force = false}) async {
    if (_insights.isEmpty && mounted) {
      setState(() => _isLoadingInsights = true);
    }
    
    try {
      final data = await _aiService.fetchAIInsights();
      if (mounted) {
        final newInsights = List<String>.from(data['insights'] ?? []);
        if (newInsights.isNotEmpty) {
          setState(() {
            _insights = newInsights;
            _wasteRisk = double.tryParse(data['waste_risk']?.toString() ?? '0.0') ?? _wasteRisk;
            _freshnessScore = data['freshness_score'] ?? _freshnessScore;
            _isLoadingInsights = false;
          });
          // Cache in background
          _cacheManager.saveAIInsights(data);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingInsights = false);
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final kitchen = context.watch<KitchenProvider>();
    final greeting = _getGreeting();
    final name = auth.user?.displayName ?? 'Chef';

    // Apply natural language AI search filter on expiring items or all items
    final filteredExpiring = AISearchService.filter(kitchen.expiringItems, _searchQuery);

    return AppScaffold(
      body: kitchen.isLoading && kitchen.items.isEmpty
          ? _buildShimmerLoading()
          : kitchen.errorMessage != null && kitchen.items.isEmpty
               ? AppRetryState(
                   errorMessage: kitchen.errorMessage!,
                   onRetry: () {
                     kitchen.fetchKitchenItems(forceRefresh: true);
                     _loadAIInsights(force: true);
                   },
                 )
               : RefreshIndicator(
                   color: AppColors.primary,
                   onRefresh: () async {
                     await Future.wait([
                       kitchen.fetchKitchenItems(forceRefresh: true),
                       _loadAIInsights(force: true),
                     ]);
                   },
                   child: CustomScrollView(
                     slivers: [
                       // Header Section
                       SliverPadding(
                         padding: EdgeInsets.all(AppSpacing.md(context)),
                         sliver: SliverList(
                           delegate: SliverChildListDelegate([
                             Row(
                               mainAxisAlignment: MainAxisAlignment.spaceBetween,
                               children: [
                                 Expanded(
                                   child: Column(
                                     crossAxisAlignment: CrossAxisAlignment.start,
                                     children: [
                                       Text(
                                         '$greeting, $name',
                                         style: AppTextStyles.headingLarge(context).copyWith(
                                           fontSize: context.scaleFont(22.0),
                                         ),
                                         maxLines: 2,
                                         overflow: TextOverflow.ellipsis,
                                       ),
                                       const SizedBox(height: 4),
                                       Text(
                                         'Here\'s your kitchen status overview',
                                         style: AppTextStyles.bodyMedium(context),
                                       ),
                                     ],
                                   ),
                                 ),
                                 CircleAvatar(
                                   radius: context.scaleWidth(20.0),
                                   backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                                   backgroundImage: auth.user?.avatarUrl != null && auth.user!.avatarUrl!.isNotEmpty
                                       ? NetworkImage(auth.user!.avatarUrl!)
                                       : null,
                                   child: auth.user?.avatarUrl == null || auth.user!.avatarUrl!.isEmpty
                                       ? Text(
                                           name.isNotEmpty ? name[0].toUpperCase() : 'C',
                                           style: AppTextStyles.labelMedium(context).copyWith(color: AppColors.primary),
                                         )
                                       : null,
                                 ),
                               ],
                             ),
                             AppGap.md(context),

                             // AI Search Bar
                             _buildAISearchBox(),
                             AppGap.md(context),

                             // Log Meal Quick Action
                             _buildLogMealAction(),
                             AppGap.md(context),

                             // Expiry Warning Banner (Dynamic)
                             if (kitchen.expiringCount > 0) ...[
                               _buildExpiryAlertBanner(kitchen.expiringCount),
                               AppGap.sm(context),
                             ],

                             // AI Natural Language Insights Panel
                             _buildAIInsightsCarousel(),
                             AppGap.md(context),

                             // Stats Grid & Utilization Chart
                             _buildDashboardAnalyticsSection(kitchen),
                             AppGap.md(context),

                             // Upcoming Expiry (Filtered by AI search query)
                             AppSectionHeader(
                               title: _searchQuery.isEmpty ? 'Upcoming Expiry' : 'Search Results',
                               actionText: 'View All',
                               onActionPressed: () {
                                 // Navigate to kitchen tab
                               },
                             ),
                             AppGap.xs(context),
                           ]),
                         ),
                       ),

                       // List of upcoming expiring items
                       filteredExpiring.isEmpty
                           ? SliverPadding(
                               padding: EdgeInsets.symmetric(horizontal: AppSpacing.md(context)),
                               sliver: SliverToBoxAdapter(
                                 child: Container(
                                   padding: const EdgeInsets.all(24.0),
                                   decoration: BoxDecoration(
                                     color: AppColors.card,
                                     borderRadius: BorderRadius.circular(12),
                                     border: Border.all(color: AppColors.cardBorder),
                                   ),
                                   child: Center(
                                     child: Text(
                                       _searchQuery.isEmpty 
                                           ? 'No expiring items currently. Everything is fresh!'
                                           : 'No matching grocery items found.',
                                       style: AppTextStyles.bodyMedium(context).copyWith(color: AppColors.textSecondary),
                                     ),
                                   ),
                                 ),
                               ),
                             )
                           : SliverPadding(
                               padding: EdgeInsets.symmetric(horizontal: AppSpacing.md(context)),
                               sliver: SliverList(
                                 delegate: SliverChildBuilderDelegate(
                                   (ctx, index) {
                                     final item = filteredExpiring[index];
                                     return GroceryItemCard(
                                       item: item,
                                       onTap: () {
                                         Navigator.push(
                                           context,
                                           MaterialPageRoute(
                                             builder: (context) => KitchenItemDetailView(item: item),
                                           ),
                                         );
                                       },
                                     );
                                   },
                                   childCount: filteredExpiring.length,
                                 ),
                               ),
                             ),
                       SliverToBoxAdapter(child: SizedBox(height: context.scaleHeight(64.0))),
                     ],
                   ),
                 ),
    );
  }

  Widget _buildAISearchBox() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8.0,
            offset: const Offset(0, 4),
          )
        ]
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'AI Search (e.g. "Show fruits expiring soon")',
          prefixIcon: const Icon(Icons.psychology_outlined, color: AppColors.primary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        style: AppTextStyles.bodyLarge(context),
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
          });
        },
      ),
    );
  }

  Widget _buildLogMealAction() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MealLogView()),
        );
      },
      borderRadius: BorderRadius.circular(AppRadius.card(context)),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md(context),
          vertical: AppSpacing.sm(context),
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, Color(0xFF5A4D9A)],
          ),
          borderRadius: BorderRadius.circular(AppRadius.card(context)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.restaurant_menu, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Log a Meal',
                    style: AppTextStyles.labelLarge(context).copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Snap a photo to deduct ingredients',
                    style: AppTextStyles.caption(context).copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildExpiryAlertBanner(int expiringCount) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.sm(context)),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 14.0,
                height: 14.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.danger.withValues(alpha: 0.3 + (0.7 * _pulseController.value)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.danger,
                      blurRadius: 4.0 + (4.0 * _pulseController.value),
                    )
                  ],
                ),
              );
            },
          ),
          AppGap.sm(context),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Expiry Alert',
                  style: AppTextStyles.labelMedium(context).copyWith(color: AppColors.danger, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  '$expiringCount items in your pantry will expire soon. Use them before they spoil.',
                  style: AppTextStyles.bodySmall(context).copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildAIInsightsCarousel() {
    if (_isLoadingInsights && _insights.isEmpty) {
      return Shimmer.fromColors(
        baseColor: AppColors.card,
        highlightColor: AppColors.surface,
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    if (_insights.isEmpty) return const SizedBox();

    return Container(
      padding: EdgeInsets.all(AppSpacing.md(context)),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'AI Smart Insights',
                style: AppTextStyles.labelMedium(context).copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: context.scaleHeight(75.0),
            child: PageView.builder(
              itemCount: _insights.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Text(
                      _insights[index],
                      style: AppTextStyles.bodyMedium(context).copyWith(height: 1.3),
                    ),
                  ),
                );
              },
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Swipe for more',
                  style: AppTextStyles.caption(context).copyWith(color: AppColors.primary, fontSize: 10),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward, size: 10, color: AppColors.primary),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDashboardAnalyticsSection(KitchenProvider kitchen) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.md(context)),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Storage Health & Analytics', style: AppTextStyles.labelMedium(context)),
          AppGap.md(context),

          // Side-by-side circular charts and metrics
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final healthSize = availableWidth * 0.35;
              final utilWidth = availableWidth * 0.45;
              final utilHeight = healthSize;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Custom Canvas Storage health circular chart
                  Flexible(
                    flex: 3,
                    child: CustomPaint(
                      size: Size(healthSize, healthSize),
                      painter: _StorageHealthPainter(
                        fresh: kitchen.totalItems - kitchen.expiringCount - kitchen.expiredCount,
                        expiring: kitchen.expiringCount,
                        expired: kitchen.expiredCount,
                        animationValue: _chartController.value,
                      ),
                    ),
                  ),
                  
                  // Custom Canvas Storage utilization bar chart
                  Flexible(
                    flex: 4,
                    child: CustomPaint(
                      size: Size(utilWidth, utilHeight),
                      painter: _StorageUtilizationPainter(
                        fridge: kitchen.fridgeItems.length,
                        freezer: kitchen.freezerItems.length,
                        pantry: kitchen.pantryItems.length,
                        animationValue: _chartController.value,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          AppGap.md(context),

          // Metrics row (Money saved, Freshness score, Waste risk)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildAnalyticsMetric('Freshness', '$_freshnessScore%', AppColors.success),
              _buildAnalyticsMetric('Saved', '₹${kitchen.items.length * 40}', AppColors.primary),
              _buildAnalyticsMetric('Waste Risk', '₹${_wasteRisk.toInt()}', AppColors.danger),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildAnalyticsMetric(String label, String value, Color color) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: AppTextStyles.headingLarge(context).copyWith(color: color, fontSize: 18.0),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTextStyles.caption(context).copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: AppColors.card,
      highlightColor: AppColors.surface,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (_, __) => Container(
          height: 100,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// Custom painter to render animated storage health ring
class _StorageHealthPainter extends CustomPainter {
  final int fresh;
  final int expiring;
  final int expired;
  final double animationValue;

  _StorageHealthPainter({
    required this.fresh,
    required this.expiring,
    required this.expired,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double center = size.width / 2;
    final double radius = (size.width - 12) / 2;
    final Rect rect = Rect.fromCircle(center: Offset(center, center), radius: radius);
    const double strokeWidth = 8.0;

    final Paint bgPaint = Paint()
      ..color = AppColors.cardBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(Offset(center, center), radius, bgPaint);

    final int total = fresh + expiring + expired;
    if (total == 0) return;

    double startAngle = -1.57; // start top

    final double freshSweep = (fresh / total) * 6.28 * animationValue;
    final double expiringSweep = (expiring / total) * 6.28 * animationValue;
    final double expiredSweep = (expired / total) * 6.28 * animationValue;

    if (fresh > 0) {
      final Paint freshPaint = Paint()
        ..color = AppColors.success
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth;
      canvas.drawArc(rect, startAngle, freshSweep, false, freshPaint);
      startAngle += freshSweep;
    }

    if (expiring > 0) {
      final Paint expiringPaint = Paint()
        ..color = AppColors.warning
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth;
      canvas.drawArc(rect, startAngle, expiringSweep, false, expiringPaint);
      startAngle += expiringSweep;
    }

    if (expired > 0) {
      final Paint expiredPaint = Paint()
        ..color = AppColors.danger
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth;
      canvas.drawArc(rect, startAngle, expiredSweep, false, expiredPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Custom painter to render animated storage utilization bars
class _StorageUtilizationPainter extends CustomPainter {
  final int fridge;
  final int freezer;
  final int pantry;
  final double animationValue;

  _StorageUtilizationPainter({
    required this.fridge,
    required this.freezer,
    required this.pantry,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double W = size.width;
    final double H = size.height;
    
    final int maxVal = [fridge, freezer, pantry, 1].reduce((a, b) => a > b ? a : b);

    final double fridgeHeight = (fridge / maxVal) * (H - 20) * animationValue;
    final double freezerHeight = (freezer / maxVal) * (H - 20) * animationValue;
    final double pantryHeight = (pantry / maxVal) * (H - 20) * animationValue;

    final double barWidth = W / 5;
    final double spacing = W / 10;

    final Paint barPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;

    // Draw fridge bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(spacing, H - 15 - fridgeHeight, barWidth, fridgeHeight),
        const Radius.circular(4),
      ),
      barPaint..color = AppColors.primary,
    );

    // Draw freezer bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(spacing * 2 + barWidth, H - 15 - freezerHeight, barWidth, freezerHeight),
        const Radius.circular(4),
      ),
      barPaint..color = const Color(0xFF29B6F6),
    );

    // Draw pantry bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(spacing * 3 + barWidth * 2, H - 15 - pantryHeight, barWidth, pantryHeight),
        const Radius.circular(4),
      ),
      barPaint..color = const Color(0xFFFFA726),
    );

    // Draw baseline
    final Paint linePaint = Paint()
      ..color = AppColors.cardBorder
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, H - 15), Offset(W, H - 15), linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
