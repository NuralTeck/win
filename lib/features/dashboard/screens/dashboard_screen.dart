import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/constants/app_constants.dart';
import '../viewmodels/dashboard_viewmodel.dart';
import '../../bookings/viewmodels/ticket_sales_viewmodel.dart';
import '../../bookings/widgets/booking_history_dialog.dart';
import '../../shared/models/draw_model.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dashboardViewModelProvider.notifier).loadDashboardData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardViewModelProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nagaland Lottery Command Center',
                      style: AppTypography.headlineLg.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Live draw monitoring, ticket revenue, agent performance — ${_todayLabel()}',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  _LiveIndicator(),
                  const SizedBox(width: 14),
                  // Date Filter Selector: Today vs Total / All
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: AppDecorations.radiusDefault,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Today', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          selected: state.dateFilter == 'Today',
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(color: state.dateFilter == 'Today' ? Colors.white : AppColors.textSecondary),
                          onSelected: (sel) {
                            if (sel) {
                              ref.read(dashboardViewModelProvider.notifier).setDateFilter('Today');
                            }
                          },
                        ),
                        const SizedBox(width: 4),
                        ChoiceChip(
                          label: const Text('Total / All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          selected: state.dateFilter == 'Total',
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(color: state.dateFilter == 'Total' ? Colors.white : AppColors.textSecondary),
                          onSelected: (sel) {
                            if (sel) {
                              ref.read(dashboardViewModelProvider.notifier).setDateFilter('Total');
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  AppSecondaryButton(
                    label: 'Daily Report',
                    icon: Icons.file_download_outlined,
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => BookingHistoryDialog(initialDate: DateTime.now()),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  AppPrimaryButton(
                    label: 'New Ticket Entry',
                    icon: Icons.local_activity,
                    onPressed: () => context.go(AppConstants.routeBookings),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── KPI Cards ─────────────────────────────────────────────────────
          SizedBox(
            height: 140,
            child: Row(
              children: state.kpis.map((kpi) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: state.kpis.last == kpi ? 0 : 16,
                    ),
                    child: KpiCard(metric: kpi),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 28),

          // ── Active Draws + Quick Stats side by side ───────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                // Active Draws Table (left, 70%)
                Expanded(
                  flex: 70,
                  child: GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Active Lottery Draws',
                              style: AppTypography.headlineMd.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextButton(
                              onPressed: () => context.go(AppConstants.routeOperations),
                              child: Text(
                                'View All Draws →',
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        AppDataTable(
                          columns: const [
                            AppTableColumn(label: 'CODE', width: 110),
                            AppTableColumn(label: 'DRAW NAME'),
                            AppTableColumn(label: 'STATUS', width: 110),
                            AppTableColumn(label: 'SOLD / TOTAL', width: 140),
                            AppTableColumn(label: '₹/TICKET', width: 90),
                            AppTableColumn(label: 'PRIZE POOL', width: 120),
                          ],
                          rows: state.recentDraws.map((d) {
                            return [
                              Text(
                                d.drawCode,
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
                                    d.drawName,
                                    style: AppTypography.bodySm.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${d.schemeType} • ${d.district}',
                                    style: AppTypography.labelSm.copyWith(
                                      color: AppColors.textSecondary.withAlpha(150),
                                    ),
                                  ),
                                ],
                              ),
                              StatusBadge.fromStatus(d.status.name),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${Formatters.formatNumber(d.ticketsSold)} / ${Formatters.formatNumber(d.totalTickets)}',
                                    style: AppTypography.bodySm.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  ClipRRect(
                                    borderRadius: AppDecorations.radiusPill,
                                    child: LinearProgressIndicator(
                                      value: d.salesProgress,
                                      minHeight: 4,
                                      backgroundColor: AppColors.surfaceContainerHigh,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        d.salesProgress > 0.8
                                            ? AppColors.success
                                            : (d.salesProgress > 0.5
                                                ? AppColors.primary
                                                : AppColors.warning),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '₹${d.ticketPrice.toStringAsFixed(d.ticketPrice % 1 == 0 ? 0 : 2)}',
                                style: AppTypography.bodySm.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.tertiary,
                                ),
                              ),
                              Text(
                                Formatters.formatIndianCurrency(d.prizePool),
                                style: AppTypography.bodySm.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ];
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 20),

                // Right Panel – Quick Stats (30%)
                Expanded(
                  flex: 30,
                  child: Column(
                    children: [
                      // Prize Pool Summary
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.tertiary.withAlpha(30),
                                    borderRadius: AppDecorations.radiusDefault,
                                  ),
                                  child: const Icon(
                                    Icons.emoji_events_outlined,
                                    color: AppColors.tertiary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Total Prize Pools',
                                    style: AppTypography.labelMd.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              Formatters.formatIndianCurrency(
                                state.recentDraws
                                    .fold(0.0, (s, d) => s + d.prizePool),
                              ),
                              style: AppTypography.headlineMd.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.tertiary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Across ${state.recentDraws.length} draws shown',
                              style: AppTypography.labelSm.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Draw Status Breakdown
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Draw Status Breakdown',
                              style: AppTypography.labelMd.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _StatusRow(
                              label: 'Open',
                              color: AppColors.success,
                              count: state.recentDraws
                                  .where((d) => d.status == DrawStatus.open)
                                  .length,
                            ),
                            const SizedBox(height: 8),
                            _StatusRow(
                              label: 'Closed / Pending',
                              color: AppColors.warning,
                              count: state.recentDraws
                                  .where((d) => d.status == DrawStatus.closed)
                                  .length,
                            ),
                            const SizedBox(height: 8),
                            _StatusRow(
                              label: 'Completed',
                              color: AppColors.primary,
                              count: state.recentDraws
                                  .where((d) => d.status == DrawStatus.completed)
                                  .length,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Quick Navigation
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Quick Access',
                              style: AppTypography.labelMd.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _QuickNavTile(
                              icon: Icons.local_activity_outlined,
                              label: 'Ticket Sales',
                              onTap: () => context.go(AppConstants.routeBookings),
                            ),
                            const SizedBox(height: 8),
                            _QuickNavTile(
                              icon: Icons.bar_chart_outlined,
                              label: 'Revenue & Payouts',
                              onTap: () => context.go(AppConstants.routeAnalytics),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

          const SizedBox(height: 28),

          // ── Recent Ticket Sales Ticker ─────────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Ticket Activity',
                      style: AppTypography.headlineMd.copyWith(fontWeight: FontWeight.w700),
                    ),
                    TextButton(
                      onPressed: () => context.go(AppConstants.routeBookings),
                      child: Text(
                        'View All Sales →',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Activity rows
                Builder(builder: (context) {
                  final allSales = ref.watch(ticketSalesViewModelProvider).sales;
                  final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                  final liveSales = state.dateFilter == 'Today'
                      ? allSales.where((s) => DateFormat('yyyy-MM-dd').format(s.saleDate) == todayStr).toList()
                      : allSales;

                  if (liveSales.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'No ticket bookings recorded for ${state.dateFilter}. Click "New Ticket Entry" to start booking live tickets.',
                          style: const TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                        ),
                      ),
                    );
                  }

                  final recentList = liveSales.take(5).toList();
                  return Column(
                    children: recentList.map((sale) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: AppDecorations.radiusDefault,
                          border: Border.all(color: AppColors.border, width: 1),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primaryContainer,
                                borderRadius: AppDecorations.radiusDefault,
                              ),
                              child: const Icon(Icons.local_activity, size: 18, color: AppColors.onPrimaryContainer),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${sale.agentName} (Buyer: ${sale.buyerName})',
                                    style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    '${sale.drawName} • ${sale.ticketSeries} ${sale.ticketNumber} (${sale.receiptNumber})',
                                    style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '₹${sale.totalAmount.toStringAsFixed(0)}',
                              style: AppTypography.bodyMd.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.tertiary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerHigh,
                                borderRadius: AppDecorations.radiusSm,
                              ),
                              child: Text(
                                sale.paymentMode.name.toUpperCase(),
                                style: AppTypography.labelSm.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }
}

class _LiveIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.success.withAlpha(20),
        borderRadius: AppDecorations.radiusPill,
        border: Border.all(color: AppColors.success.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE',
            style: AppTypography.labelSm.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final Color color;
  final int count;

  const _StatusRow({required this.label, required this.color, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(label, style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary)),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: AppDecorations.radiusSm,
          ),
          child: Text(
            count.toString(),
            style: AppTypography.labelSm.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _QuickNavTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickNavTile({required this.icon, required this.label, required this.onTap});

  @override
  State<_QuickNavTile> createState() => _QuickNavTileState();
}

class _QuickNavTileState extends State<_QuickNavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.hover : Colors.transparent,
            borderRadius: AppDecorations.radiusDefault,
            border: Border.all(
              color: _hovered ? AppColors.primary.withAlpha(80) : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: _hovered ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: AppTypography.bodySm.copyWith(
                  color: _hovered ? AppColors.textPrimary : AppColors.textSecondary,
                  fontWeight: _hovered ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const Spacer(),
              Icon(Icons.chevron_right, size: 16, color: _hovered ? AppColors.primary : AppColors.textSecondary.withAlpha(100)),
            ],
          ),
        ),
      ),
    );
  }
}
