import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_service.dart';
import '../models/lottery_sambad_result_model.dart';
import '../utils/party_hisab_settlement_engine.dart';
import '../services/party_hisab_report_service.dart';
import '../../unsold/viewmodels/voucher_viewmodel.dart';
import '../../unsold/viewmodels/unsold_viewmodel.dart';
import '../viewmodels/draws_viewmodel.dart';

enum HisabReportMode { summary, fullDetailed }

class GetFileHisabDialog extends ConsumerStatefulWidget {
  final DateTime initialDate;
  final String initialShift;

  const GetFileHisabDialog({
    super.key,
    required this.initialDate,
    required this.initialShift,
  });

  @override
  ConsumerState<GetFileHisabDialog> createState() => _GetFileHisabDialogState();
}

class _GetFileHisabDialogState extends ConsumerState<GetFileHisabDialog> {
  late DateTime _selectedDate;
  late String _selectedShift;
  bool _isCustomRange = false;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  String _selectedParty = 'ALL';
  bool _showStats = true;

  HisabReportMode _reportMode = HisabReportMode.summary;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  // SQLite se load kiye lottery results (manually entered)
  List<LotterySambadResultModel> _allLotteryResults = [];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _rangeStart = widget.initialDate;
    _rangeEnd = widget.initialDate;
    _selectedShift = widget.initialShift.isNotEmpty ? widget.initialShift : 'Dear 1 PM';
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadResultsFromDatabase();
      _loadData();
    });
  }

  Future<void> _loadResultsFromDatabase() async {
    try {
      final rows = await DatabaseService.instance.getLotteryResults();
      final List<LotterySambadResultModel> parsed = [];
      for (final r in rows) {
        final sec = (r['secondPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();
        final th  = (r['thirdPrizeNumbers']?.toString()  ?? '').split(',').where((e) => e.isNotEmpty).toList();
        final fo  = (r['fourthPrizeNumbers']?.toString()  ?? '').split(',').where((e) => e.isNotEmpty).toList();
        final fi  = (r['fifthPrizeNumbers']?.toString()   ?? '').split(',').where((e) => e.isNotEmpty).toList();
        parsed.add(LotterySambadResultModel(
          drawId:             r['id']?.toString() ?? 'draw_${r['drawDateStr']}_${r['drawTimeStr']}',
          drawName:           r['drawName']?.toString() ?? 'DEAR LOTTERY',
          drawDateStr:        r['drawDateStr']?.toString() ?? '',
          drawTimeStr:        r['drawTimeStr']?.toString() ?? '',
          firstPrize:         r['firstPrize']?.toString() ?? '',
          consolationPrize:   '',
          secondPrizeNumbers: sec,
          thirdPrizeNumbers:  th,
          fourthPrizeNumbers: fo,
          fifthPrizeNumbers:  fi,
          publishedAt:        DateTime.tryParse(r['publishedAt']?.toString() ?? '') ?? DateTime.now(),
        ));
      }
      if (mounted) setState(() => _allLotteryResults = parsed);
    } catch (e) {
      debugPrint('GetFileHisabDialog: Error loading results from DB: $e');
    }
  }

  void _loadData() {
    final shift = _selectedShift == 'ALL' ? null : _selectedShift;

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
      final dStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      ref.read(voucherViewModelProvider.notifier).loadVouchers(
        date: dStr,
        drawShift: shift,
      );
      ref.read(unsoldViewModelProvider.notifier).loadUnsold(
        date: dStr,
        drawShift: shift,
      );
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
      _loadData();
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
      _loadData();
    }
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
    final drawsState = ref.watch(drawsViewModelProvider);

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final startStr = (_isCustomRange && _rangeStart != null) ? DateFormat('yyyy-MM-dd').format(_rangeStart!) : null;
    final endStr = (_isCustomRange && _rangeEnd != null) ? DateFormat('yyyy-MM-dd').format(_rangeEnd!) : null;

    // Dynamically extract all available parties from current vouchers and unsold
    final Set<String> allPartiesSet = {'ALL'};
    for (final v in voucherState.vouchers) {
      final p = v.partyName.trim();
      if (p.isNotEmpty) allPartiesSet.add(p);
    }
    for (final u in unsoldState.unsoldList) {
      final p = u.partyName.trim();
      if (p.isNotEmpty) allPartiesSet.add(p);
    }
    final availableParties = allPartiesSet.toList()
      ..sort((a, b) {
        if (a == 'ALL') return -1;
        if (b == 'ALL') return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    // Merge SQLite DB results + Riverpod state results (avoid duplicates by drawId)
    final Map<String, LotterySambadResultModel> mergedResultsMap = {};
    for (final r in _allLotteryResults) {
      mergedResultsMap[r.drawId] = r;
    }
    for (final r in drawsState.resultsMap.values) {
      mergedResultsMap[r.drawId] = r; // state ka result override karo (zyada fresh)
    }
    final allResults = mergedResultsMap.values.toList();

    // Calculate settlements using PartyHisabSettlementEngine with merged results
    final partySummaries = PartyHisabSettlementEngine.calculatePartySettlements(
      vouchers: voucherState.vouchers,
      unsoldList: unsoldState.unsoldList,
      selectedDate: dateStr,
      startDate: startStr,
      endDate: endStr,
      selectedShift: _selectedShift,
      allResults: allResults,
    );

    // Apply Party Filter
    final partyFiltered = _selectedParty == 'ALL'
        ? partySummaries
        : partySummaries.where((s) => s.partyName.trim().toLowerCase() == _selectedParty.trim().toLowerCase()).toList();

    // Apply Search Filter
    final filteredSummaries = _searchQuery.isEmpty
        ? partyFiltered
        : partyFiltered.where((s) => s.partyName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    final totalNetAllParties = filteredSummaries.fold(0, (sum, s) => sum + s.totalNetSold);
    final totalValueAllParties = filteredSummaries.fold(0.0, (sum, s) => sum + s.finalNetPayable);
    final totalWinsAllParties = filteredSummaries.fold(0.0, (sum, s) => sum + s.totalCustomerWinAmount);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF080C1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF38BDF8).withAlpha(90), width: 1.5),
          boxShadow: [
            BoxShadow(color: const Color(0xFF0284C7).withAlpha(50), blurRadius: 40),
            BoxShadow(color: Colors.black.withAlpha(240), blurRadius: 24, spreadRadius: 8),
          ],
        ),
        child: Column(
          children: [
            // ── TOP HEADER: ROW 1 (NAVIGATION & FILTER CONTROLS) ────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0C2438), Color(0xFF0F172A)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
              ),
              child: Row(
                children: [
                  // Title Icon
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF0369A1)]),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [BoxShadow(color: const Color(0xFF0284C7).withAlpha(120), blurRadius: 8)],
                    ),
                    child: const Icon(Icons.folder_shared_rounded, color: Colors.white, size: 17),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'GET FILE • HISAB',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: Colors.white, letterSpacing: 0.6),
                  ),
                  const SizedBox(width: 14),

                  // 1. Single Date Picker Button
                  InkWell(
                    onTap: _pickSingleDate,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: !_isCustomRange ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: !_isCustomRange ? const Color(0xFF38BDF8) : const Color(0xFF334155)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 12, color: !_isCustomRange ? Colors.white : const Color(0xFF38BDF8)),
                          const SizedBox(width: 5),
                          Text(
                            DateFormat('dd-MM-yyyy').format(_selectedDate),
                            style: TextStyle(
                              color: !_isCustomRange ? Colors.white : Colors.grey.shade300,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 2. Custom Range Picker Button (Directly opens DateRangePicker)
                  InkWell(
                    onTap: _pickCustomRange,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: _isCustomRange ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _isCustomRange ? const Color(0xFF38BDF8) : const Color(0xFF334155)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.date_range_rounded, size: 13, color: _isCustomRange ? Colors.white : const Color(0xFF38BDF8)),
                          const SizedBox(width: 5),
                          Text(
                            _isCustomRange && _rangeStart != null && _rangeEnd != null
                                ? '${DateFormat('dd/MM').format(_rangeStart!)} ➔ ${DateFormat('dd/MM/yy').format(_rangeEnd!)}'
                                : '📅 Custom Range',
                            style: TextStyle(
                              color: _isCustomRange ? Colors.white : Colors.grey.shade300,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Reset Custom Range chip if active
                  if (_isCustomRange) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        setState(() => _isCustomRange = false);
                        _loadData();
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withAlpha(180),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),

                  // 3. Shift Dropdown
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF38BDF8).withAlpha(120)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedShift,
                        dropdownColor: const Color(0xFF0F172A),
                        icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF38BDF8), size: 16),
                        style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11),
                        items: const [
                          DropdownMenuItem(value: 'Dear 1 PM', child: Text('Dear 1 PM')),
                          DropdownMenuItem(value: 'Dear 6 PM', child: Text('Dear 6 PM')),
                          DropdownMenuItem(value: 'Dear 8 PM', child: Text('Dear 8 PM')),
                          DropdownMenuItem(value: 'ALL', child: Text('All Shifts')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedShift = val);
                            _loadData();
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // 4. Party Selection Dropdown (Persistent across all parties)
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: _selectedParty != 'ALL' ? const Color(0xFF1E1B4B) : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _selectedParty != 'ALL' ? const Color(0xFFFBBF24) : const Color(0xFF818CF8).withAlpha(150),
                        width: _selectedParty != 'ALL' ? 1.4 : 1.0,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: availableParties.contains(_selectedParty) ? _selectedParty : 'ALL',
                        dropdownColor: const Color(0xFF0F172A),
                        icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFA5B4FC), size: 16),
                        style: TextStyle(
                          color: _selectedParty != 'ALL' ? const Color(0xFFFBBF24) : const Color(0xFFA5B4FC),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                        items: availableParties.map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p == 'ALL' ? '👥 All Parties (${availableParties.length - 1})' : '👤 $p'),
                        )).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedParty = val);
                          }
                        },
                      ),
                    ),
                  ),

                  const Spacer(),

                  // 5. Hide / Show Stats Button
                  IconButton(
                    icon: Icon(_showStats ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18),
                    color: _showStats ? const Color(0xFF38BDF8) : Colors.grey,
                    tooltip: _showStats ? 'Hide Stats & Quick Bar' : 'Show Stats & Quick Bar',
                    onPressed: () => setState(() => _showStats = !_showStats),
                  ),

                  // 6. Close Dialog Button
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── TOP HEADER: ROW 2 (COLLAPSIBLE STATS & REPORT TOOLBAR) ───────────
            if (_showStats)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                color: const Color(0xFF0B1120),
                child: Row(
                  children: [
                    // Stats Pill 1: Parties
                    _headerStatPill('${filteredSummaries.length}', 'Parties', const Color(0xFF1E293B), Colors.white),
                    const SizedBox(width: 6),

                    // Stats Pill 2: Net Sold
                    _headerStatPill('$totalNetAllParties', 'Net Sold', const Color(0xFF07271A), const Color(0xFF4ADE80)),
                    const SizedBox(width: 6),

                    // Stats Pill 3: Net Hisab Value
                    _headerStatPill(
                      '₹${totalValueAllParties >= 100000 ? '${(totalValueAllParties / 100000).toStringAsFixed(1)}L' : totalValueAllParties.toStringAsFixed(0)}',
                      'Net Hisab',
                      const Color(0xFF2E1A04),
                      const Color(0xFFFBBF24),
                    ),

                    // Stats Pill 4: Winning Claims Total
                    if (totalWinsAllParties > 0) ...[
                      const SizedBox(width: 6),
                      _headerStatPill(
                        '₹${totalWinsAllParties.toStringAsFixed(0)}',
                        'Total Wins',
                        const Color(0xFF1E3A1A),
                        const Color(0xFF4ADE80),
                      ),
                    ],

                    const SizedBox(width: 14),

                    // Report Format: Summary Mode Pill
                    InkWell(
                      onTap: () => setState(() => _reportMode = HisabReportMode.summary),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _reportMode == HisabReportMode.summary ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: _reportMode == HisabReportMode.summary ? const Color(0xFF38BDF8) : Colors.transparent),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.table_chart_rounded, size: 12, color: _reportMode == HisabReportMode.summary ? Colors.white : Colors.grey),
                            const SizedBox(width: 5),
                            Text(
                              '📊 Summary',
                              style: TextStyle(
                                color: _reportMode == HisabReportMode.summary ? Colors.white : Colors.grey.shade400,
                                fontWeight: FontWeight.bold,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Report Format: Full Detailed Mode Pill
                    InkWell(
                      onTap: () => setState(() => _reportMode = HisabReportMode.fullDetailed),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _reportMode == HisabReportMode.fullDetailed ? const Color(0xFF7C3AED) : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: _reportMode == HisabReportMode.fullDetailed ? const Color(0xFFA78BFA) : Colors.transparent),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.receipt_long_rounded, size: 12, color: _reportMode == HisabReportMode.fullDetailed ? Colors.white : Colors.grey),
                            const SizedBox(width: 5),
                            Text(
                              '📑 Detailed',
                              style: TextStyle(
                                color: _reportMode == HisabReportMode.fullDetailed ? Colors.white : Colors.grey.shade400,
                                fontWeight: FontWeight.bold,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Search Party TextField
                    SizedBox(
                      width: 160,
                      height: 28,
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Search Party...',
                          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 10.5),
                          prefixIcon: const Icon(Icons.search, size: 13, color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                    ),
                  ],
                ),
              ),

            // ── BODY: PARTY CARDS GRID ────────────────────────
            Expanded(
              child: filteredSummaries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade700),
                          const SizedBox(height: 12),
                          Text(
                            'No Voucher or Unsold records found for $dateStr ($_selectedShift)',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredSummaries.length,
                      itemBuilder: (ctx, idx) {
                        final summary = filteredSummaries[idx];
                        return _buildPartyHisabCard(summary);
                      },
                    ),
            ),

            // ── BOTTOM GLOBAL ACTIONS FOOTER ──────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF0B1120),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                border: Border(top: BorderSide(color: Color(0xFF1E293B))),
              ),
              child: Row(
                children: [
                  Text(
                    'Total Parties: ${partySummaries.length} • Total Net Sold: $totalNetAllParties Tickets',
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),

                  // Copy Combined All Parties Summary Text
                  OutlinedButton.icon(
                    onPressed: () => _copyAllPartiesCombinedText(partySummaries),
                    icon: const Icon(Icons.copy_all_rounded, size: 14, color: Color(0xFF38BDF8)),
                    label: const Text('COPY ALL PARTIES TEXT', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF38BDF8)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                  // Export PDF Button (Party or All Parties)
                  ElevatedButton.icon(
                    onPressed: () async {
                      if (filteredSummaries.isEmpty) return;
                      for (final s in filteredSummaries) {
                        await _exportPartyPdf(s);
                      }
                    },
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 14),
                    label: Text(
                      _selectedParty != 'ALL' ? 'EXPORT PDF FOR $_selectedParty' : 'EXPORT ALL PARTIES PDF',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Close Dialog Button
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('CLOSE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerStatPill(String val, String label, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textCol.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(val, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: textCol)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 9.5, color: textCol.withAlpha(180))),
        ],
      ),
    );
  }

  Widget _buildPartyHisabCard(PartyHisabSummary summary) {
    final hasWins = summary.customerWins.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        children: [
          // Card Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_pin_rounded, size: 16, color: Color(0xFF38BDF8)),
                const SizedBox(width: 8),
                Text(
                  summary.partyName,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withAlpha(120),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(summary.shift, style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),

                // Action Buttons
                // 1. WhatsApp Copy
                ElevatedButton.icon(
                  onPressed: () => _copyPartyWhatsAppText(summary),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 12),
                  label: const Text('COPY WHATSAPP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(60, 26),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 6),

                // 2. Export PDF
                ElevatedButton.icon(
                  onPressed: () => _exportPartyPdf(summary),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 12),
                  label: const Text('SAVE PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(60, 26),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 6),

                // 3. Preview Modal
                OutlinedButton.icon(
                  onPressed: () => _previewPartyTextModal(summary),
                  icon: const Icon(Icons.remove_red_eye_outlined, size: 12, color: Colors.grey),
                  label: const Text('PREVIEW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.grey)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF334155)),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(50, 26),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ],
            ),
          ),

          // Card Body: Series Breakdown Table
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Series Summary Table
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
                          _tableHeaderCell('VOUCHER (IN)'),
                          _tableHeaderCell('UNSOLD (RET)'),
                          _tableHeaderCell('NET SOLD'),
                          _tableHeaderCell('RATE (₹)'),
                          _tableHeaderCell('NET AMOUNT (₹)'),
                        ],
                      ),
                      ...summary.seriesHisabList.map((s) => TableRow(
                        children: [
                          _tableBodyCell('Ser ${s.series}', isBold: true, color: const Color(0xFF38BDF8)),
                          _tableBodyCell('${s.voucherQty} Nos'),
                          _tableBodyCell('${s.unsoldQty} Nos', color: const Color(0xFFF87171)),
                          _tableBodyCell('${s.netSoldQty} Nos', isBold: true, color: const Color(0xFF4ADE80)),
                          _tableBodyCell('₹${s.rate.toStringAsFixed(2)}'),
                          _tableBodyCell('₹${s.netAmount.toStringAsFixed(2)}', isBold: true, color: const Color(0xFFFBBF24)),
                        ],
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Date & Shift-Wise Timings Breakdown Section
                if (summary.dateBreakdowns.isNotEmpty && (summary.dateBreakdowns.length > 1 || summary.shift == 'ALL')) ...[
                  _buildDateAndShiftBreakdownSection(summary),
                  const SizedBox(height: 10),
                ],

                // Bottom Summary & Settlement Row
                Row(
                  children: [
                    // Stock Summary Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1120),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Row(
                        children: [
                          Text('In: ${summary.totalVouchers}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          const Text(' • ', style: TextStyle(color: Colors.grey)),
                          Text('Ret: ${summary.totalUnsold}', style: const TextStyle(color: Color(0xFFF87171), fontSize: 11)),
                          const Text(' • ', style: TextStyle(color: Colors.grey)),
                          Text('Net: ${summary.totalNetSold} Nos', style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Winning adjustment pill if any
                    if (hasWins)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A1A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF4ADE80)),
                        ),
                        child: Text(
                          '🏆 Wins: - ₹${summary.totalCustomerWinAmount.toStringAsFixed(2)}',
                          style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),

                    const Spacer(),

                    // Final Net Payable Box
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1500),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFBBF24), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          const Text('FINAL NET PAYABLE: ', style: TextStyle(color: Colors.grey, fontSize: 10.5, fontWeight: FontWeight.bold)),
                          Text(
                            '₹ ${summary.finalNetPayable.toStringAsFixed(2)}',
                            style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w900, fontSize: 14),
                          ),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_rounded, size: 14, color: Color(0xFF38BDF8)),
                const SizedBox(width: 6),
                Text(
                  isMultiDate ? '📅 DATE & TIMINGS (SHIFT-WISE) BREAKDOWN' : '⏰ DRAW TIMINGS BREAKDOWN (1 PM • 6 PM • 8 PM)',
                  style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11),
                ),
                const Spacer(),
                Text(
                  isMultiDate ? '${summary.dateBreakdowns.length} Dates' : 'All 3 Shifts',
                  style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: summary.dateBreakdowns.map((dBreakdown) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B132B),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF1E3A8A).withAlpha(80)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withAlpha(150),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_note_rounded, size: 13, color: Color(0xFFFBBF24)),
                            const SizedBox(width: 6),
                            Text(
                              dBreakdown.formattedDate,
                              style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w900, fontSize: 11.5),
                            ),
                            const Spacer(),
                            if (dBreakdown.hasEntry)
                              Text(
                                'Day Net: ${dBreakdown.totalNetSold} Nos (₹${dBreakdown.totalNetAmount.toStringAsFixed(2)})',
                                style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 10.5),
                              )
                            else
                              const Text(
                                '⚪ No entries on this date',
                                style: TextStyle(color: Colors.grey, fontSize: 10, fontStyle: FontStyle.italic),
                              ),
                          ],
                        ),
                      ),

                      // Shifts Sub-Headings
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          children: dBreakdown.shifts.map((sh) {
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: sh.hasEntry ? const Color(0xFF0F172A) : const Color(0xFF070B16),
                                borderRadius: BorderRadius.circular(4),
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
                                    size: 13,
                                    color: sh.hasEntry ? const Color(0xFF38BDF8) : Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 85,
                                    child: Text(
                                      sh.shift,
                                      style: TextStyle(
                                        color: sh.hasEntry ? Colors.white : Colors.grey.shade600,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  if (!sh.hasEntry)
                                    Text(
                                      '⚪ Empty / No Entry',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 10, fontStyle: FontStyle.italic),
                                    )
                                  else ...[
                                    Text('In: ${sh.totalVouchers}', style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 10)),
                                    const Text(' • ', style: TextStyle(color: Color(0xFF475569))),
                                    Text('Ret: ${sh.totalUnsold}', style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 10)),
                                    const Text(' • ', style: TextStyle(color: Color(0xFF475569))),
                                    Text('Net: ${sh.totalNetSold} Nos', style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 10)),
                                    const Spacer(),
                                    Text('₹${sh.totalNetAmount.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold, fontSize: 10.5)),
                                    if (sh.customerWins.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(color: const Color(0xFF166534), borderRadius: BorderRadius.circular(3)),
                                        child: Text('🏆 ₹${sh.totalCustomerWinAmount.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9)),
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

  Widget _tableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 10),
      ),
    );
  }

  Widget _tableBodyCell(String text, {bool isBold = false, Color color = Colors.white70}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontSize: 11,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ACTION HANDLERS
  // ═══════════════════════════════════════════════════════════════

  void _copyPartyWhatsAppText(PartyHisabSummary summary) {
    final text = _reportMode == HisabReportMode.summary
        ? PartyHisabReportService.instance.generateSummaryWhatsAppText(summary)
        : PartyHisabReportService.instance.generateFullDetailedWhatsAppText(summary);

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📋 Copied Hisab for "${summary.partyName}" to Clipboard (Ready for WhatsApp)!'),
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
        SnackBar(
          content: Text('📄 Exported PDF: $path'),
          backgroundColor: const Color(0xFF166534),
          duration: const Duration(seconds: 4),
        ),
      );
    }
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
      SnackBar(
        content: Text('📋 Copied ${summaries.length} Parties Hisab to Clipboard!'),
        backgroundColor: const Color(0xFF166534),
        duration: const Duration(seconds: 3),
      ),
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
