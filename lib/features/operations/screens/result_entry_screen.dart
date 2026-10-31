import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/database/database_service.dart';
import '../models/lottery_sambad_result_model.dart';
import '../services/pdf_result_parser_service.dart';

import '../models/winning_claim_model.dart';
import '../utils/winner_verification_engine.dart';
import '../../../core/process/services/process_manager.dart';
import '../../../core/process/models/process_model.dart';
import '../../bookings/viewmodels/ticket_sales_viewmodel.dart';

class ResultEntryScreen extends ConsumerStatefulWidget {
  const ResultEntryScreen({super.key});

  @override
  ConsumerState<ResultEntryScreen> createState() => _ResultEntryScreenState();
}

class _ResultEntryScreenState extends ConsumerState<ResultEntryScreen>
    with SingleTickerProviderStateMixin {
  bool _isEditingMode = false;
  String _editingDrawId = '';
  bool _showBulkPasteBox = false;
  bool _showWinnerBreakdown = false;

  // Tabs
  late TabController _tabController;

  // Draw Selection State
  String _selectedShift = '1 PM';
  DateTime _selectedDate = DateTime.now();

  // Prize Controllers
  final TextEditingController _firstPrizeCtrl = TextEditingController();
  final TextEditingController _consolationPrizeCtrl = TextEditingController();
  final FocusNode _firstPrizeFocusNode = FocusNode();

  final List<TextEditingController> _secondPrizeCtrls =
      List.generate(10, (_) => TextEditingController());
  final List<TextEditingController> _thirdPrizeCtrls =
      List.generate(10, (_) => TextEditingController());
  final List<TextEditingController> _fourthPrizeCtrls =
      List.generate(10, (_) => TextEditingController());
  final List<TextEditingController> _fifthPrizeCtrls =
      List.generate(100, (_) => TextEditingController());

  final TextEditingController _bulkPasteCtrl = TextEditingController();
  final TextEditingController _fifthBulkCtrl = TextEditingController();

  // History & Winners
  int _verifiedWinnersCount = 0;
  double _totalPayoutAmount = 0.0;
  List<Map<String, dynamic>> _verifiedWinnersList = [];
  List<Map<String, dynamic>> _historyRecords = [];
  String _historySearch = '';
  String _historyShiftFilter = 'All';
  bool _isLoadingHistory = false;
  bool _isReverifyingHistory = false;
  Timer? _prizeChangeDebounce;
  List<WinningClaimModel> _latestClaims = [];
  final Map<String, (int count, double payout)> _historyWinnerCache = {};
  final Map<String, List<Map<String, dynamic>>> _historyPartySummaryCache = {};
  final Set<String> _expandedDrawIds = {};
  final Set<String> _loadingPartySummaryDrawIds = {};

  // Prize amounts (Sambad standard)
  static const Map<String, double> _prizeAmounts = {
    '1st': 10000000,
    'Consolation': 1000,
    '2nd': 9000,
    '3rd': 500,
    '4th': 250,
    '5th': 120,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        if (_historyRecords.isEmpty) {
          _fetchHistoryRecords();
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ticketSalesViewModelProvider.notifier).loadSales();
      _fetchHistoryRecords();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _prizeChangeDebounce?.cancel();
    _firstPrizeCtrl.dispose();
    _consolationPrizeCtrl.dispose();
    _firstPrizeFocusNode.dispose();
    _bulkPasteCtrl.dispose();
    _fifthBulkCtrl.dispose();
    for (var c in _secondPrizeCtrls) { c.dispose(); }
    for (var c in _thirdPrizeCtrls)  { c.dispose(); }
    for (var c in _fourthPrizeCtrls) { c.dispose(); }
    for (var c in _fifthPrizeCtrls)  { c.dispose(); }
    super.dispose();
  }

  Future<void> _fetchHistoryRecords() async {
    setState(() => _isLoadingHistory = true);
    try {
      final list = await DatabaseService.instance.getLotteryResults();
      if (mounted) {
        for (final r in list) {
          final id = r['id']?.toString() ?? '';
          if (id.isNotEmpty) {
            final wCount = int.tryParse(r['verifiedWinnersCount']?.toString() ?? '') ?? 0;
            final payout = double.tryParse(r['totalPayoutAmount']?.toString() ?? '') ?? 0.0;
            _historyWinnerCache[id] = (wCount, payout);
          }
        }
        setState(() {
          _historyRecords = list;
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching history records: $e');
      if (mounted) {
        setState(() => _isLoadingHistory = false);
      }
    }
  }

  Future<void> _reverifyAllHistoryRecords() async {
    if (_isReverifyingHistory) return;
    setState(() => _isReverifyingHistory = true);

    await ProcessManager.instance.runExclusive(
      idempotencyKey: 'reverify_history_draws',
      title: 'Audit & Re-verify Result Draws (${_historyRecords.length} draws)',
      category: 'Lottery Audit',
      priority: ProcessPriority.high,
      onDuplicateRejected: (msg) => _showSnackbar(msg, AppColors.warning),
      action: (ctx) async {
        try {

          final total = _historyRecords.length;

          for (int i = 0; i < total; i++) {
            ctx.throwIfCancelled();
            await ctx.checkPause();

            final record = _historyRecords[i];
            final dName = record['drawName']?.toString() ?? record['drawTimeStr']?.toString() ?? 'Draw ${i + 1}';
            ctx.updateProgress(
              (i + 1) / (total > 0 ? total : 1),
              message: 'Auditing $dName (${i + 1}/$total)...',
              completedSteps: i + 1,
              totalSteps: total,
            );

            final sec = (record['secondPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();
            final th = (record['thirdPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();
            final fo = (record['fourthPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();
            final fi = (record['fifthPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();

            final model = LotterySambadResultModel(
              drawId: record['id']?.toString() ?? '',
              drawName: dName,
              drawDateStr: record['drawDateStr']?.toString() ?? '',
              drawTimeStr: record['drawTimeStr']?.toString() ?? '',
              firstPrize: record['firstPrize']?.toString() ?? '',
              consolationPrize: record['consolationPrize']?.toString() ?? '',
              secondPrizeNumbers: sec,
              thirdPrizeNumbers: th,
              fourthPrizeNumbers: fo,
              fifthPrizeNumbers: fi,
              publishedAt: DateTime.tryParse(record['publishedAt']?.toString() ?? '') ?? DateTime.now(),
            );

            final liveClaims = await WinnerVerificationEngine.verifyDrawFromDatabase(
              result: model,

            );
            final liveCount = liveClaims.length;
            final livePayout = liveClaims.fold<double>(0.0, (acc, c) => acc + c.prizeAmount);
            if (liveClaims.isNotEmpty) {
              await DatabaseService.instance.saveWinningClaimsBatch(liveClaims);
            }
            _historyWinnerCache[model.drawId] = (liveCount, livePayout);
            if (liveClaims.isNotEmpty) {
              final partySummary = await DatabaseService.instance.getWinningClaimsGroupedByParty(model.drawId);
              _historyPartySummaryCache[model.drawId] = partySummary;
            }

            if (i % 2 == 0) {
              await Future.delayed(Duration.zero);
            }
          }

          if (mounted) {
            setState(() => _isReverifyingHistory = false);
            _showSnackbar('🔄 Re-verified all results with latest bookings!', AppColors.success);
          }
        } catch (e) {
          debugPrint('Error re-verifying history: $e');
          if (mounted) {
            setState(() => _isReverifyingHistory = false);
          }
          rethrow;
        }
      },
    );
  }

  void _clearForm() {
    setState(() {
      _isEditingMode = false;
      _editingDrawId = '';
      _firstPrizeCtrl.clear();
      _consolationPrizeCtrl.clear();
      _bulkPasteCtrl.clear();
      _fifthBulkCtrl.clear();
      for (var c in _secondPrizeCtrls) { c.clear(); }
      for (var c in _thirdPrizeCtrls)  { c.clear(); }
      for (var c in _fourthPrizeCtrls) { c.clear(); }
      for (var c in _fifthPrizeCtrls)  { c.clear(); }
      _verifiedWinnersCount = 0;
      _totalPayoutAmount = 0.0;
      _verifiedWinnersList = [];
      _showWinnerBreakdown = false;
    });
    _firstPrizeFocusNode.requestFocus();
  }

  void _editRecord(Map<String, dynamic> record) {
    setState(() {
      _isEditingMode = true;
      _editingDrawId = record['id']?.toString() ?? '';
      final rawShift = record['drawTimeStr']?.toString() ??
          record['drawName']?.toString() ??
          '1 PM';
      if (rawShift.contains('6') ||
          rawShift.toLowerCase().contains('day')) {
        _selectedShift = '6 PM';
      } else if (rawShift.contains('8') ||
          rawShift.toLowerCase().contains('evening') ||
          rawShift.toLowerCase().contains('night')) {
        _selectedShift = '8 PM';
      } else {
        _selectedShift = '1 PM';
      }

      try {
        _selectedDate = DateFormat('dd/MM/yyyy').parse(
            record['drawDateStr']?.toString() ??
                DateFormat('dd/MM/yyyy').format(DateTime.now()));
      } catch (_) {
        _selectedDate = DateTime.now();
      }

      _firstPrizeCtrl.text = record['firstPrize']?.toString() ?? '';
      _consolationPrizeCtrl.text = record['consolationPrize']?.toString() ?? '';

      List<String> getNumbers(String key) {
        final val = record[key];
        if (val == null || val.toString().isEmpty) return [];
        return val.toString().split(',');
      }

      final secondP = getNumbers('secondPrizeNumbers');
      final thirdP = getNumbers('thirdPrizeNumbers');
      final fourthP = getNumbers('fourthPrizeNumbers');
      final fifthP = getNumbers('fifthPrizeNumbers');

      for (int i = 0; i < 10; i++) {
        _secondPrizeCtrls[i].text = i < secondP.length ? secondP[i] : '';
        _thirdPrizeCtrls[i].text = i < thirdP.length ? thirdP[i] : '';
        _fourthPrizeCtrls[i].text = i < fourthP.length ? fourthP[i] : '';
      }
      for (int i = 0; i < 100; i++) {
        _fifthPrizeCtrls[i].text = i < fifthP.length ? fifthP[i] : '';
      }

      _verifiedWinnersCount = record['verifiedWinnersCount'] ?? 0;
      _totalPayoutAmount = (record['totalPayoutAmount'] ?? 0).toDouble();
    });
  }

  Future<void> _deleteRecord(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg),
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
          const SizedBox(width: 8),
          const Text('Delete Result?', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: const Text(
            'Are you sure you want to delete this result? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.instance.deleteLotteryResult(id);
      await _fetchHistoryRecords();
      _showSnackbar('Result deleted successfully', AppColors.success);
    }
  }

  void _populateFromModel(LotterySambadResultModel model) {
    setState(() {
      _firstPrizeCtrl.text = model.firstPrize;
      _consolationPrizeCtrl.text = model.consolationPrize;

      for (int i = 0; i < 10; i++) {
        _secondPrizeCtrls[i].text =
            i < model.secondPrizeNumbers.length ? model.secondPrizeNumbers[i] : '';
        _thirdPrizeCtrls[i].text =
            i < model.thirdPrizeNumbers.length ? model.thirdPrizeNumbers[i] : '';
        _fourthPrizeCtrls[i].text =
            i < model.fourthPrizeNumbers.length ? model.fourthPrizeNumbers[i] : '';
      }

      final sortedFifth = List<String>.from(model.fifthPrizeNumbers)..sort();
      for (int i = 0; i < 100; i++) {
        _fifthPrizeCtrls[i].text = i < sortedFifth.length ? sortedFifth[i] : '';
      }
    });
    _recalculateWinners(model);
  }

  LotterySambadResultModel _buildCurrentModel({String? overrideId}) {
    final secondP = _secondPrizeCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final thirdP = _thirdPrizeCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final fourthP = _fourthPrizeCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final fifthP = _fifthPrizeCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList()
      ..sort();

    final firstP = _firstPrizeCtrl.text.trim();
    final consoP = _consolationPrizeCtrl.text.trim().isNotEmpty
        ? _consolationPrizeCtrl.text.trim()
        : (firstP.contains(' ')
            ? firstP.split(' ').last
            : (firstP.length >= 5 ? firstP.substring(firstP.length - 5) : firstP));

    return LotterySambadResultModel(
      drawId: overrideId ??
          (_isEditingMode && _editingDrawId.isNotEmpty
              ? _editingDrawId
              : 'res_${DateTime.now().millisecondsSinceEpoch}'),
      drawName: _selectedShift,
      drawDateStr: DateFormat('dd/MM/yyyy').format(_selectedDate),
      drawTimeStr: _selectedShift,
      firstPrize: firstP,
      consolationPrize: consoP,
      secondPrizeNumbers: secondP,
      thirdPrizeNumbers: thirdP,
      fourthPrizeNumbers: fourthP,
      fifthPrizeNumbers: fifthP,
      publishedAt: DateTime.now(),
    );
  }

  Future<void> _recalculateWinners(LotterySambadResultModel resultModel) async {
    final claims = await WinnerVerificationEngine.verifyDrawFromDatabase(result: resultModel);
    _latestClaims = claims;
    if (!mounted) return;


    setState(() {
      _verifiedWinnersCount = claims.length;
      _totalPayoutAmount = claims.fold(0.0, (sum, c) => sum + c.prizeAmount);
      _verifiedWinnersList = claims
          .map((c) => {
                'ticketNumber': c.ticketNumber,
                'buyerName': c.buyerName,
                'prizeType': c.prizeTier,
                'prizeAmount': c.prizeAmount,
              })
          .toList();
    });
  }

  Future<void> _fetchPartyDetailsForDraw(Map<String, dynamic> record) async {
    final drawId = record['id']?.toString() ?? '';
    if (drawId.isEmpty) return;

    if (_expandedDrawIds.contains(drawId)) {
      setState(() => _expandedDrawIds.remove(drawId));
      return;
    }

    if (_historyPartySummaryCache.containsKey(drawId)) {
      setState(() => _expandedDrawIds.add(drawId));
      return;
    }

    setState(() => _loadingPartySummaryDrawIds.add(drawId));
    try {
      var partySummary = await DatabaseService.instance.getWinningClaimsGroupedByParty(drawId);
      if (partySummary.isEmpty) {
        final dName = record['drawName']?.toString() ?? record['drawTimeStr']?.toString() ?? '';
        final sec = (record['secondPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();
        final th = (record['thirdPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();
        final fo = (record['fourthPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();
        final fi = (record['fifthPrizeNumbers']?.toString() ?? '').split(',').where((e) => e.isNotEmpty).toList();

        final model = LotterySambadResultModel(
          drawId: drawId,
          drawName: dName,
          drawDateStr: record['drawDateStr']?.toString() ?? '',
          drawTimeStr: record['drawTimeStr']?.toString() ?? '',
          firstPrize: record['firstPrize']?.toString() ?? '',
          consolationPrize: record['consolationPrize']?.toString() ?? '',
          secondPrizeNumbers: sec,
          thirdPrizeNumbers: th,
          fourthPrizeNumbers: fo,
          fifthPrizeNumbers: fi,
          publishedAt: DateTime.tryParse(record['publishedAt']?.toString() ?? '') ?? DateTime.now(),
        );

        final liveClaims = await WinnerVerificationEngine.verifyDrawFromDatabase(result: model);
        if (liveClaims.isNotEmpty) {
          await DatabaseService.instance.saveWinningClaimsBatch(liveClaims);
          partySummary = await DatabaseService.instance.getWinningClaimsGroupedByParty(drawId);
        }
      }

      if (mounted) {
        setState(() {
          _historyPartySummaryCache[drawId] = partySummary;
          _expandedDrawIds.add(drawId);
          _loadingPartySummaryDrawIds.remove(drawId);
        });
      }
    } catch (e) {
      debugPrint('Error fetching party details: $e');
      if (mounted) {
        setState(() => _loadingPartySummaryDrawIds.remove(drawId));
      }
    }
  }

  void _copyPartyHisab(String drawName, String drawDate, Map<String, dynamic> party) {
    final buyer = party['buyerName'] ?? 'Party';
    final wins = party['totalWins'] ?? 0;
    final payout = party['totalPayout'] ?? 0.0;
    final details = party['details'] ?? '';

    final text = '''
🏆 LOTTERY WINNING INAM SUMMARY 🏆
━━━━━━━━━━━━━━━━━━━━
📅 Date: $drawDate
⏰ Draw: $drawName
👤 Party: $buyer
🎟️ Total Winning Tickets: $wins
💰 Total Winning Payout: ₹${NumberFormat('#,##,##0', 'en_IN').format(payout)}
━━━━━━━━━━━━━━━━━━━━
Winning Breakdown:
$details
━━━━━━━━━━━━━━━━━━━━
Generated by OpsCore Pro
'''.trim();

    Clipboard.setData(ClipboardData(text: text));
    _showSnackbar('📋 Party Hisab copied for $buyer!', AppColors.success);
  }

  // ── 5th Prize Bulk Paste Parser ──────────────────────────────────────────────
  void _parseFifthBulkPaste() {
    final text = _fifthBulkCtrl.text.trim();
    if (text.isEmpty) return;
    final numbers = RegExp(r'\b\d{4}\b')
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toSet()
        .toList()
      ..sort();
    setState(() {
      for (int i = 0; i < 100; i++) {
        _fifthPrizeCtrls[i].text = i < numbers.length ? numbers[i] : '';
      }
    });
    _fifthBulkCtrl.clear();
    _showSnackbar(
        '✅ ${numbers.length} 5th prize numbers filled!', AppColors.success);
  }

  // ── Full Bulk Text Parser ────────────────────────────────────────────────────
  void _parseBulkTextPaste() {
    final text = _bulkPasteCtrl.text.trim();
    if (text.isEmpty) {
      _showSnackbar('Please paste result text first!', AppColors.warning);
      return;
    }

    final tokens =
        RegExp(r'[A-Za-z0-9]+').allMatches(text).map((m) => m.group(0)!).toList();
    if (tokens.isEmpty) return;

    setState(() {
      int idx = 0;
      // 1st Prize: series + 5-digit number
      if (tokens.length >= 2 && tokens[0].length <= 4 && tokens[1].length == 5) {
        _firstPrizeCtrl.text = '${tokens[0]} ${tokens[1]}';
        // Auto-derive consolation
        _consolationPrizeCtrl.text = tokens[1];
        idx = 2;
      } else if (tokens.isNotEmpty && tokens[0].length >= 7) {
        _firstPrizeCtrl.text = tokens[0];
        _consolationPrizeCtrl.text =
            tokens[0].length >= 5 ? tokens[0].substring(tokens[0].length - 5) : tokens[0];
        idx = 1;
      }

      List<String> fiveDigit = [];
      List<String> fourDigit = [];

      for (int i = idx; i < tokens.length; i++) {
        final t = tokens[i].replaceAll(RegExp(r'[^0-9]'), '');
        if (t.length == 5) fiveDigit.add(t);
        if (t.length == 4) fourDigit.add(t);
      }

      // Fill 2nd (5-digit x10)
      for (int i = 0; i < 10; i++) {
        _secondPrizeCtrls[i].text = i < fiveDigit.length ? fiveDigit[i] : '';
      }
      // Fill 3rd (4-digit x10)
      int o4 = 0;
      for (int i = 0; i < 10; i++) {
        if (o4 < fourDigit.length) _thirdPrizeCtrls[i].text = fourDigit[o4++];
      }
      // Fill 4th (4-digit x10)
      for (int i = 0; i < 10; i++) {
        if (o4 < fourDigit.length) _fourthPrizeCtrls[i].text = fourDigit[o4++];
      }
      // Fill 5th (remaining 4-digit)
      final fifthList = <String>[];
      while (o4 < fourDigit.length && fifthList.length < 100) {
        fifthList.add(fourDigit[o4++]);
      }
      fifthList.sort();
      for (int i = 0; i < 100; i++) {
        _fifthPrizeCtrls[i].text = i < fifthList.length ? fifthList[i] : '';
      }

      _showBulkPasteBox = false;
    });
    _showSnackbar('⚡ Auto-Parsed & Filled All Prize Boxes!', AppColors.success);
    _recalculateWinners(_buildCurrentModel(overrideId: 'temp'));
  }

  // ── PDF / File Upload ───────────────────────────────────────────────────────
  Future<void> _pickAndParsePdfResult() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'csv', 'png', 'jpg'],
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      // Case 1: Single File Picked
      if (result.files.length == 1) {
        final file = result.files.first;
        if (file.path == null && file.bytes == null) {
          _showSnackbar('File could not be accessed', AppColors.error);
          return;
        }

        _showSnackbar('📄 Scanning "${file.name}"...', AppColors.primary);

        final parsed = await PdfResultParserService.instance.parseSingleFile(
          filePath: file.path ?? file.name,
          fileBytes: file.bytes,
          defaultShift: _selectedShift,
          defaultDate: _selectedDate,
        );

        if (parsed != null &&
            (parsed.firstPrize.isNotEmpty ||
                parsed.secondPrizeNumbers.isNotEmpty ||
                parsed.fifthPrizeNumbers.isNotEmpty) &&
            mounted) {
          _populateFromModel(parsed);
          await _recalculateWinners(parsed);
          await _saveResult(silent: true);
          await _fetchHistoryRecords();
          _showSnackbar(
              '⚡ PDF Scanned & Auto-Saved (${parsed.fifthPrizeNumbers.length} numbers) for ${parsed.drawName}!',
              AppColors.success);
        } else {
          _showSnackbar(
              '⚠️ PDF text could not be extracted from "${file.name}". Please ensure the PDF is valid or use Bulk Paste.',
              AppColors.warning);
        }
        return;
      }

      // Case 2: MULTIPLE Files Picked (Batch Scan & Auto-Verify)
      final validPaths = result.files
          .where((f) => f.path != null && f.path!.isNotEmpty)
          .map((f) => f.path!)
          .toList();

      if (validPaths.isEmpty) {
        _showSnackbar('No accessible file paths found in selected files.', AppColors.error);
        return;
      }

      int currentProgress = 0;
      final totalFiles = validPaths.length;
      String currentFileName = result.files.first.name;
      void Function(void Function())? updateDialogState;
      BuildContext? progressDialogCtx;

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dlgCtx) {
          progressDialogCtx = dlgCtx;
          return StatefulBuilder(
            builder: (context, setDlgState) {
              updateDialogState = setDlgState;
              final progressPercent = totalFiles > 0 ? (currentProgress / totalFiles) : 0.0;
              return AlertDialog(
                backgroundColor: AppColors.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                  borderRadius: AppDecorations.radiusLg,
                  side: const BorderSide(color: AppColors.border),
                ),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withAlpha(40),
                        borderRadius: AppDecorations.radiusDefault,
                      ),
                      child: const Icon(Icons.picture_as_pdf, color: Colors.amber),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Scanning Multiple PDFs...',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: progressPercent,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                        minHeight: 6,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Processing $currentProgress of $totalFiles files',
                            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                          Text(
                            '${(progressPercent * 100).toInt()}%',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        currentFileName,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      final report = await PdfResultParserService.instance.parseAndSaveMultipleFiles(
        files: result.files,
        defaultShift: _selectedShift,
        defaultDate: _selectedDate,
        onProgress: (current, total, filename) {
          currentProgress = current;
          currentFileName = filename;
          if (updateDialogState != null) {
            updateDialogState!(() {});
          }
        },
      );

      // Close progress dialog immediately so no popup remains on screen
      if (progressDialogCtx != null && progressDialogCtx!.mounted) {
        Navigator.of(progressDialogCtx!).pop();
      } else if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // Refresh records & display last scanned result in editor
      if (report.parsedResults.isNotEmpty && mounted) {
        final last = report.parsedResults.last;
        _populateFromModel(last);
        await _recalculateWinners(last);
        await _fetchHistoryRecords();
      }

      // Show clean snackbar notification without any blocking popup
      if (mounted) {
        if (report.failureCount == 0) {
          _showSnackbar(
            '✅ Batch Scan Complete: ${report.successCount} PDFs scanned & saved! Found ${report.totalWinnersFound} winners (₹${NumberFormat('#,##,##0', 'en_IN').format(report.totalPayoutAmount)})',
            AppColors.success,
          );
        } else {
          _showSnackbar(
            '⚠️ Saved ${report.successCount} of ${report.totalFiles} PDFs (${report.failureCount} failed). Found ${report.totalWinnersFound} winners.',
            AppColors.warning,
          );
        }
      }
    } catch (e) {
      _showSnackbar('File Error: $e', AppColors.error);
    }
  }

  // ── Export Winners to CSV ───────────────────────────────────────────────────
  Future<void> _exportWinnersCSV() async {
    if (_verifiedWinnersList.isEmpty) {
      _showSnackbar('No winners to export!', AppColors.warning);
      return;
    }
    final csv = StringBuffer();
    csv.writeln('Ticket Number,Buyer Name,Prize Type,Prize Amount');
    for (final w in _verifiedWinnersList) {
      csv.writeln(
          '${w['ticketNumber']},${w['buyerName']},${w['prizeType']},${w['prizeAmount']}');
    }
    final path =
        '${Directory.systemTemp.path}/winners_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.csv';
    await File(path).writeAsString(csv.toString());
    _showSnackbar('✅ Winners exported to: $path', AppColors.success);
  }

  // ── Copy result to clipboard ────────────────────────────────────────────────
  void _copyResultToClipboard() {
    final model = _buildCurrentModel(overrideId: 'temp');
    final buf = StringBuffer();
    buf.writeln('=== LOTTERY RESULT ===');
    buf.writeln(
        'Draw: ${model.drawName} | Date: ${model.drawDateStr} | Shift: ${model.drawTimeStr}');
    buf.writeln('1st Prize: ${model.firstPrize}');
    buf.writeln('Consolation: ${model.consolationPrize}');
    buf.writeln('2nd Prize (x${model.secondPrizeNumbers.length}): ${model.secondPrizeNumbers.join(', ')}');
    buf.writeln('3rd Prize (x${model.thirdPrizeNumbers.length}): ${model.thirdPrizeNumbers.join(', ')}');
    buf.writeln('4th Prize (x${model.fourthPrizeNumbers.length}): ${model.fourthPrizeNumbers.join(', ')}');
    buf.writeln('5th Prize (x${model.fifthPrizeNumbers.length}): ${model.fifthPrizeNumbers.join(', ')}');
    Clipboard.setData(ClipboardData(text: buf.toString()));
    _showSnackbar('Result copied to clipboard!', AppColors.success);
  }

  // ── Save Result ─────────────────────────────────────────────────────────────
  Future<void> _saveResult({bool silent = false}) async {
    final firstP = _firstPrizeCtrl.text.trim();
    if (firstP.isEmpty) {
      _showSnackbar('Please enter 1st Prize Number', AppColors.warning);
      return;
    }

    final resultModel = _buildCurrentModel();
    await _recalculateWinners(resultModel);
    if (_latestClaims.isNotEmpty) {
      await DatabaseService.instance.saveWinningClaimsBatch(_latestClaims);
    }
    await DatabaseService.instance.insertLotteryResult(resultModel,
        verifiedWinnersCount: _verifiedWinnersCount,
        totalPayoutAmount: _totalPayoutAmount);
    await _fetchHistoryRecords();
    if (!silent) {
      _showSnackbar(
          _verifiedWinnersCount > 0
              ? '✅ Result Saved! 🎉 $_verifiedWinnersCount winning ticket(s) found!'
              : '✅ Result Saved Successfully!',
          _verifiedWinnersCount > 0 ? Colors.green : AppColors.success);
    }
  }

  void _showSnackbar(String msg, Color bg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: bg,
      duration: const Duration(seconds: 3),
    ));
  }

  // ── Live recalculate on any change ─────────────────────────────────────────
  void _onPrizeChanged() {
    final firstP = _firstPrizeCtrl.text.trim();
    if (firstP.isEmpty) return;
    _prizeChangeDebounce?.cancel();
    _prizeChangeDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        _recalculateWinners(_buildCurrentModel(overrideId: 'temp'));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Header ────────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'OFFICIAL RESULT ENTRY',
                              style: AppTypography.headlineLg.copyWith(
                                  fontWeight: FontWeight.bold),
                            ),
                            if (_isEditingMode) ...[
                              const SizedBox(width: 12),
                              _statusChip('EDITING MODE', Colors.orange,
                                  trailing: InkWell(
                                      onTap: _clearForm,
                                      child: const Icon(Icons.close,
                                          size: 14, color: Colors.orange))),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Enter published lottery results · verify winners · calculate inam payouts',
                          style: AppTypography.bodySm
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  // Action Buttons
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _actionBtn(
                        icon: Icons.content_paste_go,
                        label: 'Bulk Paste',
                        color: Colors.cyanAccent,
                        onPressed: () => setState(
                            () => _showBulkPasteBox = !_showBulkPasteBox),
                      ),
                      _actionBtn(
                        icon: Icons.upload_file,
                        label: 'Upload PDF',
                        color: Colors.amber,
                        onPressed: _pickAndParsePdfResult,
                      ),
                      _actionBtn(
                        icon: Icons.copy,
                        label: 'Copy',
                        color: Colors.white60,
                        onPressed: _copyResultToClipboard,
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _saveResult(),
                        icon: const Icon(Icons.check_circle, color: Colors.white),
                        label: const Text('SAVE RESULT',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Tabs
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(
                      icon: const Icon(Icons.edit_note, size: 18),
                      text: 'Entry Form'),
                  Tab(
                      icon: const Icon(Icons.history, size: 18),
                      text: 'History (${_historyRecords.length})'),
                ],
                indicatorColor: AppColors.primary,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),

        // ── Tab Content ───────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildEntryForm(),
              _buildHistoryView(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Entry Form Tab ──────────────────────────────────────────────────────────
  Widget _buildEntryForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bulk Paste Panel
          if (_showBulkPasteBox) ...[
            _buildBulkPastePanel(),
            const SizedBox(height: 20),
          ],

          // Draw Selector + Winner Status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date + Shift Selector
              Expanded(flex: 3, child: _buildDrawSelector()),
              const SizedBox(width: 16),
              // Winner Status Box
              Expanded(flex: 2, child: _buildWinnerStatusBox()),
            ],
          ),
          const SizedBox(height: 20),

          // Prize Entry Sections
          _buildFirstPrizeSection(),
          const SizedBox(height: 16),
          _buildPrizeGrid(
              '2nd PRIZE', '₹9,000 each · 10 numbers (5-digit)',
              _secondPrizeCtrls, Colors.lightBlueAccent, 5, Icons.star),
          const SizedBox(height: 16),
          _buildPrizeGrid(
              '3rd PRIZE', '₹500 each · 10 numbers (4-digit)',
              _thirdPrizeCtrls, Colors.tealAccent, 4, Icons.star_half),
          const SizedBox(height: 16),
          _buildPrizeGrid(
              '4th PRIZE', '₹250 each · 10 numbers (4-digit)',
              _fourthPrizeCtrls, Colors.orangeAccent, 4, Icons.star_border),
          const SizedBox(height: 16),
          _buildFifthPrizeSection(),
          const SizedBox(height: 16),

          // Winner Breakdown (expanded)
          if (_showWinnerBreakdown && _verifiedWinnersList.isNotEmpty)
            _buildWinnerBreakdownTable(),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildBulkPastePanel() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('⚡ QUICK BULK TEXT PASTE & AUTO-PARSER',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.cyanAccent,
                      fontSize: 15)),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _showBulkPasteBox = false),
              ),
            ],
          ),
          const Text(
              'Paste full lottery result text. System will auto-detect 1st, 2nd, 3rd, 4th & 5th prizes.',
              style:
                  TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          TextField(
            controller: _bulkPasteCtrl,
            maxLines: 5,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Paste WhatsApp result text here...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                  onPressed: () => _bulkPasteCtrl.clear(),
                  child: const Text('Clear')),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _parseBulkTextPaste,
                icon: const Icon(Icons.flash_on, color: Colors.black),
                label: const Text('AUTO-PARSE & FILL',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.black)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDrawSelector() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DRAW DETAILS',
              style: AppTypography.labelSm.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          // Date Picker
          InkWell(
            onTap: () async {
              final p = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (p != null) setState(() => _selectedDate = p);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: AppDecorations.radiusDefault,
                border: Border.all(color: AppColors.primary.withAlpha(80)),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_month,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DRAW DATE',
                          style: AppTypography.labelSm.copyWith(
                              color: AppColors.textSecondary, fontSize: 10)),
                      Text(
                        DateFormat('dd MMM yyyy · EEEE').format(_selectedDate),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Icon(Icons.edit_calendar,
                      color: AppColors.textSecondary, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Shift Chips
          Text('SHIFT',
              style: AppTypography.labelSm.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final shift in ['1 PM', '6 PM', '8 PM'])
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ChoiceChip(
                    label: Text(shift,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: _selectedShift == shift
                              ? Colors.amberAccent
                              : Colors.white70,
                        )),
                    selected: _selectedShift == shift,
                    selectedColor: AppColors.primaryContainer,
                    backgroundColor: AppColors.surfaceContainerHigh,
                    onSelected: (v) {
                      if (v) setState(() => _selectedShift = shift);
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWinnerStatusBox() {
    final hasWinners = _verifiedWinnersCount > 0;
    final color = hasWinners ? Colors.green : Colors.blueGrey;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasWinners ? Icons.emoji_events : Icons.shield_outlined,
                color: hasWinners ? Colors.amber : Colors.blueGrey,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                hasWinners ? '🎉 WINNERS FOUND!' : 'No Winners Yet',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: hasWinners ? Colors.greenAccent : Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _statRow('Winners', '$_verifiedWinnersCount tickets',
              Colors.amberAccent),
          const SizedBox(height: 6),
          _statRow(
              'Total Payout',
              '₹${NumberFormat('#,##,##0', 'en_IN').format(_totalPayoutAmount)}',
              Colors.greenAccent),
          const SizedBox(height: 12),
          if (hasWinners)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(
                    () => _showWinnerBreakdown = !_showWinnerBreakdown),
                icon: Icon(
                    _showWinnerBreakdown
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 16,
                    color: Colors.greenAccent),
                label: Text(
                    _showWinnerBreakdown
                        ? 'Hide Breakdown'
                        : 'View Breakdown',
                    style: const TextStyle(
                        color: Colors.greenAccent, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: color.withAlpha(120))),
              ),
            ),
          if (hasWinners) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _exportWinnersCSV,
                icon: const Icon(Icons.download, size: 16, color: Colors.cyan),
                label: const Text('Export CSV',
                    style: TextStyle(color: Colors.cyan, fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFirstPrizeSection() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.military_tech, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              const Text('1st PRIZE & CONSOLATION',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                      fontSize: 16)),
              const Spacer(),
              _prizeAmountBadge('₹${_formatAmount(_prizeAmounts['1st']!)}',
                  Colors.amber),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // 1st Prize
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('1st Prize Number',
                        style: AppTypography.labelSm.copyWith(
                            color: Colors.amber.withAlpha(180), fontSize: 11)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _firstPrizeCtrl,
                      focusNode: _firstPrizeFocusNode,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          fontFamily: 'monospace',
                          color: Colors.amber),
                      decoration: const InputDecoration(
                        hintText: 'e.g. 93J 99831',
                        hintStyle:
                            TextStyle(color: Colors.white24, fontSize: 14),
                        isDense: true,
                        prefixIcon:
                            Icon(Icons.looks_one, color: Colors.amber, size: 18),
                      ),
                      onChanged: (_) => _onPrizeChanged(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Consolation Prize
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Consolation Prize (last 5 digits)',
                        style: AppTypography.labelSm.copyWith(
                            color: Colors.orangeAccent.withAlpha(180),
                            fontSize: 11)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _consolationPrizeCtrl,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          fontFamily: 'monospace',
                          color: Colors.orangeAccent),
                      maxLength: 5,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'e.g. 99831',
                        hintStyle: const TextStyle(
                            color: Colors.white24, fontSize: 14),
                        isDense: true,
                        counterText: '',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.auto_fix_high,
                              size: 16, color: Colors.orange),
                          tooltip: 'Auto-fill from 1st Prize',
                          onPressed: () {
                            final f = _firstPrizeCtrl.text.trim();
                            if (f.isNotEmpty) {
                              final digits = f.replaceAll(
                                  RegExp(r'[^0-9]'), '');
                              _consolationPrizeCtrl.text = digits.length >= 5
                                  ? digits.substring(digits.length - 5)
                                  : digits;
                            }
                          },
                        ),
                        prefixIcon: const Icon(Icons.card_giftcard,
                            color: Colors.orangeAccent, size: 18),
                      ),
                      onChanged: (_) => _onPrizeChanged(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrizeGrid(String title, String subtitle,
      List<TextEditingController> ctrls, Color color, int digits, IconData icon) {
    final prize = title.startsWith('2nd')
        ? '2nd'
        : title.startsWith('3rd')
            ? '3rd'
            : '4th';
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                          fontSize: 15)),
                  Text(subtitle,
                      style: TextStyle(
                          color: color.withAlpha(140), fontSize: 11)),
                ],
              ),
              const Spacer(),
              _prizeAmountBadge(
                  '₹${_formatAmount(_prizeAmounts[prize]!)}', color),
              const SizedBox(width: 8),
              // Fill count badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withAlpha(80)),
                ),
                child: Text(
                  '${ctrls.where((c) => c.text.trim().isNotEmpty).length}/10',
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(ctrls.length, (i) {
              return SizedBox(
                width: 110,
                child: TextField(
                  controller: ctrls[i],
                  maxLength: digits,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontFamily: 'monospace',
                      fontSize: 14),
                  decoration: InputDecoration(
                    counterText: '',
                    isDense: true,
                    prefixText: '${i + 1}. ',
                    prefixStyle:
                        const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  onChanged: (v) {
                    if (v.trim().length == digits && i < ctrls.length - 1) {
                      FocusScope.of(context).nextFocus();
                    }
                    _onPrizeChanged();
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildFifthPrizeSection() {
    final filled =
        _fifthPrizeCtrls.where((c) => c.text.trim().isNotEmpty).length;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_border, color: Colors.purpleAccent, size: 18),
              const SizedBox(width: 8),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('5th PRIZE',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.purpleAccent,
                          fontSize: 15)),
                  Text('₹120 each · 100 numbers (4-digit)',
                      style: TextStyle(
                          color: Colors.purpleAccent, fontSize: 11)),
                ],
              ),
              const Spacer(),
              _prizeAmountBadge('₹120', Colors.purpleAccent),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.purpleAccent.withAlpha(80)),
                ),
                child: Text('$filled/100',
                    style: const TextStyle(
                        color: Colors.purpleAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              // Sort button
              IconButton(
                icon: const Icon(Icons.sort,
                    size: 16, color: Colors.purpleAccent),
                tooltip: 'Sort ascending',
                onPressed: () {
                  final vals = _fifthPrizeCtrls
                      .map((c) => c.text.trim())
                      .where((t) => t.isNotEmpty)
                      .toList()
                    ..sort();
                  setState(() {
                    for (int i = 0; i < 100; i++) {
                      _fifthPrizeCtrls[i].text =
                          i < vals.length ? vals[i] : '';
                    }
                  });
                  _showSnackbar('Sorted!', AppColors.info);
                },
              ),
            ],
          ),

          // 5th Prize Bulk Paste Row
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _fifthBulkCtrl,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    hintText:
                        'Paste all 5th prize numbers here (space/comma/newline separated)...',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.content_paste,
                        size: 16, color: Colors.purpleAccent),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _parseFifthBulkPaste,
                icon: const Icon(Icons.flash_on,
                    size: 14, color: Colors.black),
                label: const Text('Fill All',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purpleAccent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 5th Prize Grid
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_fifthPrizeCtrls.length, (i) {
              return SizedBox(
                width: 90,
                child: TextField(
                  controller: _fifthPrizeCtrls[i],
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purpleAccent,
                      fontFamily: 'monospace',
                      fontSize: 13),
                  decoration: InputDecoration(
                      counterText: '',
                      isDense: true,
                      prefixText: '${i + 1}.',
                      prefixStyle:
                          const TextStyle(fontSize: 9, color: Colors.grey)),
                  onChanged: (v) {
                    if (v.trim().length == 4 && i < 99) {
                      FocusScope.of(context).nextFocus();
                    }
                    _onPrizeChanged();
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildWinnerBreakdownTable() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('🏆 WINNER BREAKDOWN',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.greenAccent,
                      fontSize: 15)),
              TextButton.icon(
                onPressed: _exportWinnersCSV,
                icon: const Icon(Icons.download,
                    size: 14, color: Colors.cyan),
                label: const Text('Export CSV',
                    style:
                        TextStyle(color: Colors.cyan, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 👥 Party-wise Winning Summary Header
          Builder(
            builder: (context) {
              final partyMap = <String, (int count, double total)>{};
              for (final w in _verifiedWinnersList) {
                final b = (w['buyerName']?.toString().trim().isNotEmpty ?? false)
                    ? w['buyerName'].toString().trim()
                    : 'Counter / Direct';
                final amt = (w['prizeAmount'] as num?)?.toDouble() ?? 0.0;
                final cur = partyMap[b] ?? (0, 0.0);
                partyMap[b] = (cur.$1 + 1, cur.$2 + amt);
              }
              if (partyMap.isEmpty) return const SizedBox.shrink();

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(90),
                  borderRadius: AppDecorations.radiusDefault,
                  border: Border.all(color: Colors.greenAccent.withAlpha(70)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.groups_rounded, size: 15, color: Colors.amberAccent),
                        const SizedBox(width: 6),
                        const Text(
                          'PARTY-WISE WINNING SUMMARY',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.amberAccent),
                        ),
                        const Spacer(),
                        Text(
                          '${partyMap.length} Party(s) Won',
                          style: const TextStyle(fontSize: 11, color: Colors.white54),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: partyMap.entries.map((e) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer.withAlpha(80),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.primary.withAlpha(120)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person, size: 13, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: Colors.green.withAlpha(60), borderRadius: BorderRadius.circular(10)),
                                child: Text('${e.value.$1} wins', style: const TextStyle(fontSize: 10, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '₹${NumberFormat('#,##,##0', 'en_IN').format(e.value.$2)}',
                                style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.amberAccent, fontSize: 12),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            },
          ),
          // Table Header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(30),
              borderRadius: AppDecorations.radiusDefault,
            ),
            child: const Row(
              children: [
                Expanded(
                    flex: 2,
                    child: Text('TICKET NO',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Colors.white54))),
                Expanded(
                    flex: 2,
                    child: Text('BUYER',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Colors.white54))),
                Expanded(
                    flex: 2,
                    child: Text('PRIZE',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Colors.white54))),
                Expanded(
                    flex: 1,
                    child: Text('AMOUNT',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Colors.white54))),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ...List.generate(
            _verifiedWinnersList.length,
            (i) {
              final w = _verifiedWinnersList[i];
              final isFirst = w['prizeType']
                  .toString()
                  .toLowerCase()
                  .contains('1st');
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isFirst
                      ? Colors.amber.withAlpha(20)
                      : i.isEven
                          ? Colors.white.withAlpha(5)
                          : Colors.transparent,
                  borderRadius: AppDecorations.radiusDefault,
                ),
                child: Row(
                  children: [
                    Expanded(
                        flex: 2,
                        child: Text(w['ticketNumber'] ?? '',
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 13))),
                    Expanded(
                        flex: 2,
                        child: Text(w['buyerName'] ?? 'Walk-in',
                            style: const TextStyle(fontSize: 13))),
                    Expanded(
                        flex: 2,
                        child: Text(w['prizeType'] ?? '',
                            style: TextStyle(
                                color: isFirst
                                    ? Colors.amber
                                    : Colors.greenAccent,
                                fontWeight: FontWeight.w600,
                                fontSize: 12))),
                    Expanded(
                      flex: 1,
                      child: Text(
                          '₹${NumberFormat('#,##,##0', 'en_IN').format(w['prizeAmount'] ?? 0)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.greenAccent,
                              fontSize: 12)),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 20, color: Colors.white24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('TOTAL PAYOUT: ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(
                '₹${NumberFormat('#,##,##0', 'en_IN').format(_totalPayoutAmount)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Colors.greenAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── History Tab ─────────────────────────────────────────────────────────────
  Widget _buildHistoryView() {
    if (_isLoadingHistory) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(80),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 18),
              Text(
                'Loading Result History & Audit Records...',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 6),
              Text(
                'Please wait, loading historical draws from database...',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    // Filtered records
    final filtered = _historyRecords.where((r) {
      final matchesSearch = _historySearch.isEmpty ||
          (r['drawDateStr']?.toString() ?? '')
              .contains(_historySearch) ||
          (r['firstPrize']?.toString() ?? '')
              .toLowerCase()
              .contains(_historySearch.toLowerCase()) ||
          (r['drawName']?.toString() ?? '')
              .toLowerCase()
              .contains(_historySearch.toLowerCase());
      final matchesShift = _historyShiftFilter == 'All' ||
          (r['drawTimeStr']?.toString() ?? '')
              .contains(_historyShiftFilter);
      return matchesSearch && matchesShift;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search + Filter Bar + Refresh
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _historySearch = v),
                  decoration: const InputDecoration(
                    hintText: 'Search by date, shift, 1st prize...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Shift filter chips
              Wrap(
                spacing: 8,
                children: ['All', '1 PM', '6 PM', '8 PM'].map((s) {
                  return ChoiceChip(
                    label: Text(s,
                        style: const TextStyle(fontSize: 12)),
                    selected: _historyShiftFilter == s,
                    selectedColor: AppColors.primaryContainer,
                    onSelected: (v) {
                      if (v) setState(() => _historyShiftFilter = s);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _isReverifyingHistory ? null : _reverifyAllHistoryRecords,
                icon: _isReverifyingHistory
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh, size: 16),
                label: Text(
                  _isReverifyingHistory ? 'Re-verifying...' : 'Refresh & Re-verify',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isReverifyingHistory)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withAlpha(90),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Auditing & re-verifying historical results against live bookings...',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

          if (filtered.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined,
                        size: 48, color: Colors.white24),
                    SizedBox(height: 12),
                    Text('No results found.',
                        style: TextStyle(color: Colors.grey, fontSize: 16)),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final record = filtered[index];

                // O(1) Instant Lookup from verified historical cache

                final recId = record['id']?.toString() ?? '';
                final cached = _historyWinnerCache[recId];
                final savedCount = int.tryParse(record['verifiedWinnersCount']?.toString() ?? '') ?? 0;
                final savedPayout = double.tryParse(record['totalPayoutAmount']?.toString() ?? '') ?? 0.0;
                final liveWinnerCount = cached?.$1 ?? savedCount;
                final liveTotalPayout = cached?.$2 ?? savedPayout;
                final hasWinners = liveWinnerCount > 0;
                final partySummary = _historyPartySummaryCache[recId];
                final isExpanded = _expandedDrawIds.contains(recId);
                final isLoadingParty = _loadingPartySummaryDrawIds.contains(recId);

                return GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Date + Shift Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer.withAlpha(80),
                              borderRadius: AppDecorations.radiusDefault,
                            ),
                            child: Column(
                              children: [
                                Text(
                                  record['drawDateStr']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      fontFamily: 'monospace'),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withAlpha(60),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    record['drawTimeStr']?.toString() ?? '',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amberAccent),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Prize info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.military_tech,
                                        color: Colors.amber, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      '1st Prize: ${record['firstPrize'] ?? '—'}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          fontFamily: 'monospace',
                                          color: Colors.amber),
                                    ),
                                  ],
                                ),
                                if ((record['consolationPrize'] ??
                                        '').isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Consolation: ${record['consolationPrize']}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.orangeAccent),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 12,
                                  children: [
                                    _miniStat(
                                        '2nd',
                                        '${(record['secondPrizeNumbers']?.toString() ?? '').split(',').where((s) => s.isNotEmpty).length}/10',
                                        Colors.lightBlueAccent),
                                    _miniStat(
                                        '3rd',
                                        '${(record['thirdPrizeNumbers']?.toString() ?? '').split(',').where((s) => s.isNotEmpty).length}/10',
                                        Colors.tealAccent),
                                    _miniStat(
                                        '4th',
                                        '${(record['fourthPrizeNumbers']?.toString() ?? '').split(',').where((s) => s.isNotEmpty).length}/10',
                                        Colors.orangeAccent),
                                    _miniStat(
                                        '5th',
                                        '${(record['fifthPrizeNumbers']?.toString() ?? '').split(',').where((s) => s.isNotEmpty).length}/100',
                                        Colors.purpleAccent),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Winners info + actions
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (hasWinners)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withAlpha(40),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color:
                                            Colors.green.withAlpha(120)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.emoji_events,
                                          size: 12, color: Colors.amber),
                                      const SizedBox(width: 4),
                                      Text(
                                          '$liveWinnerCount winner(s)',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.greenAccent)),
                                    ],
                                  ),
                                ),
                              if (hasWinners) const SizedBox(height: 4),
                              Text(
                                'Payout: ₹${NumberFormat('#,##,##0', 'en_IN').format(liveTotalPayout)}',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: hasWinners
                                        ? Colors.greenAccent
                                        : Colors.white54),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit,
                                        color: Colors.blueAccent, size: 20),
                                    onPressed: () {
                                      _editRecord(record);
                                      _tabController.animateTo(0);
                                    },
                                    tooltip: 'Edit Result',
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(8),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.redAccent, size: 20),
                                    onPressed: () => _deleteRecord(
                                        record['id'].toString()),
                                    tooltip: 'Delete Result',
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(8),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (hasWinners) ...[
                        const SizedBox(height: 10),
                        const Divider(height: 1, color: Colors.white12),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: isLoadingParty ? null : () => _fetchPartyDetailsForDraw(record),
                              icon: isLoadingParty
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Icon(
                                      isExpanded ? Icons.keyboard_arrow_up : Icons.people_alt_outlined,
                                      size: 14,
                                      color: Colors.greenAccent,
                                    ),
                              label: Text(
                                isLoadingParty
                                    ? 'Loading Party Data...'
                                    : (isExpanded ? 'Hide Party Details' : 'View Party Winning Details'),
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.greenAccent.withAlpha(120)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            if (partySummary != null && partySummary.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              Text(
                                '${partySummary.length} Party(s) Won',
                                style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ],
                        ),
                        if (isExpanded) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(120),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.greenAccent.withAlpha(70)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.groups_rounded, size: 16, color: Colors.greenAccent),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'PARTY-WISE WINNING INAM BREAKDOWN',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.greenAccent),
                                    ),
                                    const Spacer(),
                                    Text(
                                      'Total Payout: ₹${NumberFormat('#,##,##0', 'en_IN').format(liveTotalPayout)}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (partySummary == null || partySummary.isEmpty)
                                  const Text('No party claims found for this draw.', style: TextStyle(color: Colors.white54, fontSize: 11))
                                else
                                  ...partySummary.map((p) {
                                    final pName = p['buyerName']?.toString() ?? 'Party';
                                    final pWins = p['totalWins'] ?? 0;
                                    final pPayout = (p['totalPayout'] as num?)?.toDouble() ?? 0.0;
                                    final pDetails = p['details']?.toString() ?? '';
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withAlpha(8),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.person, size: 14, color: Colors.amberAccent),
                                              const SizedBox(width: 6),
                                              Text(
                                                pName,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                              ),
                                              const Spacer(),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.withAlpha(50),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Text(
                                                  '$pWins ticket(s) won',
                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                '₹${NumberFormat('#,##,##0', 'en_IN').format(pPayout)}',
                                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.amberAccent),
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                icon: const Icon(Icons.copy_rounded, size: 15, color: Colors.cyanAccent),
                                                tooltip: 'Copy Party Hisab',
                                                constraints: const BoxConstraints(),
                                                padding: const EdgeInsets.all(4),
                                                onPressed: () => _copyPartyHisab(
                                                  record['drawTimeStr']?.toString() ?? record['drawName']?.toString() ?? '',
                                                  record['drawDateStr']?.toString() ?? '',
                                                  p,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (pDetails.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              pDetails,
                                              style: const TextStyle(fontSize: 11, color: Colors.white70, fontFamily: 'monospace'),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ── Helper Widgets ──────────────────────────────────────────────────────────
  Widget _actionBtn(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onPressed}) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: 16),
      label: Text(label, style: TextStyle(color: color, fontSize: 12)),
      style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withAlpha(80)),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
    );
  }

  Widget _statusChip(String label, Color color, {Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withAlpha(40),
          borderRadius: AppDecorations.radiusPill,
          border: Border.all(color: color)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          if (trailing != null) ...[const SizedBox(width: 6), trailing],
        ],
      ),
    );
  }

  Widget _prizeAmountBadge(String amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withAlpha(80))),
      child: Text(amount,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _statRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.white54)),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13, color: color)),
      ],
    );
  }

  Widget _miniStat(String prize, String count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$prize: ',
            style:
                TextStyle(color: color.withAlpha(160), fontSize: 11)),
        Text(count,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 11)),
      ],
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 10000000) return '${(amount / 10000000).toStringAsFixed(0)} Cr';
    if (amount >= 100000) return '${(amount / 100000).toStringAsFixed(0)} L';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(0)}K';
    return NumberFormat('#,##0', 'en_IN').format(amount);
  }
}