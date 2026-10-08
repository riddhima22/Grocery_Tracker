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
import '../widgets/dashboard_analytics_section.dart';

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
    try {
      final data = await _aiService.fetchAIInsights();
      if (mounted) {
        final newInsights = List<String>.from(data['insights'] ?? []);
        if (newInsights.isNotEmpty) {
          setState(() {
            _insights = newInsights;
            _wasteRisk = double.tryParse(data['waste_risk']?.toString() ?? '0.0') ?? _wasteRisk;
            _freshnessScore = data['freshness_score'] ?? _freshnessScore;
          });
          // Cache in background
          _cacheManager.saveAIInsights(data);
        }
      }
    } catch (_) {}
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

    // Apply natural language AI search filter on urgent items (expired first, then expiring)
    final urgentItems = [...kitchen.expiredItems, ...kitchen.expiringItems];
    final filteredExpiring = AISearchService.filter(urgentItems, _searchQuery);

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

                             // Expired Warning Banner (Dynamic)
                             if (kitchen.expiredCount > 0) ...[
                               _buildExpiredAlertBanner(kitchen.expiredCount),
                               AppGap.sm(context),
                             ],

                             // Expiry Warning Banner (Dynamic)
                             if (kitchen.expiringCount > 0) ...[
                               _buildExpiryAlertBanner(kitchen.expiringCount),
                               AppGap.sm(context),
                             ],

                              // AI Dashboard Analytics & Smart Insights Suite
                              AnimatedBuilder(
                                animation: _chartController,
                                builder: (context, _) {
                                  return DashboardAnalyticsSection(
                                    kitchen: kitchen,
                                    insights: _insights,
                                    wasteRisk: _wasteRisk,
                                    freshnessScore: _freshnessScore,
                                    animation: _chartController,
                                  );
                                },
                              ),
                              AppGap.md(context),

                             // Upcoming Expiry (Filtered by AI search query)
                             AppSectionHeader(
                               title: _searchQuery.isEmpty 
                                   ? (kitchen.expiredCount > 0 ? 'Expired & Upcoming Expiry' : 'Upcoming Expiry')
                                   : 'Search Results',
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
                                           ? 'No expired or expiring items. Everything is fresh!'
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

  Widget _buildExpiredAlertBanner(int expiredCount) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.sm(context)),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning_rounded, color: AppColors.danger, size: 20),
          ),
          AppGap.sm(context),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Expired Items ($expiredCount)',
                  style: AppTextStyles.labelMedium(context).copyWith(
                    color: AppColors.danger,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$expiredCount ${expiredCount == 1 ? "item has" : "items have"} expired. Please remove or dispose of them.',
                  style: AppTextStyles.bodySmall(context).copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          )
        ],
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
