import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/app_decorations.dart';
import '../utils/formatters.dart';
import '../../features/shared/models/metric_model.dart' show KpiMetricModel;
import 'glass_card.dart';

class KpiCard extends StatelessWidget {
  final KpiMetricModel metric;

  const KpiCard({
    super.key,
    required this.metric,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  metric.title,
                  style: AppTypography.labelMd.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: metric.iconColor.withAlpha(25),
                  borderRadius: AppDecorations.radiusDefault,
                  border: Border.all(
                    color: metric.iconColor.withAlpha(50),
                    width: 1,
                  ),
                ),
                child: Icon(
                  metric.icon,
                  size: 18,
                  color: metric.iconColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            metric.value,
            style: AppTypography.headlineMd.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: (metric.isPositive ? AppColors.success : AppColors.error)
                      .withAlpha(25),
                  borderRadius: AppDecorations.radiusSm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      metric.isPositive ? Icons.trending_up : Icons.trending_down,
                      size: 11,
                      color: metric.isPositive ? AppColors.success : AppColors.error,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      Formatters.formatPercentage(metric.changePercentage),
                      style: AppTypography.labelSm.copyWith(
                        fontSize: 10,
                        color: metric.isPositive ? AppColors.success : AppColors.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  metric.subtitle,
                  style: AppTypography.labelSm.copyWith(
                    fontSize: 10,
                    color: AppColors.textSecondary.withAlpha(180),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
