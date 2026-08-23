import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/database/database_service.dart';
import '../../bookings/viewmodels/ticket_sales_viewmodel.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../../operations/models/lottery_sambad_result_model.dart';
import '../../operations/models/winning_claim_model.dart';
import '../../operations/utils/winner_verification_engine.dart';

class SellerProfileLedgerScreen extends ConsumerStatefulWidget {
  final String sellerName;

  const SellerProfileLedgerScreen({
    super.key,
    required this.sellerName,
  });

  @override
  ConsumerState<SellerProfileLedgerScreen> createState() => _SellerProfileLedgerScreenState();
}

class _SellerProfileLedgerScreenState extends ConsumerState<SellerProfileLedgerScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _filterByDate = true;
  String _selectedShift = 'All';
  List<Map<String, dynamic>> _rawResults = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    await ref.read(ticketSalesViewModelProvider.notifier).loadSales();
    final results = await DatabaseService.instance.getLotteryResults();
    if (mounted) {
      setState(() {
        _rawResults = results;
      });
    }
  }

  String _formatCurrency(double amt) {
    return NumberFormat('#,##,##0', 'en_IN').format(amt);
  }

  @override
  Widget build(BuildContext context) {
    final allSales = ref.watch(ticketSalesViewModelProvider).sales;
    final selectedDateStr = DateFormat('dd/MM/yyyy').format(_selectedDate);

    // 1. Filter tickets sold specifically by THIS SELLER
    final sellerSales = allSales.where((s) {
      final matchesSeller = (s.agentName.trim().toLowerCase() == widget.sellerName.trim().toLowerCase());
      if (!matchesSeller) return false;

      bool dateMatch = true;
      if (_filterByDate) {
        final saleDateStr = DateFormat('dd/MM/yyyy').format(s.drawDate);
        dateMatch = (saleDateStr == selectedDateStr);
      }

      bool shiftMatch = true;
      if (_selectedShift != 'All') {
        final drawNameLower = s.drawName.toLowerCase();
        if (_selectedShift.contains('1 PM') && !drawNameLower.contains('1 pm') && !drawNameLower.contains('morning')) {
          shiftMatch = false;
        } else if (_selectedShift.contains('6 PM') && !drawNameLower.contains('6 pm') && !drawNameLower.contains('day')) {
          shiftMatch = false;
        } else if (_selectedShift.contains('8 PM') && !drawNameLower.contains('8 pm') && !drawNameLower.contains('evening')) {
          shiftMatch = false;
        }
      }

      return dateMatch && shiftMatch;
    }).toList();

    // 2. Parse lottery results for winner calculation
    final List<LotterySambadResultModel> resultModels = [];
    for (final raw in _rawResults) {
      final dateStr = raw['drawDateStr']?.toString() ?? '';
      bool dateMatch = true;
      if (_filterByDate) dateMatch = (dateStr == selectedDateStr);

      if (dateMatch) {
        final firstP = raw['firstPrize']?.toString() ?? '';
        List<String> splitNums(String key) {
          final v = raw[key]?.toString();
          return (v != null && v.isNotEmpty) ? v.split(',') : [];
        }

        resultModels.add(LotterySambadResultModel(
          drawId: raw['id']?.toString() ?? '',
          drawName: raw['drawName']?.toString() ?? 'Lottery Draw',
          drawDateStr: dateStr,
          drawTimeStr: raw['drawTimeStr']?.toString() ?? '',
          firstPrize: firstP,
          consolationPrize: firstP.contains(' ') ? firstP.split(' ').last : (firstP.length >= 5 ? firstP.substring(firstP.length - 5) : firstP),
          secondPrizeNumbers: splitNums('secondPrizeNumbers'),
          thirdPrizeNumbers: splitNums('thirdPrizeNumbers'),
          fourthPrizeNumbers: splitNums('fourthPrizeNumbers'),
          fifthPrizeNumbers: splitNums('fifthPrizeNumbers'),
          publishedAt: DateTime.tryParse(raw['publishedAt']?.toString() ?? '') ?? DateTime.now(),
        ));
      }
    }

    // 3. Verify winners for THIS seller
    final List<WinningClaimModel> sellerWinners = [];
    for (final res in resultModels) {
      final claims = WinnerVerificationEngine.verifyWinners(soldTickets: sellerSales, result: res);
      sellerWinners.addAll(claims);
    }

    // 4. Financial Settlement Calculations
    final double grossSalesAmount = sellerSales.fold(0.0, (sum, s) => sum + s.totalAmount);
    final double totalBonusIncentive = sellerWinners.fold(0.0, (sum, c) => sum + c.superBonus + c.specialIncentive);
    final double winningInamAmount = sellerWinners.fold(0.0, (sum, c) => sum + c.prizeAmount);
    final double netCollectibleCash = grossSalesAmount - winningInamAmount;
    final bool isPositiveBalance = netCollectibleCash >= 0;
    final int totalTicketsCount = sellerSales.fold(0, (sum, s) => sum + s.quantity);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Navigation & Seller Identity Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppColors.primary),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: AppDecorations.radiusLg,
                      ),
                      child: const Icon(Icons.person, size: 28, color: AppColors.onPrimaryContainer),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.sellerName.toUpperCase(),
                              style: AppTypography.headlineLg.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.success.withAlpha(30),
                                borderRadius: AppDecorations.radiusPill,
                                border: Border.all(color: AppColors.success.withAlpha(120)),
                              ),
                              child: const Text(
                                'ACTIVE SELLER ACCOUNT',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.success),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Detailed Daily Ticket Sales, Time Logs, Inam Claims & Cash Settlement Statement',
                          style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),

                // Action Controls: Print Bill Button & Date Filter
                Row(
                  children: [
                    // Print Bill Receipt Button
                    ElevatedButton.icon(
                      onPressed: () => _showPrintableBillDialog(
                        context,
                        sellerName: widget.sellerName,
                        dateStr: _filterByDate ? selectedDateStr : 'All Recorded Dates',
                        shiftStr: _selectedShift,
                        ticketsSold: totalTicketsCount,
                        grossSales: grossSalesAmount,
                        bonusIncentive: totalBonusIncentive,
                        winningInam: winningInamAmount,
                        netCash: netCollectibleCash,
                        sales: sellerSales,
                        winners: sellerWinners,
                      ),
                      icon: const Icon(Icons.print_outlined, color: Colors.amber),
                      label: const Text('PRINT HISAB BILL RECEIPT', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surfaceContainerHighest,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Date & Shift Filter Control Bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: AppDecorations.radiusLg,
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_list, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Text('SETTLEMENT FILTER:', style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 16),

                  // Date Toggle
                  ChoiceChip(
                    label: Text(_filterByDate ? 'Date: $selectedDateStr' : 'All Dates', style: const TextStyle(fontWeight: FontWeight.bold)),
                    selected: _filterByDate,
                    onSelected: (val) => setState(() => _filterByDate = val),
                    selectedColor: AppColors.primaryContainer,
                  ),
                  const SizedBox(width: 8),

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
                        if (picked != null) setState(() => _selectedDate = picked);
                      },
                      tooltip: 'Select Settlement Date',
                    ),
                  const SizedBox(width: 20),

                  // Shift Dropdown
                  Text('Draw Shift:', style: AppTypography.labelMd.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: AppDecorations.radiusDefault,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedShift,
                        items: ['All', 'Morning 1 PM', 'Day 6 PM', 'Evening 8 PM']
                            .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontWeight: FontWeight.bold))))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedShift = v!),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Top 4 Financial KPI Summary Cards for this Seller
            Row(
              children: [
                // 1. Total Tickets Sold & Gross Bill
                Expanded(
                  child: GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('GROSS TICKET BILL', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                            const Icon(Icons.receipt_long, color: Colors.blueAccent, size: 22),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('₹${_formatCurrency(grossSalesAmount)}', style: AppTypography.headlineMd.copyWith(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                        const SizedBox(height: 4),
                        Text('$totalTicketsCount Tickets Booked', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // 2. Bonus & Special Incentive Earned
                Expanded(
                  child: GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('BONUS & INCENTIVE', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                            const Icon(Icons.stars_outlined, color: Colors.purpleAccent, size: 22),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('₹${_formatCurrency(totalBonusIncentive)}', style: AppTypography.headlineMd.copyWith(fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                        const SizedBox(height: 4),
                        const Text('Super Bonus + Special Incentive', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // 3. Winning Inam Open (Payout)
                Expanded(
                  child: GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('WINNING INAM OPEN', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                            const Icon(Icons.emoji_events_outlined, color: Colors.amber, size: 22),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('₹${_formatCurrency(winningInamAmount)}', style: AppTypography.headlineMd.copyWith(fontWeight: FontWeight.bold, color: Colors.amber)),
                        const SizedBox(height: 4),
                        Text('${sellerWinners.length} Winner Claims', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // 4. Net Final Collectible Cash Statement
                Expanded(
                  child: GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('NET CASH TO SETTLE', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                            Icon(isPositiveBalance ? Icons.trending_up : Icons.trending_down, color: isPositiveBalance ? Colors.greenAccent : Colors.redAccent, size: 22),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '₹${_formatCurrency(netCollectibleCash.abs())}',
                          style: AppTypography.headlineMd.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isPositiveBalance ? Colors.greenAccent : Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isPositiveBalance ? '🟢 CASH TO COLLECT FROM SELLER' : '🔴 INAM DUE: PAY TO SELLER',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isPositiveBalance ? Colors.greenAccent : Colors.redAccent),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Detailed Sales Time Logs Table
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TIME-BY-TIME TICKET BOOKING LOGS', style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Exact time, date, shift, series and ticket numbers sold by ${widget.sellerName}', style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: AppDecorations.radiusPill),
                        child: Text('${sellerSales.length} Transactions', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.onPrimaryContainer)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (sellerSales.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No ticket sales recorded for this seller under selected filters.', style: TextStyle(color: Colors.grey))),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(AppColors.surfaceContainerHigh),
                        columns: const [
                          DataColumn(label: Text('SL', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('TIME', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('DATE', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('DRAW SHIFT', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('SERIES', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('TICKET NO', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('QTY', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('PRICE / TICKET', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('TOTAL BILL (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('RECEIPT NO', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: sellerSales.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final s = entry.value;
                          final timeStr = DateFormat('HH:mm:ss').format(s.saleDate);
                          final dateStr = DateFormat('dd/MM/yyyy').format(s.saleDate);

                          return DataRow(
                            cells: [
                              DataCell(Text('${idx + 1}')),
                              DataCell(Text(timeStr, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary))),
                              DataCell(Text(dateStr)),
                              DataCell(Text(s.drawName, style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text(s.ticketSeries, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber))),
                              DataCell(Text(s.ticketNumber, style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text('${s.quantity}')),
                              DataCell(Text('₹${s.pricePerTicket.toStringAsFixed(0)}')),
                              DataCell(Text('₹${_formatCurrency(s.totalAmount)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent))),
                              DataCell(Text(s.receiptNumber, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Detailed Winning Claims Table for this Seller
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WINNING INAM CLAIMS LOGS', style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Prizes won by tickets sold by ${widget.sellerName}', style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.amber.withAlpha(30), borderRadius: AppDecorations.radiusPill),
                        child: Text('${sellerWinners.length} Winners', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amber)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (sellerWinners.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No winning tickets found for this seller under selected filters.', style: TextStyle(color: Colors.grey))),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(AppColors.surfaceContainerHigh),
                        columns: const [
                          DataColumn(label: Text('SL', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('PRIZE TIER', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('TICKET NO', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('SERIES CNT', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('BASE INAM', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('SUPER BONUS', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('INCENTIVE', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('TOTAL PAYOUT (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: sellerWinners.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final c = entry.value;
                          final baseTotal = c.baseAmount * c.seriesCount;

                          return DataRow(
                            cells: [
                              DataCell(Text('${idx + 1}')),
                              DataCell(Text(c.prizeTier, style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text('${c.ticketSeries} ${c.ticketNumber}', style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text('${c.seriesCount} Series', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyanAccent))),
                              DataCell(Text('₹${_formatCurrency(baseTotal)}')),
                              DataCell(Text('₹${_formatCurrency(c.superBonus)}')),
                              DataCell(Text('₹${_formatCurrency(c.specialIncentive)}')),
                              DataCell(Text('₹${_formatCurrency(c.prizeAmount)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Printable Invoice Bill Dialog
  void _showPrintableBillDialog(
    BuildContext ctx, {
    required String sellerName,
    required String dateStr,
    required String shiftStr,
    required int ticketsSold,
    required double grossSales,
    required double bonusIncentive,
    required double winningInam,
    required double netCash,
    required List<TicketSaleModel> sales,
    required List<WinningClaimModel> winners,
  }) {
    final isPositive = netCash >= 0;

    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('PHANTOM MANAGEMENT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.black)),
                const Text('SELLER DAILY SETTLEMENT BILL STATEMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                const Divider(color: Colors.black54, thickness: 1.5, height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Seller Name: $sellerName', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                    Text('Date: $dateStr', style: const TextStyle(color: Colors.black)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Shift: $shiftStr', style: const TextStyle(color: Colors.black)),
                    Text('Time: ${DateFormat('HH:mm:ss').format(DateTime.now())}', style: const TextStyle(color: Colors.black)),
                  ],
                ),
                const Divider(color: Colors.black26, height: 20),

                // Bill Summary Lines
                _billLine('Total Tickets Sold:', '$ticketsSold tickets', isBlack: true),
                _billLine('Gross Ticket Bill (Sales):', '₹${_formatCurrency(grossSales)}', isBlack: true, isBold: true),
                _billLine('(+) Bonus & Incentive Earned:', '₹${_formatCurrency(bonusIncentive)}', isBlack: true),
                _billLine('(-) Winning Inam Payout:', '₹${_formatCurrency(winningInam)}', isBlack: true),
                const Divider(color: Colors.black, thickness: 2, height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isPositive ? 'NET CASH TO COLLECT:' : 'NET CASH TO PAY SELLER:',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.black),
                    ),
                    Text(
                      '₹${_formatCurrency(netCash.abs())}',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: isPositive ? Colors.green.shade900 : Colors.red.shade900),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                const Text('Thank you for your business!', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black54)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Close', style: TextStyle(color: Colors.black)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🖨️ Printing Settlement Bill Receipt...'), backgroundColor: AppColors.success),
              );
            },
            icon: const Icon(Icons.print, size: 16),
            label: const Text('PRINT RECEIPT'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _billLine(String label, String val, {bool isBlack = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: isBlack ? Colors.black87 : Colors.white, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(val, style: TextStyle(color: isBlack ? Colors.black : Colors.white, fontWeight: isBold ? FontWeight.bold : FontWeight.w600)),
        ],
      ),
    );
  }
}
