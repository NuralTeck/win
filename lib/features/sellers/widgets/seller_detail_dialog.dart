import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/utils/formatters.dart';
import '../../shared/models/seller_model.dart';

class SellerDetailDialog extends StatelessWidget {
  final SellerModel seller;

  const SellerDetailDialog({
    super.key,
    required this.seller,
  });

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: seller.name,
      subtitle: '${seller.code} • ${seller.category}',
      width: 640,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Seller Tier & Status Badge Header
          Row(
            children: [
              StatusBadge.fromStatus(seller.tier.name),
              const SizedBox(width: 8),
              StatusBadge.fromStatus(seller.status.name),
              const Spacer(),
              const Icon(Icons.star, size: 16, color: AppColors.tertiary),
              const SizedBox(width: 4),
              Text(
                seller.rating.toStringAsFixed(1),
                style: AppTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                ' Rating',
                style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Stat Cards Row
          Row(
            children: [
              Expanded(
                child: _DetailStatBox(
                  title: 'Monthly Revenue',
                  value: Formatters.formatCurrency(seller.monthlyRevenue),
                  icon: Icons.attach_money,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DetailStatBox(
                  title: 'Total Bookings',
                  value: Formatters.formatNumber(seller.totalBookings),
                  icon: Icons.receipt,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DetailStatBox(
                  title: 'Fulfillment Rate',
                  value: '${seller.fulfillmentRate}%',
                  icon: Icons.verified,
                  valueColor: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Text(
            'Region / Operational Hub',
            style: AppTypography.labelMd.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            seller.region,
            style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: [
        AppSecondaryButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 12),
        AppPrimaryButton(
          label: 'View Settlement History',
          icon: Icons.history,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _DetailStatBox extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _DetailStatBox({
    required this.title,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppDecorations.radiusDefault,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(
            title,
            style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.titleMd.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
