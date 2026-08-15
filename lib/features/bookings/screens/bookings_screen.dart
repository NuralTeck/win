import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/utils/formatters.dart';
import '../viewmodels/bookings_viewmodel.dart';
import '../widgets/edit_booking_dialog.dart';
import '../../shared/models/booking_model.dart';

class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bookingsViewModelProvider);
    final notifier = ref.read(bookingsViewModelProvider.notifier);

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
                      'Bookings & Settlement Ledger',
                      style: AppTypography.headlineLg.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Immutable financial transaction trail, platform fee splits, and settlement batches',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  AppSecondaryButton(
                    label: 'Export CSV',
                    icon: Icons.table_chart_outlined,
                    onPressed: () {},
                  ),
                  const SizedBox(width: 12),
                  AppPrimaryButton(
                    label: 'Batch Settlement',
                    icon: Icons.account_balance_wallet_outlined,
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Ledger Summary Cards
          Row(
            children: [
              Expanded(
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Filtered Volume',
                        style: AppTypography.labelMd.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Formatters.formatCurrency(state.totalVolume),
                        style: AppTypography.headlineMd.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Platform Revenue (Fee Cut)',
                        style: AppTypography.labelMd.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Formatters.formatCurrency(state.totalCommissions),
                        style: AppTypography.headlineMd.copyWith(
                          color: AppColors.tertiary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Record Count',
                        style: AppTypography.labelMd.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Formatters.formatNumber(state.filteredBookings.length),
                        style: AppTypography.headlineMd.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Search & Filter Bar
          Row(
            children: [
              SizedBox(
                width: 340,
                child: AppSearchField(
                  hintText: 'Search reference #, customer, or seller...',
                  onChanged: notifier.setSearchQuery,
                ),
              ),
              const SizedBox(width: 16),
              _BookingFilterChip(
                label: 'All Statuses',
                isSelected: state.selectedStatus == null,
                onTap: () => notifier.setStatusFilter(null),
              ),
              const SizedBox(width: 8),
              _BookingFilterChip(
                label: 'Settled',
                isSelected: state.selectedStatus == BookingStatus.settled,
                onTap: () => notifier.setStatusFilter(BookingStatus.settled),
              ),
              const SizedBox(width: 8),
              _BookingFilterChip(
                label: 'Processing',
                isSelected: state.selectedStatus == BookingStatus.processing,
                onTap: () => notifier.setStatusFilter(BookingStatus.processing),
              ),
              const SizedBox(width: 8),
              _BookingFilterChip(
                label: 'Flagged',
                isSelected: state.selectedStatus == BookingStatus.flagged,
                onTap: () => notifier.setStatusFilter(BookingStatus.flagged),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Bookings Table
          AppDataTable(
            isLoading: state.isLoading,
            columns: const [
              AppTableColumn(label: 'REF NUMBER', width: 150),
              AppTableColumn(label: 'CUSTOMER & SERVICE'),
              AppTableColumn(label: 'SELLER / PARTNER', width: 220),
              AppTableColumn(label: 'GROSS AMOUNT', width: 140),
              AppTableColumn(label: 'PLATFORM FEE', width: 120),
              AppTableColumn(label: 'STATUS', width: 120),
              AppTableColumn(label: 'DATE & TIME', width: 150),
              AppTableColumn(label: 'ACTIONS', width: 60, alignment: Alignment.centerRight),
            ],
            rows: state.filteredBookings.map((b) {
              return [
                Text(
                  b.referenceNumber,
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
                      b.customerName,
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${b.serviceType} • ${b.paymentMethod}',
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.textSecondary.withAlpha(150),
                      ),
                    ),
                  ],
                ),
                Text(
                  b.sellerName,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  Formatters.formatCurrency(b.amount),
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  Formatters.formatCurrency(b.commissionFee),
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.tertiary,
                  ),
                ),
                StatusBadge.fromStatus(b.status.name),
                Text(
                  Formatters.formatDateTime(b.bookingDate),
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.tune, size: 18, color: AppColors.primary),
                  tooltip: 'Fix & Edit Ledger Entry',
                  onPressed: () {
                    showDialog(
                      context: context,
                      barrierColor: Colors.black.withAlpha(153),
                      builder: (context) => EditBookingDialog(booking: b),
                    );
                  },
                ),
              ];
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _BookingFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _BookingFilterChip({
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
