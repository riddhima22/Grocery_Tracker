import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../auth/providers/auth_provider.dart';
import '../../kitchen/providers/kitchen_provider.dart';
import 'dashboard_analytics_empty_state.dart';
import 'kitchen_health_hero_card.dart';
import 'kpi_card.dart';
import 'ai_recommendation_card.dart';
import '../../../core/utils/date_helpers.dart';

class DashboardAnalyticsSection extends StatelessWidget {
  final KitchenProvider kitchen;
  final List<String> insights;
  final double wasteRisk;
  final int freshnessScore;
  final Animation<double>? animation;

  const DashboardAnalyticsSection({
    super.key,
    required this.kitchen,
    required this.insights,
    required this.wasteRisk,
    required this.freshnessScore,
    this.animation,
  });

  String _formatLastScanTime() {
    if (kitchen.items.isEmpty) return 'No scans yet';
    DateTime latest = kitchen.items.first.purchaseDate;
    for (final item in kitchen.items) {
      if (item.purchaseDate.isAfter(latest)) {
        latest = item.purchaseDate;
      }
    }
    final now = DateTime.now();
    final diff = now.difference(latest);
    if (diff.inDays == 0 && latest.day == now.day) {
      final hour = latest.hour % 12 == 0 ? 12 : latest.hour % 12;
      final minute = latest.minute.toString().padLeft(2, '0');
      final ampm = latest.hour >= 12 ? 'PM' : 'AM';
      return 'Today, $hour:$minute $ampm';
    } else if (diff.inDays <= 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${latest.day}/${latest.month}/${latest.year}';
    }
  }

  List<String> _buildRecommendations() {
    final List<String> list = [];

    // Prioritize immediate action on expiring items
    if (kitchen.expiringItems.isNotEmpty) {
      final firstExpiring = kitchen.expiringItems.first;
      final effectiveDate = firstExpiring.effectiveExpiryDate;
      if (effectiveDate != null) {
        final days = DateHelpers.calendarDaysDifference(effectiveDate);
        if (days < 0) {
          list.add('${firstExpiring.name} has expired! Consume or discard.');
        } else if (days == 0) {
          list.add('Consume ${firstExpiring.name} today to avoid spoilage.');
        } else if (days == 1) {
          list.add('Consume ${firstExpiring.name} tomorrow (1 day left) to avoid spoilage.');
        } else {
          list.add('Consume ${firstExpiring.name} within $days days to avoid spoilage.');
        }
      } else {
        list.add('Consume ${firstExpiring.name} soon to avoid spoilage.');
      }
    }

    // Append AI insights
    for (final tip in insights) {
      if (!list.contains(tip)) {
        list.add(tip);
      }
    }

    // Fallback if none available
    if (list.isEmpty) {
      list.add('All items are fresh! Maintain current storage zones for longer shelf life.');
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    // If no real items exist, show the dedicated empty state banner
    if (kitchen.items.isEmpty) {
      return const DashboardAnalyticsEmptyState();
    }

    final totalCount = kitchen.totalItems;
    final expiringCount = kitchen.expiringCount;
    final expiredCount = kitchen.expiredCount;
    final freshCount = (totalCount - expiringCount - expiredCount).clamp(0, totalCount);

    // Dynamic Kitchen Health calculation
    int calculatedHealth = 100;
    if (kitchen.items.isNotEmpty) {
      final sum = kitchen.items.fold<int>(0, (prev, el) => prev + el.freshnessScore);
      calculatedHealth = (sum / kitchen.items.length).round().clamp(0, 100);
    }
    final effectiveHealth = (freshnessScore != 100 && freshnessScore > 0)
        ? freshnessScore
        : calculatedHealth;

    // Dynamic Waste Risk evaluation
    String wasteRiskLevel = 'Low';
    Color wasteRiskColor = AppColors.success;
    if (expiredCount > 0 || expiringCount >= 3) {
      wasteRiskLevel = 'High';
      wasteRiskColor = AppColors.danger;
    } else if (expiringCount >= 1) {
      wasteRiskLevel = 'Medium';
      wasteRiskColor = AppColors.warning;
    }

    final savedItemsCount = context.watch<AuthProvider>().user?.savedFromWaste ?? 0;
    final wasteSubtitle = expiringCount > 0
        ? '$expiringCount item${expiringCount > 1 ? 's' : ''} near expiry'
        : 'Zero items at immediate risk';

    final lastScan = _formatLastScanTime();
    final recommendations = _buildRecommendations();
    final animValue = animation?.value ?? 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Kitchen Health Hero Card
        KitchenHealthHeroCard(
          healthScore: effectiveHealth,
          freshCount: freshCount,
          totalCount: totalCount,
          lastScanTime: lastScan,
          animationValue: animValue,
        ),
        AppGap.sm(context),

        // 2. Inventory Breakdown KPI Grid (2x2)
        Row(
          children: [
            Expanded(
              child: KpiCard(
                label: 'Fresh Items',
                value: '$freshCount',
                icon: Icons.eco_rounded,
                accentColor: AppColors.success,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: KpiCard(
                label: 'Expiring Soon',
                value: '$expiringCount',
                icon: Icons.timer_outlined,
                accentColor: AppColors.warning,
                badgeText: expiringCount > 0 ? 'Urgent' : null,
                badgeColor: AppColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: KpiCard(
                label: 'Expired',
                value: '$expiredCount',
                icon: Icons.event_busy_outlined,
                accentColor: AppColors.danger,
                badgeText: expiredCount > 0 ? 'Action' : null,
                badgeColor: AppColors.danger,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: KpiCard(
                label: 'Total Inventory',
                value: '$totalCount',
                icon: Icons.inventory_2_outlined,
                accentColor: AppColors.info,
              ),
            ),
          ],
        ),
        AppGap.sm(context),

        // 3. Waste Prevention & Risk Row (2 Cards)
        Row(
          children: [
            Expanded(
              child: KpiCard(
                label: 'Saved From Waste',
                value: '$savedItemsCount',
                icon: Icons.savings_outlined,
                accentColor: AppColors.primary,
                subtitle: 'Items consumed in time',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: KpiCard(
                label: 'Waste Risk',
                value: wasteRiskLevel,
                icon: Icons.shield_outlined,
                accentColor: wasteRiskColor,
                badgeText: wasteRiskLevel,
                badgeColor: wasteRiskColor,
                subtitle: wasteSubtitle,
              ),
            ),
          ],
        ),
        AppGap.sm(context),

        // 4. AI Recommendation Spotlight
        AiRecommendationCard(
          recommendations: recommendations,
        ),
      ],
    );
  }
}
