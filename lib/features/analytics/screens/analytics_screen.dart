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
import '../../sellers/models/seller_customer_model.dart';
import '../../sellers/screens/seller_profile_ledger_screen.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _filterByDate = true; // Default: TRUE (Current Date Hisab-Kitab!)
  String _selectedShift = 'All'; // 'All', 'Morning 1 PM', 'Day 6 PM', 'Evening 8 PM'

  List<Map<String, dynamic>> _rawResults = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    if (_rawResults.isNotEmpty) return;
    await ref.read(ticketSalesViewModelProvider.notifier).loadSales();
    final results = await DatabaseService.instance.getLotteryResults();
    if (mounted) {
      setState(() {
        _rawResults = results;
      });
    }
  }


  Future<void> _generateDemoHisabData() async {
    final now = DateTime.now();
    final todayStr = DateFormat('dd/MM/yyyy').format(now);

    // 1. Ensure Sellers Exist in Database
    final sellerRepo = DatabaseService.instance;
    await sellerRepo.insertSellerCustomer(SellerCustomerModel(
      id: 'sel_rajiv',
      name: 'Rajiv Kumar',
      accessKey: 'SEL-101',
      password: '123',
      phone: '9876543210',
      isActive: true,
      createdAt: now,
    ));
    await sellerRepo.insertSellerCustomer(SellerCustomerModel(
      id: 'sel_akheto',
      name: 'Akheto Sema',
      accessKey: 'SEL-102',
      password: '123',
      phone: '9876543211',
      isActive: true,
      createdAt: now,
    ));
    await sellerRepo.insertSellerCustomer(SellerCustomerModel(
      id: 'sel_tokugha',
      name: 'Tokugha Sulai',
      accessKey: 'SEL-103',
      password: '123',
      phone: '9876543212',
      isActive: true,
      createdAt: now,
    ));

    // 2. Insert Sample Ticket Sales
    final demoSales = [
      TicketSaleModel(
        id: 'tkt_demo_1',
        receiptNumber: 'REC-82A-99831',
        buyerName: 'Ramesh Sharma',
        buyerPhone: '9876543210',
        agentCode: 'SEL-101',
        agentName: 'Rajiv Kumar',
        drawCode: 'DEAR-1PM',
        drawName: 'Dear Morning 1 PM',
        ticketSeries: '82A',
        ticketNumber: '82A 99831',
        quantity: 50,
        pricePerTicket: 10.0,
        totalAmount: 500.0,
        commissionAmount: 25.0,
        status: TicketStatus.sold,
        paymentMode: PaymentMode.cash,
        saleDate: now,
        drawDate: now,
      ),
      TicketSaleModel(
        id: 'tkt_demo_2',
        receiptNumber: 'REC-82A-48192',
        buyerName: 'Anita Roy',
        buyerPhone: '9876543211',
        agentCode: 'SEL-102',
        agentName: 'Akheto Sema',
        drawCode: 'DEAR-1PM',
        drawName: 'Dear Morning 1 PM',
        ticketSeries: '82A',
        ticketNumber: '82A 48192',
        quantity: 100,
        pricePerTicket: 10.0,
        totalAmount: 1000.0,
        commissionAmount: 50.0,
        status: TicketStatus.sold,
        paymentMode: PaymentMode.upi,
        saleDate: now,
        drawDate: now,
      ),
      TicketSaleModel(
        id: 'tkt_demo_3',
        receiptNumber: 'REC-54B-12345',
        buyerName: 'Vikram Singh',
        buyerPhone: '9876543212',
        agentCode: 'SEL-103',
        agentName: 'Tokugha Sulai',
        drawCode: 'DEAR-1PM',
        drawName: 'Dear Morning 1 PM',
        ticketSeries: '54B',
        ticketNumber: '54B 12345',
        quantity: 200,
        pricePerTicket: 10.0,
        totalAmount: 2000.0,
        commissionAmount: 100.0,
        status: TicketStatus.sold,
        paymentMode: PaymentMode.cash,
        saleDate: now,
        drawDate: now,
      ),
      TicketSaleModel(
        id: 'tkt_demo_4',
        receiptNumber: 'REC-91C-04812',
        buyerName: 'Sanjay Gupta',
        buyerPhone: '9876543213',
        agentCode: 'SEL-101',
        agentName: 'Rajiv Kumar',
        drawCode: 'DEAR-1PM',
        drawName: 'Dear Morning 1 PM',
        ticketSeries: '91C',
        ticketNumber: '91C 04812',
        quantity: 80,
        pricePerTicket: 10.0,
        totalAmount: 800.0,
        commissionAmount: 40.0,
        status: TicketStatus.sold,
        paymentMode: PaymentMode.cash,
        saleDate: now,
        drawDate: now,
      ),
    ];

    for (final sale in demoSales) {
      await ref.read(ticketSalesViewModelProvider.notifier).addTicketSale(sale);
    }

    // 3. Insert Published 1 PM Result matching 2nd, 3rd, 4th, 5th prizes
    final demoResult = LotterySambadResultModel(
      drawId: 'res_demo_1pm',
      drawName: 'Dear Morning 1 PM',
      drawDateStr: todayStr,
      drawTimeStr: 'Morning',
      firstPrize: '82A 99831', // 1st Prize Winner!
      consolationPrize: '99831',
      secondPrizeNumbers: ['48192', '11223', '33445', '55667', '77889', '99001', '12344', '56788', '90122', '34566'], // 2nd Prize Winner (48192)!
      thirdPrizeNumbers: ['2345', '4812', '6789', '0123', '4567', '8901', '2345', '6789', '0123', '4567'], // 3rd Prize Winner (04812 -> 4812)!
      fourthPrizeNumbers: ['1234', '5678', '9012', '3456', '7890', '1234', '5678', '9012', '3456', '7890'],
      fifthPrizeNumbers: ['2345', '6789', '0123', '4567', '8901', '2345', '6789', '0123', '4567', '8901'],
      publishedAt: now,
    );

    await DatabaseService.instance.insertLotteryResult(demoResult, verifiedWinnersCount: 3, totalPayoutAmount: 10009500.0);

    await _loadData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚡ Sample Demo Sales & Result Generated Successfully! Hisab is now Active.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _showSalesDetailDialog(BuildContext ctx, List<TicketSaleModel> sales) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg),
        title: Row(
          children: [
            const Icon(Icons.monetization_on, color: Colors.blueAccent),
            const SizedBox(width: 10),
            Text('Ticket Sales Detail (${sales.length} Bookings)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: sales.isEmpty
              ? const Center(child: Text('No sales recorded for this filter.'))
              : ListView.separated(
                  itemCount: sales.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, idx) {
                    final s = sales[idx];
                    return ListTile(
                      dense: true,
                      title: Text('${s.ticketSeries} ${s.ticketNumber} (${s.drawName})', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Seller: ${s.agentName} | Receipt: ${s.receiptNumber} | Date: ${DateFormat('dd/MM/yyyy HH:mm').format(s.saleDate)}'),
                      trailing: Text('₹${_formatCurrency(s.totalAmount)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 15)),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showInamDetailDialog(BuildContext ctx, List<WinningClaimModel> claims) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg),
        title: Row(
          children: [
            const Icon(Icons.emoji_events, color: Colors.amber),
            const SizedBox(width: 10),
            Text('Winning Inam Detail (${claims.length} Winners)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 650,
          height: 400,
          child: claims.isEmpty
              ? const Center(child: Text('No winning tickets found for this filter.'))
              : ListView.separated(
                  itemCount: claims.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, idx) {
                    final c = claims[idx];
                    return ListTile(
                      dense: true,
                      title: Text('${c.prizeTier} — Ticket #${c.ticketSeries} ${c.ticketNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Winning No: ${c.winningNumber} | Seller: ${c.sellerName} | Buyer: ${c.buyerName}'),
                      trailing: Text('₹${_formatCurrency(c.prizeAmount)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 15)),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showProfitLossDetailDialog(
    BuildContext ctx, {
    required double totalSalesAmount,
    required double totalInamOpenAmount,
    required double totalCommissionAmount,
    required double netCompanyProfitLoss,
    required bool isCompanyInProfit,
  }) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg),
        title: Row(
          children: [
            Icon(isCompanyInProfit ? Icons.trending_up : Icons.trending_down, color: isCompanyInProfit ? Colors.greenAccent : Colors.redAccent),
            const SizedBox(width: 10),
            Text(isCompanyInProfit ? 'Company Net Profit Breakdown' : 'Company Net Loss Breakdown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPlRow('(+) Total Ticket Sales Income', '₹${_formatCurrency(totalSalesAmount)}', Colors.blueAccent),
              const SizedBox(height: 10),
              _buildPlRow('(-) Total Open Inam (Prize Payout)', '₹${_formatCurrency(totalInamOpenAmount)}', Colors.amber),
              const SizedBox(height: 10),
              _buildPlRow('(-) Agent Commission (5%)', '₹${_formatCurrency(totalCommissionAmount)}', Colors.purpleAccent),
              const Divider(height: 24),
              _buildPlRow('(=) NET COMPANY STATUS', '₹${_formatCurrency(netCompanyProfitLoss.abs())}', isCompanyInProfit ? Colors.greenAccent : Colors.redAccent, isBold: true),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (isCompanyInProfit ? Colors.green : Colors.red).withAlpha(30),
                  borderRadius: AppDecorations.radiusDefault,
                ),
                child: Text(
                  isCompanyInProfit
                      ? '🟢 Net Company Status is in PROFIT (+₹${_formatCurrency(netCompanyProfitLoss)})'
                      : '🔴 Net Company Status is in LOSS (-₹${_formatCurrency(netCompanyProfitLoss.abs())})',
                  style: TextStyle(fontWeight: FontWeight.bold, color: isCompanyInProfit ? Colors.greenAccent : Colors.redAccent),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildPlRow(String label, String value, Color col, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w500, fontSize: isBold ? 15 : 14)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: col, fontSize: isBold ? 17 : 14)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final allSales = ref.watch(ticketSalesViewModelProvider).sales;
    final selectedDateStr = DateFormat('dd/MM/yyyy').format(_selectedDate);

    // Filter sales by selected date and shift (if date filter enabled)
    final filteredSales = allSales.where((s) {
      bool dateMatch = true;
      if (_filterByDate) {
        final saleDateStr = DateFormat('dd/MM/yyyy').format(s.saleDate);
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

    // Parse published lottery results into model list
    final List<LotterySambadResultModel> resultModels = [];
    for (final raw in _rawResults) {
      final dateStr = raw['drawDateStr']?.toString() ?? '';
      bool dateMatch = true;
      if (_filterByDate) {
        dateMatch = (dateStr == selectedDateStr);
      }

      if (dateMatch) {
        final drawTimeStr = raw['drawTimeStr']?.toString() ?? '';
        bool shiftMatch = true;
        if (_selectedShift != 'All') {
          if (_selectedShift.contains('1 PM') && !drawTimeStr.contains('Morning') && !drawTimeStr.contains('1 PM')) {
            shiftMatch = false;
          } else if (_selectedShift.contains('6 PM') && !drawTimeStr.contains('Day') && !drawTimeStr.contains('6 PM')) {
            shiftMatch = false;
          } else if (_selectedShift.contains('8 PM') && !drawTimeStr.contains('Evening') && !drawTimeStr.contains('8 PM')) {
            shiftMatch = false;
          }
        }

        if (shiftMatch) {
          final firstP = raw['firstPrize']?.toString() ?? '';
          List<String> splitNums(String key) {
            final v = raw[key]?.toString();
            return (v != null && v.isNotEmpty) ? v.split(',') : [];
          }

          resultModels.add(LotterySambadResultModel(
            drawId: raw['id']?.toString() ?? '',
            drawName: raw['drawName']?.toString() ?? 'Lottery Draw',
            drawDateStr: dateStr,
            drawTimeStr: drawTimeStr,
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
    }

    // Verify all winners using WinnerVerificationEngine
    final List<WinningClaimModel> winningClaims = [];
    for (final res in resultModels) {
      final claims = WinnerVerificationEngine.verifyWinners(soldTickets: filteredSales, result: res);
      winningClaims.addAll(claims);
    }

    // Financial Metrics Calculation
    final double totalSalesAmount = filteredSales.fold(0.0, (sum, s) => sum + s.totalAmount);
    final double totalCommissionAmount = filteredSales.fold(0.0, (sum, s) => sum + s.commissionAmount);
    final double totalInamOpenAmount = winningClaims.fold(0.0, (sum, c) => sum + c.prizeAmount);
    final double netCompanyProfitLoss = totalSalesAmount - totalInamOpenAmount - totalCommissionAmount;
    final bool isCompanyInProfit = netCompanyProfitLoss >= 0;

    // Seller-wise Breakdown Map
    final Map<String, SellerHisabSummary> sellerSummaries = {};
    for (final s in filteredSales) {
      final name = s.agentName.isNotEmpty ? s.agentName : 'Counter Walk-in';
      final current = sellerSummaries[name] ?? SellerHisabSummary(sellerName: name);
      sellerSummaries[name] = current.copyWith(
        totalTicketsSold: current.totalTicketsSold + s.quantity,
        totalSalesAmount: current.totalSalesAmount + s.totalAmount,
        totalCommission: current.totalCommission + s.commissionAmount,
      );
    }

    for (final claim in winningClaims) {
      final name = claim.sellerName.isNotEmpty ? claim.sellerName : 'Counter Walk-in';
      final current = sellerSummaries[name] ?? SellerHisabSummary(sellerName: name);
      sellerSummaries[name] = current.copyWith(
        winningTicketsCount: current.winningTicketsCount + 1,
        totalInamOpenAmount: current.totalInamOpenAmount + claim.prizeAmount,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Filter Bar
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 16,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 280, maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OWNER HISAB & PROFIT / LOSS LEDGER',
                      style: AppTypography.headlineLg.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Comprehensive ticket sales, open winning prize payout, & seller settlement report',
                      style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Today Button
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedDate = DateTime.now();
                        _filterByDate = true;
                      });
                    },
                    icon: const Icon(Icons.today, size: 16, color: Colors.greenAccent),
                    label: const Text('Today', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.greenAccent),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),

                  // Yesterday Button
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedDate = DateTime.now().subtract(const Duration(days: 1));
                        _filterByDate = true;
                      });
                    },
                    icon: const Icon(Icons.history, size: 16, color: Colors.lightBlueAccent),
                    label: const Text('Yesterday', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.lightBlueAccent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.lightBlueAccent),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),

                  // Calendar Date Picker Button
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedDate = picked;
                          _filterByDate = true;
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_month, size: 16, color: Colors.white),
                    label: Text(_filterByDate ? 'Date: $selectedDateStr' : 'Pick Date', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),

                  // All Dates Toggle Chip
                  FilterChip(
                    label: const Text('All Dates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    selected: !_filterByDate,
                    onSelected: (val) => setState(() => _filterByDate = !val),
                  ),

                  // Shift Dropdown
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

                  // Print Hisab Report Button
                  ElevatedButton.icon(
                    onPressed: () => _printOwnerHisabReport(
                      context,
                      selectedDateStr: _filterByDate ? selectedDateStr : 'All Dates',
                      selectedShift: _selectedShift,
                      totalSales: totalSalesAmount,
                      totalInam: totalInamOpenAmount,
                      totalCommission: totalCommissionAmount,
                      netProfitLoss: netCompanyProfitLoss,
                      isProfit: isCompanyInProfit,
                      sellerList: sellerSummaries.values.toList(),
                      claims: winningClaims,
                    ),
                    icon: const Icon(Icons.print, color: Colors.amber),
                    label: const Text('PRINT HISAB REPORT', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.surfaceContainerHighest),
                  ),
                ],
              ),
            ],
          ),
          // Day-by-Day Active Date Banner
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryContainer.withAlpha(140),
                  AppColors.surfaceContainerHigh,
                ],
              ),
              borderRadius: AppDecorations.radiusDefault,
              border: Border.all(color: AppColors.primary.withAlpha(100)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.event_note, color: Colors.greenAccent, size: 24),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _filterByDate ? 'DAY-BY-DAY ACCOUNTING FOR: $selectedDateStr' : 'ALL-TIME RECORDED ACCOUNTING',
                          style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.w800, color: Colors.greenAccent, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Showing ticket revenue, seller payouts, open inam prizes, and net admin profit for ${_filterByDate ? selectedDateStr : "all dates combined"}.',
                          style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: AppDecorations.radiusSm,
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    'SHIFT: $_selectedShift',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amberAccent),
                  ),
                ),
              ],
            ),
          ),

          // Banner hint if DB is empty
          if (allSales.isEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(25),
                borderRadius: AppDecorations.radiusDefault,
                border: Border.all(color: Colors.amber.withAlpha(100)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.amber),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'No tickets booked yet! Go to "Ticket Booking" screen to enter live tickets, OR click "GENERATE SAMPLE DATA" to see demo sales & winners calculation live.',
                      style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _generateDemoHisabData,
                    child: const Text('Generate Sample Data'),
                  ),
                ],
              ),
            ),

          // Top 4 Financial Summary KPI Cards
          Row(
            children: [
              // Total Sale
              Expanded(
                child: _HisabKpiCard(
                  title: 'TOTAL TICKET SALE',
                  value: '₹${_formatCurrency(totalSalesAmount)}',
                  subtitle: '${filteredSales.length} Bookings • Click for Details ➔',
                  icon: Icons.monetization_on_outlined,
                  color: Colors.blueAccent,
                  onTap: () => _showSalesDetailDialog(context, filteredSales),
                ),
              ),
              const SizedBox(width: 16),

              // Total Inam Open
              Expanded(
                child: _HisabKpiCard(
                  title: 'TOTAL INAM OPEN (PRIZE)',
                  value: '₹${_formatCurrency(totalInamOpenAmount)}',
                  subtitle: '${winningClaims.length} Winners • Click for Details ➔',
                  icon: Icons.emoji_events_outlined,
                  color: Colors.amber,
                  onTap: () => _showInamDetailDialog(context, winningClaims),
                ),
              ),
              const SizedBox(width: 16),

              // Bonus & Special Incentive Card
              Expanded(
                child: _HisabKpiCard(
                  title: 'BONUS & INCENTIVE',
                  value: '₹${_formatCurrency(winningClaims.fold(0.0, (sum, c) => sum + c.superBonus + c.specialIncentive))}',
                  subtitle: 'Super Bonus + Incentive • Details ➔',
                  icon: Icons.stars_outlined,
                  color: Colors.purpleAccent,
                  onTap: () => _showInamDetailDialog(context, winningClaims),
                ),
              ),
              const SizedBox(width: 16),

              // Net Profit / Loss Card
              Expanded(
                child: _HisabKpiCard(
                  title: 'COMPANY NET STATUS',
                  value: '₹${_formatCurrency(netCompanyProfitLoss.abs())}',
                  subtitle: '${isCompanyInProfit ? "🟢 COMPANY PROFIT" : "🔴 COMPANY LOSS"} • Details ➔',
                  icon: isCompanyInProfit ? Icons.trending_up : Icons.trending_down,
                  color: isCompanyInProfit ? Colors.greenAccent : Colors.redAccent,
                  isHighlight: true,
                  isProfit: isCompanyInProfit,
                  onTap: () => _showProfitLossDetailDialog(
                    context,
                    totalSalesAmount: totalSalesAmount,
                    totalInamOpenAmount: totalInamOpenAmount,
                    totalCommissionAmount: totalCommissionAmount,
                    netCompanyProfitLoss: netCompanyProfitLoss,
                    isCompanyInProfit: isCompanyInProfit,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Seller-Wise Settlement Table ("Kis Seller ka kitna inam open hua")
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'SELLER-WISE INAM & SETTLEMENT SUMMARY',
                      style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${sellerSummaries.length} Sellers Active',
                      style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (sellerSummaries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No ticket sales recorded for the selected filter.', style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(AppColors.surfaceContainerHigh),
                      columns: const [
                        DataColumn(label: Text('SELLER NAME', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('TICKET BOOKING', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('GROSS SALES (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('WINNING INAM (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('COMMISSION (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('NET SETTLEMENT (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('SELLER PROFILE', style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: sellerSummaries.values.map((summary) {
                        final netSettlement = summary.totalSalesAmount - summary.totalInamOpenAmount - summary.totalCommission;
                        final isPositive = netSettlement >= 0;

                        return DataRow(
                          cells: [
                            DataCell(Text(summary.sellerName, style: const TextStyle(fontWeight: FontWeight.bold))),
                            DataCell(Text('${summary.totalTicketsSold} tickets')),
                            DataCell(Text('₹${_formatCurrency(summary.totalSalesAmount)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent))),
                            DataCell(Text('₹${_formatCurrency(summary.totalInamOpenAmount)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber))),
                            DataCell(Text('₹${_formatCurrency(summary.totalCommission)}', style: const TextStyle(color: Colors.purpleAccent))),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (isPositive ? Colors.green : Colors.red).withAlpha(30),
                                  borderRadius: AppDecorations.radiusSm,
                                ),
                                child: Text(
                                  '₹${_formatCurrency(netSettlement.abs())} ${isPositive ? "(Receive)" : "(Pay Seller)"}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isPositive ? Colors.greenAccent : Colors.redAccent,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SellerProfileLedgerScreen(sellerName: summary.sellerName),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.person_pin, size: 14, color: AppColors.primary),
                                label: const Text('View Profile & Ledger', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  side: BorderSide(color: AppColors.primary.withAlpha(120)),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Winning Claims Table ("Open Inam Detail")
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'OPEN WINNING TICKETS DETAIL (${winningClaims.length} WINNERS)',
                      style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.bold, color: Colors.amber),
                    ),
                    Text(
                      'Total Payout: ₹${_formatCurrency(totalInamOpenAmount)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (winningClaims.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No winning tickets found for the selected filter.', style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: winningClaims.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, index) {
                      final claim = winningClaims[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.amber.withAlpha(40),
                          child: Text(
                            claim.prizeTier.substring(0, 2),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        title: Text(
                          '${claim.prizeTier} — Ticket #${claim.ticketSeries} ${claim.ticketNumber}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('Seller: ${claim.sellerName}  |  Buyer: ${claim.buyerName}  |  Draw: ${claim.drawName}'),
                        trailing: Text(
                          '₹${_formatCurrency(claim.prizeAmount)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.greenAccent),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(double amt) {
    final formatter = NumberFormat('#,##,##0', 'en_IN');
    return formatter.format(amt);
  }

  void _printOwnerHisabReport(
    BuildContext context, {
    required String selectedDateStr,
    required String selectedShift,
    required double totalSales,
    required double totalInam,
    required double totalCommission,
    required double netProfitLoss,
    required bool isProfit,
    required List<SellerHisabSummary> sellerList,
    required List<WinningClaimModel> claims,
  }) {
    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg),
        child: Container(
          width: 580,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    'PHANTOM MANAGEMENT — OWNER HISAB STATEMENT',
                    style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ),
                Center(
                  child: Text('Date Filter: $selectedDateStr  |  Shift: $selectedShift', style: const TextStyle(color: Colors.grey)),
                ),
                const Divider(height: 24, color: AppColors.border),

                // Financial Summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: AppDecorations.radiusDefault,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _reportRow('Total Ticket Sales:', '₹${_formatCurrency(totalSales)}', Colors.blueAccent),
                      const SizedBox(height: 6),
                      _reportRow('Total Inam Payout (Winners):', '₹${_formatCurrency(totalInam)}', Colors.amber),
                      const SizedBox(height: 6),
                      _reportRow('Total Seller Commission:', '₹${_formatCurrency(totalCommission)}', Colors.purpleAccent),
                      const Divider(height: 16, color: AppColors.border),
                      _reportRow(
                        'NET OWNER ${isProfit ? "PROFIT" : "LOSS"}:',
                        '₹${_formatCurrency(netProfitLoss.abs())}',
                        isProfit ? Colors.greenAccent : Colors.redAccent,
                        isBold: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                const Text('SELLER SETTLEMENT LIST:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                ...sellerList.map((s) {
                  final net = s.totalSalesAmount - s.totalInamOpenAmount - s.totalCommission;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${s.sellerName} (${s.totalTicketsSold} tkts):'),
                        Text(
                          'Sale: ₹${_formatCurrency(s.totalSalesAmount)} | Inam: ₹${_formatCurrency(s.totalInamOpenAmount)} | Net: ₹${_formatCurrency(net.abs())}',
                          style: TextStyle(fontWeight: FontWeight.bold, color: net >= 0 ? Colors.greenAccent : Colors.redAccent),
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Close')),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✅ Hisab Statement sent to thermal/office printer!'), backgroundColor: AppColors.success),
                        );
                      },
                      icon: const Icon(Icons.print),
                      label: const Text('Print Document'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reportRow(String label, String value, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: isBold ? 16 : 14)),
      ],
    );
  }
}

class SellerHisabSummary {
  final String sellerName;
  final int totalTicketsSold;
  final double totalSalesAmount;
  final double totalCommission;
  final int winningTicketsCount;
  final double totalInamOpenAmount;

  SellerHisabSummary({
    required this.sellerName,
    this.totalTicketsSold = 0,
    this.totalSalesAmount = 0.0,
    this.totalCommission = 0.0,
    this.winningTicketsCount = 0,
    this.totalInamOpenAmount = 0.0,
  });

  SellerHisabSummary copyWith({
    String? sellerName,
    int? totalTicketsSold,
    double? totalSalesAmount,
    double? totalCommission,
    int? winningTicketsCount,
    double? totalInamOpenAmount,
  }) {
    return SellerHisabSummary(
      sellerName: sellerName ?? this.sellerName,
      totalTicketsSold: totalTicketsSold ?? this.totalTicketsSold,
      totalSalesAmount: totalSalesAmount ?? this.totalSalesAmount,
      totalCommission: totalCommission ?? this.totalCommission,
      winningTicketsCount: winningTicketsCount ?? this.winningTicketsCount,
      totalInamOpenAmount: totalInamOpenAmount ?? this.totalInamOpenAmount,
    );
  }
}

class _HisabKpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isHighlight;
  final bool isProfit;
  final VoidCallback? onTap;

  const _HisabKpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.isHighlight = false,
    this.isProfit = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
              Icon(icon, color: color, size: 22),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: AppTypography.headlineMd.copyWith(
              fontWeight: FontWeight.bold,
              color: isHighlight ? color : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: AppTypography.labelSm.copyWith(
              color: isHighlight ? color : AppColors.textSecondary,
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
