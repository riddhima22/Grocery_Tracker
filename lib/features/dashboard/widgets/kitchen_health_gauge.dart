import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_text_styles.dart';

class KitchenHealthGauge extends StatelessWidget {
  final int score;
  final double animationValue;
  final double size;

  const KitchenHealthGauge({
    super.key,
    required this.score,
    this.animationValue = 1.0,
    this.size = 78.0,
  });

  Color _getScoreColor(int val) {
    if (val >= 85) return AppColors.success;
    if (val >= 65) return const Color(0xFF26A69A);
    if (val >= 45) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final scoreColor = _getScoreColor(score);
    final displayScore = (score * animationValue).round().clamp(0, 100);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _GaugePainter(
              percentage: (score / 100.0) * animationValue,
              color: scoreColor,
              trackColor: AppColors.cardBorder.withValues(alpha: 0.6),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$displayScore%',
                style: AppTextStyles.headingMedium(context).copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  fontSize: size * 0.26,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'HEALTH',
                style: AppTextStyles.caption(context).copyWith(
                  color: AppColors.textSecondary,
                  fontSize: size * 0.11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double percentage;
  final Color color;
  final Color trackColor;

  _GaugePainter({
    required this.percentage,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 7.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // Foreground score arc
    if (percentage > 0) {
      final progressPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      const startAngle = -math.pi / 2;
      final sweepAngle = (2 * math.pi * percentage.clamp(0.0, 1.0));

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.percentage != percentage ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}
