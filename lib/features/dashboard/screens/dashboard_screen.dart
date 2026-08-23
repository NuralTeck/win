import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/database/database_service.dart';
import '../../shared/models/ticket_sale_model.dart';

// ─── State ───────────────────────────────────────────────────────────────────

class HisabDashboardState {
  final bool isLoading;
  final String filter; // 'Today', 'All'
  final List<TicketSaleModel> sales;
  final List<Map<String, dynamic>> partyHisab; // per-seller summary
  final double totalCollection;
  final double totalInami;
  final int totalTickets;
  final int totalParties;

  const HisabDashboardState({
    this.isLoading = true,
    this.filter = 'Today',
    this.sales = const [],
    this.partyHisab = const [],
    this.totalCollection = 0,
    this.totalInami = 0,
    this.totalTickets = 0,
    this.totalParties = 0,
  });

  HisabDashboardState copyWith({
    bool? isLoading,
    String? filter,
    List<TicketSaleModel>? sales,
    List<Map<String, dynamic>>? partyHisab,
    double? totalCollection,
    double? totalInami,
    int? totalTickets,
    int? totalParties,
  }) =>
      HisabDashboardState(
        isLoading: isLoading ?? this.isLoading,
        filter: filter ?? this.filter,
        sales: sales ?? this.sales,
        partyHisab: partyHisab ?? this.partyHisab,
        totalCollection: totalCollection ?? this.totalCollection,
        totalInami: totalInami ?? this.totalInami,
        totalTickets: totalTickets ?? this.totalTickets,
        totalParties: totalParties ?? this.totalParties,
      );
}

// ─── ViewModel ───────────────────────────────────────────────────────────────

class HisabDashboardViewModel extends StateNotifier<HisabDashboardState> {
  HisabDashboardViewModel() : super(const HisabDashboardState()) {
    load();
  }

  Future<void> setFilter(String f) async {
    state = state.copyWith(filter: f);
    await load();
  }

  Future<void> load() async {
    if (!mounted) return;
    state = state.copyWith(isLoading: true);
    try {
      final allSales = await DatabaseService.instance.getTicketSales();
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final filtered = state.filter == 'Today'
          ? allSales
              .where((s) =>
                  DateFormat('yyyy-MM-dd').format(s.saleDate) == todayStr)
              .toList()
          : allSales;

      // Per-party hisab grouped by seller name
      final Map<String, Map<String, dynamic>> partyMap = {};
      for (final s in filtered) {
        final name =
            s.agentName.isNotEmpty ? s.agentName : s.buyerName.isNotEmpty ? s.buyerName : 'Direct';
        partyMap.putIfAbsent(
          name,
          () => {
            'name': name,
            'tickets': 0,
            'collection': 0.0,
            'draws': <String>{},
          },
        );
        partyMap[name]!['tickets'] =
            (partyMap[name]!['tickets'] as int) + s.quantity;
        partyMap[name]!['collection'] =
            (partyMap[name]!['collection'] as double) + s.totalAmount;
        if (s.drawName.isNotEmpty) {
          (partyMap[name]!['draws'] as Set<String>).add(s.drawName);
        }
      }

      // Sort by collection desc
      final partyList = partyMap.values.map((p) {
        return {
          'name': p['name'],
          'tickets': p['tickets'],
          'collection': p['collection'],
          'draws': (p['draws'] as Set<String>).length,
        };
      }).toList()
        ..sort((a, b) =>
            (b['collection'] as double).compareTo(a['collection'] as double));

      // Results payout from DB
      double totalInami = 0;
      try {
        final results = await DatabaseService.instance.getLotteryResults();
        totalInami = results.fold<double>(0.0, (sum, r) {
          final v = double.tryParse(r['totalPayout']?.toString() ?? '0') ?? 0.0;
          return sum + v;
        });
      } catch (_) {}

      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        sales: filtered,
        partyHisab: partyList,
        totalCollection:
            filtered.fold<double>(0.0, (s, x) => s + x.totalAmount),
        totalInami: totalInami,
        totalTickets: filtered.fold<int>(0, (s, x) => s + x.quantity),
        totalParties: partyList.length,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false);
    }
  }
}

final hisabDashboardProvider =
    StateNotifierProvider<HisabDashboardViewModel, HisabDashboardState>(
        (ref) => HisabDashboardViewModel());

// ─── Screen ──────────────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hisabDashboardProvider);
    final notifier = ref.read(hisabDashboardProvider.notifier);
    final fmt = NumberFormat('#,##,##0', 'en_IN');
    final now = DateTime.now();

    return RefreshIndicator(
      onRefresh: notifier.load,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hisab Dashboard',
                        style: AppTypography.headlineLg
                            .copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Multiple Party Lottery Hisab — ${DateFormat('EEEE, d MMM yyyy').format(now)}',
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    // Refresh
                    IconButton(
                      onPressed: notifier.load,
                      icon: state.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.primary))
                          : const Icon(Icons.refresh_rounded,
                              color: AppColors.primary),
                      tooltip: 'Refresh',
                    ),
                    const SizedBox(width: 8),
                    // Today / All filter
                    _FilterToggle(
                      selected: state.filter,
                      onChanged: notifier.setFilter,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── 4 KPI Cards ─────────────────────────────────────────────────
            GridView.count(
              crossAxisCount: 4,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 2.2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _KpiCard(
                  title: 'Total Collection',
                  value: 'Rs. ${fmt.format(state.totalCollection)}',
                  subtitle: '${state.filter} Revenue',
                  icon: Icons.currency_rupee_rounded,
                  color: const Color(0xFF22C55E),
                ),
                _KpiCard(
                  title: 'Total Tickets',
                  value: fmt.format(state.totalTickets),
                  subtitle: '${state.filter} Booked',
                  icon: Icons.local_activity_rounded,
                  color: const Color(0xFF6366F1),
                ),
                _KpiCard(
                  title: 'Active Parties',
                  value: state.totalParties.toString(),
                  subtitle: 'Sellers / Agents',
                  icon: Icons.groups_rounded,
                  color: const Color(0xFFF59E0B),
                ),
                _KpiCard(
                  title: 'Total Inami',
                  value: 'Rs. ${fmt.format(state.totalInami)}',
                  subtitle: 'Winning Payout',
                  icon: Icons.emoji_events_rounded,
                  color: const Color(0xFFEF4444),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Party-wise Hisab Table ───────────────────────────────────────
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withAlpha(30),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.receipt_long_rounded,
                                color: AppColors.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Party-wise Hisab (${state.filter})',
                            style: AppTypography.titleLg
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(20),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.primary.withAlpha(60)),
                        ),
                        child: Text(
                          '${state.partyHisab.length} Parties',
                          style: AppTypography.labelSm.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (state.isLoading)
                    const Center(
                        child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(
                          color: AppColors.primary),
                    ))
                  else if (state.partyHisab.isEmpty)
                    _EmptyParty(filter: state.filter)
                  else
                    _PartyHisabTable(
                        parties: state.partyHisab, fmt: fmt),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Draw-wise Summary ────────────────────────────────────────────
            if (state.sales.isNotEmpty) ...[
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.emoji_events_rounded,
                              color: Color(0xFF6366F1), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Draw-wise Hisab (${state.filter})',
                          style: AppTypography.titleLg
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DrawSummaryGrid(sales: state.sales, fmt: fmt),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Recent 10 Entries ────────────────────────────────────────────
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.history_rounded,
                            color: Color(0xFF22C55E), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Recent Ticket Entries',
                        style: AppTypography.titleLg
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _RecentEntriesTable(
                      sales: state.sales.take(10).toList(), fmt: fmt),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Filter Toggle ───────────────────────────────────────────────────────────

class _FilterToggle extends StatelessWidget {
  final String selected;
  final void Function(String) onChanged;

  const _FilterToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppDecorations.radiusDefault,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: ['Today', 'All'].map((f) {
          final isActive = selected == f;
          return GestureDetector(
            onTap: () => onChanged(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary
                    : Colors.transparent,
                borderRadius: AppDecorations.radiusDefault,
              ),
              child: Text(
                f,
                style: AppTypography.bodySm.copyWith(
                  color: isActive ? Colors.black : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── KPI Card ────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: AppDecorations.radiusLg,
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: AppTypography.labelSm.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTypography.titleLg.copyWith(
                      color: color, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Party Hisab Table ───────────────────────────────────────────────────────

class _PartyHisabTable extends StatelessWidget {
  final List<Map<String, dynamic>> parties;
  final NumberFormat fmt;

  const _PartyHisabTable({required this.parties, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                  flex: 3,
                  child: Text('Party / Seller',
                      style: AppTypography.labelSm.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold))),
              Expanded(
                  child: Text('Tickets',
                      textAlign: TextAlign.center,
                      style: AppTypography.labelSm.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold))),
              Expanded(
                  child: Text('Draws',
                      textAlign: TextAlign.center,
                      style: AppTypography.labelSm.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold))),
              Expanded(
                  flex: 2,
                  child: Text('Collection (Rs.)',
                      textAlign: TextAlign.right,
                      style: AppTypography.labelSm.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        const SizedBox(height: 4),
        ...parties.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          final isEven = i % 2 == 0;
          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isEven
                  ? Colors.transparent
                  : AppColors.surfaceContainerLow.withAlpha(80),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor:
                            AppColors.primary.withAlpha(40),
                        child: Text(
                          (p['name'] as String)
                              .substring(0, 1)
                              .toUpperCase(),
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          p['name'] as String,
                          style: AppTypography.bodyMd.copyWith(
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Text(
                    '${p['tickets']}',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMd.copyWith(
                        color: const Color(0xFF6366F1),
                        fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${p['draws']}',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMd
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    fmt.format(p['collection']),
                    textAlign: TextAlign.right,
                    style: AppTypography.bodyMd.copyWith(
                        color: const Color(0xFF22C55E),
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ─── Draw Summary Grid ───────────────────────────────────────────────────────

class _DrawSummaryGrid extends StatelessWidget {
  final List<TicketSaleModel> sales;
  final NumberFormat fmt;

  const _DrawSummaryGrid({required this.sales, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final Map<String, Map<String, dynamic>> drawMap = {};
    for (final s in sales) {
      final draw = s.drawName.isNotEmpty ? s.drawName : 'Unknown Draw';
      drawMap.putIfAbsent(draw, () => {'tickets': 0, 'collection': 0.0});
      drawMap[draw]!['tickets'] =
          (drawMap[draw]!['tickets'] as int) + s.quantity;
      drawMap[draw]!['collection'] =
          (drawMap[draw]!['collection'] as double) + s.totalAmount;
    }

    final draws = drawMap.entries.toList()
      ..sort((a, b) =>
          (b.value['collection'] as double)
              .compareTo(a.value['collection'] as double));

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: draws.map((e) {
        return Container(
          width: 220,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFF6366F1).withAlpha(50)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.key,
                style: AppTypography.bodyMd
                    .copyWith(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tickets:',
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.textSecondary)),
                  Text(
                    '${e.value['tickets']}',
                    style: AppTypography.bodyMd.copyWith(
                        color: const Color(0xFF6366F1),
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Collection:',
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.textSecondary)),
                  Text(
                    'Rs. ${fmt.format(e.value['collection'])}',
                    style: AppTypography.bodyMd.copyWith(
                        color: const Color(0xFF22C55E),
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── Recent Entries Table ────────────────────────────────────────────────────

class _RecentEntriesTable extends StatelessWidget {
  final List<TicketSaleModel> sales;
  final NumberFormat fmt;

  const _RecentEntriesTable({required this.sales, required this.fmt});

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No entries yet.',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                  flex: 2,
                  child: Text('Party',
                      style: AppTypography.labelSm.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold))),
              Expanded(
                  flex: 2,
                  child: Text('Draw',
                      style: AppTypography.labelSm.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold))),
              Expanded(
                  child: Text('Ticket No.',
                      style: AppTypography.labelSm.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold))),
              Expanded(
                  child: Text('Qty',
                      textAlign: TextAlign.center,
                      style: AppTypography.labelSm.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold))),
              Expanded(
                  child: Text('Amount',
                      textAlign: TextAlign.right,
                      style: AppTypography.labelSm.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        const SizedBox(height: 4),
        ...sales.asMap().entries.map((e) {
          final i = e.key;
          final s = e.value;
          final party = s.agentName.isNotEmpty
              ? s.agentName
              : s.buyerName.isNotEmpty
                  ? s.buyerName
                  : 'Direct';
          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: i % 2 == 0
                  ? Colors.transparent
                  : AppColors.surfaceContainerLow.withAlpha(80),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                    flex: 2,
                    child: Text(party,
                        style: AppTypography.bodySm
                            .copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis)),
                Expanded(
                    flex: 2,
                    child: Text(
                        s.drawName.isEmpty ? '—' : s.drawName,
                        style: AppTypography.bodySm.copyWith(
                            color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis)),
                Expanded(
                    child: Text(
                        '${s.ticketSeries}-${s.ticketNumber}',
                        style: AppTypography.bodySm.copyWith(
                            color: const Color(0xFF6366F1),
                            fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis)),
                Expanded(
                    child: Text('${s.quantity}',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySm)),
                Expanded(
                    child: Text('Rs. ${fmt.format(s.totalAmount)}',
                        textAlign: TextAlign.right,
                        style: AppTypography.bodySm.copyWith(
                            color: const Color(0xFF22C55E),
                            fontWeight: FontWeight.bold))),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ─── Empty State ─────────────────────────────────────────────────────────────

class _EmptyParty extends StatelessWidget {
  final String filter;
  const _EmptyParty({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 52, color: AppColors.textSecondary.withAlpha(100)),
            const SizedBox(height: 16),
            Text(
              filter == 'Today'
                  ? 'Aaj ki koi entry nahi\nTicket Booking tab se entry karo'
                  : 'Koi bhi hisab record nahi mila',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMd
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
