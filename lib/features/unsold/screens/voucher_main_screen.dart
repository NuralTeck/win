import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_service.dart';
import '../../settings/viewmodels/series_price_viewmodel.dart';
import '../../sellers/viewmodels/seller_customer_viewmodel.dart';
import '../../sellers/models/seller_customer_model.dart';
import '../../bookings/services/gemini_scanner_service.dart';
import '../models/voucher_model.dart';
import '../viewmodels/voucher_viewmodel.dart';
import '../widgets/ai_stock_scan_review_dialog.dart';
import '../widgets/raw_stock_text_parser_dialog.dart';
import '../widgets/searchable_dealer_picker_dialog.dart';

class VoucherMainScreen extends ConsumerStatefulWidget {
  const VoucherMainScreen({super.key});

  @override
  ConsumerState<VoucherMainScreen> createState() => _VoucherMainScreenState();
}

class _VoucherMainScreenState extends ConsumerState<VoucherMainScreen> {
  DateTime _selectedDate = DateTime.now();
  String _selectedShift = 'Dear 1 PM';
  final List<String> _shiftList = ['Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'];
  String _selectedPartyFilter = 'All Parties';
  String _selectedSeriesFilter = 'All Series';
  String _searchQuery = '';

  List<String> _availableDealers = [];
  Map<String, List<String>> _dealerToSellersMap = {};
  List<String> _availableParties = [];
  List<SellerCustomerModel>? _lastSyncedSellers;

  // Voucher Dealer Selection
  String? _selectedVoucherDealer;

  // Voucher Entry Controllers
  final TextEditingController _vPartyCtrl = TextEditingController();
  final TextEditingController _vSeriesCtrl = TextEditingController();
  final TextEditingController _vFromCtrl = TextEditingController();
  final TextEditingController _vToCtrl = TextEditingController();
  final TextEditingController _vRateCtrl = TextEditingController(text: '37.50');
  final TextEditingController _searchCtrl = TextEditingController();

  final FocusNode _vPartyFocusNode = FocusNode();
  final FocusNode _vSeriesFocusNode = FocusNode();
  final FocusNode _vFromFocusNode = FocusNode();
  final FocusNode _vToFocusNode = FocusNode();

  String _lastUsedVoucherSeries = '12';

  // Multi-Selection State
  final Set<String> _selectedVoucherIds = {};

  @override
  void initState() {
    super.initState();
    _vSeriesCtrl.text = _lastUsedVoucherSeries;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDataForCurrentFilters();
    });
  }

  @override
  void dispose() {
    _vPartyCtrl.dispose();
    _vSeriesCtrl.dispose();
    _vFromCtrl.dispose();
    _vToCtrl.dispose();
    _vRateCtrl.dispose();
    _searchCtrl.dispose();
    _vPartyFocusNode.dispose();
    _vSeriesFocusNode.dispose();
    _vFromFocusNode.dispose();
    _vToFocusNode.dispose();
    super.dispose();
  }

  void _loadDataForCurrentFilters() {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    ref.read(voucherViewModelProvider.notifier).loadVouchers(
          date: dateStr,
          drawShift: _selectedShift,
        );

    final sellers = ref.read(sellerCustomerViewModelProvider).sellers;
    if (sellers.isEmpty) {
      ref.read(sellerCustomerViewModelProvider.notifier).loadSellers();
    } else {
      _syncDealersFromSellers(sellers);
    }
  }

  void _syncDealersFromSellers(List<SellerCustomerModel> sellers) {
    if (identical(_lastSyncedSellers, sellers) && _availableDealers.isNotEmpty) {
      return;
    }
    _lastSyncedSellers = sellers;

    final dealers = <String>[];
    final dToS = <String, List<String>>{};
    final allParties = <String>{};

    for (final s in sellers) {
      final name = s.name.trim();
      if (name.isEmpty) continue;
      allParties.add(name);
      if (s.isDealer) {
        dealers.add(name);
        dToS[name] = [];
        dToS[name.toLowerCase()] = [];
      }
    }
    dealers.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    for (final s in sellers) {
      final name = s.name.trim();
      if (name.isEmpty || s.isDealer) continue;
      final parent = (s.parentDealer ?? '').trim();
      if (parent.isNotEmpty) {
        if (dToS.containsKey(parent)) {
          dToS[parent]!.add(name);
        }
        final pLower = parent.toLowerCase();
        if (dToS.containsKey(pLower) && pLower != parent) {
          dToS[pLower]!.add(name);
        }
      }
    }

    for (final list in dToS.values) {
      list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }

    _availableDealers = dealers;
    _dealerToSellersMap = dToS;
    _availableParties = allParties.toList()..sort();
  }

  void _refreshAvailableParties() {
    final sellers = ref.read(sellerCustomerViewModelProvider).sellers;
    if (sellers.isNotEmpty) {
      setState(() {
        _syncDealersFromSellers(sellers);
      });
    } else {
      ref.read(sellerCustomerViewModelProvider.notifier).loadSellers();
    }
  }

  Future<void> _openSearchableDealerPicker({
    required BuildContext context,
    required String? selectedDealer,
    required ValueChanged<String?> onSelected,
    String title = 'Select Dealer',
    bool allowAllOption = false,
    String allOptionLabel = '🏢 All Dealers / Direct',
    String allOptionValue = 'All Dealers',
  }) async {
    final sellers = ref.read(sellerCustomerViewModelProvider).sellers;
    if (sellers.isNotEmpty && (_availableDealers.isEmpty || _dealerToSellersMap.isEmpty)) {
      _syncDealersFromSellers(sellers);
    }

    final chosen = await SearchableDealerPickerDialog.show(
      context: context,
      dealers: _availableDealers,
      dealerToSellersMap: _dealerToSellersMap,
      selectedDealer: selectedDealer,
      title: title,
      allowAllOption: allowAllOption,
      allOptionLabel: allOptionLabel,
      allOptionValue: allOptionValue,
    );

    if (chosen != null) {
      onSelected(chosen == allOptionValue ? null : chosen);
    }
  }

  double _getPriceForSeries(String series) {
    final state = ref.read(seriesPriceViewModelProvider);
    return state.getPriceForSeries(series);
  }

  void _updateVoucherRate(String series) {
    final price = _getPriceForSeries(series.trim().toUpperCase());
    _vRateCtrl.text = price.toStringAsFixed(2);
  }

  ({String from, String to, int qty}) _resolveRange(String rawFrom, String rawTo) {
    String f = rawFrom.trim();
    String t = rawTo.trim();

    if (f.contains('-')) {
      final parts = f.split('-').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        f = parts[0];
        if (t.isEmpty && parts.length >= 2) {
          if (parts.length == 2 && parts[1] == '1') {
            t = f;
          } else {
            t = parts[1];
          }
        }
      }
    }

    if (t.contains('-')) {
      final parts = t.split('-').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        t = parts[0];
      }
    }

    if (t.isNotEmpty && t.length < 5 && f.length == 5) {
      t = f.substring(0, 5 - t.length) + t;
    } else if (t.isEmpty) {
      t = f;
    }

    final start = int.tryParse(f);
    final end = int.tryParse(t);
    int qty = 1;
    if (start != null && end != null && end >= start) {
      qty = (end - start) + 1;
    }

    return (from: f, to: t, qty: qty);
  }

  Set<String> _expandTicketRange(String from, String to) {
    final r = _resolveRange(from, to);
    final start = int.tryParse(r.from);
    final end = int.tryParse(r.to);

    if (start == null) return {r.from};
    if (end == null || end < start) return {r.from.padLeft(5, '0')};
    final count = end - start + 1;
    if (count > 1000) return {r.from.padLeft(5, '0')};

    final set = <String>{};
    for (int i = start; i <= end; i++) {
      set.add(i.toString().padLeft(5, '0'));
    }
    return set;
  }

  Future<void> _addVoucher() async {
    if (_selectedVoucherDealer == null || _selectedVoucherDealer!.isEmpty) {
      _showSnack('⚠️ Set First Dealer! Please select a Main Dealer before entering vouchers.', AppColors.warning);
      return;
    }

    final party = _vPartyCtrl.text.trim();
    if (party.isEmpty) {
      _showSnack('Please select or enter Sub-Seller / Party Name!', AppColors.warning);
      _vPartyFocusNode.requestFocus();
      return;
    }

    final series = _vSeriesCtrl.text.trim().isNotEmpty
        ? _vSeriesCtrl.text.trim().toUpperCase()
        : _lastUsedVoucherSeries;
    _lastUsedVoucherSeries = series;
    _vSeriesCtrl.text = series;

    final resolved = _resolveRange(_vFromCtrl.text, _vToCtrl.text);
    final from = resolved.from;
    final to = resolved.to;
    final qty = resolved.qty;

    if (from.isEmpty || from.length != 5 || int.tryParse(from) == null) {
      _showSnack('From Number must be an exact 5-digit number (e.g. 28301)!', AppColors.warning);
      _vFromFocusNode.requestFocus();
      return;
    }

    final newTickets = _expandTicketRange(from, to);
    final voucherState = ref.read(voucherViewModelProvider);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // Duplicate Check: Same party in this shift
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

    // Also check SQLite DB
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

    final rate = double.tryParse(_vRateCtrl.text.trim()) ?? _getPriceForSeries(series);
    final total = qty * rate;

    final now = DateTime.now();
    final voucherNo = 'VOUCH-${DateFormat('HHmmss').format(now)}';
    final dealerName = await DatabaseService.instance.getParentDealerForParty(party);

    final voucher = VoucherModel(
      id: 'vouch_${now.microsecondsSinceEpoch}',
      voucherNo: voucherNo,
      date: dateStr,
      drawShift: _selectedShift,
      partyName: party,
      dealerName: dealerName,
      series: series,
      fromTicket: from,
      toTicket: to,
      totalQty: qty,
      pricePerTicket: rate,
      totalAmount: total,
      createdAt: now,
    );

    final success = await ref.read(voucherViewModelProvider.notifier).addVoucher(voucher);
    if (success) {
      _vFromCtrl.clear();
      _vToCtrl.clear();
      _vFromFocusNode.requestFocus();

      if (_selectedPartyFilter != 'All Parties' && _selectedPartyFilter != party) {
        setState(() {
          _selectedPartyFilter = 'All Parties';
        });
        _loadDataForCurrentFilters();
      } else {
        _refreshAvailableParties();
      }

      _showSnack('✅ Added Voucher #$voucherNo ($qty Tickets | ₹${total.toStringAsFixed(2)})', AppColors.success);
    }
  }

  Future<void> _scanParchaImage() async {
    if (_selectedVoucherDealer == null || _selectedVoucherDealer!.isEmpty) {
      _showSnack('⚠️ Set First Dealer! Please select a Main Dealer before scanning vouchers.', AppColors.warning);
      return;
    }

    final currentParty = _vPartyCtrl.text.trim();
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
            : 'Scanning Voucher Parcha with AI...',
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
            scanContext: ScanContext.voucher,
          );
          for (final t in tickets) {
            t.photoIndex = i;
          }
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

      final detectedShift = GeminiScannerService.instance.lastDetectedShift;
      final effectiveShift = (detectedShift != null && detectedShift.isNotEmpty) ? detectedShift : _selectedShift;

      final detectedParty = GeminiScannerService.instance.lastDetectedParty;
      final effectiveParty = (detectedParty != null && detectedParty.isNotEmpty) ? detectedParty : targetParty;

      GeminiScannerService.instance.lastStockScanSession = LastStockScanSession(
        imageBytes: fileBytes,
        allFilesBytes: allFilesBytes,
        items: scannedTickets,
        isVoucher: true,
        activeShift: effectiveShift,
        activeDate: _selectedDate,
        defaultParty: effectiveParty,
        aiConfusions: GeminiScannerService.instance.lastAiConfusions,
      );

      final saved = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: Colors.black.withAlpha(150),
        builder: (ctx) => AiStockScanReviewDialog(
          imageBytes: fileBytes,
          allImageBytes: allFilesBytes,
          initialItems: scannedTickets,
          mode: StockScanMode.voucher,
          activeShift: effectiveShift,
          activeDate: _selectedDate,
          defaultParty: effectiveParty,
        ),
      );

      if (saved == true && mounted) {
        GeminiScannerService.instance.lastStockScanSession = null;
        _selectedSeriesFilter = 'All Series';
        _selectedPartyFilter = 'All Parties';
        if (effectiveShift.isNotEmpty && _shiftList.contains(effectiveShift)) {
          _selectedShift = effectiveShift;
        }
        setState(() {});
        _loadDataForCurrentFilters();
        _showSnack('✅ Vouchers scanned & saved successfully!', AppColors.success);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error picking image: $e', AppColors.error);
      }
    }
  }

  Future<void> _openPasteTextParser() async {
    if (_selectedVoucherDealer == null || _selectedVoucherDealer!.isEmpty) {
      _showSnack('⚠️ Set First Dealer! Please select a Main Dealer before pasting vouchers.', AppColors.warning);
      return;
    }

    final currentParty = _vPartyCtrl.text.trim();
    final defaultParty = currentParty.isNotEmpty ? currentParty : 'Walk-in Party';

    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha(150),
      builder: (ctx) => RawStockTextParserDialog(
        mode: StockScanMode.voucher,
        activeShift: _selectedShift,
        activeDate: _selectedDate,
        defaultParty: defaultParty,
      ),
    );

    if (saved == true && mounted) {
      _selectedSeriesFilter = 'All Series';
      _selectedPartyFilter = 'All Parties';
      setState(() {});
      _loadDataForCurrentFilters();
      _showSnack('✅ Vouchers parsed & saved successfully!', AppColors.success);
    }
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
      buffer.writeln('SL,Date,Shift,Party Name,Dealer,Series,Ticket Range,From Ticket,To Ticket,Quantity,Rate,Total Amount,Created At');

      for (int i = 0; i < list.length; i++) {
        final v = list[i];
        buffer.writeln(
          '${i + 1},"${v.date}","${v.drawShift}","${v.partyName}","${v.effectiveDealer}","${v.series}","${v.series}-${v.fromTicket.padLeft(5, '0')} to ${v.toTicket.padLeft(5, '0')}","${v.fromTicket}","${v.toTicket}",${v.totalQty},${v.pricePerTicket},${v.totalAmount},"${DateFormat('yyyy-MM-dd HH:mm').format(v.createdAt)}"',
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

  Future<void> _openBulkUpdatePartyDialog() async {
    if (_selectedVoucherIds.isEmpty) return;

    final sellerState = ref.read(sellerCustomerViewModelProvider);
    final voucherState = ref.read(voucherViewModelProvider);

    final recentParties = <String>{
      ...sellerState.sellers.map((s) => s.name.trim()).where((n) => n.isNotEmpty),
      ...voucherState.vouchers.map((v) => v.partyName.trim()).where((p) => p.isNotEmpty),
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
                    'Update Party Name (${_selectedVoucherIds.length} Selected)',
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
      final count = _selectedVoucherIds.length;
      final idsList = _selectedVoucherIds.toList();
      final success = await ref.read(voucherViewModelProvider.notifier).bulkUpdateParty(idsList, newParty);

      if (success) {
        setState(() {
          _selectedVoucherIds.clear();
        });
        _loadDataForCurrentFilters();
        _showSnack('✅ Updated Party Name to "$newParty" for $count voucher(s)!', AppColors.success);
      } else {
        _showSnack('❌ Error updating party name.', AppColors.error);
      }
    }
  }

  Future<void> _openBulkUpdateSeriesDialog() async {
    if (_selectedVoucherIds.isEmpty) return;

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
                    'Change Series (${_selectedVoucherIds.length} Selected)',
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
      final count = _selectedVoucherIds.length;
      final idsList = _selectedVoucherIds.toList();
      final newRate = _getPriceForSeries(newSeries);
      final success = await ref.read(voucherViewModelProvider.notifier).bulkUpdateSeries(idsList, newSeries, newRate);

      if (success) {
        setState(() {
          _selectedVoucherIds.clear();
        });
        _loadDataForCurrentFilters();
        _showSnack('✅ Changed Series to "Ser $newSeries" (Rate ₹${newRate.toStringAsFixed(2)}) for $count voucher(s)!', AppColors.success);
      } else {
        _showSnack('❌ Error changing series.', AppColors.error);
      }
    }
  }

  Future<void> _confirmBulkDelete() async {
    if (_selectedVoucherIds.isEmpty) return;

    final count = _selectedVoucherIds.length;
    final idsToDelete = _selectedVoucherIds.toList();

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
          'Are you sure you want to permanently delete $count selected voucher(s)?\nThis action cannot be undone.',
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('DELETE ALL SELECTED'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(voucherViewModelProvider.notifier).bulkDelete(idsToDelete);
      setState(() {
        _selectedVoucherIds.clear();
      });
      _loadDataForCurrentFilters();
      _showSnack('🗑️ Successfully deleted $count voucher(s)!', AppColors.success);
    }
  }

  Future<void> _showDeleteAllVouchersDialog() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final dateDisplayStr = DateFormat('dd-MM-yyyy').format(_selectedDate);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
                Text('Delete All Vouchers', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Clear stock vouchers for this shift', style: TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ],
        ),
        content: Text(
          'Target Date: $dateDisplayStr\nShift: $_selectedShift\n\nThis will permanently delete all stock vouchers for this date and shift. Continue?',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('DELETE ALL VOUCHERS', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref.read(voucherViewModelProvider.notifier).deleteAll(
            date: dateStr,
            drawShift: _selectedShift,
          );
      if (success) {
        setState(() {
          _selectedVoucherIds.clear();
        });
        _loadDataForCurrentFilters();
        _showSnack('🗑️ All vouchers cleared for $dateDisplayStr ($_selectedShift)!', AppColors.success);
      } else {
        _showSnack('❌ Error clearing vouchers.', AppColors.error);
      }
    }
  }

  Future<void> _showRecalculateVoucherRatesDialog() async {
    final now = DateTime.now();
    final seriesState = ref.read(seriesPriceViewModelProvider);
    final base100 = seriesState.series100Price;
    final perUnit = seriesState.perUnitRate;

    // Date Mode & Values
    String selectedDateMode = 'single'; // 'single', 'range', 'all'
    DateTime individualDate = _selectedDate;
    DateTimeRange? customRange;

    // Filters & Processing
    String selectedParty = _selectedPartyFilter;
    bool isAllPartiesSelected = true;
    final Set<String> selectedParties = {};
    String partySearchQuery = '';
    final TextEditingController partySearchCtrl = TextEditingController();
    String selectedShift = _selectedShift;
    bool isProcessing = false;

    // Active Parties State
    bool isLoadingParties = true;
    bool hasInitialized = false;
    bool showAllRegisteredParties = false;
    List<String> activePartiesOnDate = [];

    final sellers = ref.read(sellerCustomerViewModelProvider).sellers;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          // Helper to fetch parties who actually have entries on selected date/range
          Future<void> refreshActiveParties() async {
            setDialogState(() => isLoadingParties = true);
            String? targetDate;
            String? startDateStr;
            String? endDateStr;

            if (selectedDateMode == 'single') {
              targetDate = DateFormat('yyyy-MM-dd').format(individualDate);
            } else if (selectedDateMode == 'range' && customRange != null) {
              startDateStr = DateFormat('yyyy-MM-dd').format(customRange!.start);
              endDateStr = DateFormat('yyyy-MM-dd').format(customRange!.end);
            }

            final list = await DatabaseService.instance.getActivePartiesForSelection(
              date: targetDate,
              startDate: startDateStr,
              endDate: endDateStr,
              drawShift: selectedShift == 'All Shifts' ? null : selectedShift,
            );

            if (dialogCtx.mounted) {
              setDialogState(() {
                activePartiesOnDate = list;
                isLoadingParties = false;
                if (selectedParty != 'All Parties' && !activePartiesOnDate.contains(selectedParty) && !showAllRegisteredParties) {
                  selectedParty = 'All Parties';
                }
              });
            }
          }

          // Initial Load on opening dialog
          if (!hasInitialized) {
            hasInitialized = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              refreshActiveParties();
            });
          }

          // Build party dropdown items
          final displayedParties = <String>['All Parties'];
          if (showAllRegisteredParties || activePartiesOnDate.isEmpty) {
            for (final s in sellers) {
              final n = s.name.trim();
              if (n.isNotEmpty && !displayedParties.contains(n)) displayedParties.add(n);
            }
            for (final p in _availableParties) {
              final n = p.trim();
              if (n.isNotEmpty && !displayedParties.contains(n)) displayedParties.add(n);
            }
          } else {
            for (final p in activePartiesOnDate) {
              if (!displayedParties.contains(p)) displayedParties.add(p);
            }
          }

          final singleDateDisplay = DateFormat('dd MMM yyyy').format(individualDate);

          return AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF22C55E), width: 1.5),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.sync, color: Color(0xFF22C55E), size: 24),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recalculate Voucher Rates', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Sync with Master Series 100 Dynamic Pricing', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blueAccent.withAlpha(50)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('Master Base Rate (100 Ser): ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              Text('₹${base100.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold, fontSize: 14)),
                              const Spacer(),
                              Text('(₹${perUnit.toStringAsFixed(2)} / unit)', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '⚡ Multipliers: 12 Ser = ₹${(12 * perUnit).toStringAsFixed(2)} | 24 Ser = ₹${(24 * perUnit).toStringAsFixed(2)} | 50 Ser = ₹${(50 * perUnit).toStringAsFixed(2)} | 100 Ser = ₹${(100 * perUnit).toStringAsFixed(2)}',
                            style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Target Date Scope
                    const Text('Select Date Mode:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Individual Date'),
                          selected: selectedDateMode == 'single',
                          selectedColor: const Color(0xFF22C55E).withAlpha(80),
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() => selectedDateMode = 'single');
                              refreshActiveParties();
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('Date Range'),
                          selected: selectedDateMode == 'range',
                          selectedColor: const Color(0xFF22C55E).withAlpha(80),
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() => selectedDateMode = 'range');
                              refreshActiveParties();
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('All Dates'),
                          selected: selectedDateMode == 'all',
                          selectedColor: const Color(0xFF22C55E).withAlpha(80),
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() => selectedDateMode = 'all');
                              refreshActiveParties();
                            }
                          },
                        ),
                      ],
                    ),

                    // 1. Single / Individual Date Controls
                    if (selectedDateMode == 'single') ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ActionChip(
                            label: const Text('Today'),
                            avatar: const Icon(Icons.today, size: 14),
                            backgroundColor: DateUtils.isSameDay(individualDate, now)
                                ? const Color(0xFF22C55E).withAlpha(60)
                                : null,
                            onPressed: () {
                              setDialogState(() => individualDate = now);
                              refreshActiveParties();
                            },
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            label: const Text('Yesterday'),
                            avatar: const Icon(Icons.history, size: 14),
                            backgroundColor: DateUtils.isSameDay(
                                    individualDate, now.subtract(const Duration(days: 1)))
                                ? const Color(0xFF22C55E).withAlpha(60)
                                : null,
                            onPressed: () {
                              setDialogState(() =>
                                  individualDate = now.subtract(const Duration(days: 1)));
                              refreshActiveParties();
                            },
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_month,
                                  size: 16, color: Color(0xFF22C55E)),
                              label: Text(
                                singleDateDisplay,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF22C55E)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                              ),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: dialogCtx,
                                  initialDate: individualDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                  builder: (c, child) {
                                    return Theme(
                                      data: ThemeData.dark().copyWith(
                                        colorScheme: const ColorScheme.dark(
                                          primary: Color(0xFF22C55E),
                                          onPrimary: Colors.black,
                                          surface: Color(0xFF1E293B),
                                          onSurface: Colors.white,
                                        ),
                                        dialogTheme: const DialogThemeData(
                                          backgroundColor: Color(0xFF0F172A),
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked != null) {
                                  setDialogState(() => individualDate = picked);
                                  refreshActiveParties();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],

                    // 2. Date Range Controls
                    if (selectedDateMode == 'range') ...[
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () async {
                          final picked = await showDateRangePicker(
                            context: dialogCtx,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            initialDateRange: customRange ??
                                DateTimeRange(
                                  start: now.subtract(const Duration(days: 7)),
                                  end: now,
                                ),
                            builder: (c, child) {
                              return Theme(
                                data: ThemeData.dark().copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: Color(0xFF22C55E),
                                    onPrimary: Colors.black,
                                    surface: Color(0xFF1E293B),
                                    onSurface: Colors.white,
                                  ),
                                  dialogTheme: const DialogThemeData(
                                    backgroundColor: Color(0xFF0F172A),
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            setDialogState(() => customRange = picked);
                            refreshActiveParties();
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF22C55E).withAlpha(120)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.date_range, color: Color(0xFF22C55E), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  customRange != null
                                      ? '${DateFormat('dd MMM yyyy').format(customRange!.start)}  →  ${DateFormat('dd MMM yyyy').format(customRange!.end)}'
                                      : 'Click to select Date Range',
                                  style: TextStyle(
                                    color: customRange != null ? Colors.white : Colors.white60,
                                    fontSize: 12,
                                    fontWeight: customRange != null ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                              const Icon(Icons.edit_calendar, color: Color(0xFF22C55E), size: 16),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Target Draw Shift Filter
                    const Text('Select Draw Shift:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedShift,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'All Shifts', child: Text('All Shifts (1 PM, 6 PM, 8 PM)')),
                        DropdownMenuItem(value: 'Dear 1 PM', child: Text('Dear 1 PM (Morning)')),
                        DropdownMenuItem(value: 'Dear 6 PM', child: Text('Dear 6 PM (Day)')),
                        DropdownMenuItem(value: 'Dear 8 PM', child: Text('Dear 8 PM (Night)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedShift = val);
                          refreshActiveParties();
                        }
                      },
                    ),

                    const SizedBox(height: 14),

                    // Multi-Customer / Parties Selection Section
                    Row(
                      children: [
                        const Text(
                          'Select Parties / Customers:',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (isLoadingParties)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF22C55E),
                            ),
                          )
                        else
                          Text(
                            isAllPartiesSelected
                                ? '⭐ All Parties Selected'
                                : '${selectedParties.length} Selected',
                            style: TextStyle(
                              color: isAllPartiesSelected ? const Color(0xFF22C55E) : const Color(0xFF38BDF8),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('⭐ All Parties'),
                          selected: isAllPartiesSelected,
                          selectedColor: const Color(0xFF22C55E).withAlpha(80),
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() {
                                isAllPartiesSelected = true;
                                selectedParties.clear();
                              });
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text(
                            selectedParties.isEmpty
                                ? 'Select Multiple Customers'
                                : 'Selected (${selectedParties.length} Customers)',
                          ),
                          selected: !isAllPartiesSelected,
                          selectedColor: const Color(0xFF22C55E).withAlpha(80),
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() {
                                isAllPartiesSelected = false;
                                if (selectedParties.isEmpty && activePartiesOnDate.isNotEmpty) {
                                  selectedParties.addAll(activePartiesOnDate);
                                }
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    if (!isAllPartiesSelected) ...[
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF22C55E).withAlpha(120)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 32,
                                      child: TextField(
                                        controller: partySearchCtrl,
                                        style: const TextStyle(fontSize: 12, color: Colors.white),
                                        decoration: InputDecoration(
                                          hintText: 'Search customer name...',
                                          hintStyle: const TextStyle(fontSize: 11, color: Colors.white60),
                                          prefixIcon: const Icon(Icons.search, size: 14, color: Colors.white60),
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                          filled: true,
                                          fillColor: const Color(0xFF0F172A),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                        onChanged: (val) => setDialogState(() => partySearchQuery = val.toLowerCase()),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  TextButton(
                                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                                    onPressed: () {
                                      setDialogState(() {
                                        selectedParties.addAll(displayedParties.where((p) => p != 'All Parties'));
                                      });
                                    },
                                    child: const Text('Select All', style: TextStyle(fontSize: 11, color: Color(0xFF22C55E))),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                                    onPressed: () {
                                      setDialogState(() {
                                        selectedParties.clear();
                                      });
                                    },
                                    child: const Text('Clear', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFF334155)),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 140),
                              child: ListView(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                children: displayedParties.where((p) {
                                  if (p == 'All Parties') return false;
                                  if (partySearchQuery.isNotEmpty && !p.toLowerCase().contains(partySearchQuery)) return false;
                                  return true;
                                }).map((name) {
                                  final isChecked = selectedParties.contains(name);
                                  final hasEntry = activePartiesOnDate.contains(name);
                                  return CheckboxListTile(
                                    dense: true,
                                    visualDensity: VisualDensity.compact,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                    value: isChecked,
                                    title: Row(
                                      children: [
                                        Icon(
                                          hasEntry ? Icons.check_circle : Icons.person_outline,
                                          size: 14,
                                          color: hasEntry ? const Color(0xFF22C55E) : Colors.grey,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: hasEntry ? FontWeight.bold : FontWeight.normal,
                                              color: hasEntry ? Colors.white : Colors.white70,
                                            ),
                                          ),
                                        ),
                                        if (hasEntry)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF22C55E).withAlpha(30),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'Active',
                                              style: TextStyle(fontSize: 9, color: Color(0xFF22C55E), fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                      ],
                                    ),
                                    onChanged: (val) {
                                      setDialogState(() {
                                        if (val == true) {
                                          selectedParties.add(name);
                                        } else {
                                          selectedParties.remove(name);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (activePartiesOnDate.isNotEmpty && !showAllRegisteredParties) ...[
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () {
                          setDialogState(() => showAllRegisteredParties = true);
                        },
                        child: const Text(
                          'Showing only parties with entries. Tap to show all registered parties.',
                          style: TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 11,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.pop(dialogCtx),
                child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                icon: isProcessing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.flash_on, size: 16),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  foregroundColor: Colors.black,
                ),
                label: Text(
                  isProcessing ? 'RECALCULATING...' : 'RECALCULATE RATES',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: isProcessing
                    ? null
                    : () async {
                        setDialogState(() => isProcessing = true);
                        try {
                          String? targetDate;
                          String? startDateStr;
                          String? endDateStr;

                          if (selectedDateMode == 'single') {
                            targetDate = DateFormat('yyyy-MM-dd').format(individualDate);
                          } else if (selectedDateMode == 'range' && customRange != null) {
                            startDateStr = DateFormat('yyyy-MM-dd').format(customRange!.start);
                            endDateStr = DateFormat('yyyy-MM-dd').format(customRange!.end);
                          }

                          final targetParties = (!isAllPartiesSelected && selectedParties.isNotEmpty)
                              ? selectedParties.toList()
                              : null;

                          final res = await DatabaseService.instance.recalculateRatesAcrossSystem(
                            date: targetDate,
                            startDate: startDateStr,
                            endDate: endDateStr,
                            partyName: targetParties == null && selectedParty != 'All Parties' ? selectedParty : null,
                            partyNames: targetParties,
                            drawShift: selectedShift == 'All Shifts' ? null : selectedShift,
                            customSeries100Price: base100,
                            updateVouchers: true,
                            updateUnsold: false,
                            updateSales: false,
                          );

                          if (dialogCtx.mounted && Navigator.canPop(dialogCtx)) {
                            Navigator.pop(dialogCtx);
                          }
                          if (mounted) {
                            _loadDataForCurrentFilters();
                            _showSnack(
                              '⚡ Recalculated ${res['vouchers']} voucher(s) with new dynamic rates!',
                              AppColors.success,
                            );
                          }
                        } catch (e) {
                          if (dialogCtx.mounted) {
                            setDialogState(() => isProcessing = false);
                          }
                          if (mounted) {
                            _showSnack('Recalculation error: $e', AppColors.error);
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final first = _selectedDate.isBefore(DateTime(2020)) ? _selectedDate : DateTime(2020);
    final last = _selectedDate.isAfter(DateTime(2035)) ? _selectedDate : DateTime(2035);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: first,
      lastDate: last,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: Colors.black,
              surface: Color(0xFF1E293B),
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadDataForCurrentFilters();
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.only(bottom: 20, right: 20, left: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateDisplayStr = DateFormat('dd-MM-yyyy').format(_selectedDate);
    final voucherState = ref.watch(voucherViewModelProvider);
    final sellerCustomerState = ref.watch(sellerCustomerViewModelProvider);
    _syncDealersFromSellers(sellerCustomerState.sellers);

    // Dynamic available series
    final Set<String> availableSeriesSet = {'All Series'};
    for (final v in voucherState.vouchers) {
      final s = v.series.trim();
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

    // Filter by Party / Dealer
    final partyVouchers = _selectedPartyFilter == 'All Parties'
        ? voucherState.vouchers
        : voucherState.vouchers.where((v) {
            final pFilter = _selectedPartyFilter.trim().toLowerCase();
            return v.partyName.trim().toLowerCase() == pFilter ||
                v.effectiveDealer.trim().toLowerCase() == pFilter ||
                (v.dealerName != null && v.dealerName!.trim().toLowerCase() == pFilter);
          }).toList();

    // Filter by Series
    final seriesVouchers = _selectedSeriesFilter == 'All Series'
        ? partyVouchers
        : partyVouchers.where((v) {
            final sV = v.series.replaceAll(RegExp(r'\D'), '');
            final sF = _selectedSeriesFilter.replaceAll(RegExp(r'\D'), '');
            return v.series.trim().toUpperCase() == _selectedSeriesFilter.trim().toUpperCase() ||
                (sV.isNotEmpty && sV == sF);
          }).toList();

    // Search query filter
    final filteredVouchers = _searchQuery.isEmpty
        ? seriesVouchers
        : seriesVouchers.where((v) {
            final q = _searchQuery.toLowerCase();
            return v.voucherNo.toLowerCase().contains(q) ||
                v.partyName.toLowerCase().contains(q) ||
                v.effectiveDealer.toLowerCase().contains(q) ||
                v.series.toLowerCase().contains(q) ||
                v.fromTicket.contains(q) ||
                v.toTicket.contains(q);
          }).toList();

    final issuedTickets = filteredVouchers.fold<int>(0, (sum, v) => sum + v.totalQty);
    final issuedAmount = filteredVouchers.fold<double>(0.0, (sum, v) => sum + v.totalAmount);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Column(
        children: [
          // 1. Top Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left: Title + Badge + Jump to Unsold
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withAlpha(40),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF6366F1).withAlpha(100)),
                              ),
                              child: const Icon(
                                Icons.confirmation_number_outlined,
                                color: Color(0xFF818CF8),
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'STOCK VOUCHERS / TICKET ISSUE',
                                      style: AppTypography.titleMd.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF818CF8).withAlpha(40),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFF818CF8).withAlpha(120)),
                                      ),
                                      child: Text(
                                        '${filteredVouchers.length} Vouchers',
                                        style: const TextStyle(
                                          color: Color(0xFF818CF8),
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  'Issue fresh stock to dealers & sub-sellers',
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 10.5),
                                ),
                              ],
                            ),
                            const SizedBox(width: 20),

                            // Shortcut Button: Go to Number Unsold
                            SizedBox(
                              height: 32,
                              child: OutlinedButton.icon(
                                onPressed: () => context.go(AppConstants.routeUnsold),
                                icon: const Icon(Icons.inventory_2_outlined, size: 14, color: Color(0xFFEF4444)),
                                label: const Text(
                                  'NUMBER UNSOLD',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFFEF4444)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: const Color(0xFFEF4444).withAlpha(120)),
                                  backgroundColor: const Color(0xFFEF4444).withAlpha(20),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                              ),
                            ),

                            const SizedBox(width: 8),

                            // Shortcut Button: Recalculate Voucher Rates
                            SizedBox(
                              height: 32,
                              child: OutlinedButton.icon(
                                onPressed: _showRecalculateVoucherRatesDialog,
                                icon: const Icon(Icons.sync, size: 14, color: Color(0xFF22C55E)),
                                label: const Text(
                                  'SYNC RATES',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF22C55E)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: const Color(0xFF22C55E).withAlpha(120)),
                                  backgroundColor: const Color(0xFF22C55E).withAlpha(20),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(width: 20),

                        // Right: Filters & Action Buttons
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Party Filter Dropdown
                            InkWell(
                              onTap: () async {
                                final allFilterOptions = <String>{
                                  ..._availableDealers,
                                  ..._availableParties,
                                }.toList()..sort();

                                final chosen = await SearchableDealerPickerDialog.show(
                                  context: context,
                                  dealers: allFilterOptions,
                                  dealerToSellersMap: _dealerToSellersMap,
                                  selectedDealer: _selectedPartyFilter,
                                  title: 'Filter by Party / Dealer',
                                  hintText: 'Search dealer or party name...',
                                  allowAllOption: true,
                                  allOptionLabel: '👥 All Parties',
                                  allOptionValue: 'All Parties',
                                  icon: Icons.filter_alt_rounded,
                                );

                                if (chosen != null) {
                                  setState(() {
                                    _selectedPartyFilter = chosen;
                                    if (chosen != 'All Parties') {
                                      _vPartyCtrl.text = chosen;
                                    }
                                  });
                                  _loadDataForCurrentFilters();
                                }
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: _selectedPartyFilter == 'All Parties' ? AppColors.surfaceContainerLow : const Color(0xFF1E1B4B),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _selectedPartyFilter == 'All Parties' ? AppColors.border : Colors.cyanAccent,
                                    width: _selectedPartyFilter == 'All Parties' ? 1.0 : 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _selectedPartyFilter == 'All Parties' ? Icons.person : Icons.filter_alt_rounded,
                                      color: _selectedPartyFilter == 'All Parties' ? AppColors.primary : Colors.cyanAccent,
                                      size: 15,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _selectedPartyFilter == 'All Parties'
                                          ? '👥 All Parties'
                                          : (_availableDealers.contains(_selectedPartyFilter)
                                              ? '👑 $_selectedPartyFilter (Dealer)'
                                              : '👤 $_selectedPartyFilter'),
                                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary, size: 16),
                                  ],
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
                                      setState(() {
                                        _selectedShift = val;
                                      });
                                      _loadDataForCurrentFilters();
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Date Selector
                            InkWell(
                              onTap: () => _selectDate(context),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.calendar_today, size: 13, color: AppColors.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      dateDisplayStr,
                                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // AI SCAN SLIP Button
                            SizedBox(
                              height: 32,
                              child: ElevatedButton.icon(
                                onPressed: _scanParchaImage,
                                icon: const Icon(Icons.auto_awesome, size: 14),
                                label: const Text('AI SCAN SLIP', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF7C3AED),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // PASTE RAW TEXT Button
                            SizedBox(
                              height: 32,
                              child: ElevatedButton.icon(
                                onPressed: _openPasteTextParser,
                                icon: const Icon(Icons.content_paste_go_rounded, size: 14),
                                label: const Text('PASTE JSON / TEXT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF059669),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // EXPORT CSV Button
                            SizedBox(
                              height: 32,
                              child: ElevatedButton.icon(
                                onPressed: () => _exportVouchersToCsv(filteredVouchers),
                                icon: const Icon(Icons.download_rounded, size: 14),
                                label: const Text('CSV EXPORT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF475569),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // DELETE SHIFT VOUCHERS Button
                            SizedBox(
                              height: 32,
                              child: ElevatedButton.icon(
                                onPressed: _showDeleteAllVouchersDialog,
                                icon: const Icon(Icons.delete_sweep_rounded, size: 14),
                                label: const Text('DELETE SHIFT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.3)),
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
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // 2. Metrics Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
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
                          'PARTY: $_selectedPartyFilter',
                          style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                _buildMiniPill('Total Vouchers', '${filteredVouchers.length} Entries', const Color(0xFF818CF8)),
                const SizedBox(width: 14),
                _buildMiniPill('Total Issued Tickets', '$issuedTickets Nos', Colors.cyanAccent),
                const SizedBox(width: 14),
                _buildMiniPill('Total Issued Value', '₹${issuedAmount.toStringAsFixed(2)}', Colors.amberAccent),
              ],
            ),
          ),

          // 3. Main Content: Fast Keyboard Voucher Issue Entry Bar + Table
          Expanded(
            child: Column(
              children: [
                _buildFastVoucherEntryBar(),
                _buildFilterChipsAndSearchBar(availableSeries),
                Expanded(
                  child: filteredVouchers.isEmpty
                      ? _buildEmptyPlaceholder()
                      : _buildVoucherTable(filteredVouchers),
                ),
              ],
            ),
          ),

          // 4. Bulk Action Bar when items selected
          _buildBulkActionBar(_selectedVoucherIds.length),
        ],
      ),
    );
  }

  Widget _buildMiniPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(color: Colors.grey.shade400, fontSize: 10.5, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildFastVoucherEntryBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 980;
          final inputsRow = Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 1. Select Main Dealer
              _buildResponsiveBox(
                isWide: isWide,
                flex: 3,
                minWidth: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '1. Main Dealer *',
                      style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 10.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => _openSearchableDealerPicker(
                        context: context,
                        selectedDealer: _selectedVoucherDealer,
                        title: 'Select Main Dealer (${_availableDealers.length})',
                        onSelected: (val) {
                          setState(() {
                            _selectedVoucherDealer = val;
                            if (val != null) {
                              _vPartyCtrl.text = val;
                              _selectedPartyFilter = val;
                            }
                          });
                        },
                      ),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _selectedVoucherDealer != null ? const Color(0xFFF59E0B) : Colors.redAccent.withAlpha(180),
                            width: _selectedVoucherDealer != null ? 1 : 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.business_rounded, color: Color(0xFFF59E0B), size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _selectedVoucherDealer ?? '⚠️ Set First Dealer!',
                                style: TextStyle(
                                  color: _selectedVoucherDealer != null ? Colors.white : Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // 2. Select Sub-Seller / Party Name
              _buildResponsiveBox(
                isWide: isWide,
                flex: 3,
                minWidth: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '2. Sub-Seller / Party *',
                      style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 10.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () async {
                        final chosen = await SearchableDealerPickerDialog.show(
                          context: context,
                          dealers: _availableParties,
                          dealerToSellersMap: _dealerToSellersMap,
                          selectedDealer: _vPartyCtrl.text.trim().isNotEmpty ? _vPartyCtrl.text.trim() : null,
                          title: 'Select Sub-Seller / Customer (${_availableParties.length})',
                          hintText: 'Search seller or customer name...',
                          icon: Icons.person_search_rounded,
                        );
                        if (chosen != null && chosen.isNotEmpty) {
                          setState(() {
                            _vPartyCtrl.text = chosen;
                            final parent = _dealerToSellersMap.entries
                                .firstWhere(
                                  (e) => e.value.contains(chosen),
                                  orElse: () => MapEntry('', <String>[]),
                                )
                                .key;
                            if (parent.isNotEmpty && _selectedVoucherDealer != parent) {
                              _selectedVoucherDealer = parent;
                            }
                          });
                          _vSeriesFocusNode.requestFocus();
                        }
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _vPartyCtrl.text.isNotEmpty ? const Color(0xFF38BDF8) : AppColors.border,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline, color: Color(0xFF38BDF8), size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _vPartyCtrl.text.isNotEmpty ? _vPartyCtrl.text : 'Select Sub-Seller...',
                                style: TextStyle(
                                  color: _vPartyCtrl.text.isNotEmpty ? Colors.white : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // 3. Series
              _buildResponsiveBox(
                isWide: isWide,
                flex: 2,
                minWidth: 90,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Series', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10.5)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _vSeriesCtrl,
                        focusNode: _vSeriesFocusNode,
                        style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11.5),
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: 'e.g. 12',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary)),
                        ),
                        onChanged: (val) {
                          _updateVoucherRate(val);
                        },
                        onSubmitted: (_) => _vFromFocusNode.requestFocus(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // 4. From Ticket
              _buildResponsiveBox(
                isWide: isWide,
                flex: 2,
                minWidth: 105,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('From No.', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10.5)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _vFromCtrl,
                        focusNode: _vFromFocusNode,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                        keyboardType: TextInputType.text,
                        decoration: InputDecoration(
                          hintText: '28301',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary)),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _vToFocusNode.requestFocus(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // 5. To Ticket
              _buildResponsiveBox(
                isWide: isWide,
                flex: 2,
                minWidth: 105,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('To No.', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10.5)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _vToCtrl,
                        focusNode: _vToFocusNode,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                        keyboardType: TextInputType.text,
                        decoration: InputDecoration(
                          hintText: '28350',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary)),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _addVoucher(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Calculated Qty
              _buildCalculatedQtyBadge(),
              const SizedBox(width: 8),

              // Rate Field
              _buildResponsiveBox(
                isWide: isWide,
                flex: 2,
                minWidth: 80,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Rate (₹)', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10.5)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _vRateCtrl,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary)),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Add Button
              SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  onPressed: _addVoucher,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('ADD VOUCHER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ],
          );

          if (isWide) return inputsRow;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: inputsRow,
            ),
          );
        },
      ),
    );
  }

  Widget _buildCalculatedQtyBadge() {
    final res = _resolveRange(_vFromCtrl.text, _vToCtrl.text);
    final rate = double.tryParse(_vRateCtrl.text.trim()) ?? 0.0;
    final total = res.qty * rate;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.cyanAccent.withAlpha(80)),
      ),
      child: Center(
        child: Text(
          '${res.qty} Nos | ₹${total.toStringAsFixed(1)}',
          style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11),
        ),
      ),
    );
  }

  Widget _buildResponsiveBox({
    required bool isWide,
    required int flex,
    required double minWidth,
    required Widget child,
  }) {
    if (isWide) {
      return Expanded(flex: flex, child: child);
    }
    return SizedBox(width: minWidth, child: child);
  }

  Widget _buildFilterChipsAndSearchBar(List<String> availableSeries) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          // Series Filter Chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: availableSeries.map((s) {
                  final isSelected = _selectedSeriesFilter == s;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(s == 'All Series' ? 'All Series' : 'Ser $s'),
                      selected: isSelected,
                      onSelected: (val) {
                        setState(() {
                          _selectedSeriesFilter = s;
                        });
                      },
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 10.5,
                      ),
                      backgroundColor: const Color(0xFF1E293B),
                      selectedColor: Colors.cyanAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Search Field
          SizedBox(
            width: 200,
            height: 30,
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 11),
              decoration: InputDecoration(
                hintText: 'Search vouchers...',
                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                prefixIcon: const Icon(Icons.search, size: 14, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 14, color: Colors.grey),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary)),
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val.trim());
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoucherTable(List<VoucherModel> list) {
    final allSelected = list.isNotEmpty && list.every((v) => _selectedVoucherIds.contains(v.id));

    return Column(
      children: [
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            border: Border(bottom: BorderSide(color: Color(0xFF334155))),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Checkbox(
                  value: allSelected,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedVoucherIds.addAll(list.map((v) => v.id));
                      } else {
                        _selectedVoucherIds.clear();
                      }
                    });
                  },
                  activeColor: AppColors.primary,
                  checkColor: Colors.black,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              const SizedBox(width: 36, child: Text('#', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
              const SizedBox(width: 70, child: Text('Time', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
              const Expanded(flex: 3, child: Text('Voucher / Slip', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
              const Expanded(flex: 4, child: Text('Sub-Seller / Party', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
              const Expanded(flex: 2, child: Text('Series', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
              const Expanded(flex: 3, child: Text('Ticket Range', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
              const Expanded(flex: 2, child: Text('Qty', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
              const Expanded(flex: 2, child: Text('Rate', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
              const Expanded(flex: 2, child: Text('Total', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
              const SizedBox(width: 50, child: Text('Action', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center)),
            ],
          ),
        ),

        // Table Rows
        Expanded(
          child: ListView.separated(
            itemCount: list.length,
            separatorBuilder: (ctx, i) => const Divider(height: 1, color: Color(0xFF1E293B)),
            itemBuilder: (ctx, i) {
              final v = list[i];
              final isChecked = _selectedVoucherIds.contains(v.id);
              final timeStr = DateFormat('HH:mm').format(v.createdAt);
              final rangeDisplay = '${v.fromTicket.padLeft(5, '0')} - ${v.toTicket.padLeft(5, '0')}';

              return Container(
                color: isChecked ? const Color(0xFF1E1B4B).withAlpha(120) : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Checkbox(
                        value: isChecked,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedVoucherIds.add(v.id);
                            } else {
                              _selectedVoucherIds.remove(v.id);
                            }
                          });
                        },
                        activeColor: AppColors.primary,
                        checkColor: Colors.black,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 36,
                      child: Text('${i + 1}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    ),
                    SizedBox(
                      width: 70,
                      child: Text(timeStr, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        v.voucherNo,
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 11.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.partyName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (v.dealerName != null &&
                              v.dealerName!.isNotEmpty &&
                              v.dealerName!.trim().toLowerCase() != v.partyName.trim().toLowerCase()) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0284C7).withAlpha(40),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: const Color(0xFF0284C7).withAlpha(140)),
                              ),
                              child: Text(
                                '🏢 Dealer: ${v.dealerName}',
                                style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withAlpha(35),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: const Color(0xFFF59E0B).withAlpha(140)),
                              ),
                              child: const Text(
                                '👑 Main Dealer',
                                style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6B21A8).withAlpha(80),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Ser ${v.series}',
                          style: const TextStyle(color: Color(0xFFC084FC), fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        rangeDisplay,
                        style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12),
                      ),
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
      ],
    );
  }

  Widget _buildBulkActionBar(int selectedCount) {
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
            onPressed: _openBulkUpdatePartyDialog,
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
            onPressed: _openBulkUpdateSeriesDialog,
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
            onPressed: _confirmBulkDelete,
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
                _selectedVoucherIds.clear();
              });
            },
            icon: const Icon(Icons.close, size: 14, color: Colors.grey),
            label: const Text('Clear Selection', style: TextStyle(color: Colors.grey, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.confirmation_number_outlined, size: 48, color: Colors.grey.shade600),
          const SizedBox(height: 12),
          const Text('No Vouchers Found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            'Use the entry bar above or scan slip to issue stock vouchers.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _scanParchaImage,
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('AI Scan Slip', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}
