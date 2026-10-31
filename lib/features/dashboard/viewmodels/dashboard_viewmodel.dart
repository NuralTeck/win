import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../shared/models/draw_model.dart';
import '../../shared/models/metric_model.dart';
import '../../../core/database/database_service.dart';
import '../../operations/models/winning_claim_model.dart';

class DashboardState {
  final bool isLoading;
  final String dateFilter; // 'Today', 'Total'
  final List<KpiMetricModel> kpis;
  final List<DrawModel> recentDraws;
  final List<WinningClaimModel> winningClaims;
  final double totalWinningPayout;
  final String? errorMessage;

  const DashboardState({
    this.isLoading = false,
    this.dateFilter = 'Today',
    this.kpis = const [],
    this.recentDraws = const [],
    this.winningClaims = const [],
    this.totalWinningPayout = 0.0,
    this.errorMessage,
  });

  DashboardState copyWith({
    bool? isLoading,
    String? dateFilter,
    List<KpiMetricModel>? kpis,
    List<DrawModel>? recentDraws,
    List<WinningClaimModel>? winningClaims,
    double? totalWinningPayout,
    String? errorMessage,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      dateFilter: dateFilter ?? this.dateFilter,
      kpis: kpis ?? this.kpis,
      recentDraws: recentDraws ?? this.recentDraws,
      winningClaims: winningClaims ?? this.winningClaims,
      totalWinningPayout: totalWinningPayout ?? this.totalWinningPayout,
      errorMessage: errorMessage,
    );
  }
}

class DashboardViewModel extends StateNotifier<DashboardState> {

  DashboardViewModel() : super(const DashboardState()) {
    loadDashboardData();
  }

  Future<void> setDateFilter(String filter) async {
    state = state.copyWith(dateFilter: filter);
    await loadDashboardData();
  }

  Future<void> loadDashboardData() async {
    if (!mounted) return;
    try {
      final now = DateTime.now();
      final targetDate = state.dateFilter == 'Today' ? now : null;

      final results = await Future.wait([
        DatabaseService.instance.getDashboardMetrics(targetDate: targetDate),
        DatabaseService.instance.getDrawHisabSummary(targetDate: targetDate),
        DatabaseService.instance.getSellerCustomers(),
        DatabaseService.instance.getTotalInamiPayout(targetDate: targetDate),
      ]);

      if (!mounted) return;

      final metrics = results[0] as Map<String, dynamic>;
      final drawSummary = results[1] as List<Map<String, dynamic>>;
      final sellers = results[2] as List<dynamic>;
      final totalWinningPayout = results[3] as double;

      final totalRev = (metrics['totalCollection'] as num?)?.toDouble() ?? 0.0;
      final totalTkts = (metrics['totalTickets'] as num?)?.toInt() ?? 0;
      final activeSellersCount = sellers.where((s) => s.isActive == true).length;

      int count1PM = 0, count6PM = 0, count8PM = 0;
      double rev1PM = 0.0, rev6PM = 0.0, rev8PM = 0.0;

      for (var d in drawSummary) {
        final lower = (d['drawName'] ?? '').toString().toLowerCase();
        final qty = (d['tickets'] as num?)?.toInt() ?? 0;
        final col = (d['collection'] as num?)?.toDouble() ?? 0.0;
        if (lower.contains('1 pm') || lower.contains('1pm') || lower.contains('morning')) {
          count1PM += qty;
          rev1PM += col;
        } else if (lower.contains('6 pm') || lower.contains('6pm') || lower.contains('day')) {
          count6PM += qty;
          rev6PM += col;
        } else if (lower.contains('8 pm') || lower.contains('8pm') || lower.contains('night')) {
          count8PM += qty;
          rev8PM += col;
        }
      }

      final realDraws = [
        DrawModel(
          id: 'draw_1pm',
          drawCode: 'NL-1PM',
          drawName: 'Dear Morning 1:00 PM',
          drawDate: now,
          updatedAt: now,
          status: DrawStatus.open,
          priority: DrawPriority.daily,
          conductedBy: 'Directorate of Nagaland State Lotteries',
          ticketsSold: count1PM,
          totalTickets: 1000,
          ticketPrice: 6.0,
          prizePool: rev1PM,
          schemeType: 'Daily Morning',
          district: 'Nagaland State',
        ),
        DrawModel(
          id: 'draw_6pm',
          drawCode: 'NL-6PM',
          drawName: 'Dear Day 6:00 PM',
          drawDate: now,
          updatedAt: now,
          status: DrawStatus.open,
          priority: DrawPriority.daily,
          conductedBy: 'Directorate of Nagaland State Lotteries',
          ticketsSold: count6PM,
          totalTickets: 1000,
          ticketPrice: 6.0,
          prizePool: rev6PM,
          schemeType: 'Daily Day',
          district: 'Nagaland State',
        ),
        DrawModel(
          id: 'draw_8pm',
          drawCode: 'NL-8PM',
          drawName: 'Dear Night 8:00 PM',
          drawDate: now,
          updatedAt: now,
          status: DrawStatus.open,
          priority: DrawPriority.daily,
          conductedBy: 'Directorate of Nagaland State Lotteries',
          ticketsSold: count8PM,
          totalTickets: 1000,
          ticketPrice: 6.0,
          prizePool: rev8PM,
          schemeType: 'Daily Night',
          district: 'Nagaland State',
        ),
      ];

      final liveKpis = [
        KpiMetricModel(
          title: 'Total Inami Payout (${state.dateFilter})',
          value: 'Rs. ${NumberFormat('#,##,##0', 'en_IN').format(totalWinningPayout)}',
          changePercentage: 0.0,
          isPositive: true,
          subtitle: 'Winning Payout',
          icon: Icons.emoji_events_rounded,
          iconColor: const Color(0xFFFFD700),
        ),
        KpiMetricModel(
          title: 'Active Sellers',
          value: activeSellersCount.toString(),
          changePercentage: 0.0,
          isPositive: true,
          subtitle: 'Registered Sellers',
          icon: Icons.badge_outlined,
          iconColor: const Color(0xFFDDB7FF),
        ),
        KpiMetricModel(
          title: 'Revenue (${state.dateFilter})',
          value: 'Rs. ${NumberFormat('#,##,##0', 'en_IN').format(totalRev)}',
          changePercentage: 0.0,
          isPositive: true,
          subtitle: state.dateFilter == 'Today' ? 'Today Revenue' : 'Total Revenue All-Time',
          icon: Icons.currency_rupee_outlined,
          iconColor: const Color(0xFFFFB869),
        ),
        KpiMetricModel(
          title: 'Tickets Booked (${state.dateFilter})',
          value: NumberFormat('#,##,##0', 'en_IN').format(totalTkts),
          changePercentage: 0.0,
          isPositive: true,
          subtitle: state.dateFilter == 'Today' ? 'Today Ticket Sales' : 'Total Tickets All-Time',
          icon: Icons.local_activity_outlined,
          iconColor: const Color(0xFF22C55E),
        ),
      ];

      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        recentDraws: realDraws,
        winningClaims: const [],
        totalWinningPayout: totalWinningPayout,
        kpis: liveKpis,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load dashboard data.',
      );
    }
  }

  void updateDynamicMetrics({int? totalSellers, double? totalRevenue, int? totalTickets}) {}
}

final dashboardViewModelProvider =
    StateNotifierProvider<DashboardViewModel, DashboardState>((ref) {
  return DashboardViewModel();
});
