import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';

enum CategoryStatus {
  allGood,
  expiringSoon,
  expired,
  empty,
}

class KitchenCategoryCard extends StatefulWidget {
  final String name;
  final int count;
  final IconData icon;
  final CategoryStatus status;
  final VoidCallback onTap;

  const KitchenCategoryCard({
    super.key,
    required this.name,
    required this.count,
    required this.icon,
    required this.status,
    required this.onTap,
  });

  @override
  State<KitchenCategoryCard> createState() => _KitchenCategoryCardState();
}

class _KitchenCategoryCardState extends State<KitchenCategoryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  Color get _statusColor {
    switch (widget.status) {
      case CategoryStatus.allGood:
        return AppColors.success;
      case CategoryStatus.expiringSoon:
        return AppColors.warning;
      case CategoryStatus.expired:
        return AppColors.danger;
      case CategoryStatus.empty:
        return const Color(0xFF94A3B8);
    }
  }

  String get _statusLabel {
    switch (widget.status) {
      case CategoryStatus.allGood:
        return 'All Good';
      case CategoryStatus.expiringSoon:
        return 'Expiring Soon';
      case CategoryStatus.expired:
        return 'Expired';
      case CategoryStatus.empty:
        return 'Empty';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.cardBorder,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 8.0,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTapDown: (_) => _pressController.forward(),
            onTapUp: (_) => _pressController.reverse(),
            onTapCancel: () => _pressController.reverse(),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
              child: Row(
                children: [
                  // Large rounded icon container
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Icon(
                        widget.icon,
                        size: 22,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Category info & status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.name,
                          style: AppTextStyles.labelMedium(context).copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.count} ${widget.count == 1 ? "item" : "items"}',
                          style: AppTextStyles.caption(context).copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6.5,
                              height: 6.5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _statusLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
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

                  // Right chevron icon
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
