import 'package:flutter/material.dart';
import '../../config/app_colors.dart';

class DateHelpers {
  /// Computes the difference in whole calendar days between [target] and [from] (default: today).
  /// Strips the time component so an item expiring tomorrow always yields 1 day,
  /// regardless of what time of day it is currently.
  static int calendarDaysDifference(DateTime target, [DateTime? from]) {
    final fromDay = DateUtils.dateOnly(from ?? DateTime.now());
    final targetDay = DateUtils.dateOnly(target);
    return targetDay.difference(fromDay).inDays;
  }

  /// Calculates the effective expiration moment for [target].
  /// If [target] is midnight (00:00:00), treats it as expiring at the end of the day (23:59:59).
  static DateTime effectiveExpiryMoment(DateTime target) {
    if (target.hour == 0 && target.minute == 0 && target.second == 0) {
      return DateTime(target.year, target.month, target.day, 23, 59, 59);
    }
    return target;
  }

  /// Computes remaining time until expiration.
  static Duration remainingDuration(DateTime target) {
    final moment = effectiveExpiryMoment(target);
    return moment.difference(DateTime.now());
  }

  /// Formats concise intraday time left (e.g. '8 hr left', '45 min left', '30 sec left', 'Expired').
  static String formatIntradayTimeLeft(DateTime target) {
    final rem = remainingDuration(target);
    if (rem.isNegative) return 'Expired';
    if (rem.inHours >= 1) {
      return '${rem.inHours} hr left';
    }
    if (rem.inMinutes >= 1) {
      return '${rem.inMinutes} min left';
    }
    final secs = rem.inSeconds.clamp(1, 59);
    return '$secs sec left';
  }

  /// Formats verbose intraday time left for detail views (e.g. '8 hr 15 min left', '45 min left', '30 sec left').
  static String formatIntradayTimeLeftVerbose(DateTime target) {
    final rem = remainingDuration(target);
    if (rem.isNegative) return 'Expired';
    if (rem.inHours >= 1) {
      final mins = rem.inMinutes % 60;
      return mins > 0 ? '${rem.inHours} hr $mins min left' : '${rem.inHours} hr left';
    }
    if (rem.inMinutes >= 1) {
      final secs = rem.inSeconds % 60;
      return secs > 0 ? '${rem.inMinutes} min $secs sec left' : '${rem.inMinutes} min left';
    }
    return '${rem.inSeconds.clamp(1, 59)} sec left';
  }

  /// Formats the remaining shelf life text for detail views.
  static String formatRemainingDaysText(DateTime target) {
    final diff = calendarDaysDifference(target);
    if (diff < 0) {
      return 'Expired';
    } else if (diff == 0) {
      return formatIntradayTimeLeftVerbose(target);
    } else if (diff == 1) {
      return '1 day left';
    } else {
      return '$diff days left';
    }
  }

  /// Formats concise shelf life text for candidate cards.
  static String formatCandidateShelfText(DateTime target, {bool isEstimated = false}) {
    final diff = calendarDaysDifference(target);
    if (diff < 0) {
      return 'expired';
    } else if (diff == 0) {
      final text = formatIntradayTimeLeft(target);
      return isEstimated ? '~$text' : text;
    } else if (diff == 1) {
      return isEstimated ? '~1d (tomorrow)' : 'tomorrow (1d)';
    } else {
      return isEstimated ? '~$diff days' : '$diff days';
    }
  }

  /// Formats shelf life text for detail counter display.
  static String formatRemainingDaysCount(DateTime target) {
    final diff = calendarDaysDifference(target);
    if (diff < 0) {
      return 'Expired';
    } else if (diff == 0) {
      return formatIntradayTimeLeftVerbose(target);
    } else if (diff == 1) {
      return '1 day left';
    } else {
      return '$diff days left';
    }
  }

  /// Returns badge configuration (label and color) for an expiry date.
  static ({String label, Color color}) formatExpiryBadge(DateTime target, {bool isEstimated = false}) {
    final diff = calendarDaysDifference(target);
    if (diff < 0) {
      return (
        label: isEstimated ? 'Past Est.' : 'Expired',
        color: AppColors.danger,
      );
    } else if (diff == 0) {
      final timeStr = formatIntradayTimeLeft(target);
      return (
        label: isEstimated ? '$timeStr (Est)' : timeStr,
        color: AppColors.danger,
      );
    } else if (diff == 1) {
      return (
        label: isEstimated ? '~1d left' : '1d left',
        color: AppColors.warning,
      );
    } else if (diff <= 3) {
      return (
        label: isEstimated ? '~$diff d (Est)' : '$diff d left',
        color: AppColors.warning,
      );
    } else {
      return (
        label: isEstimated ? '~$diff d (Est)' : '$diff d left',
        color: AppColors.success,
      );
    }
  }
}
