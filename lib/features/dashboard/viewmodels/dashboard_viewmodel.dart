import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../shared/models/draw_model.dart';
import '../../shared/models/metric_model.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../../../core/database/database_service.dart';
import '../../operations/models/winning_claim_model.dart';
import '../../operations/models/lottery_sambad_result_model.dart';
import '../../operations/utils/winner_verification_engine.dart';

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
      final allSales = await DatabaseService.instance.getTicketSales();
      final sellers = await DatabaseService.instance.getSellerCustomers();

      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);

      List<TicketSaleModel> filteredSales = allSales;
      if (state.dateFilter == 'Today') {
        filteredSales = allSales.where((s) {
          final sDate = DateFormat('yyyy-MM-dd').format(s.saleDate);
          return sDate == todayStr;
        }).toList();
      }

      final totalRev = filteredSales.fold(0.0, (sum, s) => sum + s.totalAmount);
      final totalTkts = filteredSales.fold(0, (sum, s) => sum + s.quantity);
      final activeSellersCount = sellers.where((s) => s.isActive).length;

      // Calculate real active draw stats from sales
      int count1PM = 0, count6PM = 0, count8PM = 0;
      double rev1PM = 0.0, rev6PM = 0.0, rev8PM = 0.0;

      for (var sale in filteredSales) {
        final lower = sale.drawName.toLowerCase();
        if (lower.contains('1 pm') || lower.contains('1pm') || lower.contains('morning')) {
          count1PM += sale.quantity;
          rev1PM += sale.totalAmount;
        } else if (lower.contains('6 pm') || lower.contains('6pm') || lower.contains('day')) {
          count6PM += sale.quantity;
          rev6PM += sale.totalAmount;
        } else if (lower.contains('8 pm') || lower.contains('8pm') || lower.contains('night')) {
          count8PM += sale.quantity;
          rev8PM += sale.totalAmount;
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

      // Calculate verified winners & itemized prize/bonus/incentive metrics
      final List<WinningClaimModel> verifiedWinners = [];
      try {
        final rawResults = await DatabaseService.instance.getLotteryResults();
        for (final raw in rawResults) {
          final drawTimeStr = raw['drawTimeStr']?.toString() ?? '';
          final firstP = raw['firstPrize']?.toString() ?? '';
          List<String> splitNums(String key) {
            final v = raw[key]?.toString();
            return (v != null && v.isNotEmpty) ? v.split(',') : [];
          }

          final resModel = LotterySambadResultModel(
            drawId: raw['id']?.toString() ?? '',
            drawName: raw['drawName']?.toString() ?? 'Lottery Draw',
            drawDateStr: raw['drawDateStr']?.toString() ?? '',
            drawTimeStr: drawTimeStr,
            firstPrize: firstP,
            consolationPrize: firstP.contains(' ') ? firstP.split(' ').last : (firstP.length >= 5 ? firstP.substring(firstP.length - 5) : firstP),
            secondPrizeNumbers: splitNums('secondPrizeNumbers'),
            thirdPrizeNumbers: splitNums('thirdPrizeNumbers'),
            fourthPrizeNumbers: splitNums('fourthPrizeNumbers'),
            fifthPrizeNumbers: splitNums('fifthPrizeNumbers'),
            publishedAt: DateTime.tryParse(raw['publishedAt']?.toString() ?? '') ?? DateTime.now(),
          );

          final claims = WinnerVerificationEngine.verifyWinners(soldTickets: filteredSales, result: resModel);
          verifiedWinners.addAll(claims);
        }
      } catch (_) {}

      final totalWinningPayout = verifiedWinners.fold(0.0, (sum, c) => sum + c.prizeAmount);

      final liveKpis = [
        KpiMetricModel(
          title: 'Total Inami Payout (${state.dateFilter})',
          value: 'Rs. ${NumberFormat('#,##,##0', 'en_IN').format(totalWinningPayout)}',
          changePercentage: 0.0,
          isPositive: true,
          subtitle: '${verifiedWinners.length} Winning Claims',
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
        winningClaims: verifiedWinners,
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
