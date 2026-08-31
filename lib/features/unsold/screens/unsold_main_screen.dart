import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../settings/viewmodels/series_price_viewmodel.dart';
import '../../sellers/viewmodels/seller_customer_viewmodel.dart';
import '../../bookings/services/gemini_scanner_service.dart';
import '../../../core/database/database_service.dart';
import '../models/voucher_model.dart';
import '../models/unsold_model.dart';
import '../viewmodels/voucher_viewmodel.dart';
import '../viewmodels/unsold_viewmodel.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../widgets/ai_stock_scan_review_dialog.dart';
import '../widgets/raw_stock_text_parser_dialog.dart';

class UnsoldMainScreen extends ConsumerStatefulWidget {
  const UnsoldMainScreen({super.key});

  @override
  ConsumerState<UnsoldMainScreen> createState() => _UnsoldMainScreenState();
}

class _UnsoldMainScreenState extends ConsumerState<UnsoldMainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedDate = DateTime.now();
  String _selectedShift = 'Dear 1 PM';
  final List<String> _shiftList = ['Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'];
  String _selectedPartyFilter = 'All Parties';

  // Voucher Entry Controllers
  final TextEditingController _vPartyCtrl = TextEditingController();
  final TextEditingController _vSeriesCtrl = TextEditingController();
  final TextEditingController _vFromCtrl = TextEditingController();
  final TextEditingController _vToCtrl = TextEditingController();
  final TextEditingController _vRateCtrl = TextEditingController(text: '37.50');
  final FocusNode _vPartyFocusNode = FocusNode();
  final FocusNode _vSeriesFocusNode = FocusNode();
  final FocusNode _vFromFocusNode = FocusNode();
  final FocusNode _vToFocusNode = FocusNode();
  String _lastUsedVoucherSeries = '12';

  // Unsold Entry Controllers
  final TextEditingController _uPartyCtrl = TextEditingController();
  final TextEditingController _uSeriesCtrl = TextEditingController();
  final TextEditingController _uFromCtrl = TextEditingController();
  final TextEditingController _uToCtrl = TextEditingController();
  final FocusNode _uPartyFocusNode = FocusNode();
  final FocusNode _uSeriesFocusNode = FocusNode();
  final FocusNode _uFromFocusNode = FocusNode();
  final FocusNode _uToFocusNode = FocusNode();
  String _lastUsedUnsoldSeries = '12';

  // Multi-Selection State
  final Set<String> _selectedVoucherIds = {};
  final Set<String> _selectedUnsoldIds = {};

  // Available Sellers List for Dynamic Dropdown
  List<String> _availableParties = [];
  String _selectedSeriesFilter = 'All Series';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _vSeriesCtrl.text = _lastUsedVoucherSeries;
    _uSeriesCtrl.text = _lastUsedUnsoldSeries;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDataForCurrentFilters();
    });
  }

  void _onTabChanged() {
    if (_tabController.index == 1) {
      // Switching to Unsold Tab: Auto-sync party from Voucher if Unsold party is empty
      if (_uPartyCtrl.text.isEmpty && _vPartyCtrl.text.isNotEmpty) {
        setState(() {
          _uPartyCtrl.text = _vPartyCtrl.text;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _vPartyCtrl.dispose();
    _vSeriesCtrl.dispose();
    _vFromCtrl.dispose();
    _vToCtrl.dispose();
    _vRateCtrl.dispose();
    _vPartyFocusNode.dispose();
    _vSeriesFocusNode.dispose();
    _vFromFocusNode.dispose();
    _vToFocusNode.dispose();

    _uPartyCtrl.dispose();
    _uSeriesCtrl.dispose();
    _uFromCtrl.dispose();
    _uToCtrl.dispose();
    _uPartyFocusNode.dispose();
    _uSeriesFocusNode.dispose();
    _uFromFocusNode.dispose();
    _uToFocusNode.dispose();
    super.dispose();
  }

  void _loadDataForCurrentFilters() {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final filterParty = _selectedPartyFilter == 'All Parties' ? null : _selectedPartyFilter;
    ref.read(voucherViewModelProvider.notifier).loadVouchers(
      date: dateStr,
      drawShift: _selectedShift,
      partyName: filterParty,
    );
    ref.read(unsoldViewModelProvider.notifier).loadUnsold(
      date: dateStr,
      drawShift: _selectedShift,
      partyName: filterParty,
    );
    _refreshAvailableParties();
  }

  Future<void> _refreshAvailableParties() async {
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final db = DatabaseService.instance;
      final allV = await db.getVouchers(date: dateStr, drawShift: _selectedShift);
      final allU = await db.getUnsoldTickets(date: dateStr, drawShift: _selectedShift);

      // 🛡️ STRICT RULE: Only include parties who actually have vouchers or unsold data for this date & shift!
      final names = <String>{
        ...allV.map((v) => (v['party_name'] as String? ?? '').trim()).where((n) => n.isNotEmpty),
        ...allU.map((u) => (u['party_name'] as String? ?? '').trim()).where((n) => n.isNotEmpty),
      }.toList()..sort();

      if (mounted) {
        setState(() {
          _availableParties = names;
          if (_selectedPartyFilter != 'All Parties' && !names.contains(_selectedPartyFilter)) {
            _selectedPartyFilter = 'All Parties';
          }
        });
      }
    } catch (e) {
      debugPrint('Error refreshing available parties: $e');
    }
  }

  double _getPriceForSeries(String series) {
    final state = ref.read(seriesPriceViewModelProvider);
    final calculated = state.getPriceForSeries(series);
    if (calculated > 0) return calculated;
    final numVal = double.tryParse(series.replaceAll(RegExp(r'\D'), '')) ?? 12.0;
    return numVal * 3.75;
  }

  void _updateVoucherRate(String series) {
    final price = _getPriceForSeries(series.trim().toUpperCase());
    _vRateCtrl.text = price.toStringAsFixed(2);
  }

  int _calculateQuantity(String from, String to) {
    final start = int.tryParse(from);
    if (start == null) return 1;
    if (to.isEmpty) return 1;

    int? end;
    if (to.length == 5) {
      end = int.tryParse(to);
    } else if (to.length < 5 && from.length == 5) {
      final resolved = from.substring(0, 5 - to.length) + to;
      end = int.tryParse(resolved);
    }

    if (end == null || end < start) return 1;
    final count = end - start + 1;
    return count > 0 && count <= 500 ? count : 1;
  }

  Set<String> _expandTicketRange(String from, String to) {
    final start = int.tryParse(from);
    if (start == null) return {from};
    if (to.isEmpty || to == from) return {from.padLeft(5, '0')};

    int? end;
    if (to.length == 5) {
      end = int.tryParse(to);
    } else if (to.length < 5 && from.length == 5) {
      final resolved = from.substring(0, 5 - to.length) + to;
      end = int.tryParse(resolved);
    }

    if (end == null || end < start) return {from.padLeft(5, '0')};
    final count = end - start + 1;
    if (count > 500) return {from.padLeft(5, '0')};

    final set = <String>{};
    for (int i = start; i <= end; i++) {
      set.add(i.toString().padLeft(5, '0'));
    }
    return set;
  }

  Future<void> _addVoucher() async {
    final party = _vPartyCtrl.text.trim();
    if (party.isEmpty) {
      _showSnack('Please enter Party / Seller Name!', AppColors.warning);
      _vPartyFocusNode.requestFocus();
      return;
    }

    final series = _vSeriesCtrl.text.trim().isNotEmpty
        ? _vSeriesCtrl.text.trim().toUpperCase()
        : _lastUsedVoucherSeries;
    _lastUsedVoucherSeries = series;
    _vSeriesCtrl.text = series;

    final from = _vFromCtrl.text.trim();
    if (from.isEmpty || from.length != 5) {
      _showSnack('From Number must be an exact 5-digit number (e.g. 28301)!', AppColors.warning);
      _vFromFocusNode.requestFocus();
      return;
    }

    final to = _vToCtrl.text.trim();
    final newTickets = _expandTicketRange(from, to);
    final voucherState = ref.read(voucherViewModelProvider);

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // 🔒 DUPLICATE CHECK: Prevent issuing same ticket number to the SAME party in this shift.
    // If customer / party name is DIFFERENT, it is accepted!
    for (final v in voucherState.vouchers) {
      if (v.partyName.trim().toLowerCase() == party.toLowerCase() &&
          v.series.toUpperCase() == series.toUpperCase()) {
        final existingRange = _expandTicketRange(v.fromTicket, v.toTicket);
        final overlap = newTickets.intersection(existingRange);
        if (overlap.isNotEmpty) {
          final dup = overlap.first;
          _showSnack('⚠️ Duplicate Voucher: Ticket #$dup (Series $series) is ALREADY entered for $party in this shift!', AppColors.warning);
          _vFromFocusNode.requestFocus();
          return;
        }
      }
    }

    // Also check SQLite DB for the SAME party in this date & shift
    final dbExistingVouchers = await DatabaseService.instance.getVouchers(
      date: dateStr,
      drawShift: _selectedShift,
      partyName: party,
    );
    for (final row in dbExistingVouchers) {
      final vSer = (row['series'] as String? ?? '').toUpperCase();
      if (vSer == series.toUpperCase()) {
        final existingRange = _expandTicketRange(row['from_ticket'] as String? ?? '', row['to_ticket'] as String? ?? '');
        final overlap = newTickets.intersection(existingRange);
        if (overlap.isNotEmpty) {
          final dup = overlap.first;
          _showSnack('⚠️ Duplicate Voucher: Ticket #$dup (Series $series) is ALREADY entered for $party in this shift!', AppColors.warning);
          _vFromFocusNode.requestFocus();
          return;
        }
      }
    }

    final qty = _calculateQuantity(from, to);
    final rate = double.tryParse(_vRateCtrl.text.trim()) ?? _getPriceForSeries(series);
    final total = qty * rate;

    final now = DateTime.now();
    final voucherNo = 'VOUCH-${DateFormat('HHmmss').format(now)}';

    final voucher = VoucherModel(
      id: 'vouch_${now.microsecondsSinceEpoch}',
      voucherNo: voucherNo,
      date: dateStr,
      drawShift: _selectedShift,
      partyName: party,
      series: series,
      fromTicket: from,
      toTicket: to.isNotEmpty ? to : from,
      totalQty: qty,
      pricePerTicket: rate,
      totalAmount: total,
      createdAt: now,
    );

    final success = await ref.read(voucherViewModelProvider.notifier).addVoucher(voucher);
    if (success) {
      // Retain Party Name & Series for fast continuous range entry!
      _vFromCtrl.clear();
      _vToCtrl.clear();
      _vFromFocusNode.requestFocus();
      _showSnack('✅ Added Voucher #$voucherNo ($qty Tickets | ₹${total.toStringAsFixed(2)})', AppColors.success);
    }
  }

  Future<void> _addUnsold() async {
    final party = _uPartyCtrl.text.trim();
    if (party.isEmpty) {
      _showSnack('Please enter Party / Seller Name!', AppColors.warning);
      _uPartyFocusNode.requestFocus();
      return;
    }

    final series = _uSeriesCtrl.text.trim().isNotEmpty
        ? _uSeriesCtrl.text.trim().toUpperCase()
        : _lastUsedUnsoldSeries;
    _lastUsedUnsoldSeries = series;
    _uSeriesCtrl.text = series;

    final from = _uFromCtrl.text.trim();
    if (from.isEmpty || from.length != 5) {
      _showSnack('From Number must be an exact 5-digit number (e.g. 28381)!', AppColors.warning);
      _uFromFocusNode.requestFocus();
      return;
    }

    final to = _uToCtrl.text.trim();
    final newTickets = _expandTicketRange(from, to);
    final voucherState = ref.read(voucherViewModelProvider);
    final unsoldState = ref.read(unsoldViewModelProvider);

    // 🔒 RULE 1: Soft check if ticket exists in issued Vouchers (warning only)
    final partyIssuedTickets = <String>{};
    for (final v in voucherState.vouchers) {
      if (v.partyName.trim().toLowerCase() == party.toLowerCase() &&
          v.series.toUpperCase() == series.toUpperCase()) {
        partyIssuedTickets.addAll(_expandTicketRange(v.fromTicket, v.toTicket));
      }
    }

    if (partyIssuedTickets.isNotEmpty) {
      final notIssued = newTickets.where((tkt) => !partyIssuedTickets.contains(tkt)).toList();
      if (notIssued.isNotEmpty) {
        debugPrint('ℹ️ Notice: ${notIssued.length} tickets returned were not in current vouchers for this party/shift.');
      }
    }

    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // 🔒 RULE 2: Duplicate Check in Unsold (Cannot return same ticket twice for the SAME party in same shift)
    // If customer / party name is DIFFERENT, it is accepted!
    for (final u in unsoldState.unsoldList) {
      if (u.partyName.trim().toLowerCase() == party.toLowerCase() &&
          u.series.toUpperCase() == series.toUpperCase()) {
        final existingUnsold = _expandTicketRange(u.fromTicket, u.toTicket);
        final overlap = newTickets.intersection(existingUnsold);
        if (overlap.isNotEmpty) {
          final dup = overlap.first;
          _showSnack('⚠️ Duplicate Return: Ticket #$dup (Series $series) is ALREADY returned in Unsold by $party for this shift!', AppColors.warning);
          _uFromFocusNode.requestFocus();
          return;
        }
      }
    }

    // Party DB check for duplicates in same date & shift for THIS party
    final dbExisting = await DatabaseService.instance.getUnsoldTickets(
      date: dateStr,
      drawShift: _selectedShift,
      partyName: party,
    );
    for (final row in dbExisting) {
      final uSer = (row['series'] as String? ?? '').toUpperCase();
      if (uSer == series.toUpperCase()) {
        final existingUnsold = _expandTicketRange(row['from_ticket'] as String? ?? '', row['to_ticket'] as String? ?? '');
        final overlap = newTickets.intersection(existingUnsold);
        if (overlap.isNotEmpty) {
          final dup = overlap.first;
          _showSnack('⚠️ Duplicate Return: Ticket #$dup (Series $series) is ALREADY returned in Unsold by $party for this shift!', AppColors.warning);
          _uFromFocusNode.requestFocus();
          return;
        }
      }
    }

    final qty = _calculateQuantity(from, to);
    final rate = _getPriceForSeries(series);
    final total = qty * rate;

    final returnNo = 'RET-${DateFormat('HHmmss').format(now)}';

    final unsold = UnsoldModel(
      id: 'unsold_${now.microsecondsSinceEpoch}',
      returnNo: returnNo,
      date: dateStr,
      drawShift: _selectedShift,
      partyName: party,
      series: series,
      fromTicket: from,
      toTicket: to.isNotEmpty ? to : from,
      totalQty: qty,
      pricePerTicket: rate,
      totalAmount: total,
      createdAt: now,
    );

    final success = await ref.read(unsoldViewModelProvider.notifier).addUnsold(unsold);
    if (success) {
      // Retain Party Name & Series for fast continuous range entry!
      _uFromCtrl.clear();
      _uToCtrl.clear();
      _uFromFocusNode.requestFocus();
      _showSnack('✅ Logged Unsold #$returnNo ($qty Tickets | -₹${total.toStringAsFixed(2)})', const Color(0xFFEF4444));
    }
  }

  Future<void> _scanParchaImage(StockScanMode mode) async {
    final currentParty = mode == StockScanMode.voucher
        ? _vPartyCtrl.text.trim()
        : _uPartyCtrl.text.trim();

    final targetParty = currentParty.isNotEmpty ? currentParty : 'Walk-in Party';

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final List<Uint8List> allFilesBytes = [];
      for (final f in result.files) {
        Uint8List? b = f.bytes;
        if (b == null && f.path != null) {
          b = await File(f.path!).readAsBytes();
        }
        if (b != null && b.isNotEmpty) {
          allFilesBytes.add(b);
        }
      }

      if (allFilesBytes.isEmpty) {
        _showSnack('Could not read image file bytes.', AppColors.error);
        return;
      }

      if (!mounted) return;

      List<GeminiScannedItem> scannedTickets = [];
      final ValueNotifier<String> scanProgressNotifier = ValueNotifier<String>(
        allFilesBytes.length > 1
            ? 'Scanning 1 of ${allFilesBytes.length} Slips...'
            : (mode == StockScanMode.voucher ? 'Scanning Voucher Parcha with AI...' : 'Scanning Unsold Parcha with AI...'),
      );

      BuildContext? progressDialogCtx;
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (ctx) {
          progressDialogCtx = ctx;
          return Dialog(
            backgroundColor: const Color(0xFF1E293B),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.purpleAccent),
                  const SizedBox(width: 18),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ValueListenableBuilder<String>(
                        valueListenable: scanProgressNotifier,
                        builder: (_, msg, _) => Text(
                          msg,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Extracting numbers and series...',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );

      try {
        for (int i = 0; i < allFilesBytes.length; i++) {
          if (allFilesBytes.length > 1) {
            scanProgressNotifier.value = 'Scanning Slip ${i + 1} of ${allFilesBytes.length}...';
          }
          final tickets = await GeminiScannerService.instance.scanImage(
            imageBytes: allFilesBytes[i],
            defaultSeller: targetParty,
            scanContext: mode == StockScanMode.voucher ? ScanContext.voucher : ScanContext.unsold,
          );
          scannedTickets.addAll(tickets);
        }
      } catch (e) {
        debugPrint('Scan error: $e');
      } finally {
        if (progressDialogCtx != null && progressDialogCtx!.mounted) {
          Navigator.of(progressDialogCtx!, rootNavigator: true).pop();
        }
      }

      final fileBytes = allFilesBytes.first;

      if (!mounted) return;

      // Use auto-detected shift if found from parcha text, otherwise current selected shift
      final detectedShift = GeminiScannerService.instance.lastDetectedShift;
      final effectiveShift = (detectedShift != null && detectedShift.isNotEmpty) ? detectedShift : _selectedShift;

      final detectedParty = GeminiScannerService.instance.lastDetectedParty;
      final effectiveParty = (detectedParty != null && detectedParty.isNotEmpty) ? detectedParty : targetParty;

      final validBytes = fileBytes;

      // Save scan session in memory so it can be restored anytime
      GeminiScannerService.instance.lastStockScanSession = LastStockScanSession(
        imageBytes: validBytes,
        allFilesBytes: allFilesBytes,
        items: scannedTickets,
        isVoucher: mode == StockScanMode.voucher,
        activeShift: effectiveShift,
        activeDate: _selectedDate,
        defaultParty: effectiveParty,
      );

      final saved = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: Colors.black.withAlpha(150),
        builder: (ctx) => AiStockScanReviewDialog(
          imageBytes: validBytes,
          allImageBytes: allFilesBytes,
          initialItems: scannedTickets,
          mode: mode,
          activeShift: effectiveShift,
          activeDate: _selectedDate,
          defaultParty: effectiveParty,
        ),
      );

      if (saved == true && mounted) {
        GeminiScannerService.instance.lastStockScanSession = null;
        _selectedSeriesFilter = 'All Series';
        if (effectiveParty.isNotEmpty && effectiveParty != 'Walk-in Party') {
          _selectedPartyFilter = effectiveParty;
          _uPartyCtrl.text = effectiveParty;
          _vPartyCtrl.text = effectiveParty;
        }
        if (effectiveShift.isNotEmpty && _shiftList.contains(effectiveShift)) {
          _selectedShift = effectiveShift;
        }
        setState(() {});
        _loadDataForCurrentFilters();
        _showSnack(
          mode == StockScanMode.voucher
              ? '✅ Vouchers scanned & saved successfully!'
              : '✅ Unsold returns scanned & saved successfully!',
          AppColors.success,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error picking image: $e', AppColors.error);
      }
    }
  }

  Future<void> _reopenLastScan() async {
    final session = GeminiScannerService.instance.lastStockScanSession;
    if (session == null) {
      _showSnack('No recent scan found in memory.', AppColors.warning);
      return;
    }

    final mode = session.isVoucher ? StockScanMode.voucher : StockScanMode.unsold;

    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha(150),
      builder: (ctx) => AiStockScanReviewDialog(
        imageBytes: session.imageBytes,
        allImageBytes: session.allFilesBytes ?? [session.imageBytes],
        initialItems: session.items,
        mode: mode,
        activeShift: session.activeShift,
        activeDate: session.activeDate,
        defaultParty: session.defaultParty,
      ),
    );

    if (saved == true && mounted) {
      GeminiScannerService.instance.lastStockScanSession = null;
      _selectedSeriesFilter = 'All Series';
      if (session.defaultParty.isNotEmpty && session.defaultParty != 'Walk-in Party') {
        _selectedPartyFilter = session.defaultParty;
        _uPartyCtrl.text = session.defaultParty;
        _vPartyCtrl.text = session.defaultParty;
      }
      if (session.activeShift.isNotEmpty && _shiftList.contains(session.activeShift)) {
        _selectedShift = session.activeShift;
      }
      _selectedDate = session.activeDate;
      setState(() {});
      _loadDataForCurrentFilters();
      _showSnack(
        session.isVoucher
            ? '✅ Vouchers scanned & saved successfully!'
            : '✅ Unsold returns scanned & saved successfully!',
        AppColors.success,
      );
    }
  }

  Future<void> _openPasteTextParser(StockScanMode mode) async {
    final currentParty = mode == StockScanMode.voucher
        ? _vPartyCtrl.text.trim()
        : _uPartyCtrl.text.trim();
    final defaultParty = currentParty.isNotEmpty ? currentParty : 'Walk-in Party';

    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha(150),
      builder: (ctx) => RawStockTextParserDialog(
        mode: mode,
        activeShift: _selectedShift,
        activeDate: _selectedDate,
        defaultParty: defaultParty,
      ),
    );

    if (saved == true && mounted) {
      _loadDataForCurrentFilters();
      _showSnack(
        mode == StockScanMode.voucher
            ? '✅ Vouchers parsed & saved successfully!'
            : '✅ Unsold returns parsed & saved successfully!',
        AppColors.success,
      );
    }
  }

  void _openGetFileHisabDialog() {
    context.go(AppConstants.routeGetFileReports);
  }

  Future<void> _exportVouchersToCsv(List<VoucherModel> list) async {
    if (list.isEmpty) {
      _showSnack('⚠️ No vouchers to export for selected filters!', AppColors.warning);
      return;
    }

    try {
      final dateStr = DateFormat('yyyyMMdd').format(_selectedDate);
      final shiftClean = _selectedShift.replaceAll(' ', '_');
      final defaultFileName = 'vouchers_${dateStr}_$shiftClean.csv';

      String? filePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Vouchers (Stock Issue) CSV',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (filePath == null) {
        final docsDir = Platform.environment['USERPROFILE'] != null
            ? '${Platform.environment['USERPROFILE']}\\Documents'
            : Directory.systemTemp.path;
        filePath = '$docsDir\\$defaultFileName';
      }

      final buffer = StringBuffer();
      buffer.writeln('SL,Date,Shift,Party Name,Series,Ticket Range,From Ticket,To Ticket,Quantity,Rate,Total Amount,Created At');

      for (int i = 0; i < list.length; i++) {
        final v = list[i];
        buffer.writeln(
          '${i + 1},"${v.date}","${v.drawShift}","${v.partyName}","${v.series}","${v.series}-${v.fromTicket.padLeft(5, '0')} to ${v.toTicket.padLeft(5, '0')}","${v.fromTicket}","${v.toTicket}",${v.totalQty},${v.pricePerTicket},${v.totalAmount},"${DateFormat('yyyy-MM-dd HH:mm').format(v.createdAt)}"',
        );
      }

      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      await Clipboard.setData(ClipboardData(text: buffer.toString()));

      _showSnack('📊 Exported ${list.length} vouchers to: $filePath (Copied to Clipboard)', AppColors.success);
    } catch (e) {
      _showSnack('Export error: $e', AppColors.error);
    }
  }

  Future<void> _exportUnsoldToCsv(List<UnsoldModel> list) async {
    if (list.isEmpty) {
      _showSnack('⚠️ No unsold returns to export for selected filters!', AppColors.warning);
      return;
    }

    try {
      final dateStr = DateFormat('yyyyMMdd').format(_selectedDate);
      final shiftClean = _selectedShift.replaceAll(' ', '_');
      final defaultFileName = 'unsold_${dateStr}_$shiftClean.csv';

      String? filePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Unsold Returns CSV',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (filePath == null) {
        final docsDir = Platform.environment['USERPROFILE'] != null
            ? '${Platform.environment['USERPROFILE']}\\Documents'
            : Directory.systemTemp.path;
        filePath = '$docsDir\\$defaultFileName';
      }

      final buffer = StringBuffer();
      buffer.writeln('SL,Date,Shift,Party Name,Series,Ticket Range,From Ticket,To Ticket,Quantity,Rate,Total Amount,Created At');

      for (int i = 0; i < list.length; i++) {
        final u = list[i];
        buffer.writeln(
          '${i + 1},"${u.date}","${u.drawShift}","${u.partyName}","${u.series}","${u.series}-${u.fromTicket.padLeft(5, '0')} to ${u.toTicket.padLeft(5, '0')}","${u.fromTicket}","${u.toTicket}",${u.totalQty},${u.pricePerTicket},${u.totalAmount},"${DateFormat('yyyy-MM-dd HH:mm').format(u.createdAt)}"',
        );
      }

      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      await Clipboard.setData(ClipboardData(text: buffer.toString()));

      _showSnack('📊 Exported ${list.length} unsold returns to: $filePath (Copied to Clipboard)', AppColors.success);
    } catch (e) {
      _showSnack('Export error: $e', AppColors.error);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ─── 📦 BULK SELECTION ACTIONS ───────────────────────────────────────────────

  Future<void> _openBulkUpdatePartyDialog(bool isVoucher) async {
    final selectedIds = isVoucher ? _selectedVoucherIds : _selectedUnsoldIds;
    if (selectedIds.isEmpty) return;

    final sellerState = ref.read(sellerCustomerViewModelProvider);
    final voucherState = ref.read(voucherViewModelProvider);
    final unsoldState = ref.read(unsoldViewModelProvider);

    final recentParties = <String>{
      ...sellerState.sellers.map((s) => s.name.trim()).where((n) => n.isNotEmpty),
      ...voucherState.vouchers.map((v) => v.partyName.trim()).where((p) => p.isNotEmpty),
      ...unsoldState.unsoldList.map((u) => u.partyName.trim()).where((p) => p.isNotEmpty),
    }.toList();

    final inputCtrl = TextEditingController();

    final newParty = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
        ),
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.drive_file_rename_outline, color: Color(0xFF38BDF8), size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Update Party Name (${selectedIds.length} Selected)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: inputCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'New Party / Seller Name *',
                  labelStyle: const TextStyle(color: Colors.cyanAccent, fontSize: 12),
                  hintText: 'e.g. Wakil / Raju / Amit',
                  hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  prefixIcon: const Icon(Icons.person, color: Colors.cyanAccent, size: 16),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.5)),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) Navigator.pop(ctx, val.trim());
                },
              ),
              if (recentParties.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Quick Select Party:', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: recentParties.take(6).map((p) {
                    return ActionChip(
                      label: Text(p),
                      labelStyle: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                      backgroundColor: const Color(0xFF1E293B),
                      side: const BorderSide(color: Color(0xFF334155)),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      onPressed: () => Navigator.pop(ctx, p),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () {
                      if (inputCtrl.text.trim().isNotEmpty) {
                        Navigator.pop(ctx, inputCtrl.text.trim());
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                    child: const Text('UPDATE PARTY', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (newParty != null && newParty.isNotEmpty) {
      final count = selectedIds.length;
      final idsList = selectedIds.toList();
      bool success = false;
      if (isVoucher) {
        success = await ref.read(voucherViewModelProvider.notifier).bulkUpdateParty(idsList, newParty);
      } else {
        success = await ref.read(unsoldViewModelProvider.notifier).bulkUpdateParty(idsList, newParty);
      }

      if (success) {
        setState(() {
          if (isVoucher) { _selectedVoucherIds.clear(); }
          else { _selectedUnsoldIds.clear(); }
        });
        _loadDataForCurrentFilters();
        _showSnack('✅ Updated Party Name to "$newParty" for $count item(s)!', AppColors.success);
      } else {
        _showSnack('❌ Error updating party name.', AppColors.error);
      }
    }
  }

  Future<void> _openBulkUpdateSeriesDialog(bool isVoucher) async {
    final selectedIds = isVoucher ? _selectedVoucherIds : _selectedUnsoldIds;
    if (selectedIds.isEmpty) return;

    final inputCtrl = TextEditingController(text: '12');

    final newSeries = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF7C3AED), width: 1.5),
        ),
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune, color: Color(0xFFC084FC), size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Change Series (${selectedIds.length} Selected)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: inputCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'New Series *',
                  labelStyle: const TextStyle(color: Colors.cyanAccent, fontSize: 12),
                  hintText: 'e.g. 12, 24, 36, 100',
                  hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.5)),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) Navigator.pop(ctx, val.trim().toUpperCase());
                },
              ),
              const SizedBox(height: 12),
              const Text('Quick Series Choices:', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ['12', '24', '36', '100', '84', '92'].map((s) {
                  return ActionChip(
                    label: Text('Ser $s'),
                    labelStyle: const TextStyle(color: Colors.cyanAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
                    backgroundColor: const Color(0xFF1E293B),
                    side: const BorderSide(color: Color(0xFF334155)),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    onPressed: () => Navigator.pop(ctx, s),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () {
                      if (inputCtrl.text.trim().isNotEmpty) {
                        Navigator.pop(ctx, inputCtrl.text.trim().toUpperCase());
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), foregroundColor: Colors.white),
                    child: const Text('CHANGE SERIES', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (newSeries != null && newSeries.isNotEmpty) {
      final count = selectedIds.length;
      final idsList = selectedIds.toList();
      final newRate = _getPriceForSeries(newSeries);
      bool success = false;
      if (isVoucher) {
        success = await ref.read(voucherViewModelProvider.notifier).bulkUpdateSeries(idsList, newSeries, newRate);
      } else {
        success = await ref.read(unsoldViewModelProvider.notifier).bulkUpdateSeries(idsList, newSeries, newRate);
      }

      if (success) {
        setState(() {
          if (isVoucher) { _selectedVoucherIds.clear(); }
          else { _selectedUnsoldIds.clear(); }
        });
        _loadDataForCurrentFilters();
        _showSnack('✅ Changed Series to "Ser $newSeries" (Rate ₹${newRate.toStringAsFixed(2)}) for $count item(s)!', AppColors.success);
      } else {
        _showSnack('❌ Error changing series.', AppColors.error);
      }
    }
  }

  Future<void> _confirmBulkDelete(bool isVoucher) async {
    final selectedIds = isVoucher ? _selectedVoucherIds : _selectedUnsoldIds;
    if (selectedIds.isEmpty) return;

    final count = selectedIds.length;
    final idsToDelete = selectedIds.toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Confirm Bulk Delete', style: TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete $count selected ${isVoucher ? 'voucher(s)' : 'unsold return(s)'}? This action cannot be undone.',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: Text('DELETE $count ITEMS', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      bool success = false;
      if (isVoucher) {
        success = await ref.read(voucherViewModelProvider.notifier).bulkDelete(idsToDelete);
      } else {
        success = await ref.read(unsoldViewModelProvider.notifier).bulkDelete(idsToDelete);
      }

      if (success) {
        setState(() {
          if (isVoucher) { _selectedVoucherIds.clear(); }
          else { _selectedUnsoldIds.clear(); }
        });
        _loadDataForCurrentFilters();
        _showSnack('🗑️ Deleted $count items successfully!', AppColors.success);
      } else {
        _showSnack('❌ Error deleting items.', AppColors.error);
      }
    }
  }

  Future<void> _showDeleteAllDataDialog({bool defaultToUnsoldOnly = false, bool defaultToVouchersOnly = false}) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final dateDisplayStr = DateFormat('dd-MM-yyyy').format(_selectedDate);
    final hasPartyFilter = _selectedPartyFilter != 'All Parties';

    String deleteScope = defaultToUnsoldOnly
        ? 'unsold_only'
        : (defaultToVouchersOnly ? 'vouchers_only' : 'both_current');
    bool filterByParty = hasPartyFilter;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.redAccent, width: 1.5),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Delete All Stock / Unsold Data', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('Permanently remove records from database', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: Colors.cyanAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Target: $dateDisplayStr • Shift: $_selectedShift${hasPartyFilter ? ' • Party: $_selectedPartyFilter' : ''}',
                              style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Select what you want to delete:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),

                    // Option 1: Unsold Only
                    _buildDeleteScopeTile(
                      title: 'Delete Unsold Returns ONLY ($dateDisplayStr, $_selectedShift)',
                      subtitle: 'Remove all return wapasi for current date & shift',
                      value: 'unsold_only',
                      groupValue: deleteScope,
                      icon: Icons.inventory_2_outlined,
                      activeColor: Colors.redAccent,
                      onTap: () => setModalState(() => deleteScope = 'unsold_only'),
                    ),

                    // Option 2: Vouchers Only
                    _buildDeleteScopeTile(
                      title: 'Delete Vouchers ONLY ($dateDisplayStr, $_selectedShift)',
                      subtitle: 'Remove all issued vouchers for current date & shift',
                      value: 'vouchers_only',
                      groupValue: deleteScope,
                      icon: Icons.receipt_rounded,
                      activeColor: Colors.amberAccent,
                      onTap: () => setModalState(() => deleteScope = 'vouchers_only'),
                    ),

                    // Option 3: Both Vouchers & Unsold
                    _buildDeleteScopeTile(
                      title: 'Delete BOTH Vouchers & Unsold ($dateDisplayStr, $_selectedShift)',
                      subtitle: 'Reset entire stock issue & wapasi for this date & shift',
                      value: 'both_current',
                      groupValue: deleteScope,
                      icon: Icons.refresh_rounded,
                      activeColor: Colors.orangeAccent,
                      onTap: () => setModalState(() => deleteScope = 'both_current'),
                    ),

                    // Option 4: Purge All
                    _buildDeleteScopeTile(
                      title: '⚠️ PURGE ALL HISTORIC DATA (All Dates & Shifts)',
                      subtitle: 'Permanently wipe ALL vouchers & unsold records across entire app history',
                      value: 'purge_all',
                      groupValue: deleteScope,
                      icon: Icons.warning_amber_rounded,
                      activeColor: Colors.red,
                      onTap: () => setModalState(() => deleteScope = 'purge_all'),
                    ),

                    if (hasPartyFilter && deleteScope != 'purge_all') ...[
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        value: filterByParty,
                        dense: true,
                        activeColor: Colors.redAccent,
                        contentPadding: EdgeInsets.zero,
                        title: Text('Only delete records for "$_selectedPartyFilter"', style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        subtitle: const Text('Uncheck to delete for all parties in this shift', style: TextStyle(color: Colors.grey, fontSize: 10)),
                        onChanged: (val) => setModalState(() => filterByParty = val ?? false),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.delete_forever, size: 16),
                  label: const Text('CONFIRM DELETE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      final targetParty = filterByParty ? _selectedPartyFilter : null;
      bool success = false;

      if (deleteScope == 'unsold_only') {
        success = await ref.read(unsoldViewModelProvider.notifier).deleteAll(
          date: dateStr,
          drawShift: _selectedShift,
          partyName: targetParty,
        );
      } else if (deleteScope == 'vouchers_only') {
        success = await ref.read(voucherViewModelProvider.notifier).deleteAll(
          date: dateStr,
          drawShift: _selectedShift,
          partyName: targetParty,
        );
      } else if (deleteScope == 'both_current') {
        final uOk = await ref.read(unsoldViewModelProvider.notifier).deleteAll(
          date: dateStr,
          drawShift: _selectedShift,
          partyName: targetParty,
        );
        final vOk = await ref.read(voucherViewModelProvider.notifier).deleteAll(
          date: dateStr,
          drawShift: _selectedShift,
          partyName: targetParty,
        );
        success = uOk || vOk;
      } else if (deleteScope == 'purge_all') {
        final uOk = await ref.read(unsoldViewModelProvider.notifier).deleteAll();
        final vOk = await ref.read(voucherViewModelProvider.notifier).deleteAll();
        success = uOk || vOk;
      }

      setState(() {
        _selectedVoucherIds.clear();
        _selectedUnsoldIds.clear();
      });
      _loadDataForCurrentFilters();

      if (success) {
        _showSnack('🗑️ Successfully deleted requested stock/unsold data!', AppColors.success);
      } else {
        _showSnack('❌ Error deleting data or no records found.', AppColors.error);
      }
    }
  }

  Widget _buildDeleteScopeTile({
    required String title,
    required String subtitle,
    required String value,
    required String groupValue,
    required IconData icon,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final isSelected = value == groupValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withAlpha(25) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? activeColor : Colors.white12,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: isSelected ? activeColor : Colors.grey),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold, fontSize: 11.5)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: isSelected ? Colors.white60 : Colors.grey.shade500, fontSize: 10)),
                  ],
                ),
              ),
              // Custom radio indicator (Radio.groupValue + onChanged deprecated in Flutter 3.32+)
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? activeColor : Colors.white30,
                    width: isSelected ? 2.0 : 1.5,
                  ),
                  color: isSelected ? activeColor.withAlpha(40) : Colors.transparent,
                ),
                child: isSelected
                    ? Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: activeColor),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBulkActionBar(bool isVoucher, int selectedCount) {
    if (selectedCount == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B4B),
        border: Border(top: BorderSide(color: Colors.indigoAccent.withAlpha(150), width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(160),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.indigoAccent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$selectedCount Selected',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
            ),
          ),
          const SizedBox(width: 12),

          // 1. Update Party Name Button
          ElevatedButton.icon(
            onPressed: () => _openBulkUpdatePartyDialog(isVoucher),
            icon: const Icon(Icons.person, size: 14),
            label: const Text('Update Party Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(width: 8),

          // 2. Change Series Button
          ElevatedButton.icon(
            onPressed: () => _openBulkUpdateSeriesDialog(isVoucher),
            icon: const Icon(Icons.tune, size: 14),
            label: const Text('Change Series', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(width: 8),

          // 3. Bulk Delete Button
          ElevatedButton.icon(
            onPressed: () => _confirmBulkDelete(isVoucher),
            icon: const Icon(Icons.delete_outline, size: 14),
            label: const Text('Delete Selected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),

          const Spacer(),

          // Clear Selection
          TextButton.icon(
            onPressed: () {
              setState(() {
                if (isVoucher) { _selectedVoucherIds.clear(); }
                else { _selectedUnsoldIds.clear(); }
              });
            },
            icon: const Icon(Icons.close, size: 14, color: Colors.grey),
            label: const Text('Deselect All', style: TextStyle(color: Colors.grey, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: Colors.black,
              surface: Color(0xFF1E293B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadDataForCurrentFilters();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateDisplayStr = DateFormat('dd-MM-yyyy').format(_selectedDate);
    final voucherState = ref.watch(voucherViewModelProvider);
    final unsoldState = ref.watch(unsoldViewModelProvider);

    // Dynamic available series from current vouchers and unsold items
    final Set<String> availableSeriesSet = {'All Series'};
    for (final v in voucherState.vouchers) {
      final s = v.series.trim();
      if (s.isNotEmpty) availableSeriesSet.add(s);
    }
    for (final u in unsoldState.unsoldList) {
      final s = u.series.trim();
      if (s.isNotEmpty) availableSeriesSet.add(s);
    }
    final availableSeries = availableSeriesSet.toList()
      ..sort((a, b) {
        if (a == 'All Series') return -1;
        if (b == 'All Series') return 1;
        final numA = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 999;
        final numB = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 999;
        return numA.compareTo(numB);
      });

    // Filter lists by selected series
    final filteredVouchers = _selectedSeriesFilter == 'All Series'
        ? voucherState.vouchers
        : voucherState.vouchers.where((v) {
            final sV = v.series.replaceAll(RegExp(r'\D'), '');
            final sF = _selectedSeriesFilter.replaceAll(RegExp(r'\D'), '');
            return v.series.trim().toUpperCase() == _selectedSeriesFilter.trim().toUpperCase() ||
                (sV.isNotEmpty && sV == sF);
          }).toList();

    final filteredUnsold = _selectedSeriesFilter == 'All Series'
        ? unsoldState.unsoldList
        : unsoldState.unsoldList.where((u) {
            final sU = u.series.replaceAll(RegExp(r'\D'), '');
            final sF = _selectedSeriesFilter.replaceAll(RegExp(r'\D'), '');
            return u.series.trim().toUpperCase() == _selectedSeriesFilter.trim().toUpperCase() ||
                (sU.isNotEmpty && sU == sF);
          }).toList();

    final issuedTickets = filteredVouchers.fold<int>(0, (sum, v) => sum + v.totalQty);
    final issuedAmount = filteredVouchers.fold<double>(0.0, (sum, v) => sum + v.totalAmount);
    final unsoldTickets = filteredUnsold.fold<int>(0, (sum, u) => sum + u.totalQty);
    final unsoldAmount = filteredUnsold.fold<double>(0.0, (sum, u) => sum + u.totalAmount);
    final netSoldTickets = issuedTickets - unsoldTickets;
    final netAmount = issuedAmount - unsoldAmount;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Column(
        children: [
          // 1. Top Header Bar with Sub-Tabs & Filters
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFEF4444).withAlpha(80)),
                        ),
                        child: const Icon(
                          Icons.inventory_2_outlined,
                          color: Color(0xFFEF4444),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'UNSOLD & VOUCHERS',
                        style: AppTypography.titleMd.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 16),

                  // Sub-Tabs Switcher (Voucher vs Unsold)
                  Container(
                    height: 32,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicator: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.black,
                      unselectedLabelColor: AppColors.textSecondary,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                      tabs: [
                        Tab(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.receipt_rounded, size: 13),
                                const SizedBox(width: 5),
                                Text('Vouchers (${filteredVouchers.length})'),
                              ],
                            ),
                          ),
                        ),
                        Tab(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.inventory_2_outlined, size: 13),
                                const SizedBox(width: 5),
                                Text('Unsold Returns (${filteredUnsold.length})'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 14),

                  // Party Filter Dropdown
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: _selectedPartyFilter == 'All Parties' ? AppColors.surfaceContainerLow : const Color(0xFF1E1B4B),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _selectedPartyFilter == 'All Parties' ? AppColors.border : Colors.cyanAccent,
                        width: _selectedPartyFilter == 'All Parties' ? 1.0 : 1.5,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _availableParties.contains(_selectedPartyFilter) || _selectedPartyFilter == 'All Parties'
                            ? _selectedPartyFilter
                            : 'All Parties',
                        dropdownColor: AppColors.surfaceContainerHighest,
                        icon: Icon(Icons.person, color: _selectedPartyFilter == 'All Parties' ? AppColors.primary : Colors.cyanAccent, size: 15),
                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 11),
                        items: <String>{
                          'All Parties',
                          ..._availableParties,
                          ...voucherState.vouchers.map((v) => v.partyName.trim()).where((p) => p.isNotEmpty),
                          ...unsoldState.unsoldList.map((u) => u.partyName.trim()).where((p) => p.isNotEmpty),
                        }.map<DropdownMenuItem<String>>((p) {
                          return DropdownMenuItem<String>(
                            value: p,
                            child: Text(p == 'All Parties' ? '👥 All Parties' : '👤 $p'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedPartyFilter = val;
                              if (val != 'All Parties') {
                                _vPartyCtrl.text = val;
                                _uPartyCtrl.text = val;
                              }
                            });
                            _loadDataForCurrentFilters();
                          }
                        },
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Shift Selector
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedShift,
                        dropdownColor: AppColors.surfaceContainerHighest,
                        icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary, size: 16),
                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 11),
                        items: _shiftList.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedShift = val);
                            _loadDataForCurrentFilters();
                          }
                        },
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Series Filter Dropdown
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: _selectedSeriesFilter != 'All Series' ? const Color(0xFF1E1B4B) : AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _selectedSeriesFilter != 'All Series' ? const Color(0xFFFBBF24) : AppColors.border,
                        width: _selectedSeriesFilter != 'All Series' ? 1.5 : 1.0,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: availableSeries.contains(_selectedSeriesFilter) ? _selectedSeriesFilter : 'All Series',
                        dropdownColor: AppColors.surfaceContainerHighest,
                        icon: Icon(
                          Icons.tune_rounded,
                          color: _selectedSeriesFilter != 'All Series' ? const Color(0xFFFBBF24) : AppColors.primary,
                          size: 15,
                        ),
                        style: TextStyle(
                          color: _selectedSeriesFilter != 'All Series' ? const Color(0xFFFBBF24) : AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                        items: availableSeries.map((ser) {
                          return DropdownMenuItem<String>(
                            value: ser,
                            child: Text(ser == 'All Series' ? '🎲 All Series' : 'Ser $ser'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedSeriesFilter = val;
                              if (val != 'All Series') {
                                _vSeriesCtrl.text = val;
                                _uSeriesCtrl.text = val;
                                _updateVoucherRate(val);
                              }
                            });
                          }
                        },
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Date Picker
                  InkWell(
                    onTap: () => _selectDate(context),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today, size: 12, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(dateDisplayStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textPrimary)),
                        ],
                      ),
                    ),
                  ),

                  // 📁 GET FILE Reports Button
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 32,
                    child: ElevatedButton.icon(
                      onPressed: _openGetFileHisabDialog,
                      icon: const Icon(Icons.folder_shared_rounded, size: 14),
                      label: const Text('GET FILE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),

                  // 🗑️ DELETE ALL DATA Button
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 32,
                    child: ElevatedButton.icon(
                      onPressed: () => _showDeleteAllDataDialog(),
                      icon: const Icon(Icons.delete_sweep_rounded, size: 15),
                      label: const Text('DELETE ALL DATA', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.3)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 🌟 Full-Width Live Net Reconciliation Bar (Zero Overflow, Party-Filtered)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: _selectedPartyFilter == 'All Parties' ? const Color(0xFF0F172A) : const Color(0xFF0C192E),
              border: Border(
                bottom: BorderSide(
                  color: _selectedPartyFilter == 'All Parties' ? const Color(0xFF1E293B) : Colors.cyanAccent.withAlpha(80),
                  width: _selectedPartyFilter == 'All Parties' ? 1.0 : 1.5,
                ),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_selectedPartyFilter != 'All Parties') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.cyanAccent.withAlpha(120)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person, size: 12, color: Colors.cyanAccent),
                          const SizedBox(width: 4),
                          Text(
                            'SELLER: $_selectedPartyFilter',
                            style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  _buildMiniPill('Issued Stock', '$issuedTickets Nos (₹${issuedAmount.toStringAsFixed(2)})', Colors.cyanAccent),
                  const SizedBox(width: 14),
                  const Text('—', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 14),
                  _buildMiniPill('Unsold Return', '$unsoldTickets Nos (-₹${unsoldAmount.toStringAsFixed(2)})', const Color(0xFFF87171)),
                  const SizedBox(width: 14),
                  const Text('=', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 14),
                  _buildMiniPill('Net Sold', '$netSoldTickets Nos', const Color(0xFF4ADE80)),
                  const SizedBox(width: 14),
                  Container(width: 1, height: 16, color: Colors.grey.shade700),
                  const SizedBox(width: 14),
                  _buildMiniPill('Net Billable', '₹${netAmount >= 0 ? netAmount.toStringAsFixed(2) : '0.00'}', Colors.amberAccent),
                ],
              ),
            ),
          ),

          // 2. Tab Views (Voucher & Unsold)
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: [
                    _buildVoucherTab(filteredVouchers, availableSeries),
                    _buildUnsoldTab(filteredUnsold, availableSeries),
                  ],
                ),

                // Floating Interactive Dock Bar (Allows 100% background work when minimized)
                if (GeminiScannerService.instance.lastStockScanSession != null)
                  Positioned(
                    right: 24,
                    bottom: 16,
                    child: _buildFloatingScanDock(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingScanDock() {
    final session = GeminiScannerService.instance.lastStockScanSession;
    if (session == null) return const SizedBox.shrink();

    final isVoucher = session.isVoucher;
    final totalQty = session.items.fold<int>(0, (sum, it) => sum + it.quantity);
    final totalAmt = session.items.fold<double>(0.0, (sum, it) => sum + it.amount);
    final primaryColor = isVoucher ? const Color(0xFF3B82F6) : const Color(0xFFEF4444);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1120),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primaryColor.withAlpha(160), width: 1.5),
          boxShadow: [
            BoxShadow(color: primaryColor.withAlpha(80), blurRadius: 18, spreadRadius: 1),
            BoxShadow(color: Colors.black.withAlpha(220), blurRadius: 20, spreadRadius: 4),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: primaryColor.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.document_scanner_rounded, color: primaryColor, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isVoucher ? 'AI Voucher Scan (Minimized)' : 'AI Unsold Scan (Minimized)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF166534).withAlpha(100),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xFF4ADE80).withAlpha(120)),
                      ),
                      child: const Text('Background Active', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 8.5, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${session.items.length} Ranges • $totalQty Tickets • ₹${totalAmt >= 100000 ? '${(totalAmt / 100000).toStringAsFixed(1)}L' : totalAmt.toStringAsFixed(0)}',
                  style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w600, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(width: 14),
            ElevatedButton.icon(
              onPressed: () async {
                await _reopenLastScan();
                setState(() {});
              },
              icon: const Icon(Icons.open_in_full_rounded, size: 13),
              label: const Text('OPEN REVIEW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                elevation: 4,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Discard Scan',
              icon: const Icon(Icons.close, size: 16, color: Colors.white54),
              onPressed: () {
                setState(() {
                  GeminiScannerService.instance.lastStockScanSession = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildMiniPill(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11.5)),
      ],
    );
  }

  Widget _buildSellerFilterBar(
    List<String> activeParties,
    Map<String, int> partyStockMap,
    List<String> availableSeries,
  ) {
    // 🛡️ STRICT RULE: Only show parties that actually have data for this date & shift!
    final allParties = activeParties.where((p) => p.trim().isNotEmpty).toSet().toList()..sort();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(bottom: BorderSide(color: Color(0xFF334155))),
      ),
      child: Row(
        children: [
          const Icon(Icons.people_alt_outlined, size: 14, color: Colors.cyanAccent),
          const SizedBox(width: 6),
          const Text('Filter by Seller:', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // ALL PARTIES CHIP
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedPartyFilter = 'All Parties';
                        });
                        _loadDataForCurrentFilters();
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _selectedPartyFilter == 'All Parties' ? AppColors.primary : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _selectedPartyFilter == 'All Parties' ? AppColors.primary : const Color(0xFF334155),
                          ),
                        ),
                        child: Text(
                          '👥 ALL PARTIES',
                          style: TextStyle(
                            color: _selectedPartyFilter == 'All Parties' ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // INDIVIDUAL SELLER CHIPS
                  ...allParties.map((pName) {
                    final isSelected = _selectedPartyFilter.trim().toLowerCase() == pName.trim().toLowerCase();
                    final stock = partyStockMap[pName];
                    final stockStr = stock != null ? ' ($stock Nos)' : '';

                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedPartyFilter = pName;
                            _vPartyCtrl.text = pName;
                            _uPartyCtrl.text = pName;
                          });
                          _loadDataForCurrentFilters();
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.cyanAccent : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSelected ? Colors.cyanAccent : const Color(0xFF334155),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person, size: 11, color: isSelected ? Colors.black : Colors.cyanAccent),
                              const SizedBox(width: 4),
                              Text(
                                '$pName$stockStr',
                                style: TextStyle(
                                  color: isSelected ? Colors.black : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                   }),
                ],
              ),
            ),
          ),
          if (_selectedPartyFilter != 'All Parties')
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedPartyFilter = 'All Parties';
                  });
                  _loadDataForCurrentFilters();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.amberAccent.withAlpha(100)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close, size: 11, color: Colors.amberAccent),
                      SizedBox(width: 3),
                      Text('Show All', style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),

          // Series Quick Filter chips in the toolbar
          if (availableSeries.length > 1) ...[
            Container(width: 1, height: 16, color: const Color(0xFF334155), margin: const EdgeInsets.symmetric(horizontal: 8)),
            const Text('SERIES:', style: TextStyle(color: Colors.grey, fontSize: 10.5, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            ...availableSeries.take(6).map((ser) {
              final isSel = _selectedSeriesFilter == ser;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedSeriesFilter = ser;
                      if (ser != 'All Series') {
                        _vSeriesCtrl.text = ser;
                        _uSeriesCtrl.text = ser;
                        _updateVoucherRate(ser);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: isSel ? const Color(0xFF7C3AED) : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSel ? const Color(0xFFA78BFA) : const Color(0xFF334155),
                      ),
                    ),
                    child: Text(
                      ser == 'All Series' ? 'ALL' : 'Ser $ser',
                      style: TextStyle(
                        color: isSel ? Colors.white : Colors.grey.shade400,
                        fontSize: 10,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // --- SUB TAB 1: VOUCHER ---
  Widget _buildVoucherTab(List<VoucherModel> vouchers, List<String> availableSeries) {
    final partyStockMap = <String, int>{};
    for (final v in vouchers) {
      final name = v.partyName.trim();
      if (name.isNotEmpty) {
        partyStockMap[name] = (partyStockMap[name] ?? 0) + v.totalQty.toInt();
      }
    }
    final voucherParties = partyStockMap.keys.toList();

    return Column(
      children: [
        // Quick Seller Filter Bar
        _buildSellerFilterBar(voucherParties, partyStockMap, availableSeries),
        // Fast Keyboard Voucher Issue Entry Bar
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Party / Seller
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Party / Seller Name *', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _vPartyCtrl,
                        focusNode: _vPartyFocusNode,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12.5),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'e.g. Wakil / Raju',
                          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          prefixIcon: const Icon(Icons.person_outline, size: 14, color: AppColors.primary),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                        ),
                        onSubmitted: (_) => _vSeriesFocusNode.requestFocus(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Series
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Series *', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _vSeriesCtrl,
                        focusNode: _vSeriesFocusNode,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12.5),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Ser ($_lastUsedVoucherSeries)',
                          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.5)),
                        ),
                        onChanged: (val) => _updateVoucherRate(val),
                        onSubmitted: (val) {
                          final s = val.trim().isNotEmpty ? val.trim().toUpperCase() : _lastUsedVoucherSeries;
                          _lastUsedVoucherSeries = s;
                          _vSeriesCtrl.text = s;
                          _vFromFocusNode.requestFocus();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // From 5-Digits
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('From (5-Digits) *', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _vFromCtrl,
                        focusNode: _vFromFocusNode,
                        maxLength: 5,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(5),
                        ],
                        style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          counterText: '',
                          hintText: 'e.g. 28301',
                          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF4ADE80), width: 1.5)),
                        ),
                        onSubmitted: (_) {
                          if (_vToCtrl.text.isNotEmpty) {
                            _addVoucher();
                          } else {
                            _vToFocusNode.requestFocus();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // To Range End
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('To (Range End)', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _vToCtrl,
                        focusNode: _vToFocusNode,
                        maxLength: 5,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(5),
                        ],
                        style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          counterText: '',
                          hintText: 'e.g. 400 / 28400',
                          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.amberAccent, width: 1.5)),
                        ),
                        onSubmitted: (_) => _addVoucher(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Rate
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Rate (₹)', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _vRateCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixText: '₹',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Add Voucher Button
              SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  onPressed: _addVoucher,
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text('ADD VOUCHER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Scan Voucher Parcha with AI Button
              SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  onPressed: () => _scanParchaImage(StockScanMode.voucher),
                  icon: const Icon(Icons.document_scanner, size: 14),
                  label: const Text('SCAN VOUCHER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),

              // Paste Voucher Text Button
              const SizedBox(width: 8),
              SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  onPressed: () => _openPasteTextParser(StockScanMode.voucher),
                  icon: const Icon(Icons.paste_rounded, size: 14),
                  label: const Text('PASTE TEXT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),

              // Export Vouchers Button
              const SizedBox(width: 8),
              SizedBox(
                height: 34,
                child: OutlinedButton.icon(
                  onPressed: () => _exportVouchersToCsv(vouchers),
                  icon: const Icon(Icons.file_download_outlined, size: 14, color: Color(0xFF38BDF8)),
                  label: const Text('EXPORT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: Color(0xFF38BDF8), letterSpacing: 0.5)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                    backgroundColor: const Color(0xFF0C2433),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),

              // Re-open Last Scan Button (recovers scanned parcha if closed)
              if (GeminiScannerService.instance.lastStockScanSession != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 34,
                  child: OutlinedButton.icon(
                    onPressed: _reopenLastScan,
                    icon: const Icon(Icons.history_rounded, size: 14, color: Color(0xFF38BDF8)),
                    label: const Text('RE-OPEN SCAN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF38BDF8), letterSpacing: 0.5)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                      backgroundColor: const Color(0xFF0C2433),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
              ],

              // Delete All Vouchers Button
              const SizedBox(width: 8),
              SizedBox(
                height: 34,
                child: OutlinedButton.icon(
                  onPressed: () => _showDeleteAllDataDialog(defaultToVouchersOnly: true),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 14, color: Colors.redAccent),
                  label: const Text('DELETE ALL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: Colors.redAccent, letterSpacing: 0.3)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent, width: 1.2),
                    backgroundColor: const Color(0xFF2A0D0D),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Voucher List Table
        Expanded(
          child: vouchers.isEmpty
              ? _buildEmptyPlaceholder(
                  icon: Icons.receipt_long_outlined,
                  title: 'No Stock Issue Vouchers Found',
                  subtitle: 'No vouchers match the current series/seller/shift filters.',
                )
              : _buildVoucherTable(vouchers),
        ),
      ],
    );
  }

  Widget _buildVoucherTable(List<VoucherModel> list) {
    final allSelected = list.isNotEmpty && list.every((v) => _selectedVoucherIds.contains(v.id));

    return Container(
      color: AppColors.bgPrimary,
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                // Select All Checkbox
                SizedBox(
                  width: 32,
                  child: Checkbox(
                    value: allSelected,
                    activeColor: AppColors.primary,
                    checkColor: Colors.black,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedVoucherIds.addAll(list.map((v) => v.id));
                        } else {
                          _selectedVoucherIds.clear();
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 30, child: Text('#', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const Expanded(flex: 2, child: Text('VOUCHER NO', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const Expanded(flex: 3, child: Text('PARTY / SELLER', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const Expanded(flex: 2, child: Text('SERIES', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const Expanded(flex: 3, child: Text('ISSUED RANGE', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const Expanded(flex: 2, child: Text('QTY (NOS)', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const Expanded(flex: 2, child: Text('RATE', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const Expanded(flex: 2, child: Text('TOTAL (₹)', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const SizedBox(width: 50, child: Center(child: Text('ACTION', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11)))),
              ],
            ),
          ),

          // Table Rows
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.border),
              itemBuilder: (ctx, idx) {
                final v = list[idx];
                final rangeDisplay = v.fromTicket == v.toTicket ? v.fromTicket : '${v.fromTicket} ➔ ${v.toTicket}';
                final isChecked = _selectedVoucherIds.contains(v.id);

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  color: isChecked
                      ? Colors.indigoAccent.withAlpha(40)
                      : (idx % 2 == 0 ? Colors.transparent : const Color(0xFF161A30).withAlpha(60)),
                  child: Row(
                    children: [
                      // Row Checkbox
                      SizedBox(
                        width: 32,
                        child: Checkbox(
                          value: isChecked,
                          activeColor: AppColors.primary,
                          checkColor: Colors.black,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedVoucherIds.add(v.id);
                              } else {
                                _selectedVoucherIds.remove(v.id);
                              }
                            });
                          },
                        ),
                      ),
                      SizedBox(width: 30, child: Text('${idx + 1}', style: const TextStyle(color: Colors.grey, fontSize: 11))),
                      Expanded(
                        flex: 2,
                        child: Text(v.voucherNo, style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11.5, fontFamily: 'monospace')),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(v.partyName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6B21A8).withAlpha(80),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('Ser ${v.series}', style: const TextStyle(color: Color(0xFFC084FC), fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(rangeDisplay, style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('${v.totalQty} Nos', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('₹${v.pricePerTicket.toStringAsFixed(2)}', style: const TextStyle(color: Colors.grey, fontSize: 11.5)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('₹${v.totalAmount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      SizedBox(
                        width: 50,
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                          tooltip: 'Delete Voucher',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                backgroundColor: const Color(0xFF1E293B),
                                title: const Text('Delete Voucher?', style: TextStyle(color: Colors.white)),
                                content: Text('Are you sure you want to remove Voucher #${v.voucherNo}?', style: const TextStyle(color: Colors.grey)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              ref.read(voucherViewModelProvider.notifier).deleteVoucher(v.id);
                              setState(() => _selectedVoucherIds.remove(v.id));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Bulk Action Toolbar for Vouchers
          _buildBulkActionBar(true, _selectedVoucherIds.length),
        ],
      ),
    );
  }

  // --- SUB TAB 2: UNSOLD ---
  Widget _buildUnsoldTab(List<UnsoldModel> unsoldList, List<String> availableSeries) {
    final voucherState = ref.watch(voucherViewModelProvider);
    final partyStockMap = <String, int>{};
    for (final v in voucherState.vouchers) {
      final name = v.partyName.trim();
      if (name.isNotEmpty) {
        partyStockMap[name] = (partyStockMap[name] ?? 0) + v.totalQty.toInt();
      }
    }
    for (final u in unsoldList) {
      final name = u.partyName.trim();
      if (name.isNotEmpty && !partyStockMap.containsKey(name)) {
        partyStockMap[name] = 0;
      }
    }
    final activeParties = partyStockMap.keys.toList()..sort();

    return Column(
      children: [
        // Quick Seller Filter Bar (Only parties with data!)
        _buildSellerFilterBar(activeParties, partyStockMap, availableSeries),

        // Fast Keyboard Unsold Return Entry Bar
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Party / Seller
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Party / Seller Name *', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _uPartyCtrl,
                        focusNode: _uPartyFocusNode,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12.5),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'e.g. Wakil / Raju',
                          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          prefixIcon: const Icon(Icons.person_outline, size: 14, color: AppColors.primary),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                        ),
                        onSubmitted: (_) => _uSeriesFocusNode.requestFocus(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Series
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Series *', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _uSeriesCtrl,
                        focusNode: _uSeriesFocusNode,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12.5),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Ser ($_lastUsedUnsoldSeries)',
                          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.5)),
                        ),
                        onSubmitted: (val) {
                          final s = val.trim().isNotEmpty ? val.trim().toUpperCase() : _lastUsedUnsoldSeries;
                          _lastUsedUnsoldSeries = s;
                          _uSeriesCtrl.text = s;
                          _uFromFocusNode.requestFocus();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // From 5-Digits
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('From (5-Digits) *', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _uFromCtrl,
                        focusNode: _uFromFocusNode,
                        maxLength: 5,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(5),
                        ],
                        style: const TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          counterText: '',
                          hintText: 'e.g. 28381',
                          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFF87171), width: 1.5)),
                        ),
                        onSubmitted: (_) {
                          if (_uToCtrl.text.isNotEmpty) {
                            _addUnsold();
                          } else {
                            _uToFocusNode.requestFocus();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // To Range End
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('To (Range End)', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _uToCtrl,
                        focusNode: _uToFocusNode,
                        maxLength: 5,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(5),
                        ],
                        style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          counterText: '',
                          hintText: 'e.g. 400 / 28400',
                          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.amberAccent, width: 1.5)),
                        ),
                        onSubmitted: (_) => _addUnsold(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Add Unsold Button
              SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  onPressed: _addUnsold,
                  icon: const Icon(Icons.remove_circle_outline, size: 15),
                  label: const Text('ADD UNSOLD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Scan Unsold Parcha with AI Button
              SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  onPressed: () => _scanParchaImage(StockScanMode.unsold),
                  icon: const Icon(Icons.document_scanner, size: 14),
                  label: const Text('SCAN UNSOLD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),

              // Paste Unsold Text Button
              const SizedBox(width: 8),
              SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  onPressed: () => _openPasteTextParser(StockScanMode.unsold),
                  icon: const Icon(Icons.paste_rounded, size: 14),
                  label: const Text('PASTE TEXT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),

              // Export Unsold Button
              const SizedBox(width: 8),
              SizedBox(
                height: 34,
                child: OutlinedButton.icon(
                  onPressed: () => _exportUnsoldToCsv(unsoldList),
                  icon: const Icon(Icons.file_download_outlined, size: 14, color: Color(0xFF38BDF8)),
                  label: const Text('EXPORT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: Color(0xFF38BDF8), letterSpacing: 0.5)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                    backgroundColor: const Color(0xFF0C2433),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),

              // Re-open Last Scan Button (recovers scanned parcha if closed)
              if (GeminiScannerService.instance.lastStockScanSession != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 34,
                  child: OutlinedButton.icon(
                    onPressed: _reopenLastScan,
                    icon: const Icon(Icons.history_rounded, size: 14, color: Color(0xFF38BDF8)),
                    label: const Text('RE-OPEN SCAN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF38BDF8), letterSpacing: 0.5)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                      backgroundColor: const Color(0xFF0C2433),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),

              // Lock Shift Button
              SizedBox(
                height: 34,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
                    await ref.read(unsoldViewModelProvider.notifier).lockShift(dateStr, _selectedShift);
                    _showSnack('🔒 Unsold Returns Locked for $_selectedShift!', AppColors.info);
                  },
                  icon: const Icon(Icons.lock_clock, size: 14),
                  label: const Text('LOCK SHIFT', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amberAccent,
                    side: const BorderSide(color: Colors.amberAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),

              // Delete All Unsold Button
              const SizedBox(width: 6),
              SizedBox(
                height: 34,
                child: OutlinedButton.icon(
                  onPressed: () => _showDeleteAllDataDialog(defaultToUnsoldOnly: true),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 14, color: Colors.redAccent),
                  label: const Text('DELETE ALL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: Colors.redAccent, letterSpacing: 0.3)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent, width: 1.2),
                    backgroundColor: const Color(0xFF2A0D0D),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Unsold List Table
        Expanded(
          child: unsoldList.isEmpty
              ? _buildEmptyPlaceholder(
                  icon: Icons.inventory_2_outlined,
                  title: 'No Unsold Returns Found',
                  subtitle: 'No unsold returns match the current series/seller/shift filters.',
                )
              : _buildUnsoldTable(unsoldList),
        ),
      ],
    );
  }

  Widget _buildUnsoldTable(List<UnsoldModel> list) {
    final allSelected = list.isNotEmpty && list.every((u) => _selectedUnsoldIds.contains(u.id));

    return Container(
      color: AppColors.bgPrimary,
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                // Select All Checkbox
                SizedBox(
                  width: 32,
                  child: Checkbox(
                    value: allSelected,
                    activeColor: Colors.redAccent,
                    checkColor: Colors.white,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedUnsoldIds.addAll(list.map((u) => u.id));
                        } else {
                          _selectedUnsoldIds.clear();
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 30, child: Text('#', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const Expanded(flex: 2, child: Text('RETURN NO', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const Expanded(flex: 3, child: Text('PARTY / SELLER', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const Expanded(flex: 2, child: Text('SERIES', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const Expanded(flex: 3, child: Text('RETURNED RANGE', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const Expanded(flex: 2, child: Text('QTY (NOS)', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const Expanded(flex: 2, child: Text('DEDUCTION (₹)', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const Expanded(flex: 2, child: Text('STATUS', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                const SizedBox(width: 50, child: Center(child: Text('ACTION', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11)))),
              ],
            ),
          ),

          // Table Rows
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.border),
              itemBuilder: (ctx, idx) {
                final u = list[idx];
                final rangeDisplay = u.fromTicket == u.toTicket ? u.fromTicket : '${u.fromTicket} ➔ ${u.toTicket}';
                final isChecked = _selectedUnsoldIds.contains(u.id);

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  color: isChecked
                      ? Colors.redAccent.withAlpha(40)
                      : (idx % 2 == 0 ? Colors.transparent : const Color(0xFF161A30).withAlpha(60)),
                  child: Row(
                    children: [
                      // Row Checkbox
                      SizedBox(
                        width: 32,
                        child: Checkbox(
                          value: isChecked,
                          activeColor: Colors.redAccent,
                          checkColor: Colors.white,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedUnsoldIds.add(u.id);
                              } else {
                                _selectedUnsoldIds.remove(u.id);
                              }
                            });
                          },
                        ),
                      ),
                      SizedBox(width: 30, child: Text('${idx + 1}', style: const TextStyle(color: Colors.grey, fontSize: 11))),
                      Expanded(
                        flex: 2,
                        child: Text(u.returnNo, style: const TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold, fontSize: 11.5, fontFamily: 'monospace')),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(u.partyName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6B21A8).withAlpha(80),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('Ser ${u.series}', style: const TextStyle(color: Color(0xFFC084FC), fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(rangeDisplay, style: const TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('${u.totalQty} Nos', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('-₹${u.totalAmount.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: u.isLocked ? Colors.amber.withAlpha(40) : Colors.green.withAlpha(40),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            u.isLocked ? '🔒 LOCKED' : '🟢 ACTIVE',
                            style: TextStyle(color: u.isLocked ? Colors.amberAccent : Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 10),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 50,
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                          tooltip: 'Delete Return',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                backgroundColor: const Color(0xFF1E293B),
                                title: const Text('Delete Unsold Record?', style: TextStyle(color: Colors.white)),
                                content: Text('Remove Return #${u.returnNo}?', style: const TextStyle(color: Colors.grey)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              ref.read(unsoldViewModelProvider.notifier).deleteUnsold(u.id);
                              setState(() => _selectedUnsoldIds.remove(u.id));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Bulk Action Toolbar for Unsold
          _buildBulkActionBar(false, _selectedUnsoldIds.length),
        ],
      ),
    );
  }

  Widget _buildEmptyPlaceholder({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: Colors.grey.shade600),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white70)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
