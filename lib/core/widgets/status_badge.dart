import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/app_decorations.dart';

enum StatusBadgeStyle {
  active,
  pending,
  completed,
  suspended,
  failed,
  highPriority,
  criticalPriority,
  mediumPriority,
  info,
}

class StatusBadge extends StatelessWidget {
  final String label;
  final StatusBadgeStyle style;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.style,
    this.icon,
  });

  factory StatusBadge.fromStatus(String statusStr) {
    final lower = statusStr.toLowerCase();
    if (lower.contains('active') || lower.contains('settled') || lower.contains('confirmed')) {
      return StatusBadge(label: statusStr, style: StatusBadgeStyle.active);
    } else if (lower.contains('pending') || lower.contains('processing') || lower.contains('review')) {
      return StatusBadge(label: statusStr, style: StatusBadgeStyle.pending);
    } else if (lower.contains('completed')) {
      return StatusBadge(label: statusStr, style: StatusBadgeStyle.completed);
    } else if (lower.contains('critical') || lower.contains('failed') || lower.contains('flagged')) {
      return StatusBadge(label: statusStr, style: StatusBadgeStyle.criticalPriority);
    } else if (lower.contains('high')) {
      return StatusBadge(label: statusStr, style: StatusBadgeStyle.highPriority);
    } else if (lower.contains('suspended')) {
      return StatusBadge(label: statusStr, style: StatusBadgeStyle.suspended);
    }
    return StatusBadge(label: statusStr, style: StatusBadgeStyle.info);
  }

  @override
  Widget build(BuildContext context) {
    final (Color bgColor, Color textColor, Color borderColor) = _getColors();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: AppDecorations.radiusPill,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: textColor),
            const SizedBox(width: 4),
          ] else ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: textColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: AppTypography.labelSm.copyWith(
                color: textColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color, Color) _getColors() {
    switch (style) {
      case StatusBadgeStyle.active:
      case StatusBadgeStyle.completed:
        return (
          AppColors.success.withAlpha(25),
          AppColors.success,
          AppColors.success.withAlpha(50),
        );
      case StatusBadgeStyle.pending:
      case StatusBadgeStyle.mediumPriority:
        return (
          AppColors.warning.withAlpha(25),
          AppColors.warning,
          AppColors.warning.withAlpha(50),
        );
      case StatusBadgeStyle.criticalPriority:
      case StatusBadgeStyle.failed:
        return (
          AppColors.error.withAlpha(25),
          AppColors.error,
          AppColors.error.withAlpha(50),
        );
      case StatusBadgeStyle.highPriority:
        return (
          AppColors.tertiary.withAlpha(25),
          AppColors.tertiary,
          AppColors.tertiary.withAlpha(50),
        );
      case StatusBadgeStyle.suspended:
        return (
          AppColors.textSecondary.withAlpha(25),
          AppColors.textSecondary,
          AppColors.textSecondary.withAlpha(50),
        );
      case StatusBadgeStyle.info:
        return (
          AppColors.info.withAlpha(25),
          AppColors.info,
          AppColors.info.withAlpha(50),
        );
    }
  }
}
