import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/app_radius.dart';
import '../../../config/app_text_styles.dart';
import 'kitchen_health_gauge.dart';

class KitchenHealthHeroCard extends StatelessWidget {
  final int healthScore;
  final int freshCount;
  final int totalCount;
  final String lastScanTime;
  final double animationValue;

  const KitchenHealthHeroCard({
    super.key,
    required this.healthScore,
    required this.freshCount,
    required this.totalCount,
    required this.lastScanTime,
    this.animationValue = 1.0,
  });

  String get _healthRating {
    if (healthScore >= 85) return 'Excellent';
    if (healthScore >= 65) return 'Good';
    if (healthScore >= 45) return 'Fair';
    return 'Needs Attention';
  }

  Color get _ratingColor {
    if (healthScore >= 85) return AppColors.success;
    if (healthScore >= 65) return const Color(0xFF26A69A);
    if (healthScore >= 45) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final ratingColor = _ratingColor;

    return Container(
      padding: EdgeInsets.all(AppSpacing.md(context)),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card(context)),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            children: [
              KitchenHealthGauge(
                score: healthScore,
                animationValue: animationValue,
                size: constraints.maxWidth < 320 ? 68.0 : 80.0,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Kitchen Health',
                            style: AppTextStyles.labelMedium(context).copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: ratingColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: ratingColor.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            _healthRating,
                            style: AppTextStyles.caption(context).copyWith(
                              color: ratingColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$freshCount of $totalCount items are fresh',
                      style: AppTextStyles.headingSmall(context).copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Last scan: $lastScanTime',
                            style: AppTextStyles.caption(context).copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
