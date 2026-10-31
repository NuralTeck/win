import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
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
import '../../bookings/services/booking_pdf_service.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../models/lottery_sambad_result_model.dart';
import '../models/winning_claim_model.dart';
import '../utils/winner_verification_engine.dart';
import '../../../core/process/services/process_manager.dart';
import '../../../core/process/models/process_model.dart';

enum DateFilterMode {
  single,
  range,
  all,
}

/// Party-wise settlement breakdown inside a draw
class DrawPartySettlement {
  final String partyName;
  final int ticketCount;
  final double totalSales;
  final double totalCommission;
  final double totalInam;
  final double netBalance;
  final List<WinningClaimModel> winners;

  const DrawPartySettlement({
    required this.partyName,
    required this.ticketCount,
    required this.totalSales,
    required this.totalCommission,
    required this.totalInam,
    required this.netBalance,
    required this.winners,
  });
}

/// Precomputed lightweight model for each draw settlement card
class DrawHisabCardData {
  final String groupKey;
  final String shiftPart;
  final String datePart;
  final DateTime cardDate;
  final List<TicketSaleModel> sales;
  final LotterySambadResultModel? matchingResult;
  final List<WinningClaimModel> winners;
  final double totalSales;
  final double totalCommission;
  final double totalInam;
  final double netBalance;
  final Map<String, DrawPartySettlement> partyBreakdown;

  const DrawHisabCardData({
    required this.groupKey,
    required this.shiftPart,
    required this.datePart,
    required this.cardDate,
    required this.sales,
    required this.matchingResult,
    required this.winners,
    required this.totalSales,
    required this.totalCommission,
    required this.totalInam,
    required this.netBalance,
    this.partyBreakdown = const {},
  });
}

class GeneratedHisabScreen extends ConsumerStatefulWidget {
  const GeneratedHisabScreen({super.key});

  @override
  ConsumerState<GeneratedHisabScreen> createState() => _GeneratedHisabScreenState();
}

class _GeneratedHisabScreenState extends ConsumerState<GeneratedHisabScreen> {
  DateFilterMode _dateMode = DateFilterMode.single;
  DateTime _selectedDate = DateTime.now();
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  String _selectedShift = 'All';
  String _selectedParty = 'All';
  bool _isExportingPdf = false;

  List<LotterySambadResultModel> _savedResults = [];
  final Map<String, List<WinningClaimModel>> _winnerCache = {};

  // 🚀 SMOOTH CHUNK PROCESSING & PRECOMPUTED STATE (No UI freeze)
  bool _isProcessingChunks = false;
  double _chunkProgress = 0.0;
  String _chunkStatus = '';
  List<TicketSaleModel> _filteredSales = [];
  List<DrawHisabCardData> _processedDrawCards = [];
  List<String> _cachedParties = ['All'];
  double _overallSalesAmt = 0.0;
  double _overallCommissionAmt = 0.0;
  double _overallInamAmt = 0.0;
  double _overallNetAmt = 0.0;
  int _displayedCardsLimit = 25;

  Timer? _recomputeDebounce;

  void _triggerRecomputeDebounced({int ms = 120}) {
    _recomputeDebounce?.cancel();
    _recomputeDebounce = Timer(Duration(milliseconds: ms), () {
      if (mounted) {
        _recomputeHisabChunks();
      }
    });
  }

  @override
  void dispose() {
    _recomputeDebounce?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadResultsFromDb();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recomputeHisabChunks();
    });
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
        _triggerRecomputeDebounced();
      }
    } catch (e) {
      debugPrint('Error loading results: $e');
    }
  }

  /// 🚀 Chunked Asynchronous Aggregation Pipeline
  /// Splits processing into microtask chunks of 500-1000 items so UI stays 60-120 FPS buttery smooth.
  Future<void> _recomputeHisabChunks() async {
    if (!mounted) return;
    setState(() {
      _isProcessingChunks = true;
      _chunkProgress = 0.05;
      _chunkStatus = 'Loading booking sales...';
    });

    await Future.delayed(Duration.zero);

    List<TicketSaleModel> allSales = [];
    try {
      if (_dateMode == DateFilterMode.single) {
        allSales = await DatabaseService.instance.getTicketSalesByDate(_selectedDate);
      } else if (_dateMode == DateFilterMode.range && _rangeStart != null && _rangeEnd != null) {
        allSales = await DatabaseService.instance.getTicketSalesByDateRange(_rangeStart!, _rangeEnd!);
      } else {
        allSales = await DatabaseService.instance.getTicketSalesByDateRange(
          DateTime(2020, 1, 1),
          DateTime(2035, 12, 31),
        );
      }
    } catch (e) {
      debugPrint('Error loading ticket sales for hisab from DB: $e');
      allSales = ref.read(ticketSalesViewModelProvider).sales;
    }

    // 1. Extract dynamic unique parties / sellers with quick cache
    final Map<int, String> dmyCache = {};
    String getDmy(DateTime dt) {
      final key = dt.year * 10000 + dt.month * 100 + dt.day;
      final existing = dmyCache[key];
      if (existing != null) return existing;
      final val = DateFormat('dd/MM/yyyy').format(dt);
      dmyCache[key] = val;
      return val;
    }

    // Process party list with case-insensitive uniqueness from DB + current sales
    final Set<String> seenPartyLower = {'all'};
    final List<String> sortedParties = ['All'];
    try {
      final dbParties = await DatabaseService.instance.getActivePartiesForSelection();
      for (final p in dbParties) {
        final name = p.trim();
        if (name.isNotEmpty && seenPartyLower.add(name.toLowerCase())) {
          sortedParties.add(name);
        }
      }
    } catch (_) {}

    for (final s in allSales) {
      final name = s.buyerName.trim().isNotEmpty ? s.buyerName.trim() : s.agentName.trim();
      if (name.isNotEmpty && seenPartyLower.add(name.toLowerCase())) {
        sortedParties.add(name);
      }
    }
    sortedParties.sort((a, b) => a == 'All' ? -1 : (b == 'All' ? 1 : a.toLowerCase().compareTo(b.toLowerCase())));

    if (!seenPartyLower.contains(_selectedParty.toLowerCase())) {
      _selectedParty = 'All';
    }

    if (!mounted) return;
    setState(() {
      _cachedParties = sortedParties;
      _chunkProgress = 0.20;
      _chunkStatus = 'Filtering sales in chunks...';
    });
    await Future.delayed(Duration.zero);

    // 2. Filter sales in chunk batches
    final List<TicketSaleModel> matchingSales = [];
    final Map<String, List<TicketSaleModel>> rawGroups = {};

    const int filterChunkSize = 1000;
    final int totalSalesCount = allSales.length;

    for (int i = 0; i < totalSalesCount; i += filterChunkSize) {
      final end = (i + filterChunkSize < totalSalesCount) ? i + filterChunkSize : totalSalesCount;
      for (int j = i; j < end; j++) {
        final s = allSales[j];

        // Date filter
        if (_dateMode == DateFilterMode.single) {
          if (s.drawDate.year != _selectedDate.year ||
              s.drawDate.month != _selectedDate.month ||
              s.drawDate.day != _selectedDate.day) {
            continue;
          }
        } else if (_dateMode == DateFilterMode.range && _rangeStart != null && _rangeEnd != null) {
          final d = DateTime(s.drawDate.year, s.drawDate.month, s.drawDate.day);
          final start = DateTime(_rangeStart!.year, _rangeStart!.month, _rangeStart!.day);
          final end = DateTime(_rangeEnd!.year, _rangeEnd!.month, _rangeEnd!.day);
          if (d.isBefore(start) || d.isAfter(end)) {
            continue;
          }
        }

        // Party filter
        if (_selectedParty != 'All') {
          final pBuyer = s.buyerName.trim().toLowerCase();
          final pAgent = s.agentName.trim().toLowerCase();
          final target = _selectedParty.trim().toLowerCase();
          if (pBuyer != target && pAgent != target) {
            continue;
          }
        }

        // Shift detection
        String shiftKey = 'Dear 1 PM';
        final dName = s.drawName.toLowerCase();
        if (dName.contains('6:00') || dName.contains('6 pm') || dName.contains('6pm') || dName.contains('day')) {
          shiftKey = 'Dear 6 PM';
        } else if (dName.contains('8:00') || dName.contains('8 pm') || dName.contains('8pm') || dName.contains('night') || dName.contains('evening')) {
          shiftKey = 'Dear 8 PM';
        }

        // Shift filter
        if (_selectedShift != 'All' && !_matchesShift(shiftKey, _selectedShift)) {
          continue;
        }

        matchingSales.add(s);
        final sDateStr = getDmy(s.drawDate);
        final groupKey = '$sDateStr — $shiftKey';
        rawGroups.putIfAbsent(groupKey, () => []).add(s);
      }

      // Yield frame every chunk to keep UI at 60 FPS
      if (totalSalesCount > 1000) {
        await Future.delayed(Duration.zero);
        if (!mounted) return;
        if (end == totalSalesCount || end % 10000 == 0) {
          setState(() {
            _chunkProgress = 0.20 + (0.35 * (end / totalSalesCount));
            _chunkStatus = 'Filtered $end / $totalSalesCount tickets in chunks...';
          });
        }
      }
    }

    // Default Draw Shifts for Selected Date if no sales exist yet
    if (rawGroups.isEmpty && _dateMode == DateFilterMode.single && _selectedParty == 'All') {
      final sDateStr = getDmy(_selectedDate);
      final shifts = ['Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'];
      for (final sh in shifts) {
        if (_selectedShift == 'All' || _matchesShift(sh, _selectedShift)) {
          rawGroups['$sDateStr — $sh'] = [];
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _chunkProgress = 0.60;
      _chunkStatus = 'Computing draw settlements & verified inam...';
    });
    await Future.delayed(Duration.zero);

    // 3. Process each Draw Card in chunks
    final List<DrawHisabCardData> cards = [];
    double overallSales = 0.0;
    double overallComm = 0.0;
    double overallInam = 0.0;

    final groupKeys = rawGroups.keys.toList();
    for (int k = 0; k < groupKeys.length; k++) {
      final groupKey = groupKeys[k];
      final sales = rawGroups[groupKey]!;

      final parts = groupKey.split(' — ');
      final datePart = parts[0];
      final shiftPart = parts.length > 1 ? parts[1] : 'Dear 1 PM';

      DateTime cardDate = _selectedDate;
      try {
        cardDate = DateFormat('dd/MM/yyyy').parse(datePart);
      } catch (_) {}

      final matchingResult = _findResultForDraw(shiftPart, cardDate);

      List<WinningClaimModel> winners = [];
      if (matchingResult != null && sales.isNotEmpty) {
        final cacheKey = '${matchingResult.drawId}_${sales.length}';
        winners = _winnerCache[cacheKey] ??= WinnerVerificationEngine.verifyWinners(
          result: matchingResult,
          soldTickets: sales,
        );
      }

      final tSales = sales.fold<double>(0.0, (acc, e) => acc + e.totalAmount);
      final tComm = sales.fold<double>(0.0, (acc, e) => acc + e.commissionAmount);
      final tInam = winners.fold<double>(0.0, (acc, e) => acc + e.prizeAmount);
      final nBalance = tSales - tComm - tInam;

      // Group sales by party inside this draw
      final Map<String, List<TicketSaleModel>> salesByParty = {};
      for (final s in sales) {
        final pName = s.buyerName.trim().isNotEmpty
            ? s.buyerName.trim()
            : (s.agentName.trim().isNotEmpty ? s.agentName.trim() : 'Counter');
        salesByParty.putIfAbsent(pName, () => []).add(s);
      }

      final Map<String, DrawPartySettlement> partyMap = {};
      for (final entry in salesByParty.entries) {
        final pName = entry.key;
        final pSales = entry.value;
        final pTotalSales = pSales.fold<double>(0.0, (acc, e) => acc + e.totalAmount);
        final pComm = pSales.fold<double>(0.0, (acc, e) => acc + e.commissionAmount);
        final pWinners = winners.where((w) {
          final b = w.buyerName.trim().toLowerCase();
          final s = w.sellerName.trim().toLowerCase();
          final target = pName.toLowerCase();
          return b == target || s == target;
        }).toList();
        final pInam = pWinners.fold<double>(0.0, (acc, e) => acc + e.prizeAmount);
        final pNet = pTotalSales - pComm - pInam;

        partyMap[pName] = DrawPartySettlement(
          partyName: pName,
          ticketCount: pSales.length,
          totalSales: pTotalSales,
          totalCommission: pComm,
          totalInam: pInam,
          netBalance: pNet,
          winners: pWinners,
        );
      }

      overallSales += tSales;
      overallComm += tComm;
      overallInam += tInam;

      cards.add(DrawHisabCardData(
        groupKey: groupKey,
        shiftPart: shiftPart,
        datePart: datePart,
        cardDate: cardDate,
        sales: sales,
        matchingResult: matchingResult,
        winners: winners,
        totalSales: tSales,
        totalCommission: tComm,
        totalInam: tInam,
        netBalance: nBalance,
        partyBreakdown: partyMap,
      ));

      if (k % 5 == 0 && k > 0) {
        await Future.delayed(Duration.zero);
      }
    }

    if (!mounted) return;
    setState(() {
      _filteredSales = matchingSales;
      _processedDrawCards = cards;
      _overallSalesAmt = overallSales;
      _overallCommissionAmt = overallComm;
      _overallInamAmt = overallInam;
      _overallNetAmt = overallSales - overallComm - overallInam;
      _displayedCardsLimit = math.min(25, cards.length);
      _isProcessingChunks = false;
      _chunkProgress = 1.0;
      _chunkStatus = 'Done';
    });
  }

  Future<void> _pickSingleDate() async {
    final first = _selectedDate.isBefore(DateTime(2020)) ? _selectedDate : DateTime(2020);
    final last = _selectedDate.isAfter(DateTime(2035)) ? _selectedDate : DateTime(2035);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateMode = DateFilterMode.single;
      });
      _triggerRecomputeDebounced();
    }
  }

  Future<void> _pickDateRange() async {
    final initialStart = _rangeStart ?? _selectedDate.subtract(const Duration(days: 7));
    final initialEnd = _rangeEnd ?? _selectedDate;
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _rangeStart = picked.start;
        _rangeEnd = picked.end;
        _dateMode = DateFilterMode.range;
      });
      _triggerRecomputeDebounced();
    }
  }

  void _previousDay() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
      _dateMode = DateFilterMode.single;
    });
    _triggerRecomputeDebounced();
  }

  void _nextDay() {
    setState(() {
      _selectedDate = _selectedDate.add(const Duration(days: 1));
      _dateMode = DateFilterMode.single;
    });
    _triggerRecomputeDebounced();
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
    final d1 = DateFormat('dd/MM/yyyy').format(date);
    final d2 = DateFormat('yyyy-MM-dd').format(date);
    final d3 = DateFormat('dd-MM-yyyy').format(date);

    for (final r in _savedResults) {
      final clean = r.drawDateStr.trim();
      final matchDate = clean == d1 || clean == d2 || clean == d3 || clean.contains(d1) || clean.contains(d2);
      if (matchDate && _matchesShift(r.drawName, drawShift)) {
        return r;
      }
    }
    return null;
  }

  void _shareHisabViaWhatsApp({
    required String title,
    required double sales,
    required double inam,
    required double net,
    required int tktCount,
    required List<WinningClaimModel> winners,
    String? partyName,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('📊 *DEAR LOTTERY HISAB SETTLEMENT REPORT*');
    buffer.writeln('----------------------------------------');
    buffer.writeln('🎯 *Draw/Period*: $title');
    if (partyName != null && partyName != 'All' && partyName.isNotEmpty) {
      buffer.writeln('👤 *Party/Seller*: $partyName');
    }
    buffer.writeln('🎟️ *Tickets Sold*: $tktCount');
    buffer.writeln('💰 *Total Sales*: ₹${sales.toStringAsFixed(0)}');
    buffer.writeln('🏆 *Inami Payout*: ₹${inam.toStringAsFixed(0)}');
    buffer.writeln('💵 *Net Balance*: ₹${net.toStringAsFixed(0)} (${net >= 0 ? 'PROFIT' : 'DEFICIT'})');
    buffer.writeln('----------------------------------------');
    if (winners.isNotEmpty) {
      buffer.writeln('🏆 *Top Winners (${winners.length})*:');
      for (final w in winners.take(10)) {
        buffer.writeln('• ${w.ticketSeries} ${w.ticketNumber} -> ₹${w.prizeAmount.toStringAsFixed(0)} (${w.prizeTier})');
      }
    }
    buffer.writeln('\nGenerated via *PhantomManagement*');

    final url = 'https://wa.me/?text=${Uri.encodeComponent(buffer.toString())}';
    Process.run('cmd', ['/c', 'start', '', url]);
  }

  Future<void> _exportCustomHisabPdf({
    required List<TicketSaleModel> filteredSales,
    bool isSummaryOnly = false,
    bool directPrint = false,
    String? overrideTitle,
    DateTime? overrideDate,
  }) async {
    if (filteredSales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ No sales or booking tickets found matching the selected filters.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    setState(() => _isExportingPdf = true);

    await ProcessManager.instance.runExclusive(
      idempotencyKey: 'export_hisab_pdf',
      title: overrideTitle ?? 'Generate Hisab PDF Report',
      category: 'PDF Reports',
      priority: ProcessPriority.high,
      onDuplicateRejected: (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.amber));
        }
      },
      action: (ctx) async {
        ctx.updateProgress(0.15, message: 'Formatting luxury layout & calculations...');
        try {
          String rangeTitle = 'HISAB SETTLEMENT REPORT';
          if (overrideTitle != null && overrideTitle.isNotEmpty) {
            rangeTitle = overrideTitle;
          } else if (_dateMode == DateFilterMode.range && _rangeStart != null && _rangeEnd != null) {
            rangeTitle = 'HISAB SETTLEMENT (${DateFormat('dd/MM/yyyy').format(_rangeStart!)} to ${DateFormat('dd/MM/yyyy').format(_rangeEnd!)})';
          } else if (_dateMode == DateFilterMode.single) {
            rangeTitle = 'HISAB SETTLEMENT (${DateFormat('dd/MM/yyyy').format(_selectedDate)})';
          } else {
            rangeTitle = 'ALL DATES HISAB SETTLEMENT';
          }

          if (_selectedShift != 'All') {
            rangeTitle += ' • ${_selectedShift.toUpperCase()}';
          }

          final targetDate = overrideDate ??
              (_dateMode == DateFilterMode.range ? (_rangeStart ?? _selectedDate) : _selectedDate);

          final custName = (_selectedParty != 'All' && _selectedParty.trim().isNotEmpty) ? _selectedParty : null;

          ctx.updateProgress(0.40, message: 'Compiling sales & inami matrix...');
          ctx.throwIfCancelled();

          final res = await BookingPdfService.instance.savePdfToDisk(
            date: targetDate,
            sales: filteredSales,
            rangeTitle: rangeTitle,
            customerName: custName,
            isSummaryOnly: isSummaryOnly,
          );

          ctx.updateProgress(0.85, message: 'Writing PDF to storage...');
          final filePath = res['filePath'] as String? ?? '';
          final pdfBytes = res['bytes'] as Uint8List?;
          final fileName = res['fileName'] as String? ?? 'Hisab_Report.pdf';

          if (directPrint && pdfBytes != null) {
            await BookingPdfService.instance.printPdfLayout(pdfBytes, fileName);
          } else if (filePath.isNotEmpty) {
            await BookingPdfService.instance.openPdfFile(filePath);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                      const SizedBox(width: 10),
                      Expanded(child: Text('✅ PDF Saved & Opened: $fileName')),
                    ],
                  ),
                  backgroundColor: const Color(0xFF1E1B4B),
                  action: SnackBarAction(
                    label: 'SHOW IN FOLDER',
                    textColor: Colors.amberAccent,
                    onPressed: () => BookingPdfService.instance.showInExplorer(filePath),
                  ),
                  duration: const Duration(seconds: 6),
                ),
              );
            }
          }
          ctx.updateProgress(1.0, message: 'PDF generated successfully');
        } catch (e) {
          debugPrint('Error generating Hisab PDF: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Error generating PDF: $e'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          rethrow;
        } finally {
          if (mounted) {
            setState(() => _isExportingPdf = false);
          }
        }
      },
    );
  }

  void _showGenerateCustomPdfDialog({
    required BuildContext context,
    required List<TicketSaleModel> initialSales,
    String? dialogTitle,
    DateTime? customDate,
  }) {
    bool isSummaryOnly = false;
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final totalAmt = initialSales.fold<double>(0.0, (acc, e) => acc + e.totalAmount);
          final dateLabel = customDate != null
              ? DateFormat('dd/MM/yyyy').format(customDate)
              : (_dateMode == DateFilterMode.single
                  ? DateFormat('dd/MM/yyyy').format(_selectedDate)
                  : (_dateMode == DateFilterMode.range && _rangeStart != null && _rangeEnd != null
                      ? '${DateFormat('dd/MM/yyyy').format(_rangeStart!)} - ${DateFormat('dd/MM/yyyy').format(_rangeEnd!)}'
                      : 'All Dates'));

          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 580,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 1.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 36,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dialog Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                        ),
                        child: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.primary, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dialogTitle ?? 'GENERATE HISAB PDF REPORT',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Customized Draw Settlement, Inami payouts & Party Ledger',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 18),

                  // Selected Filter Summary Info Box
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 15, color: Colors.cyanAccent),
                            const SizedBox(width: 8),
                            const Text('Date / Range: ', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            Text(dateLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.access_time_rounded, size: 15, color: Colors.amberAccent),
                            const SizedBox(width: 8),
                            const Text('Shift: ', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            Text(
                              _selectedShift == 'All' ? 'All Shifts (1 PM, 6 PM, 8 PM)' : _selectedShift,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.person_rounded, size: 15, color: Colors.purpleAccent),
                            const SizedBox(width: 8),
                            const Text('Party / Seller: ', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            Text(
                              _selectedParty == 'All' ? 'All Parties & Sellers' : _selectedParty,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.confirmation_number_outlined, size: 15, color: Colors.lightGreenAccent),
                            const SizedBox(width: 8),
                            const Text('Matched Records: ', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            Text(
                              '${initialSales.length} Tickets Booked (₹${totalAmt.toStringAsFixed(0)})',
                              style: const TextStyle(color: Colors.lightGreenAccent, fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Report Format Toggle
                  const Text('Select PDF Format Style:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => isSummaryOnly = false),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            decoration: BoxDecoration(
                              color: !isSummaryOnly ? AppColors.primary.withValues(alpha: 0.15) : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: !isSummaryOnly ? AppColors.primary : const Color(0xFF334155),
                                width: !isSummaryOnly ? 1.8 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.format_list_bulleted_rounded,
                                        size: 16, color: !isSummaryOnly ? AppColors.primary : AppColors.textSecondary),
                                    const SizedBox(width: 6),
                                    Text('Full Detailed',
                                        style: TextStyle(
                                            color: !isSummaryOnly ? Colors.white : AppColors.textSecondary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text('Itemized tickets, series & prizes', style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => isSummaryOnly = true),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            decoration: BoxDecoration(
                              color: isSummaryOnly ? AppColors.primary.withValues(alpha: 0.15) : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSummaryOnly ? AppColors.primary : const Color(0xFF334155),
                                width: isSummaryOnly ? 1.8 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.dashboard_customize_rounded,
                                        size: 16, color: isSummaryOnly ? AppColors.primary : AppColors.textSecondary),
                                    const SizedBox(width: 6),
                                    Text('Executive Summary',
                                        style: TextStyle(
                                            color: isSummaryOnly ? Colors.white : AppColors.textSecondary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text('KPI cards, draw totals & ledger', style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  if (isProcessing)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(color: AppColors.primary),
                            SizedBox(height: 8),
                            Text('Generating luxury PDF report...', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.file_open_rounded, size: 18),
                            label: const Text('SAVE & OPEN PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                            onPressed: () async {
                              setDialogState(() => isProcessing = true);
                              Navigator.of(ctx).pop();
                              await _exportCustomHisabPdf(
                                filteredSales: initialSales,
                                isSummaryOnly: isSummaryOnly,
                                directPrint: false,
                                overrideTitle: dialogTitle,
                                overrideDate: customDate,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFF6B21A8), width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.print_rounded, size: 18, color: Color(0xFFC084FC)),
                            label: const Text('PRINT PREVIEW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.white)),
                            onPressed: () async {
                              setDialogState(() => isProcessing = true);
                              Navigator.of(ctx).pop();
                              await _exportCustomHisabPdf(
                                filteredSales: initialSales,
                                isSummaryOnly: isSummaryOnly,
                                directPrint: true,
                                overrideTitle: dialogTitle,
                                overrideDate: customDate,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
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
    // Group sales by party / seller
    final Map<String, List<TicketSaleModel>> sellerMap = {};
    for (final s in sales) {
      final name = s.buyerName.trim().isNotEmpty
          ? s.buyerName.trim()
          : (s.agentName.trim().isNotEmpty ? s.agentName.trim() : 'Counter');
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
                            text: 'Party-Wise Hisab (${sellerMap.length} Parties)',
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
                            // 1. Seller / Party Wise Hisab List
                            ListView.separated(
                              itemCount: sellerMap.length,
                              separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                              itemBuilder: (context, idx) {
                                final sellerName = sellerMap.keys.elementAt(idx);
                                final sellerSales = sellerMap[sellerName]!;
                                final sTotalSales = sellerSales.fold<double>(0.0, (acc, e) => acc + e.totalAmount);
                                final sCommission = sellerSales.fold<double>(0.0, (acc, e) => acc + e.commissionAmount);

                                // Find inam for this party/seller
                                final sWinners = winners.where((w) {
                                  final b = w.buyerName.trim().toLowerCase();
                                  final s = w.sellerName.trim().toLowerCase();
                                  final target = sellerName.toLowerCase();
                                  return b == target || s == target;
                                }).toList();
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
                        _shareHisabViaWhatsApp(
                          title: drawTitle,
                          sales: totalSalesAmount,
                          inam: totalInamAmount,
                          net: netBalance,
                          tktCount: sales.length,
                          winners: winners,
                          partyName: _selectedParty != 'All' ? _selectedParty : null,
                        );
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
                      label: const Text('GENERATE DRAW PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _showGenerateCustomPdfDialog(
                          context: context,
                          initialSales: sales,
                          dialogTitle: 'Export Hisab PDF - $drawTitle',
                          customDate: drawDate,
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

  Widget _buildOverviewKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.5)),
                const SizedBox(height: 3),
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.white60)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen for sales updates from Riverpod with smooth debouncing
    ref.listen(ticketSalesViewModelProvider, (previous, next) {
      if (previous?.sales != next.sales) {
        _triggerRecomputeDebounced();
      }
    });

    final safeShiftOptions = ['All', 'Morning', 'Day', 'Evening'];
    final safeSelectedShift = safeShiftOptions.contains(_selectedShift) ? _selectedShift : 'All';

    // Build 100% deduplicated, case-insensitive safe list of parties from cached state (O(1) instant)
    final Set<String> seenPartiesInBuild = {'all'};
    final List<String> safeParties = ['All'];

    for (final p in _cachedParties) {
      final clean = p.trim();
      if (clean.isNotEmpty && seenPartiesInBuild.add(clean.toLowerCase())) {
        safeParties.add(clean);
      }
    }

    if (_selectedParty.trim().isNotEmpty && seenPartiesInBuild.add(_selectedParty.trim().toLowerCase())) {
      safeParties.add(_selectedParty.trim());
    }

    // Match selected party case-insensitively to exact item in safeParties
    final String safeSelectedParty = safeParties.firstWhere(
      (p) => p.toLowerCase() == _selectedParty.toLowerCase(),
      orElse: () => 'All',
    );

    final filteredSales = _filteredSales;
    final processedCards = _processedDrawCards;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header & Action Bar ──────────────────────────────────────────
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
                        'Fast Chunk Processing • Custom Date, Shift & Party settlement • PDF generator',
                        style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  // Dedicated PDF Generation Action Button
                  ElevatedButton.icon(
                    onPressed: _isExportingPdf
                        ? null
                        : () => _showGenerateCustomPdfDialog(
                              context: context,
                              initialSales: filteredSales,
                            ),
                    icon: _isExportingPdf
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 18),
                    label: Text(
                      _isExportingPdf ? 'EXPORTING...' : 'GENERATE HISAB PDF',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 4,
                      shadowColor: const Color(0xFF7C3AED).withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => context.go(AppConstants.routeResultEntry),
                    icon: const Icon(Icons.add_task_rounded, color: Colors.white, size: 18),
                    label: const Text('ENTER DRAW RESULT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Luxury PDF Export Loading Banner ───────────────────────────────
          if (_isExportingPdf)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF3B0764).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC084FC), width: 1.5),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF7C3AED).withValues(alpha: 0.35), blurRadius: 18),
                ],
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.8, color: Color(0xFFC084FC)),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('GENERATING ROYAL PURPLE HISAB PDF REPORT...',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
                        SizedBox(height: 2),
                        Text('Compiling party ledger, formatting luxury purple statement & saving to disk...',
                            style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // ── Realtime Chunk Processing Banner (Smooth & Responsive) ────────
          if (_isProcessingChunks)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1B4B).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC084FC)),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _chunkStatus.isNotEmpty ? _chunkStatus : 'Processing hisab in chunks (60 FPS smooth)...',
                            style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Text(
                        '${(_chunkProgress * 100).toInt()}%',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFC084FC), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _chunkProgress > 0 ? _chunkProgress : null,
                      minHeight: 4,
                      backgroundColor: const Color(0xFF2E1065),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFC084FC)),
                    ),
                  ),
                ],
              ),
            ),

          // ── Filter Controls (Date, Shift, Party) ──────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: AppDecorations.radiusLg,
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Date Filter Mode & Date Selector
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Date Filter:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textSecondary)),
                        const SizedBox(width: 10),
                        // Date Mode Chips
                        ChoiceChip(
                          label: const Text('Single Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          selected: _dateMode == DateFilterMode.single,
                          selectedColor: AppColors.primaryContainer,
                          onSelected: (val) {
                            if (val) {
                              setState(() => _dateMode = DateFilterMode.single);
                              _triggerRecomputeDebounced();
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('Custom Range', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          selected: _dateMode == DateFilterMode.range,
                          selectedColor: AppColors.primaryContainer,
                          onSelected: (val) {
                            if (val) {
                              setState(() => _dateMode = DateFilterMode.range);
                              if (_rangeStart == null) {
                                _pickDateRange();
                              } else {
                                _recomputeHisabChunks();
                              }
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('All Dates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          selected: _dateMode == DateFilterMode.all,
                          selectedColor: AppColors.primaryContainer,
                          onSelected: (val) {
                            if (val) {
                              setState(() => _dateMode = DateFilterMode.all);
                              _triggerRecomputeDebounced();
                            }
                          },
                        ),
                      ],
                    ),

                    // Interactive Date Picker Controls
                    if (_dateMode == DateFilterMode.single)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded, color: AppColors.primary),
                            onPressed: _previousDay,
                            tooltip: 'Previous Day',
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.primary),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.primary),
                            label: Text(
                              DateFormat('dd/MM/yyyy (EEEE)').format(_selectedDate),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                            ),
                            onPressed: _pickSingleDate,
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
                            onPressed: _nextDay,
                            tooltip: 'Next Day',
                          ),
                        ],
                      )
                    else if (_dateMode == DateFilterMode.range)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.cyanAccent),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.date_range_rounded, size: 16, color: Colors.cyanAccent),
                        label: Text(
                          _rangeStart != null && _rangeEnd != null
                              ? '${DateFormat('dd/MM/yyyy').format(_rangeStart!)}  →  ${DateFormat('dd/MM/yyyy').format(_rangeEnd!)}'
                              : 'Select Date Range',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                        ),
                        onPressed: _pickDateRange,
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.all_inclusive_rounded, size: 16, color: Colors.amberAccent),
                            SizedBox(width: 8),
                            Text('All Historical Records', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 14),

                // Row 2: Shift Filter, Party Filter & Refresh Action
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Shift Selector Dropdown
                        const Text('Shift:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textSecondary)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: AppDecorations.radiusDefault,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: safeSelectedShift,
                              items: safeShiftOptions.map((s) {
                                String label = s;
                                if (s == 'All') label = 'All Shifts (1 PM, 6 PM, 8 PM)';
                                if (s == 'Morning') label = '1:00 PM (Morning Draw)';
                                if (s == 'Day') label = '6:00 PM (Day Draw)';
                                if (s == 'Evening') label = '8:00 PM (Night Draw)';
                                return DropdownMenuItem(value: s, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)));
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _selectedShift = v);
                                  _triggerRecomputeDebounced();
                                }
                              },
                            ),
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Party / Seller Selector Dropdown
                        const Text('Party / Seller:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textSecondary)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: AppDecorations.radiusDefault,
                            border: Border.all(color: safeSelectedParty != 'All' ? AppColors.primary : AppColors.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: safeSelectedParty,
                              items: safeParties.map((p) {
                                final label = p == 'All' ? 'All Parties & Sellers (${safeParties.length - 1})' : p;
                                return DropdownMenuItem(
                                  value: p,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        p == 'All' ? Icons.people_alt_rounded : Icons.person_outline_rounded,
                                        size: 16,
                                        color: p == 'All' ? AppColors.textSecondary : AppColors.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _selectedParty = v);
                                  _triggerRecomputeDebounced();
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),

                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selectedParty != 'All' || _selectedShift != 'All' || _dateMode != DateFilterMode.single)
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedParty = 'All';
                                _selectedShift = 'All';
                                _dateMode = DateFilterMode.single;
                                _selectedDate = DateTime.now();
                                _rangeStart = null;
                                _rangeEnd = null;
                              });
                              _triggerRecomputeDebounced();
                            },
                            icon: const Icon(Icons.clear_all_rounded, size: 16, color: Colors.amberAccent),
                            label: const Text('Reset Filters', style: TextStyle(color: Colors.amberAccent, fontSize: 12.5)),
                          ),
                        const SizedBox(width: 8),
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
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Executive KPI Summary Strip (O(1) from Precomputed State) ─────
          Row(
            children: [
              Expanded(
                child: _buildOverviewKpiCard(
                  title: 'MATCHED TICKETS',
                  value: '${filteredSales.length}',
                  subtitle: safeSelectedParty != 'All' ? 'Seller: $safeSelectedParty' : '${safeParties.length - 1} Sellers',
                  icon: Icons.confirmation_number_outlined,
                  color: Colors.lightBlueAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildOverviewKpiCard(
                  title: 'TOTAL SALES',
                  value: '₹${_overallSalesAmt.toStringAsFixed(0)}',
                  subtitle: 'Comm: ₹${_overallCommissionAmt.toStringAsFixed(0)} • Gross',
                  icon: Icons.account_balance_wallet_outlined,
                  color: const Color(0xFF60A5FA),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildOverviewKpiCard(
                  title: 'INAMI PAYOUT',
                  value: '₹${_overallInamAmt.toStringAsFixed(0)}',
                  subtitle: 'Verified Winning Claims',
                  icon: Icons.emoji_events_outlined,
                  color: Colors.amberAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildOverviewKpiCard(
                  title: 'NET BALANCE',
                  value: '₹${_overallNetAmt.toStringAsFixed(0)}',
                  subtitle: _overallNetAmt >= 0 ? 'Profit Margin' : 'Deficit / Higher Inam',
                  icon: _overallNetAmt >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  color: _overallNetAmt >= 0 ? const Color(0xFF4ADE80) : Colors.redAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Draw Hisab Cards Grid (Instant 60/120 FPS Rendering) ───────────
          if (_isProcessingChunks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1B4B).withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.5,
                          color: Color(0xFFC084FC),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'CALCULATING HISAB & VERIFYING DRAW CLAIMS',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _chunkStatus.isNotEmpty ? _chunkStatus : 'Matching sold tickets against Sambad results...',
                        style: const TextStyle(color: Color(0xFFC084FC), fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: 240,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _chunkProgress > 0 ? _chunkProgress : null,
                            minHeight: 6,
                            backgroundColor: const Color(0xFF2E1065),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFC084FC)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${(_chunkProgress * 100).toInt()}% Completed',
                        style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (processedCards.isEmpty)
            Padding(
              padding: const EdgeInsets.all(60),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textSecondary),
                    const SizedBox(height: 12),
                    Text(
                      _selectedParty != 'All'
                          ? 'No hisab records found for seller "$_selectedParty" with current filters.'
                          : 'No hisab records found for selected filters.',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: math.min(_displayedCardsLimit, processedCards.length),
              itemBuilder: (context, index) {
                final card = processedCards[index];

                // Color accent based on draw timing
                Color shiftColor = Colors.amber;
                IconData shiftIcon = Icons.wb_sunny_outlined;
                if (card.shiftPart.contains('6')) {
                  shiftColor = Colors.lightBlueAccent;
                  shiftIcon = Icons.wb_twilight;
                } else if (card.shiftPart.contains('8')) {
                  shiftColor = Colors.purpleAccent;
                  shiftIcon = Icons.nights_stay_outlined;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: GlassCard(
                    child: InkWell(
                      onTap: () {
                        _showDrawHisabDetailsModal(
                          drawTitle: '${card.shiftPart} (${card.datePart})',
                          drawDate: card.cardDate,
                          sales: card.sales,
                          result: card.matchingResult,
                          winners: card.winners,
                          totalSalesAmount: card.totalSales,
                          totalInamAmount: card.totalInam,
                          netBalance: card.netBalance,
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
                                        card.shiftPart.toUpperCase(),
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
                                          color: card.matchingResult != null
                                              ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                              : Colors.amber.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: card.matchingResult != null ? const Color(0xFF10B981) : Colors.amber,
                                          ),
                                        ),
                                        child: Text(
                                          card.matchingResult != null ? 'SETTLED' : 'RESULT PENDING',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: card.matchingResult != null ? const Color(0xFF34D399) : Colors.amberAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Draw Date: ${card.datePart} • ${card.sales.length} Tickets Booked${_selectedParty != 'All' ? ' (Party: $_selectedParty)' : ''}',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                  ),
                                  if (card.matchingResult != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '1st Prize Number: ${card.matchingResult!.firstPrize}',
                                        style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ),
                                  if (card.partyBreakdown.length > 1) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: card.partyBreakdown.values.map((p) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E293B),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFF334155)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.person, size: 11, color: Colors.amberAccent),
                                              const SizedBox(width: 4),
                                              Text(p.partyName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                              const SizedBox(width: 4),
                                              Text('(${p.ticketCount} tkt • ₹${p.totalSales.toInt()})', style: const TextStyle(fontSize: 10, color: Colors.white70)),
                                              if (p.totalInam > 0) ...[
                                                const SizedBox(width: 4),
                                                Text('Inam: ₹${p.totalInam.toInt()}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                                              ],
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // Metrics Summary (Instantly displayed from precomputed card)
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('TOTAL SALES', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text('₹${card.totalSales.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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
                                    '₹${card.totalInam.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: card.totalInam > 0 ? Colors.amberAccent : Colors.white70,
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
                                    '₹${card.netBalance.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: card.netBalance >= 0 ? const Color(0xFF4ADE80) : Colors.redAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Quick PDF Export Button on Card
                            IconButton(
                              icon: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFC084FC), size: 20),
                              tooltip: 'Export PDF for this Draw',
                              onPressed: () {
                                _showGenerateCustomPdfDialog(
                                  context: context,
                                  initialSales: card.sales,
                                  dialogTitle: 'Export Draw PDF - ${card.shiftPart} (${card.datePart})',
                                  customDate: card.cardDate,
                                );
                              },
                            ),
                            const SizedBox(width: 4),

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

            // Pagination Load More Button if more draws exist
            if (processedCards.length > _displayedCardsLimit)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF7C3AED), width: 1.5),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.keyboard_double_arrow_down_rounded, size: 18, color: Color(0xFFC084FC)),
                    label: Text(
                      'LOAD MORE DRAWS (${processedCards.length - _displayedCardsLimit} Remaining)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: () {
                      setState(() {
                        _displayedCardsLimit = math.min(_displayedCardsLimit + 25, processedCards.length);
                      });
                    },
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
