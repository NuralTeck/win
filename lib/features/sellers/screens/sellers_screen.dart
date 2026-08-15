import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/utils/formatters.dart';
import '../viewmodels/sellers_viewmodel.dart';
import '../widgets/seller_detail_dialog.dart';
import '../widgets/edit_seller_dialog.dart';
import '../../shared/models/seller_model.dart';

class SellersScreen extends ConsumerWidget {
  const SellersScreen({super.key});

  void _openSellerDetail(BuildContext context, SellerModel seller) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(153),
      builder: (context) => SellerDetailDialog(seller: seller),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sellersViewModelProvider);
    final notifier = ref.read(sellersViewModelProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sellers Directory',
                      style: AppTypography.headlineLg.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage enterprise partner profiles, performance tiers, and fulfillment metrics',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              AppPrimaryButton(
                label: 'Onboard Partner',
                icon: Icons.person_add_alt_1_outlined,
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Filters Row
          Row(
            children: [
              SizedBox(
                width: 320,
                child: AppSearchField(
                  hintText: 'Search partner name, code, or category...',
                  onChanged: notifier.setSearchQuery,
                ),
              ),
              const SizedBox(width: 16),

              _TierFilterChip(
                label: 'All Tiers',
                isSelected: state.selectedTier == null,
                onTap: () => notifier.setTierFilter(null),
              ),
              const SizedBox(width: 8),
              _TierFilterChip(
                label: 'Enterprise',
                isSelected: state.selectedTier == SellerTier.enterprise,
                onTap: () => notifier.setTierFilter(SellerTier.enterprise),
              ),
              const SizedBox(width: 8),
              _TierFilterChip(
                label: 'Gold',
                isSelected: state.selectedTier == SellerTier.gold,
                onTap: () => notifier.setTierFilter(SellerTier.gold),
              ),
              const SizedBox(width: 8),
              _TierFilterChip(
                label: 'Silver',
                isSelected: state.selectedTier == SellerTier.silver,
                onTap: () => notifier.setTierFilter(SellerTier.silver),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Data Table
          AppDataTable(
            isLoading: state.isLoading,
            columns: const [
              AppTableColumn(label: 'PARTNER CODE', width: 110),
              AppTableColumn(label: 'ENTERPRISE SELLER NAME'),
              AppTableColumn(label: 'TIER', width: 120),
              AppTableColumn(label: 'MONTHLY REVENUE', width: 150),
              AppTableColumn(label: 'FULFILLMENT', width: 120),
              AppTableColumn(label: 'RATING', width: 90),
              AppTableColumn(label: 'STATUS', width: 110),
              AppTableColumn(label: 'ACTIONS', width: 90, alignment: Alignment.centerRight),
            ],
            rows: state.filteredSellers.map((seller) {
              return [
                Text(
                  seller.code,
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      seller.name,
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${seller.category} • ${seller.region}',
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.textSecondary.withAlpha(150),
                      ),
                    ),
                  ],
                ),
                StatusBadge.fromStatus(seller.tier.name),
                Text(
                  Formatters.formatCurrency(seller.monthlyRevenue),
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${seller.fulfillmentRate}%',
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.star, size: 14, color: AppColors.tertiary),
                    const SizedBox(width: 4),
                    Text(
                      seller.rating.toStringAsFixed(1),
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                StatusBadge.fromStatus(seller.status.name),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.tune, size: 18, color: AppColors.primary),
                      tooltip: 'Fix & Edit Partner Profile',
                      onPressed: () {
                        showDialog(
                          context: context,
                          barrierColor: Colors.black.withAlpha(153),
                          builder: (context) => EditSellerDialog(seller: seller),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
                      tooltip: 'View Details',
                      onPressed: () => _openSellerDetail(context, seller),
                    ),
                  ],
                ),
              ];
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _TierFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TierFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppDecorations.radiusPill,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryContainer : AppColors.surfaceContainerLow,
          borderRadius: AppDecorations.radiusPill,
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelSm.copyWith(
            color: isSelected ? AppColors.onPrimaryContainer : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
