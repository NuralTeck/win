import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_service.dart';
import '../../bookings/viewmodels/ticket_sales_viewmodel.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../models/lottery_sambad_result_model.dart';
import '../models/winning_claim_model.dart';
import '../utils/winner_verification_engine.dart';
import '../../bookings/widgets/booking_history_dialog.dart';

class GeneratedHisabScreen extends ConsumerStatefulWidget {
  const GeneratedHisabScreen({super.key});

  @override
  ConsumerState<GeneratedHisabScreen> createState() => _GeneratedHisabScreenState();
}

class _GeneratedHisabScreenState extends ConsumerState<GeneratedHisabScreen> {
  DateTime _selectedDate = DateTime.now();
  String _selectedShift = 'All';
  bool _filterByDate = true;

  List<LotterySambadResultModel> _savedResults = [];

  @override
  void initState() {
    super.initState();
    _loadResultsFromDb();
  }

  Future<void> _loadResultsFromDb() async {
    try {
      final rows = await DatabaseService.instance.getLotteryResults();
      final List<LotterySambadResultModel> parsed = [];
      for (final r in rows) {
        final sec = (r['secondPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();
        final th = (r['thirdPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();
        final fo = (r['fourthPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();
        final fi = (r['fifthPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();

        parsed.add(LotterySambadResultModel(
          drawId: r['id']?.toString() ?? 'draw_${DateTime.now().millisecondsSinceEpoch}',
          drawName: r['drawName']?.toString() ?? 'DEAR MORNING 1 PM',
          drawDateStr: r['drawDateStr']?.toString() ?? '',
          drawTimeStr: r['drawTimeStr']?.toString() ?? '',
          firstPrize: r['firstPrize']?.toString() ?? '',
          consolationPrize: '',
          secondPrizeNumbers: sec,
          thirdPrizeNumbers: th,
          fourthPrizeNumbers: fo,
          fifthPrizeNumbers: fi,
          publishedAt: DateTime.tryParse(r['publishedAt']?.toString() ?? '') ?? DateTime.now(),
        ));
      }
      if (mounted) {
        setState(() {
          _savedResults = parsed;
        });
      }
    } catch (e) {
      debugPrint('Error loading results: $e');
    }
  }

  bool _matchesShift(String drawName, String shift) {
    if (shift == 'All') return true;
    final d = drawName.toLowerCase();
    final s = shift.toLowerCase();

    if (s.contains('morning') || s.contains('1')) {
      return (d.contains('1:00') || d.contains('morning') || d.contains('1 pm') || d.contains('1pm') || d.contains('1')) &&
          !d.contains('6:00') && !d.contains('6 pm') && !d.contains('6pm') &&
          !d.contains('8:00') && !d.contains('8 pm') && !d.contains('8pm');
    }
    if (s.contains('day') || s.contains('6')) {
      return (d.contains('6:00') || d.contains('day') || d.contains('6 pm') || d.contains('6pm') || d.contains('6')) &&
          !d.contains('1:00') && !d.contains('1 pm') && !d.contains('1pm') &&
          !d.contains('8:00') && !d.contains('8 pm') && !d.contains('8pm');
    }
    if (s.contains('evening') || s.contains('night') || s.contains('8')) {
      return (d.contains('8:00') || d.contains('evening') || d.contains('night') || d.contains('8 pm') || d.contains('8pm') || d.contains('8')) &&
          !d.contains('1:00') && !d.contains('1 pm') && !d.contains('1pm') &&
          !d.contains('6:00') && !d.contains('6 pm') && !d.contains('6pm');
    }
    return d.contains(s);
  }

  LotterySambadResultModel? _findResultForDraw(String drawShift, DateTime date) {
    final dateStr1 = DateFormat('dd/MM/yyyy').format(date);
    final dateStr2 = DateFormat('yyyy-MM-dd').format(date);

    for (final r in _savedResults) {
      final matchDate = r.drawDateStr == dateStr1 || r.drawDateStr == dateStr2 || r.drawDateStr.contains(dateStr1);
      if (matchDate && _matchesShift(r.drawName, drawShift)) {
        return r;
      }
    }
    return null;
  }

  void _shareHisabViaWhatsApp(String title, double sales, double inam, double net, int tktCount, List<WinningClaimModel> winners) {
    final buffer = StringBuffer();
    buffer.writeln('📊 *HISAB SETTLEMENT REPORT*');
    buffer.writeln('----------------------------------------');
    buffer.writeln('🎯 *Draw*: $title');
    buffer.writeln('🎟️ *Tickets Sold*: $tktCount');
    buffer.writeln('💰 *Total Sales*: ₹${sales.toStringAsFixed(0)}');
    buffer.writeln('🏆 *Inami Payout*: ₹${inam.toStringAsFixed(0)}');
    buffer.writeln('💵 *Net Balance*: ₹${net.toStringAsFixed(0)}');
    buffer.writeln('----------------------------------------');
    if (winners.isNotEmpty) {
      buffer.writeln('🏆 *Winners (${winners.length})*:');
      for (final w in winners.take(10)) {
        buffer.writeln('• ${w.ticketSeries} ${w.ticketNumber} -> ₹${w.prizeAmount.toStringAsFixed(0)} (${w.prizeTier})');
      }
    }
    buffer.writeln('\nGenerated via *PhantomManagement*');

    final url = 'https://wa.me/?text=${Uri.encodeComponent(buffer.toString())}';
    Process.run('cmd', ['/c', 'start', '', url]);
  }

  void _showDrawHisabDetailsModal({
    required String drawTitle,
    required DateTime drawDate,
    required List<TicketSaleModel> sales,
    required LotterySambadResultModel? result,
    required List<WinningClaimModel> winners,
    required double totalSalesAmount,
    required double totalInamAmount,
    required double netBalance,
  }) {
    // Group sales by seller
    final Map<String, List<TicketSaleModel>> sellerMap = {};
    for (final s in sales) {
      final name = s.agentName.isNotEmpty ? s.agentName : s.buyerName;
      sellerMap.putIfAbsent(name, () => []).add(s);
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 820,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 40,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          drawTitle.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Draw Date: ${DateFormat('EEEE, dd MMMM yyyy').format(drawDate)} • ${sales.length} Tickets Booked',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: result != null ? const Color(0xFF10B981).withValues(alpha: 0.15) : Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: result != null ? const Color(0xFF10B981) : Colors.amber),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          result != null ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                          size: 14,
                          color: result != null ? const Color(0xFF34D399) : Colors.amberAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          result != null ? 'SETTLED & VERIFIED' : 'AWAITING RESULT ENTRY',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: result != null ? const Color(0xFF34D399) : Colors.amberAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 16),

              // KPI Row
              Row(
                children: [
                  Expanded(
                    child: _buildModalKpi(
                      title: 'TOTAL SALES',
                      value: '₹${totalSalesAmount.toStringAsFixed(0)}',
                      subtitle: '${sales.length} Tickets',
                      color: Colors.lightBlueAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildModalKpi(
                      title: 'INAMI PAYOUT',
                      value: '₹${totalInamAmount.toStringAsFixed(0)}',
                      subtitle: '${winners.length} Winning Claims',
                      color: Colors.amberAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildModalKpi(
                      title: 'NET BALANCE',
                      value: '₹${netBalance.toStringAsFixed(0)}',
                      subtitle: netBalance >= 0 ? 'Profit Margin' : 'Deficit / Inam Higher',
                      color: netBalance >= 0 ? const Color(0xFF4ADE80) : Colors.redAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Detailed Content Area (Tabs / Scrollable Body)
              Expanded(
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      TabBar(
                        indicatorColor: AppColors.primary,
                        labelColor: Colors.white,
                        unselectedLabelColor: AppColors.textSecondary,
                        tabs: [
                          Tab(
                            icon: const Icon(Icons.people_alt_outlined, size: 18),
                            text: 'Seller-Wise Hisab (${sellerMap.length} Sellers)',
                          ),
                          Tab(
                            icon: const Icon(Icons.emoji_events_outlined, size: 18),
                            text: 'Winning Tickets (${winners.length} Winners)',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: TabBarView(
                          children: [
                            // 1. Seller Wise Hisab List
                            ListView.separated(
                              itemCount: sellerMap.length,
                              separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                              itemBuilder: (context, idx) {
                                final sellerName = sellerMap.keys.elementAt(idx);
                                final sellerSales = sellerMap[sellerName]!;
                                final sTotalSales = sellerSales.fold<double>(0.0, (acc, e) => acc + e.totalAmount);
                                final sCommission = sellerSales.fold<double>(0.0, (acc, e) => acc + e.commissionAmount);

                                // Find inam for this seller
                                final sWinners = winners.where((w) => w.sellerName.toLowerCase() == sellerName.toLowerCase()).toList();
                                final sInam = sWinners.fold<double>(0.0, (acc, e) => acc + e.prizeAmount);
                                final sNet = sTotalSales - sCommission - sInam;

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  color: idx % 2 == 0 ? const Color(0xFF0F172A) : const Color(0xFF1E293B).withValues(alpha: 0.5),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              sellerName,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                            ),
                                            Text(
                                              '${sellerSales.length} Tickets Booked',
                                              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          'Sale: ₹${sTotalSales.toStringAsFixed(0)}',
                                          style: const TextStyle(fontSize: 13, color: Colors.white70),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          'Inam: ₹${sInam.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: sInam > 0 ? Colors.amberAccent : AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          'Net: ₹${sNet.toStringAsFixed(0)}',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: sNet >= 0 ? const Color(0xFF4ADE80) : Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                            // 2. Winning Tickets List
                            winners.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          result != null ? Icons.verified_outlined : Icons.pending_actions_outlined,
                                          size: 48,
                                          color: AppColors.textSecondary,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          result != null
                                              ? 'No winning tickets identified in this draw.'
                                              : 'Result entry pending. Enter results to check winners.',
                                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: winners.length,
                                    separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                                    itemBuilder: (context, idx) {
                                      final w = winners[idx];
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        color: idx % 2 == 0 ? const Color(0xFF0F172A) : const Color(0xFF1E293B).withValues(alpha: 0.5),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.withValues(alpha: 0.15),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.emoji_events, color: Colors.amberAccent, size: 18),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${w.ticketSeries} ${w.ticketNumber}',
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 15,
                                                      letterSpacing: 0.8,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Seller: ${w.sellerName} • ${w.prizeTier}',
                                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Text(
                                              '₹${w.prizeAmount.toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: Colors.amberAccent,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Bottom Actions
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                      label: const Text('SHARE ON WHATSAPP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () {
                        _shareHisabViaWhatsApp(drawTitle, totalSalesAmount, totalInamAmount, netBalance, sales.length, winners);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text('PDF HISAB & EXPORT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        showDialog(
                          context: context,
                          builder: (c) => BookingHistoryDialog(initialDate: drawDate),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModalKpi({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allSales = ref.watch(ticketSalesViewModelProvider).sales;
    final selectedDateStr = DateFormat('dd/MM/yyyy').format(_selectedDate);

    // Group all sales by Date & Shift
    final Map<String, List<TicketSaleModel>> drawGroups = {};
    for (final s in allSales) {
      final sDateStr = DateFormat('dd/MM/yyyy').format(s.drawDate);
      if (_filterByDate && sDateStr != selectedDateStr) continue;

      String shiftKey = 'Dear 1 PM';
      final d = s.drawName.toLowerCase();
      if (d.contains('6:00') || d.contains('6 pm') || d.contains('6pm') || d.contains('day')) {
        shiftKey = 'Dear 6 PM';
      } else if (d.contains('8:00') || d.contains('8 pm') || d.contains('8pm') || d.contains('night') || d.contains('evening')) {
        shiftKey = 'Dear 8 PM';
      }

      if (_selectedShift != 'All' && !_matchesShift(shiftKey, _selectedShift)) continue;

      final groupKey = '$sDateStr — $shiftKey';
      drawGroups.putIfAbsent(groupKey, () => []).add(s);
    }

    // Default Draw Shifts for Selected Date if no sales exist yet
    if (drawGroups.isEmpty && _filterByDate) {
      final shifts = ['Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'];
      for (final sh in shifts) {
        if (_selectedShift == 'All' || _matchesShift(sh, _selectedShift)) {
          drawGroups['$selectedDateStr — $sh'] = [];
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: AppDecorations.radiusLg,
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GENERATED HISAB & DRAW SETTLEMENTS',
                        style: AppTypography.headlineLg.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Auto-calculated Draw settlements, Inami payouts, and Seller commission ledger',
                        style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => context.go(AppConstants.routeResultEntry),
                icon: const Icon(Icons.add_task_rounded, color: Colors.white, size: 18),
                label: const Text('ENTER DRAW RESULT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Filter Controls ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: AppDecorations.radiusLg,
              border: Border.all(color: AppColors.border),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Date Filter Chip
                    ChoiceChip(
                      label: Text(_filterByDate ? 'Date: $selectedDateStr' : 'All Dates', style: const TextStyle(fontWeight: FontWeight.bold)),
                      selected: _filterByDate,
                      onSelected: (val) => setState(() => _filterByDate = val),
                      selectedColor: AppColors.primaryContainer,
                    ),
                    if (_filterByDate)
                      IconButton(
                        icon: const Icon(Icons.calendar_month, color: AppColors.primary),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setState(() => _selectedDate = picked);
                            _loadResultsFromDb();
                          }
                        },
                        tooltip: 'Select Date',
                      ),
                    const SizedBox(width: 10),

                    // Shift Filter Dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: AppDecorations.radiusDefault,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedShift,
                          items: ['All', 'Morning', 'Day', 'Evening'].map((s) {
                            String label = s;
                            if (s == 'Morning') label = '1:00 PM (Morning Draw)';
                            if (s == 'Day') label = '6:00 PM (Day Draw)';
                            if (s == 'Evening') label = '8:00 PM (Night Draw)';
                            return DropdownMenuItem(value: s, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)));
                          }).toList(),
                          onChanged: (v) => setState(() => _selectedShift = v!),
                        ),
                      ),
                    ),
                  ],
                ),

                // Refresh Button
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(ticketSalesViewModelProvider.notifier).loadSales();
                    _loadResultsFromDb();
                  },
                  icon: const Icon(Icons.refresh, size: 16, color: AppColors.primary),
                  label: const Text('Refresh Data', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Draw Hisab Cards Grid ──────────────────────────────────────────
          if (drawGroups.isEmpty)
            const Padding(
              padding: EdgeInsets.all(60),
              child: Center(
                child: Text('No hisab records found for selected filters.', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: drawGroups.length,
              itemBuilder: (context, index) {
                final groupKey = drawGroups.keys.elementAt(index);
                final sales = drawGroups[groupKey]!;

                // Extract Shift and Date
                final parts = groupKey.split(' — ');
                final datePart = parts[0];
                final shiftPart = parts.length > 1 ? parts[1] : 'Dear 1 PM';

                // Look up matching official result
                final matchingResult = _findResultForDraw(shiftPart, _selectedDate);

                // Compute verified winners if result is entered
                List<WinningClaimModel> winners = [];
                if (matchingResult != null && sales.isNotEmpty) {
                  winners = WinnerVerificationEngine.verifyWinners(
                    result: matchingResult,
                    soldTickets: sales,
                  );
                }

                final totalSales = sales.fold<double>(0.0, (acc, e) => acc + e.totalAmount);
                final totalCommission = sales.fold<double>(0.0, (acc, e) => acc + e.commissionAmount);
                final totalInam = winners.fold<double>(0.0, (acc, e) => acc + e.prizeAmount);
                final netBalance = totalSales - totalCommission - totalInam;

                // Color accent based on draw timing
                Color shiftColor = Colors.amber;
                IconData shiftIcon = Icons.wb_sunny_outlined;
                if (shiftPart.contains('6')) {
                  shiftColor = Colors.lightBlueAccent;
                  shiftIcon = Icons.wb_twilight;
                } else if (shiftPart.contains('8')) {
                  shiftColor = Colors.purpleAccent;
                  shiftIcon = Icons.nights_stay_outlined;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: GlassCard(
                    child: InkWell(
                      onTap: () {
                        _showDrawHisabDetailsModal(
                          drawTitle: '$shiftPart ($datePart)',
                          drawDate: _selectedDate,
                          sales: sales,
                          result: matchingResult,
                          winners: winners,
                          totalSalesAmount: totalSales,
                          totalInamAmount: totalInam,
                          netBalance: netBalance,
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            // Draw Icon
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: shiftColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                                border: Border.all(color: shiftColor.withValues(alpha: 0.4), width: 2),
                              ),
                              child: Icon(shiftIcon, color: shiftColor, size: 28),
                            ),
                            const SizedBox(width: 18),

                            // Draw Title & Status
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        shiftPart.toUpperCase(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 17,
                                          color: shiftColor,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: matchingResult != null
                                              ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                              : Colors.amber.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: matchingResult != null ? const Color(0xFF10B981) : Colors.amber,
                                          ),
                                        ),
                                        child: Text(
                                          matchingResult != null ? 'SETTLED' : 'RESULT PENDING',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: matchingResult != null ? const Color(0xFF34D399) : Colors.amberAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Draw Date: $datePart • ${sales.length} Tickets Booked',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                  ),
                                  if (matchingResult != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '1st Prize Number: ${matchingResult.firstPrize}',
                                        style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            // Metrics Summary
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('TOTAL SALES', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text('₹${totalSales.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                ],
                              ),
                            ),

                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('INAMI PAYOUT', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '₹${totalInam.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: totalInam > 0 ? Colors.amberAccent : Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('NET HISAB', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '₹${netBalance.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: netBalance >= 0 ? const Color(0xFF4ADE80) : Colors.redAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Right Action Arrow
                            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
