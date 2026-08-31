import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_service.dart';
import '../models/lottery_sambad_result_model.dart';
import '../utils/party_hisab_settlement_engine.dart';
import '../services/party_hisab_report_service.dart';
import '../../unsold/viewmodels/voucher_viewmodel.dart';
import '../../unsold/viewmodels/unsold_viewmodel.dart';
import '../../bookings/viewmodels/ticket_sales_viewmodel.dart';
import '../../bookings/services/booking_pdf_service.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../viewmodels/draws_viewmodel.dart';
import '../widgets/get_file_hisab_dialog.dart';

enum MainHisabCategory {
  partyUnsoldHisab, // 📦 Wholesale Party Stock & Unsold Returns
  customerBookingHisab, // 🎟️ Retail Customer Ticket Bookings & Sales
}

enum HisabSourceFilter { all, vouchersOnly, unsoldOnly }

class PartyHisabReportsScreen extends ConsumerStatefulWidget {
  const PartyHisabReportsScreen({super.key});

  @override
  ConsumerState<PartyHisabReportsScreen> createState() => _PartyHisabReportsScreenState();
}

class _PartyHisabReportsScreenState extends ConsumerState<PartyHisabReportsScreen> {
  MainHisabCategory _activeCategory = MainHisabCategory.partyUnsoldHisab;
  DateTime _selectedDate = DateTime.now();
  bool _isCustomRange = false;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  String _selectedShift = 'Dear 1 PM';
  String _selectedSeries = 'ALL';
  HisabReportMode _reportMode = HisabReportMode.summary;
  HisabSourceFilter _sourceFilter = HisabSourceFilter.all;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  final List<String> _shiftList = ['Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM', 'ALL'];

  List<LotterySambadResultModel> _allLotteryResults = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadAllData();
    });
  }

  Future<void> _reloadAllData() async {
    final shift = _selectedShift == 'ALL' ? null : _selectedShift;

    try {
      if (_isCustomRange && _rangeStart != null && _rangeEnd != null) {
        final sStr = DateFormat('yyyy-MM-dd').format(_rangeStart!);
        final eStr = DateFormat('yyyy-MM-dd').format(_rangeEnd!);
        ref.read(voucherViewModelProvider.notifier).loadVouchers(
          startDate: sStr,
          endDate: eStr,
          drawShift: shift,
        );
        ref.read(unsoldViewModelProvider.notifier).loadUnsold(
          startDate: sStr,
          endDate: eStr,
          drawShift: shift,
        );
      } else {
        final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
        ref.read(voucherViewModelProvider.notifier).loadVouchers(
          date: dateStr,
          drawShift: shift,
        );
        ref.read(unsoldViewModelProvider.notifier).loadUnsold(
          date: dateStr,
          drawShift: shift,
        );
      }
      ref.read(ticketSalesViewModelProvider.notifier).loadSales();
      await _loadResultsFromDatabase();
    } catch (e) {
      debugPrint('Error reloading hisab data: $e');
    }
  }

  Future<void> _pickSingleDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF0284C7),
              onPrimary: Colors.white,
              surface: Color(0xFF0F172A),
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF0B1120)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _isCustomRange = false;
        _selectedDate = picked;
      });
      _reloadAllData();
    }
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: _rangeStart ?? _selectedDate,
        end: _rangeEnd ?? _selectedDate,
      ),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF0284C7),
              onPrimary: Colors.white,
              surface: Color(0xFF0F172A),
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF0B1120)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _isCustomRange = true;
        _rangeStart = picked.start;
        _rangeEnd = picked.end;
      });
      _reloadAllData();
    }
  }

  void _resetToSingleDate() {
    setState(() {
      _isCustomRange = false;
      _rangeStart = null;
      _rangeEnd = null;
    });
    _reloadAllData();
  }

  Future<void> _loadResultsFromDatabase() async {
    try {
      final rows = await DatabaseService.instance.getLotteryResults();
      final List<LotterySambadResultModel> parsed = [];
      for (final r in rows) {
        final sec = (r['secondPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();
        final th = (r['thirdPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();
        final fo = (r['fourthPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();
        final fi = (r['fifthPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();

        parsed.add(LotterySambadResultModel(
          drawId: r['id']?.toString() ?? 'draw_${r['drawDateStr']}_${r['drawTimeStr']}',
          drawName: r['drawName']?.toString() ?? 'DEAR LOTTERY',
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
          _allLotteryResults = parsed;
        });
      }
    } catch (e) {
      debugPrint('Error loading results in PartyHisabReportsScreen: $e');
    }
  }

  LotterySambadResultModel? _findMatchingResult(DateTime date, String shift) {
    final ymd = DateFormat('yyyy-MM-dd').format(date);
    final dmy = DateFormat('dd/MM/yyyy').format(date);
    final dmyDot = DateFormat('dd.MM.yyyy').format(date);
    final dmyDash = DateFormat('dd-MM-yyyy').format(date);

    for (final r in _allLotteryResults) {
      final rDate = r.drawDateStr.trim();
      final dateMatches = rDate == ymd ||
          rDate == dmy ||
          rDate == dmyDot ||
          rDate == dmyDash ||
          rDate.contains(dmy) ||
          rDate.contains(dmyDash) ||
          ymd.contains(rDate);
      if (!dateMatches) continue;

      if (shift == 'ALL') return r;

      final s = shift.toLowerCase().replaceAll('dear ', '').replaceAll(' ', '');
      final rName = r.drawName.toLowerCase().replaceAll('dear ', '').replaceAll(' ', '');
      final rTime = r.drawTimeStr.toLowerCase().replaceAll(' ', '');

      bool shiftMatches = false;
      if (s.contains('1pm') || s.contains('1:00') || s.contains('morning') || s == '1') {
        shiftMatches = rName.contains('1pm') || rName.contains('1:00') || rName.contains('morning') || rTime.contains('1pm') || rTime.contains('1:00');
      } else if (s.contains('6pm') || s.contains('6:00') || s.contains('day') || s == '6') {
        shiftMatches = rName.contains('6pm') || rName.contains('6:00') || rName.contains('day') || rTime.contains('6pm') || rTime.contains('6:00');
      } else if (s.contains('8pm') || s.contains('8:00') || s.contains('evening') || s.contains('night') || s == '8') {
        shiftMatches = rName.contains('8pm') || rName.contains('8:00') || rName.contains('evening') || rName.contains('night') || rTime.contains('8pm') || rTime.contains('8:00');
      } else {
        shiftMatches = rName.contains(s) || rTime.contains(s);
      }

      if (shiftMatches) return r;
    }
    return null;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voucherState = ref.watch(voucherViewModelProvider);
    final unsoldState = ref.watch(unsoldViewModelProvider);
    final ticketSalesState = ref.watch(ticketSalesViewModelProvider);
    final drawsState = ref.watch(drawsViewModelProvider);

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // Extract all distinct available series dynamically
    final Set<String> allSeriesSet = {'ALL'};
    for (final v in voucherState.vouchers) {
      final s = v.series.trim();
      if (s.isNotEmpty) allSeriesSet.add(s);
    }
    for (final u in unsoldState.unsoldList) {
      final s = u.series.trim();
      if (s.isNotEmpty) allSeriesSet.add(s);
    }
    for (final s in ticketSalesState.sales) {
      final ser = s.ticketSeries.trim();
      if (ser.isNotEmpty) allSeriesSet.add(ser);
    }
    final availableSeriesList = allSeriesSet.toList()
      ..sort((a, b) {
        if (a == 'ALL') return -1;
        if (b == 'ALL') return 1;
        final numA = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 999;
        final numB = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 999;
        return numA.compareTo(numB);
      });

    // Find matching lottery result from SQLite database or state
    final matchingResult = _findMatchingResult(_selectedDate, _selectedShift) ??
        drawsState.resultsMap.values.where((r) {
          final matchesDate = r.drawDateStr.contains(dateStr) || dateStr.contains(r.drawDateStr);
          final matchesShift = _selectedShift == 'ALL' ||
              r.drawName.toLowerCase().contains(_selectedShift.toLowerCase().replaceAll('dear ', ''));
          return matchesDate && matchesShift;
        }).firstOrNull;

    final startStr = (_isCustomRange && _rangeStart != null) ? DateFormat('yyyy-MM-dd').format(_rangeStart!) : null;
    final endStr = (_isCustomRange && _rangeEnd != null) ? DateFormat('yyyy-MM-dd').format(_rangeEnd!) : null;

    final combinedResults = <LotterySambadResultModel>[
      ..._allLotteryResults,
      ...drawsState.resultsMap.values,
    ];

    // ── 1. PARTY UNSOLD HISAB CALCULATIONS ──────────────────────
    final allPartySummaries = PartyHisabSettlementEngine.calculatePartySettlements(
      vouchers: voucherState.vouchers,
      unsoldList: unsoldState.unsoldList,
      selectedDate: dateStr,
      startDate: startStr,
      endDate: endStr,
      selectedShift: _selectedShift,
      selectedSeries: _selectedSeries,
      allResults: combinedResults,
      lotteryResult: matchingResult,
    );

    final partySourceFiltered = allPartySummaries.where((s) {
      if (_sourceFilter == HisabSourceFilter.vouchersOnly) {
        return s.totalVouchers > 0;
      } else if (_sourceFilter == HisabSourceFilter.unsoldOnly) {
        return s.totalUnsold > 0;
      }
      return true;
    }).toList();

    final filteredPartySummaries = _searchQuery.isEmpty
        ? partySourceFiltered
        : partySourceFiltered.where((s) => s.partyName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    // ── 2. CUSTOMER BOOKINGS HISAB CALCULATIONS ─────────────────
    final filteredSales = ticketSalesState.sales.where((s) {
      final sDateStr = DateFormat('yyyy-MM-dd').format(s.saleDate);
      final matchesDate = (_isCustomRange && _rangeStart != null && _rangeEnd != null)
          ? (s.saleDate.isAfter(_rangeStart!.subtract(const Duration(seconds: 1))) &&
             s.saleDate.isBefore(_rangeEnd!.add(const Duration(days: 1))))
          : sDateStr == dateStr;
      final shift = BookingPdfService.instance.getDrawShift(s.drawName);
      final matchesShift = _selectedShift == 'ALL' || shift == _selectedShift;

      final serS = s.ticketSeries.replaceAll(RegExp(r'\D'), '');
      final serF = _selectedSeries.replaceAll(RegExp(r'\D'), '');
      final matchesSeries = _selectedSeries == 'ALL' ||
          s.ticketSeries.trim().toUpperCase() == _selectedSeries.trim().toUpperCase() ||
          (serS.isNotEmpty && serS == serF);

      final matchesSearch = _searchQuery.isEmpty ||
          s.buyerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.ticketNumber.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesDate && matchesShift && matchesSeries && matchesSearch;
    }).toList();

    // Group customer sales by Buyer Name
    final Map<String, List<TicketSaleModel>> customerGrouped = {};
    for (final sale in filteredSales) {
      final buyer = sale.buyerName.trim().isNotEmpty ? sale.buyerName.trim() : 'Walk-in Customer';
      customerGrouped.putIfAbsent(buyer, () => []).add(sale);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: Column(
        children: [
          // ── TOP CATEGORY SWITCHER BAR (BOOKING vs UNSOLD) ───────
          Container(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            decoration: const BoxDecoration(
              color: Color(0xFF081220),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Main Tab 1: Party Stock & Unsold Hisab
                      _buildMainCategoryTab(
                        title: '📦 1. PARTY STOCK & UNSOLD HISAB',
                        subtitle: 'Wholesale Vouchers Issued vs Unsold Returns Settlement',
                        category: MainHisabCategory.partyUnsoldHisab,
                        activeColor: const Color(0xFF0284C7),
                        countBadge: '${allPartySummaries.length} Parties',
                      ),
                      const SizedBox(width: 14),

                      // Main Tab 2: Customer Bookings & Sales Hisab
                      _buildMainCategoryTab(
                        title: '🎟️ 2. CUSTOMER BOOKINGS & SALES HISAB',
                        subtitle: 'Retail Customer Counter Sales & Winning Payouts',
                        category: MainHisabCategory.customerBookingHisab,
                        activeColor: const Color(0xFF10B981),
                        countBadge: '${customerGrouped.length} Buyers (${filteredSales.length} Tkt)',
                      ),

                      const SizedBox(width: 14),

                      // Single Date Button
                      InkWell(
                        onTap: _pickSingleDate,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: !_isCustomRange ? const Color(0xFF0369A1).withAlpha(120) : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: !_isCustomRange ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                              width: !_isCustomRange ? 1.4 : 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 13, color: !_isCustomRange ? const Color(0xFF38BDF8) : Colors.grey),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat('dd-MM-yyyy (EEE)').format(_selectedDate),
                                style: TextStyle(
                                  color: !_isCustomRange ? const Color(0xFF38BDF8) : Colors.grey.shade400,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Custom Date Range Button
                      InkWell(
                        onTap: _pickCustomRange,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: _isCustomRange ? const Color(0xFF10B981).withAlpha(120) : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isCustomRange ? const Color(0xFF34D399) : const Color(0xFF334155),
                              width: _isCustomRange ? 1.4 : 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.date_range_rounded, size: 14, color: _isCustomRange ? const Color(0xFF34D399) : const Color(0xFFFBBF24)),
                              const SizedBox(width: 6),
                              Text(
                                (_isCustomRange && _rangeStart != null && _rangeEnd != null)
                                    ? '${DateFormat('dd/MM').format(_rangeStart!)} ➔ ${DateFormat('dd/MM/yy').format(_rangeEnd!)}'
                                    : '📅 Custom Range',
                                style: TextStyle(
                                  color: _isCustomRange ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_isCustomRange) ...[
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: _resetToSingleDate,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withAlpha(40),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFEF4444)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.close_rounded, size: 12, color: Color(0xFFFCA5A5)),
                                SizedBox(width: 3),
                                Text('Reset', style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 10.5, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),

                      // Shift Dropdown
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF38BDF8).withAlpha(150)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedShift,
                            dropdownColor: const Color(0xFF0F172A),
                            icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF38BDF8), size: 16),
                            style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11.5),
                            items: _shiftList.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedShift = val);
                                _reloadAllData();
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Series Switcher Dropdown
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: _selectedSeries != 'ALL' ? const Color(0xFF1E1B4B) : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _selectedSeries != 'ALL' ? const Color(0xFFFBBF24) : const Color(0xFFC084FC).withAlpha(150),
                            width: _selectedSeries != 'ALL' ? 1.5 : 1.0,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: availableSeriesList.contains(_selectedSeries) ? _selectedSeries : 'ALL',
                            dropdownColor: const Color(0xFF0F172A),
                            icon: Icon(
                              Icons.tune_rounded,
                              color: _selectedSeries != 'ALL' ? const Color(0xFFFBBF24) : const Color(0xFFC084FC),
                              size: 15,
                            ),
                            style: TextStyle(
                              color: _selectedSeries != 'ALL' ? const Color(0xFFFBBF24) : const Color(0xFFC084FC),
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                            items: availableSeriesList.map((ser) {
                              return DropdownMenuItem<String>(
                                value: ser,
                                child: Text(ser == 'ALL' ? '🎲 All Series' : 'Ser $ser'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedSeries = val);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          // ── KPI STATS STRIP ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            color: const Color(0xFF0F172A),
            child: _activeCategory == MainHisabCategory.partyUnsoldHisab
                ? _buildPartyKpiStrip(filteredPartySummaries, isResultDeclared: matchingResult != null)
                : _buildCustomerKpiStrip(customerGrouped, filteredSales),
          ),

          // ── FILTER TOOLBAR ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF0C1322),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. SEARCH BAR (FIRST!)
                  SizedBox(
                    width: 220,
                    height: 32,
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 11.5),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: _activeCategory == MainHisabCategory.partyUnsoldHisab ? 'Search Party Name...' : 'Search Customer / Ticket...',
                        hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                        prefixIcon: const Icon(Icons.search_rounded, size: 15, color: Color(0xFF38BDF8)),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 14, color: Colors.grey),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.2)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),

                  const SizedBox(width: 12),
                  Container(width: 1, height: 20, color: const Color(0xFF334155)),
                  const SizedBox(width: 12),

                  // 2. FORMAT (SECOND!)
                  if (_activeCategory == MainHisabCategory.partyUnsoldHisab) ...[
                    const Text('FORMAT:', style: TextStyle(color: Colors.grey, fontSize: 10.5, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    _formatSwitchBtn('📊 Summary', HisabReportMode.summary),
                    const SizedBox(width: 6),
                    _formatSwitchBtn('📑 Detailed Parcha', HisabReportMode.fullDetailed),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFF064E3B), borderRadius: BorderRadius.circular(4)),
                      child: const Text('🎟️ Customer Sales Bookings', style: TextStyle(color: Color(0xFF6EE7B7), fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],

                  const SizedBox(width: 12),
                  Container(width: 1, height: 20, color: const Color(0xFF334155)),
                  const SizedBox(width: 12),

                  // 3. REFRESH & BATCH COPY (THIRD!)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _reloadAllData();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🔄 Real-time data refreshed! Vouchers, Unsold & Results up to date.'),
                            duration: Duration(seconds: 1),
                            backgroundColor: Color(0xFF0284C7),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 14, color: Color(0xFF38BDF8)),
                    label: const Text('REFRESH', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: Color(0xFF38BDF8))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF0284C7)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                  const SizedBox(width: 8),

                  ElevatedButton.icon(
                    onPressed: () {
                      if (_activeCategory == MainHisabCategory.partyUnsoldHisab) {
                        _copyAllPartiesCombinedText(filteredPartySummaries);
                      } else {
                        _copyAllCustomersCombinedText(customerGrouped);
                      }
                    },
                    icon: const Icon(Icons.copy_all_rounded, size: 13),
                    label: Text(_activeCategory == MainHisabCategory.partyUnsoldHisab ? 'COPY ALL PARTIES' : 'COPY ALL BOOKINGS', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),

                  // 4. SERIES (FOURTH!)
                  if (availableSeriesList.length > 1) ...[
                    const SizedBox(width: 12),
                    Container(width: 1, height: 20, color: const Color(0xFF334155)),
                    const SizedBox(width: 10),
                    const Text('SERIES:', style: TextStyle(color: Colors.grey, fontSize: 10.5, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    ...availableSeriesList.take(6).map((ser) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: InkWell(
                            onTap: () => setState(() => _selectedSeries = ser),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: _selectedSeries == ser ? const Color(0xFF7C3AED) : const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _selectedSeries == ser ? const Color(0xFFA78BFA) : const Color(0xFF334155),
                                ),
                              ),
                              child: Text(
                                ser == 'ALL' ? 'All' : 'Ser $ser',
                                style: TextStyle(
                                  color: _selectedSeries == ser ? Colors.white : Colors.grey.shade400,
                                  fontSize: 10,
                                  fontWeight: _selectedSeries == ser ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        )),
                  ],

                  // 5. FILTER (FIFTH!)
                  if (_activeCategory == MainHisabCategory.partyUnsoldHisab) ...[
                    const SizedBox(width: 12),
                    Container(width: 1, height: 20, color: const Color(0xFF334155)),
                    const SizedBox(width: 10),
                    const Text('FILTER:', style: TextStyle(color: Colors.grey, fontSize: 10.5, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    _sourceFilterChip('🌐 ALL HISAB', HisabSourceFilter.all, Colors.white70),
                    const SizedBox(width: 6),
                    _sourceFilterChip('🔵 INWARD VOUCHERS', HisabSourceFilter.vouchersOnly, const Color(0xFF60A5FA)),
                    const SizedBox(width: 6),
                    _sourceFilterChip('🔴 UNSOLD RETURNS', HisabSourceFilter.unsoldOnly, const Color(0xFFF87171)),
                  ],
                ],
              ),
            ),
          ),

          // ── RESULT STATUS BANNER ─────────────────────────────────
          if (_activeCategory == MainHisabCategory.partyUnsoldHisab)
            _buildResultStatusBanner(matchingResult),

          // ── MAIN CONTENT LIST ───────────────────────────────────
          Expanded(
            child: _activeCategory == MainHisabCategory.partyUnsoldHisab
                ? _buildPartyHisabList(
                    filteredPartySummaries,
                    (_isCustomRange && _rangeStart != null && _rangeEnd != null)
                        ? '${DateFormat('dd-MM-yyyy').format(_rangeStart!)} to ${DateFormat('dd-MM-yyyy').format(_rangeEnd!)}'
                        : dateStr,
                    isResultDeclared: matchingResult != null)
                : _buildCustomerBookingList(
                    customerGrouped,
                    (_isCustomRange && _rangeStart != null && _rangeEnd != null)
                        ? '${DateFormat('dd-MM-yyyy').format(_rangeStart!)} to ${DateFormat('dd-MM-yyyy').format(_rangeEnd!)}'
                        : dateStr),
          ),
        ],
      ),
    );
  }

  Widget _buildMainCategoryTab({
    required String title,
    required String subtitle,
    required MainHisabCategory category,
    required Color activeColor,
    required String countBadge,
  }) {
    final isSelected = _activeCategory == category;
    return InkWell(
      onTap: () => setState(() => _activeCategory = category),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withAlpha(40) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFF1E293B),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: activeColor.withAlpha(50), blurRadius: 10, offset: const Offset(0, 2))]
              : [],
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey.shade400,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: isSelected ? activeColor : Colors.grey.shade600, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                countBadge,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartyKpiStrip(List<PartyHisabSummary> summaries, {required bool isResultDeclared}) {
    final totalInward = summaries.fold(0, (sum, s) => sum + s.totalVouchers);
    final totalInwardAmount = summaries.fold(0.0, (sum, s) => sum + s.totalVoucherAmount);
    final totalUnsold = summaries.fold(0, (sum, s) => sum + s.totalUnsold);
    final totalUnsoldAmount = summaries.fold(0.0, (sum, s) => sum + s.totalUnsoldAmount);
    final totalNetSold = summaries.fold(0, (sum, s) => sum + s.totalNetSold);
    final totalNetAmount = summaries.fold(0.0, (sum, s) => sum + s.totalNetAmount);
    final totalCustomerWins = summaries.fold(0.0, (sum, s) => sum + s.totalCustomerWinAmount);
    final totalNetPayable = summaries.fold(0.0, (sum, s) => sum + s.finalNetPayable);

    return Row(
      children: [
        _kpiStatCard('PARTIES', '${summaries.length}', 'Active Sellers', const Color(0xFF38BDF8), Icons.people_alt_rounded),
        const SizedBox(width: 8),
        _kpiStatCard('🔵 VOUCHER INWARD', '$totalInward', '₹${totalInwardAmount.toStringAsFixed(0)} (Stock)', const Color(0xFF60A5FA), Icons.arrow_downward_rounded, badgeBg: const Color(0xFF1E3A8A)),
        const SizedBox(width: 8),
        _kpiStatCard('🔴 UNSOLD RETURNS', '$totalUnsold', '-₹${totalUnsoldAmount.toStringAsFixed(0)} (Wapas)', const Color(0xFFF87171), Icons.arrow_upward_rounded, badgeBg: const Color(0xFF7F1D1D)),
        const SizedBox(width: 8),
        _kpiStatCard('🟢 NET SOLD BIKRI', '$totalNetSold', 'Inward - Unsold', const Color(0xFF4ADE80), Icons.check_circle_rounded, badgeBg: const Color(0xFF064E3B)),
        const SizedBox(width: 8),
        if (!isResultDeclared) ...[
          _kpiStatCard('🏆 CUSTOMER WINS', 'PENDING', 'Result Not Declared', const Color(0xFFFB923C), Icons.hourglass_empty_rounded),
          const SizedBox(width: 8),
          _kpiStatCard('⏳ GROSS BIKRI', '₹${totalNetAmount.toStringAsFixed(2)}', 'Result Pending (Pre-Claim)', const Color(0xFFF97316), Icons.pending_actions_rounded, isHighlight: true),
        ] else ...[
          _kpiStatCard('🏆 CUSTOMER WINS', '₹${totalCustomerWins.toStringAsFixed(0)}', 'Prize Deducted', const Color(0xFFA78BFA), Icons.emoji_events_rounded),
          const SizedBox(width: 8),
          _kpiStatCard('💰 FINAL NET PAYABLE', '₹${totalNetPayable.toStringAsFixed(2)}', 'Final Settled Receivable', const Color(0xFFFBBF24), Icons.account_balance_wallet_rounded, isHighlight: true),
        ],
      ],
    );
  }

  Widget _buildCustomerKpiStrip(Map<String, List<TicketSaleModel>> grouped, List<TicketSaleModel> sales) {
    final totalTickets = sales.fold(0, (sum, s) => sum + s.quantity);
    final totalAmount = sales.fold(0.0, (sum, s) => sum + s.totalAmount);
    final totalCommission = sales.fold(0.0, (sum, s) => sum + s.commissionAmount);

    return Row(
      children: [
        _kpiStatCard('BUYERS / CUSTOMERS', '${grouped.length}', 'Active Counter Clients', const Color(0xFF10B981), Icons.person_rounded),
        const SizedBox(width: 8),
        _kpiStatCard('🎟️ TOTAL TICKETS SOLD', '$totalTickets', '${sales.length} Bookings', const Color(0xFF34D399), Icons.local_activity_rounded),
        const SizedBox(width: 8),
        _kpiStatCard('💵 TOTAL COUNTER SALES', '₹${totalAmount.toStringAsFixed(2)}', 'Gross Sales', const Color(0xFF38BDF8), Icons.payments_rounded),
        const SizedBox(width: 8),
        _kpiStatCard('💼 AGENT COMMISSION', '₹${totalCommission.toStringAsFixed(2)}', 'Payout Share', const Color(0xFFA78BFA), Icons.savings_rounded),
        const SizedBox(width: 8),
        _kpiStatCard('💰 NET COUNTER CASH', '₹${(totalAmount - totalCommission).toStringAsFixed(2)}', 'Shop Cash Net', const Color(0xFFFBBF24), Icons.account_balance_wallet_rounded, isHighlight: true),
      ],
    );
  }

  Widget _kpiStatCard(String label, String value, String sub, Color color, IconData icon, {bool isHighlight = false, Color? badgeBg}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isHighlight ? const Color(0xFF1C1605) : (badgeBg?.withAlpha(40) ?? const Color(0xFF111827)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isHighlight ? color : (badgeBg != null ? color.withAlpha(120) : color.withAlpha(50)),
            width: isHighlight ? 1.2 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            Text(sub, style: TextStyle(color: Colors.grey.shade400, fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _sourceFilterChip(String label, HisabSourceFilter filter, Color activeColor) {
    final isSelected = _sourceFilter == filter;
    return InkWell(
      onTap: () => setState(() => _sourceFilter = filter),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withAlpha(40) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? activeColor : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? activeColor : Colors.grey.shade400,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 10,
          ),
        ),
      ),
    );
  }

  Widget _formatSwitchBtn(String label, HisabReportMode mode) {
    final isSelected = _reportMode == mode;
    return InkWell(
      onTap: () => setState(() => _reportMode = mode),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? const Color(0xFF38BDF8) : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade400,
            fontWeight: FontWeight.bold,
            fontSize: 10.5,
          ),
        ),
      ),
    );
  }

  Widget _buildResultStatusBanner(LotterySambadResultModel? result) {
    if (result == null) {
      // ⚠️ Result NOT declared
      return Container(
        margin: const EdgeInsets.fromLTRB(24, 10, 24, 2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF261205),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFF97316), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF97316).withAlpha(30),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFFEA580C).withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.pending_actions_rounded, color: Color(0xFFFB923C), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        '⚠️ RESULT ENTRY PENDING: ${_selectedShift == 'ALL' ? 'Selected Draws' : _selectedShift} (${(_isCustomRange && _rangeStart != null && _rangeEnd != null) ? '${DateFormat('dd-MM-yyyy').format(_rangeStart!)} to ${DateFormat('dd-MM-yyyy').format(_rangeEnd!)}' : DateFormat('dd-MM-yyyy (EEE)').format(_selectedDate)})',
                        style: const TextStyle(color: Color(0xFFFED7AA), fontWeight: FontWeight.w900, fontSize: 12.5),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C2D12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('NO RESULTS YET', style: TextStyle(color: Color(0xFFFDBA74), fontSize: 9.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Is Date aur Time (Shift) ka official result entry abhi nahi hua hai. Voucher stock aur Unsold returns ka hisab taiyar hai. Result aane ke baad "Enter Result Now" par click karein taki Inam auto-match hokar deduct ho sakein.',
                    style: TextStyle(color: Color(0xFFFDBA74), fontSize: 11, height: 1.25),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () async {
                await context.push(AppConstants.routeResultEntry);
                _reloadAllData();
              },
              icon: const Icon(Icons.add_circle_outline_rounded, size: 14),
              label: const Text('ENTER RESULT NOW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEA580C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                elevation: 4,
              ),
            ),
          ],
        ),
      );
    }

    // ✅ Result DECLARED
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 10, 24, 2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF032212),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF22C55E), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22C55E).withAlpha(25),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_rounded, color: Color(0xFF4ADE80), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Text(
                  '✅ Official Result Declared for ${DateFormat('dd-MM-yyyy').format(_selectedDate)} (${result.drawName})',
                  style: const TextStyle(color: Color(0xFFDCFCE7), fontWeight: FontWeight.w900, fontSize: 12.5),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14532D),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFF22C55E).withAlpha(100)),
                  ),
                  child: Text(
                    '🥇 1st Prize: ${result.firstPrize}',
                    style: const TextStyle(color: Color(0xFF86EFAC), fontWeight: FontWeight.bold, fontSize: 11.5, fontFamily: 'monospace'),
                  ),
                ),
                if (result.secondPrizeNumbers.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF064E3B),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '🥈 2nd: ${result.secondPrizeNumbers.take(3).join(", ")}...',
                      style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await context.push(AppConstants.routeResultEntry);
              _reloadAllData();
            },
            icon: const Icon(Icons.edit_note_rounded, size: 14, color: Color(0xFF4ADE80)),
            label: const Text('VIEW / EDIT RESULT', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 11, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF22C55E)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ],
      ),
    );
  }

  // ── 1. PARTY HISAB LIST VIEW ────────────────────────────
  Widget _buildPartyHisabList(List<PartyHisabSummary> summaries, String dateStr, {required bool isResultDeclared}) {
    if (summaries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 54, color: Colors.grey.shade700),
            const SizedBox(height: 12),
            Text('No Party Voucher or Unsold records found for $dateStr ($_selectedShift)', style: TextStyle(color: Colors.grey.shade400, fontSize: 13.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Entries made in "Number Unsold" will appear here automatically.', style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: summaries.length,
      itemBuilder: (ctx, idx) => _buildEnhancedPartyCard(summaries[idx], isResultDeclared: isResultDeclared),
    );
  }

  Widget _buildEnhancedPartyCard(PartyHisabSummary summary, {required bool isResultDeclared}) {
    final hasCustomerWins = summary.customerWins.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // Card Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront_rounded, size: 16, color: Color(0xFF38BDF8)),
                const SizedBox(width: 8),
                Text(
                  'PARTY: ${summary.partyName}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF0284C7).withAlpha(80), borderRadius: BorderRadius.circular(4)),
                  child: Text(summary.shift, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),

                ElevatedButton.icon(
                  onPressed: () => _copyPartyWhatsAppText(summary),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 12),
                  label: const Text('COPY WHATSAPP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    minimumSize: const Size(60, 28),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 6),
                ElevatedButton.icon(
                  onPressed: () => _exportPartyPdf(summary),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 12),
                  label: const Text('SAVE PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    minimumSize: const Size(60, 28),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: () => _previewPartyTextModal(summary),
                  icon: const Icon(Icons.remove_red_eye_outlined, size: 12, color: Colors.grey),
                  label: const Text('PREVIEW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: Colors.grey)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF475569)),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    minimumSize: const Size(50, 28),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ],
            ),
          ),

          // Card Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Dual Box Comparison: 🔵 VOUCHER INWARD vs 🔴 UNSOLD RETURNS
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🔵 Blue Box: Inward Vouchers
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF071B2F),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF38BDF8).withAlpha(120), width: 1.2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.arrow_downward_rounded, color: Color(0xFF38BDF8), size: 14),
                                const SizedBox(width: 4),
                                const Text('🔵 1. VOUCHER INWARD (STOCK)', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11)),
                                const Spacer(),
                                Text('${summary.totalVouchers} Tickets', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                              ],
                            ),
                            const Divider(color: Color(0xFF1E3A5F), thickness: 0.8),
                            if (summary.rawVouchers.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4),
                                child: Text('No Vouchers recorded', style: TextStyle(color: Colors.grey, fontSize: 10.5, fontStyle: FontStyle.italic)),
                              )
                            else
                              ...summary.rawVouchers.take(4).map((v) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Ser ${v.series} • ${v.fromTicket}-${v.toTicket}', style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontFamily: 'monospace')),
                                    Text('${v.totalQty} Nos (₹${v.totalAmount.toStringAsFixed(0)})', style: const TextStyle(color: Color(0xFF7DD3FC), fontSize: 10.5, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              )),
                            if (summary.rawVouchers.length > 4)
                              Text('+ ${summary.rawVouchers.length - 4} more ranges...', style: const TextStyle(color: Colors.grey, fontSize: 9.5)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(color: const Color(0xFF0F2847), borderRadius: BorderRadius.circular(4)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Total Inward Amount:', style: TextStyle(color: Colors.grey, fontSize: 10)),
                                  Text('₹ ${summary.totalVoucherAmount.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // 🔴 Red Box: Unsold Returns
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF270E14),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF87171).withAlpha(120), width: 1.2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.arrow_upward_rounded, color: Color(0xFFF87171), size: 14),
                                const SizedBox(width: 4),
                                const Text('🔴 2. UNSOLD RETURNS (WAPAS)', style: TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold, fontSize: 11)),
                                const Spacer(),
                                Text('${summary.totalUnsold} Tickets', style: const TextStyle(color: Color(0xFFFCA5A5), fontWeight: FontWeight.w900, fontSize: 12)),
                              ],
                            ),
                            const Divider(color: Color(0xFF4C1D24), thickness: 0.8),
                            if (summary.rawUnsold.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4),
                                child: Text('No Unsold returns', style: TextStyle(color: Colors.grey, fontSize: 10.5, fontStyle: FontStyle.italic)),
                              )
                            else
                              ...summary.rawUnsold.take(4).map((u) {
                                final rangeStr = u.fromTicket == u.toTicket ? u.fromTicket : '${u.fromTicket}-${u.toTicket}';
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Ser ${u.series} • $rangeStr', style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontFamily: 'monospace')),
                                      Text('${u.totalQty} Nos (-₹${u.totalAmount.toStringAsFixed(0)})', style: const TextStyle(color: Color(0xFFF87171), fontSize: 10.5, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                );
                              }),
                            if (summary.rawUnsold.length > 4)
                              Text('+ ${summary.rawUnsold.length - 4} more ranges...', style: const TextStyle(color: Colors.grey, fontSize: 9.5)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(color: const Color(0xFF3F131A), borderRadius: BorderRadius.circular(4)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Unsold Return Credit:', style: TextStyle(color: Colors.grey, fontSize: 10)),
                                  Text('- ₹ ${summary.totalUnsoldAmount.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 2. Series Settlement Table ($Inward - Returns = Net Sold$)
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF070B16),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.2),
                      1: FlexColumnWidth(1.2),
                      2: FlexColumnWidth(1.2),
                      3: FlexColumnWidth(1.2),
                      4: FlexColumnWidth(1.0),
                      5: FlexColumnWidth(1.5),
                    },
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F172A),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                        ),
                        children: [
                          _tableHeaderCell('SERIES'),
                          _tableHeaderCell('🔵 VOUCHER (IN)'),
                          _tableHeaderCell('🔴 UNSOLD (RET)'),
                          _tableHeaderCell('🟢 NET SOLD (BIKRI)'),
                          _tableHeaderCell('RATE (₹)'),
                          _tableHeaderCell('NET AMOUNT (₹)'),
                        ],
                      ),
                      ...summary.seriesHisabList.map((s) => TableRow(
                        children: [
                          _tableBodyCell('Ser ${s.series}', isBold: true, color: const Color(0xFF38BDF8)),
                          _tableBodyCell('${s.voucherQty} Nos', color: const Color(0xFF93C5FD)),
                          _tableBodyCell('${s.unsoldQty} Nos', color: const Color(0xFFFCA5A5)),
                          _tableBodyCell('${s.netSoldQty} Nos', isBold: true, color: const Color(0xFF4ADE80)),
                          _tableBodyCell('₹${s.rate.toStringAsFixed(2)}'),
                          _tableBodyCell('₹${s.netAmount.toStringAsFixed(2)}', isBold: true, color: const Color(0xFFFBBF24)),
                        ],
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // 3. Winning Tickets Breakdown for this Party (Customer Wins)
                if (hasCustomerWins) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF072315),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF22C55E).withAlpha(180), width: 1.2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.emoji_events_rounded, color: Color(0xFF4ADE80), size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '🎉 PARTY WINNING TICKETS (${summary.customerWins.length} Inam Found in Net Sold Stock)',
                              style: const TextStyle(color: Color(0xFF86EFAC), fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const Spacer(),
                            Text(
                              'Total Winning Inam: - ₹${summary.totalCustomerWinAmount.toStringAsFixed(2)}',
                              style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w900, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: summary.customerWins.map((w) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF03140C),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF34D399).withAlpha(120)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(w.prizeTier, style: const TextStyle(color: Color(0xFF86EFAC), fontWeight: FontWeight.bold, fontSize: 11)),
                                  const SizedBox(width: 8),
                                  Text('#${w.ticketNumber} (Ser ${w.ticketSeries})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5, fontFamily: 'monospace')),
                                  const SizedBox(width: 8),
                                  Text('₹${w.prizeAmount.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w900, fontSize: 11.5)),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],

                // 4. Date & Shift-Wise Timings Breakdown Section
                if (summary.dateBreakdowns.isNotEmpty && (summary.dateBreakdowns.length > 1 || summary.shift == 'ALL' || _reportMode == HisabReportMode.fullDetailed)) ...[
                  const SizedBox(height: 10),
                  _buildDateAndShiftBreakdownSection(summary),
                ],

                const SizedBox(height: 12),

                // 5. Bottom Summary Row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFF0B1120), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF1E293B))),
                        child: Row(
                          children: [
                            const Text('🔵 In: ', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                            Text('${summary.totalVouchers}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                            const Text('  |  🔴 Ret: ', style: TextStyle(color: Color(0xFFF87171), fontSize: 11, fontWeight: FontWeight.bold)),
                            Text('${summary.totalUnsold}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                            const Text('  =  🟢 Net: ', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 11, fontWeight: FontWeight.bold)),
                            Text('${summary.totalNetSold} Nos', style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.w900, fontSize: 11.5)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      if (hasCustomerWins)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: const Color(0xFF1E3A1A), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF4ADE80))),
                          child: Text('🏆 Winning Inam: - ₹${summary.totalCustomerWinAmount.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 11)),
                        ),

                      const SizedBox(width: 14),

                      if (!isResultDeclared) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF261205),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFF97316), width: 1.2),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.hourglass_top_rounded, color: Color(0xFFFB923C), size: 14),
                              const SizedBox(width: 6),
                              const Text('GROSS BIKRI (Result Pending): ', style: TextStyle(color: Color(0xFFFED7AA), fontSize: 10.5, fontWeight: FontWeight.bold)),
                              Text('₹ ${summary.totalNetAmount.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFFDBA74), fontWeight: FontWeight.w900, fontSize: 14.5)),
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(color: const Color(0xFF1A1500), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFFBBF24), width: 1.2)),
                          child: Row(
                            children: [
                              const Text('FINAL NET PAYABLE: ', style: TextStyle(color: Colors.grey, fontSize: 10.5, fontWeight: FontWeight.bold)),
                              Text('₹ ${summary.finalNetPayable.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w900, fontSize: 14.5)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateAndShiftBreakdownSection(PartyHisabSummary summary) {
    if (summary.dateBreakdowns.isEmpty) return const SizedBox.shrink();
    final isMultiDate = summary.dateBreakdowns.length > 1;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF070E1C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_rounded, size: 15, color: Color(0xFF38BDF8)),
                const SizedBox(width: 8),
                Text(
                  isMultiDate ? '📅 DATE & TIMINGS (SHIFT-WISE) BREAKDOWN' : '⏰ DRAW TIMINGS BREAKDOWN (1 PM • 6 PM • 8 PM)',
                  style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF0284C7).withAlpha(60), borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    isMultiDate ? '${summary.dateBreakdowns.length} Dates in Range' : 'All 3 Shifts',
                    style: const TextStyle(color: Color(0xFF7DD3FC), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: summary.dateBreakdowns.map((dBreakdown) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B132B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E3A8A).withAlpha(80)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Main Date Heading
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withAlpha(150),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_note_rounded, size: 14, color: Color(0xFFFBBF24)),
                            const SizedBox(width: 6),
                            Text(
                              dBreakdown.formattedDate,
                              style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w900, fontSize: 12),
                            ),
                            const Spacer(),
                            if (dBreakdown.hasEntry)
                              Text(
                                'Day Net: ${dBreakdown.totalNetSold} Nos (₹${dBreakdown.totalNetAmount.toStringAsFixed(2)})',
                                style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 11),
                              )
                            else
                              const Text(
                                '⚪ No entries on this date',
                                style: TextStyle(color: Colors.grey, fontSize: 10.5, fontStyle: FontStyle.italic),
                              ),
                          ],
                        ),
                      ),

                      // Sub-Headings: 1:00 PM, 6:00 PM, 8:00 PM
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: dBreakdown.shifts.map((sh) {
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: sh.hasEntry ? const Color(0xFF0F172A) : const Color(0xFF070B16),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: sh.hasEntry ? const Color(0xFF334155) : const Color(0xFF1E293B).withAlpha(80),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    sh.canonicalShift == '1PM'
                                        ? Icons.wb_sunny_outlined
                                        : (sh.canonicalShift == '6PM' ? Icons.wb_twilight_rounded : Icons.nights_stay_outlined),
                                    size: 14,
                                    color: sh.hasEntry ? const Color(0xFF38BDF8) : Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 90,
                                    child: Text(
                                      sh.shift,
                                      style: TextStyle(
                                        color: sh.hasEntry ? Colors.white : Colors.grey.shade600,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  if (!sh.hasEntry)
                                    Text(
                                      '⚪ Empty / No Entry',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 10.5, fontStyle: FontStyle.italic),
                                    )
                                  else ...[
                                    Text(
                                      'In: ${sh.totalVouchers} Nos',
                                      style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 10.5),
                                    ),
                                    const Text('  •  ', style: TextStyle(color: Color(0xFF475569))),
                                    Text(
                                      'Ret: ${sh.totalUnsold} Nos',
                                      style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 10.5),
                                    ),
                                    const Text('  •  ', style: TextStyle(color: Color(0xFF475569))),
                                    Text(
                                      'Net: ${sh.totalNetSold} Nos',
                                      style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 10.5),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '₹${sh.totalNetAmount.toStringAsFixed(2)}',
                                      style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                    if (sh.customerWins.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF166534),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '🏆 Inam: ₹${sh.totalCustomerWinAmount.toStringAsFixed(0)}',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9.5),
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. CUSTOMER BOOKINGS LIST VIEW ──────────────────────
  Widget _buildCustomerBookingList(Map<String, List<TicketSaleModel>> grouped, String dateStr) {
    if (grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_activity_outlined, size: 54, color: Colors.grey.shade700),
            const SizedBox(height: 12),
            Text('No Customer Bookings recorded for $dateStr ($_selectedShift)', style: TextStyle(color: Colors.grey.shade400, fontSize: 13.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Ticket sales entered in "Number Booking" will appear here.', style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
          ],
        ),
      );
    }

    final buyerList = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: buyerList.length,
      itemBuilder: (ctx, idx) {
        final buyer = buyerList[idx];
        final sales = grouped[buyer]!;
        return _buildCustomerBookingCard(buyer, sales);
      },
    );
  }

  Widget _buildCustomerBookingCard(String buyerName, List<TicketSaleModel> sales) {
    final totalQty = sales.fold(0, (sum, s) => sum + s.quantity);
    final totalAmt = sales.fold(0.0, (sum, s) => sum + s.totalAmount);
    final totalComm = sales.fold(0.0, (sum, s) => sum + s.commissionAmount);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_rounded, size: 16, color: Color(0xFF34D399)),
                const SizedBox(width: 8),
                Text(
                  'CUSTOMER / BUYER: $buyerName',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF065F46), borderRadius: BorderRadius.circular(4)),
                  child: Text('${sales.length} Bookings ($totalQty Nos)', style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),

                // Copy WhatsApp slip
                ElevatedButton.icon(
                  onPressed: () => _copyCustomerWhatsAppSlip(buyerName, sales),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 12),
                  label: const Text('COPY SLIP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    minimumSize: const Size(60, 28),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 6),

                // Save PDF
                ElevatedButton.icon(
                  onPressed: () => _exportCustomerPdf(buyerName, sales),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 12),
                  label: const Text('PDF SLIP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    minimumSize: const Size(60, 28),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ],
            ),
          ),

          // Items Table
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF070B16),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.0),
                      1: FlexColumnWidth(1.5),
                      2: FlexColumnWidth(1.0),
                      3: FlexColumnWidth(1.0),
                      4: FlexColumnWidth(1.2),
                      5: FlexColumnWidth(1.2),
                    },
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F172A),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                        ),
                        children: [
                          _tableHeaderCell('#'),
                          _tableHeaderCell('TICKET NUMBER'),
                          _tableHeaderCell('SERIES'),
                          _tableHeaderCell('QTY'),
                          _tableHeaderCell('PRICE'),
                          _tableHeaderCell('TOTAL (₹)'),
                        ],
                      ),
                      ...sales.take(8).map((s) => TableRow(
                        children: [
                          _tableBodyCell(s.receiptNumber.isNotEmpty ? s.receiptNumber : 'SALE'),
                          _tableBodyCell(s.ticketNumber, isBold: true, color: const Color(0xFF38BDF8)),
                          _tableBodyCell('Ser ${s.ticketSeries}'),
                          _tableBodyCell('${s.quantity} Nos'),
                          _tableBodyCell('₹${s.pricePerTicket.toStringAsFixed(2)}'),
                          _tableBodyCell('₹${s.totalAmount.toStringAsFixed(2)}', isBold: true, color: const Color(0xFFFBBF24)),
                        ],
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Bottom Totals Row
                Row(
                  children: [
                    Text('Total Tickets: $totalQty Nos', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                    if (totalComm > 0) ...[
                      const Text('  •  Commission: ', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      Text('₹${totalComm.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(color: const Color(0xFF064E3B), borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        children: [
                          const Text('TOTAL BILL: ', style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
                          Text('₹ ${totalAmt.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.w900, fontSize: 13.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Text(text, style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 10)),
    );
  }

  Widget _tableBodyCell(String text, {bool isBold = false, Color color = Colors.white70}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      child: Text(text, style: TextStyle(color: color, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: 11)),
    );
  }

  // ── ACTION HANDLERS ─────────────────────────────────────
  void _copyPartyWhatsAppText(PartyHisabSummary summary) {
    final text = _reportMode == HisabReportMode.summary
        ? PartyHisabReportService.instance.generateSummaryWhatsAppText(summary)
        : PartyHisabReportService.instance.generateFullDetailedWhatsAppText(summary);

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📋 Copied Wholesale Hisab for "${summary.partyName}" (Ready for WhatsApp)!'),
        backgroundColor: const Color(0xFF166534),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _exportPartyPdf(PartyHisabSummary summary) async {
    final path = _reportMode == HisabReportMode.summary
        ? await PartyHisabReportService.instance.exportSummaryPdf(summary)
        : await PartyHisabReportService.instance.exportFullDetailedPdf(summary);

    if (path != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('📄 Exported PDF: $path'), backgroundColor: const Color(0xFF166534), duration: const Duration(seconds: 4)),
      );
    }
  }

  void _copyCustomerWhatsAppSlip(String buyerName, List<TicketSaleModel> sales) {
    final buffer = StringBuffer();
    final dateStr = DateFormat('dd-MMM-yyyy').format(_selectedDate);
    final totalQty = sales.fold(0, (sum, s) => sum + s.quantity);
    final totalAmt = sales.fold(0.0, (sum, s) => sum + s.totalAmount);

    buffer.writeln('====================================');
    buffer.writeln('     🎟️ CUSTOMER BOOKING SLIP');
    buffer.writeln('====================================');
    buffer.writeln('Customer : $buyerName');
    buffer.writeln('Date     : $dateStr | Shift: $_selectedShift');
    buffer.writeln('------------------------------------');
    buffer.writeln('NO.   SERIES   TICKET NO.   QTY   AMOUNT');
    buffer.writeln('------------------------------------');
    for (int i = 0; i < sales.length; i++) {
      final s = sales[i];
      buffer.writeln('${(i + 1).toString().padRight(4)} Ser ${s.ticketSeries.padRight(4)} ${s.ticketNumber.padRight(10)} ${s.quantity} Nos  ₹${s.totalAmount.toStringAsFixed(2)}');
    }
    buffer.writeln('------------------------------------');
    buffer.writeln('TOTAL TICKETS : $totalQty Nos');
    buffer.writeln('TOTAL PAYABLE : Rs. ${totalAmt.toStringAsFixed(2)}');
    buffer.writeln('====================================');

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('📋 Copied Booking Slip for "$buyerName"!'), backgroundColor: const Color(0xFF166534), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _exportCustomerPdf(String buyerName, List<TicketSaleModel> sales) async {
    final bytes = await BookingPdfService.instance.generatePdfReport(
      date: _selectedDate,
      sales: sales,
      customerName: buyerName,
      rangeTitle: 'CUSTOMER BOOKING SLIP - $buyerName',
    );
    // Print / share PDF
    await Printing.sharePdf(bytes: bytes, filename: 'booking_${buyerName}_${DateFormat('yyyyMMdd').format(_selectedDate)}.pdf');
  }

  void _copyAllPartiesCombinedText(List<PartyHisabSummary> summaries) {
    if (summaries.isEmpty) return;
    final buffer = StringBuffer();
    for (final s in summaries) {
      final t = _reportMode == HisabReportMode.summary
          ? PartyHisabReportService.instance.generateSummaryWhatsAppText(s)
          : PartyHisabReportService.instance.generateFullDetailedWhatsAppText(s);
      buffer.writeln(t);
      buffer.writeln('\n------------------------------------------------\n');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('📋 Copied ${summaries.length} Wholesale Parties Hisab!'), backgroundColor: const Color(0xFF166534), duration: const Duration(seconds: 3)),
    );
  }

  void _copyAllCustomersCombinedText(Map<String, List<TicketSaleModel>> grouped) {
    if (grouped.isEmpty) return;
    final buffer = StringBuffer();
    final dateStr = DateFormat('dd-MMM-yyyy').format(_selectedDate);

    buffer.writeln('====================================');
    buffer.writeln('   📊 ALL CUSTOMER BOOKINGS SUMMARY');
    buffer.writeln('   Date: $dateStr | Shift: $_selectedShift');
    buffer.writeln('====================================\n');

    for (final entry in grouped.entries) {
      final buyer = entry.key;
      final sales = entry.value;
      final totalQty = sales.fold(0, (sum, s) => sum + s.quantity);
      final totalAmt = sales.fold(0.0, (sum, s) => sum + s.totalAmount);

      buffer.writeln('• $buyer : $totalQty Tickets (Rs. ${totalAmt.toStringAsFixed(2)})');
    }
    buffer.writeln('\n====================================');

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('📋 Copied ${grouped.length} Customer Bookings Summary!'), backgroundColor: const Color(0xFF166534), duration: const Duration(seconds: 3)),
    );
  }

  void _previewPartyTextModal(PartyHisabSummary summary) {
    final text = _reportMode == HisabReportMode.summary
        ? PartyHisabReportService.instance.generateSummaryWhatsAppText(summary)
        : PartyHisabReportService.instance.generateFullDetailedWhatsAppText(summary);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 680,
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded, color: Color(0xFF38BDF8), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Preview Hisab: ${summary.partyName}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('📋 Copied to Clipboard!'), backgroundColor: Color(0xFF166534)),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 13),
                      label: const Text('COPY TEXT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                      onPressed: () => Navigator.pop(ctx),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Divider(color: Color(0xFF1E293B)),
                const SizedBox(height: 4),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF070B16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SelectableText(
                          text,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFFE2E8F0),
                            fontSize: 12,
                            letterSpacing: 0.2,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
