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

  /// Formats the remaining shelf life text for detail views (e.g., '1 day left', '5 days left', 'Expires today', 'Expired').
  static String formatRemainingDaysText(DateTime target) {
    final diff = calendarDaysDifference(target);
    if (diff < 0) {
      return 'Expired';
    } else if (diff == 0) {
      return 'Expires today';
    } else if (diff == 1) {
      return '1 day left';
    } else {
      return '$diff days left';
    }
  }

  /// Formats concise shelf life text for candidate cards (e.g., 'today', 'tomorrow', '~1d left', '~5 days', 'expired').
  static String formatCandidateShelfText(DateTime target, {bool isEstimated = false}) {
    final diff = calendarDaysDifference(target);
    if (diff < 0) {
      return 'expired';
    } else if (diff == 0) {
      return 'today';
    } else if (diff == 1) {
      return isEstimated ? '~1d (tomorrow)' : 'tomorrow (1d)';
    } else {
      return isEstimated ? '~$diff days' : '$diff days';
    }
  }

  /// Formats shelf life text for detail counter display (e.g., 'Expired', 'Expires today', '1 day left', '5 days left').
  static String formatRemainingDaysCount(DateTime target) {
    final diff = calendarDaysDifference(target);
    if (diff < 0) {
      return 'Expired';
    } else if (diff == 0) {
      return 'Expires today';
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
      return (
        label: isEstimated ? 'Today (Est)' : 'Expires today',
        color: AppColors.danger,
      );
    } else if (diff == 1) {
      return (
        label: isEstimated ? '~1d (Est)' : '1d left',
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
