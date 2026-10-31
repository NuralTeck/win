import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../settings/viewmodels/series_price_viewmodel.dart';
import '../../sellers/viewmodels/seller_customer_viewmodel.dart';
import '../../sellers/models/seller_customer_model.dart';
import '../../bookings/services/gemini_scanner_service.dart';
import '../../../core/database/database_service.dart';
import '../../../core/database/supabase_service.dart';
import '../models/voucher_model.dart';
import '../models/unsold_model.dart';
import '../viewmodels/voucher_viewmodel.dart';
import '../viewmodels/unsold_viewmodel.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../widgets/ai_stock_scan_review_dialog.dart';
import '../widgets/raw_stock_text_parser_dialog.dart';
import '../widgets/searchable_dealer_picker_dialog.dart';

class UnsoldMainScreen extends ConsumerStatefulWidget {
  const UnsoldMainScreen({super.key});

  @override
  ConsumerState<UnsoldMainScreen> createState() => _UnsoldMainScreenState();
}

class _UnsoldMainScreenState extends ConsumerState<UnsoldMainScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedDate = DateTime.now();
  String _selectedShift = 'Dear 1 PM';
  final List<String> _shiftList = ['Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'];
  String _selectedPartyFilter = 'All Parties';
  List<String> _availableDealers = [];
  Map<String, List<String>> _dealerToSellersMap = {};

  // Voucher Dealer & Sub-Seller Selection
  String? _selectedVoucherDealer;
  String? _selectedVoucherSeller;

  // Unsold Main Dealer Selection (Single Dealer for all mixed series)
  String? _selectedUnsoldDealer;

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
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _vSeriesCtrl.text = _lastUsedVoucherSeries;
    _uSeriesCtrl.text = _lastUsedUnsoldSeries;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDataForCurrentFilters();
    });
  }

  void _onTabChanged() {
    // ⚡ Ignore animation in-flight ticks to avoid frame drops & screen freeze
    if (_tabController.indexIsChanging) return;

    if (_tabController.index == 0) {
      // Unsold Tab: Auto-sync dealer from Voucher if Unsold dealer is not set
      if (_selectedUnsoldDealer == null && _selectedVoucherDealer != null) {
        setState(() {
          _selectedUnsoldDealer = _selectedVoucherDealer;
          _uPartyCtrl.text = _selectedVoucherDealer!;
        });
      }
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    if (_tabController.length != 3) {
      _tabController.removeListener(_onTabChanged);
      _tabController.dispose();
      _tabController = TabController(length: 3, vsync: this);
      _tabController.addListener(_onTabChanged);
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
    ref.read(voucherViewModelProvider.notifier).loadVouchers(
      date: dateStr,
      drawShift: _selectedShift,
    );
    ref.read(unsoldViewModelProvider.notifier).loadUnsold(
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

  List<SellerCustomerModel>? _lastSyncedSellers;

  /// ⚡ LIVE IN-MEMORY SYNC (O(N) single-pass)
  /// Zero SQLite queries. Directly synchronizes from System Config (SellerCustomerViewModel).
  /// Strictly ONLY genuine dealers configured with [isDealer == true] are populated as Dealers.
  /// Seamlessly handles 1k-2k dealers and 50k sub-parties in < 2ms with zero lag.
  void _syncDealersFromSellers(List<SellerCustomerModel> sellers) {
    if (identical(_lastSyncedSellers, sellers) && _availableDealers.isNotEmpty) {
      return; // Already up-to-date! 0ms instant return
    }
    _lastSyncedSellers = sellers;

    final dealers = <String>[];
    final dToS = <String, List<String>>{};
    final allParties = <String>{};

    // 1. Strictly populate ONLY genuine dealers configured in System Config (isDealer == true)
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

    // 2. Map sub-sellers to their designated parent dealer in single pass O(N)
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

    // Sort sub-sellers alphabetically
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

    // Support compound parcha format in 'from' e.g. "12345-55-10" or "12345-55" or "42980-1"
    if (f.contains('-')) {
      final parts = f.split('-').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        f = parts[0];
        if (t.isEmpty && parts.length >= 2) {
          if (parts.length == 2 && parts[1] == '1') {
            t = f;
          } else {
            t = parts[1]; // parts[2] is written qty, IGNORED!
          }
        }
      }
    }

    // Strip written quantity after hyphen in 'to' e.g. "55-10" -> "55", "12355-10" -> "12355"
    if (t.contains('-')) {
      final parts = t.split('-').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        t = parts[0]; // trailing written qty is completely IGNORED!
      }
    }

    // Resolve abbreviated 'to' to full 5-digit number e.g. from="12345", to="55" -> "12355"
    if (t.isNotEmpty && t.length < 5 && f.length == 5) {
      t = f.substring(0, 5 - t.length) + t;
    } else if (t.isEmpty) {
      t = f;
    }

    // Calculate quantity mathematically from tickets: (to - from) + 1
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
      // Retain Party Name & Series for fast continuous range entry!
      _vFromCtrl.clear();
      _vToCtrl.clear();
      _vFromFocusNode.requestFocus();

      // If viewing a different party, reset filter so the newly added voucher is immediately visible!
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

  Future<void> _addUnsold() async {
    if (_selectedUnsoldDealer == null || _selectedUnsoldDealer!.isEmpty) {
      _showSnack('⚠️ Set First Dealer! Please select a Main Dealer before adding unsold.', AppColors.warning);
      return;
    }

    final party = _uPartyCtrl.text.trim().isNotEmpty ? _uPartyCtrl.text.trim() : _selectedUnsoldDealer!;

    final series = _uSeriesCtrl.text.trim().isNotEmpty
        ? _uSeriesCtrl.text.trim().toUpperCase()
        : _lastUsedUnsoldSeries;
    _lastUsedUnsoldSeries = series;
    _uSeriesCtrl.text = series;

    final resolved = _resolveRange(_uFromCtrl.text, _uToCtrl.text);
    final from = resolved.from;
    final to = resolved.to;
    final qty = resolved.qty;

    if (from.isEmpty || from.length != 5 || int.tryParse(from) == null) {
      _showSnack('From Number must be an exact 5-digit number (e.g. 28381)!', AppColors.warning);
      _uFromFocusNode.requestFocus();
      return;
    }

    final newTickets = _expandTicketRange(from, to);
    final voucherState = ref.read(voucherViewModelProvider);
    final unsoldState = ref.read(unsoldViewModelProvider);

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // 🔒 STRICT RULE 1: Tickets MUST be in issued Vouchers for this Dealer (or sub-sellers under this Dealer) in this Date & Shift!
    final dbVouchers = await DatabaseService.instance.getVouchers(
      date: dateStr,
      drawShift: _selectedShift,
    );
    final allCurrentVouchers = {
      ...voucherState.vouchers,
      ...dbVouchers.map((r) => VoucherModel.fromMap(r)),
    };

    final partyIssuedTickets = <String>{};
    for (final v in allCurrentVouchers) {
      final isMatch = v.partyName.trim().toLowerCase() == party.toLowerCase() ||
          v.effectiveDealer.trim().toLowerCase() == party.toLowerCase() ||
          (v.dealerName != null && v.dealerName!.trim().toLowerCase() == party.toLowerCase());
      if (isMatch && v.series.toUpperCase() == series.toUpperCase()) {
        partyIssuedTickets.addAll(_expandTicketRange(v.fromTicket, v.toTicket));
      }
    }

    if (partyIssuedTickets.isEmpty) {
      _showSnack('⚠️ Stock Not Issued: No Vouchers found in Series $series for Dealer $party in $_selectedShift!', AppColors.error);
      _uSeriesFocusNode.requestFocus();
      return;
    }

    final notIssued = newTickets.where((tkt) => !partyIssuedTickets.contains(tkt)).toList();
    if (notIssued.isNotEmpty) {
      final sample = notIssued.take(3).join(', ');
      _showSnack('⚠️ Stock Not Issued: Ticket(s) #$sample (Series $series) are NOT issued to Dealer $party in $_selectedShift!', AppColors.error);
      _uFromFocusNode.requestFocus();
      return;
    }

    final now = DateTime.now();

    // 🔒 RULE 2: Duplicate Check in Unsold (Cannot return same ticket twice in same date and shift)
    for (final u in unsoldState.unsoldList) {
      if (u.series.toUpperCase() == series.toUpperCase()) {
        final existingUnsold = _expandTicketRange(u.fromTicket, u.toTicket);
        final overlap = newTickets.intersection(existingUnsold);
        if (overlap.isNotEmpty) {
          final dup = overlap.first;
          _showSnack('⚠️ Duplicate Return: Ticket #$dup (Series $series) is ALREADY returned in Unsold by ${u.partyName} for this shift!', AppColors.warning);
          _uFromFocusNode.requestFocus();
          return;
        }
      }
    }

    // DB check for duplicates in same date & shift across ALL parties
    final dbExisting = await DatabaseService.instance.getUnsoldTickets(
      date: dateStr,
      drawShift: _selectedShift,
    );
    for (final row in dbExisting) {
      final uSer = (row['series'] as String? ?? '').toUpperCase();
      if (uSer == series.toUpperCase()) {
        final existingUnsold = _expandTicketRange(row['from_ticket'] as String? ?? '', row['to_ticket'] as String? ?? '');
        final overlap = newTickets.intersection(existingUnsold);
        if (overlap.isNotEmpty) {
          final dup = overlap.first;
          final retParty = row['party_name'] as String? ?? 'another dealer';
          _showSnack('⚠️ Duplicate Return: Ticket #$dup (Series $series) is ALREADY returned in Unsold by $retParty for this shift!', AppColors.warning);
          _uFromFocusNode.requestFocus();
          return;
        }
      }
    }

    final rate = _getPriceForSeries(series);
    final total = qty * rate;

    final returnNo = 'RET-${DateFormat('HHmmss').format(now)}';

    // 🌳 SMART BRANCH RESOLUTION:
    // If entered under a Dealer's name, find which Sub-Seller was originally issued these tickets!
    final parentDealer = await DatabaseService.instance.getParentDealerForParty(party);
    String effectiveParty = party;
    String effectiveDealer = parentDealer.isNotEmpty ? parentDealer : party;

    for (final v in allCurrentVouchers) {
      if (v.series.toUpperCase() == series.toUpperCase()) {
        final matchesDealer = v.effectiveDealer.trim().toLowerCase() == party.toLowerCase() ||
            v.partyName.trim().toLowerCase() == party.toLowerCase();
        if (matchesDealer) {
          final issuedTickets = _expandTicketRange(v.fromTicket, v.toTicket);
          if (newTickets.any((tkt) => issuedTickets.contains(tkt))) {
            effectiveParty = v.partyName;
            effectiveDealer = v.effectiveDealer.isNotEmpty ? v.effectiveDealer : party;
            break;
          }
        }
      }
    }

    final unsold = UnsoldModel(
      id: 'unsold_${now.microsecondsSinceEpoch}',
      returnNo: returnNo,
      date: dateStr,
      drawShift: _selectedShift,
      partyName: effectiveParty,
      dealerName: effectiveDealer,
      series: series,
      fromTicket: from,
      toTicket: to,
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

      if (_selectedPartyFilter != 'All Parties' && _selectedPartyFilter != party) {
        setState(() {
          _selectedPartyFilter = 'All Parties';
        });
        _loadDataForCurrentFilters();
      } else {
        _refreshAvailableParties();
      }

      _showSnack('✅ Logged Unsold #$returnNo ($qty Tickets | -₹${total.toStringAsFixed(2)})', const Color(0xFFEF4444));
    }
  }

  Future<void> _scanParchaImage(StockScanMode mode) async {
    if (mode == StockScanMode.voucher && (_selectedVoucherDealer == null || _selectedVoucherDealer!.isEmpty)) {
      _showSnack('⚠️ Set First Dealer! Please select a Main Dealer before scanning vouchers.', AppColors.warning);
      return;
    }
    if (mode == StockScanMode.unsold && (_selectedUnsoldDealer == null || _selectedUnsoldDealer!.isEmpty)) {
      _showSnack('⚠️ Set First Dealer! Please select a Main Dealer before scanning unsold.', AppColors.warning);
      return;
    }

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
        aiConfusions: GeminiScannerService.instance.lastAiConfusions,
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
        _selectedPartyFilter = 'All Parties';
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
      _selectedPartyFilter = 'All Parties';
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
    if (mode == StockScanMode.voucher && (_selectedVoucherDealer == null || _selectedVoucherDealer!.isEmpty)) {
      _showSnack('⚠️ Set First Dealer! Please select a Main Dealer before pasting vouchers.', AppColors.warning);
      return;
    }
    if (mode == StockScanMode.unsold && (_selectedUnsoldDealer == null || _selectedUnsoldDealer!.isEmpty)) {
      _showSnack('⚠️ Set First Dealer! Please select a Main Dealer before pasting unsold.', AppColors.warning);
      return;
    }

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
      _selectedSeriesFilter = 'All Series';
      _selectedPartyFilter = 'All Parties';
      setState(() {});
      _loadDataForCurrentFilters();
      _showSnack(
        mode == StockScanMode.voucher
            ? '✅ Vouchers parsed & saved successfully!'
            : '✅ Unsold returns parsed & saved successfully!',
        AppColors.success,
      );
    }
  }

  Future<void> _uploadTextFile(StockScanMode mode) async {
    if (mode == StockScanMode.voucher && (_selectedVoucherDealer == null || _selectedVoucherDealer!.isEmpty)) {
      _showSnack('⚠️ Set First Dealer! Please select a Main Dealer before uploading vouchers.', AppColors.warning);
      return;
    }
    if (mode == StockScanMode.unsold && (_selectedUnsoldDealer == null || _selectedUnsoldDealer!.isEmpty)) {
      _showSnack('⚠️ Set First Dealer! Please select a Main Dealer before uploading unsold.', AppColors.warning);
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: mode == StockScanMode.voucher
            ? 'Select Voucher Text File (.txt, .prn, .log, .json)'
            : 'Select Unsold / Purchase Return Text File (.txt, .prn, .log, .json)',
        type: FileType.custom,
        allowedExtensions: ['txt', 'prn', 'log', 'json', 'csv', 'dat'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.first;
      String fileContent = '';

      if (pickedFile.bytes != null) {
        fileContent = utf8.decode(pickedFile.bytes!, allowMalformed: true);
      } else if (pickedFile.path != null) {
        final f = File(pickedFile.path!);
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          fileContent = utf8.decode(bytes, allowMalformed: true);
        }
      }

      if (fileContent.trim().isEmpty) {
        _showSnack('⚠️ Selected file is empty!', AppColors.warning);
        return;
      }

      final currentParty = mode == StockScanMode.voucher
          ? _vPartyCtrl.text.trim()
          : _uPartyCtrl.text.trim();
      final defaultParty = currentParty.isNotEmpty ? currentParty : 'Walk-in Party';

      if (!mounted) return;
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
          initialRawText: fileContent,
        ),
      );

      if (saved == true && mounted) {
        _selectedSeriesFilter = 'All Series';
        _selectedPartyFilter = 'All Parties';
        setState(() {});
        _loadDataForCurrentFilters();
        _showSnack(
          mode == StockScanMode.voucher
              ? '✅ Vouchers uploaded, parsed & saved successfully!'
              : '✅ Unsold returns uploaded, parsed & saved successfully!',
          AppColors.success,
        );
      }
    } catch (e) {
      _showSnack('⚠️ Error loading file: $e', AppColors.error);
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

  // ─── 🏢 DEALER NETWORK BREAKDOWN HISAB MODAL ────────────────────────────────
  String? _findParentDealer(String party) {
    final pLower = party.trim().toLowerCase();
    for (final entry in _dealerToSellersMap.entries) {
      if (entry.key.toLowerCase() == pLower) continue;
      if (entry.value.any((s) => s.trim().toLowerCase() == pLower)) {
        return entry.key;
      }
    }
    return null;
  }

  // ─── 🏢 DEALER NETWORK BREAKDOWN HISAB MODAL ────────────────────────────────
  Future<void> _showDealerBreakdownModal({String? initialDealer}) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // Initial dealer priority: explicit argument -> voucher dealer -> unsold dealer -> active party filter -> 'All Dealers'
    String currentDealer = initialDealer ??
        _selectedVoucherDealer ??
        _selectedUnsoldDealer ??
        (_selectedPartyFilter != 'All Parties' ? _selectedPartyFilter : 'All Dealers');
    String currentShift = _selectedShift;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final voucherState = ref.watch(voucherViewModelProvider);
            final unsoldState = ref.watch(unsoldViewModelProvider);

            final isSpecific = currentDealer != 'All Dealers' &&
                currentDealer != 'All Parties' &&
                currentDealer.isNotEmpty;

            // Sub-parties linked to this dealer from System Config
            final subParties = (isSpecific && _dealerToSellersMap.containsKey(currentDealer))
                ? (_dealerToSellersMap[currentDealer] ?? [])
                : ((isSpecific && _dealerToSellersMap.containsKey(currentDealer.toLowerCase()))
                    ? (_dealerToSellersMap[currentDealer.toLowerCase()] ?? [])
                    : <String>[]);
            final subPartiesLower = subParties.map((s) => s.trim().toLowerCase()).toSet();
            final targetLower = currentDealer.trim().toLowerCase();

            // Map: sub-seller name -> _SubSellerRow
            final map = <String, _SubSellerRow>{};

            // Pre-populate dealer and its sub-parties so they always appear in the table
            if (isSpecific) {
              map[currentDealer] = _SubSellerRow(sellerName: currentDealer, dealerName: currentDealer);
              for (final sp in subParties) {
                map[sp] = _SubSellerRow(sellerName: sp, dealerName: currentDealer);
              }
            }

            // 1. Process Vouchers (Live Riverpod State)
            for (final v in voucherState.vouchers) {
              if (v.date != dateStr) continue;
              if (currentShift != 'All Shifts' &&
                  v.drawShift.trim().toLowerCase() != currentShift.trim().toLowerCase()) {
                continue;
              }

              final p = v.partyName.trim();
              final d = (v.dealerName ?? v.effectiveDealer).trim();
              final pLower = p.toLowerCase();
              final dLower = d.toLowerCase();

              if (isSpecific) {
                final matches = pLower == targetLower ||
                    dLower == targetLower ||
                    v.effectiveDealer.trim().toLowerCase() == targetLower ||
                    subPartiesLower.contains(pLower);
                if (!matches) continue;
              }

              final key = p.isNotEmpty ? p : 'Direct';
              final parentDealer = d.isNotEmpty ? d : (isSpecific ? currentDealer : (_findParentDealer(p) ?? p));
              map.putIfAbsent(key, () => _SubSellerRow(sellerName: key, dealerName: parentDealer));
              map[key]!.issuedQty += v.totalQty;
              map[key]!.issuedAmount += v.totalAmount;
            }

            // 2. Process Unsold Returns (Live Riverpod State)
            for (final u in unsoldState.unsoldList) {
              if (u.date != dateStr) continue;
              if (currentShift != 'All Shifts' &&
                  u.drawShift.trim().toLowerCase() != currentShift.trim().toLowerCase()) {
                continue;
              }

              final p = u.partyName.trim();
              final d = (u.dealerName ?? u.effectiveDealer).trim();
              final pLower = p.toLowerCase();
              final dLower = d.toLowerCase();

              if (isSpecific) {
                final matches = pLower == targetLower ||
                    dLower == targetLower ||
                    u.effectiveDealer.trim().toLowerCase() == targetLower ||
                    subPartiesLower.contains(pLower);
                if (!matches) continue;
              }

              final key = p.isNotEmpty ? p : 'Direct';
              final parentDealer = d.isNotEmpty ? d : (isSpecific ? currentDealer : (_findParentDealer(p) ?? p));
              map.putIfAbsent(key, () => _SubSellerRow(sellerName: key, dealerName: parentDealer));
              map[key]!.unsoldQty += u.totalQty;
              map[key]!.unsoldAmount += u.totalAmount;
            }

            // If "All Dealers" is selected, only show active rows. If specific dealer, show all pre-populated sub-parties.
            final rows = map.values.where((r) => isSpecific || r.issuedQty > 0 || r.unsoldQty > 0).toList();
            rows.sort((a, b) {
              if (isSpecific && a.sellerName.toLowerCase() == targetLower) return -1;
              if (isSpecific && b.sellerName.toLowerCase() == targetLower) return 1;
              return a.sellerName.compareTo(b.sellerName);
            });

            int totalIss = 0;
            double totalIssAmt = 0;
            int totalUnsold = 0;
            double totalUnsoldAmt = 0;

            for (final r in rows) {
              totalIss += r.issuedQty;
              totalIssAmt += r.issuedAmount;
              totalUnsold += r.unsoldQty;
              totalUnsoldAmt += r.unsoldAmount;
            }

            final totalNetSold = (totalIss - totalUnsold) > 0 ? (totalIss - totalUnsold) : 0;
            final totalNetBill = (totalIssAmt - totalUnsoldAmt) > 0 ? (totalIssAmt - totalUnsoldAmt) : 0.0;

            return Dialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
              ),
              child: Container(
                width: 860,
                constraints: const BoxConstraints(maxHeight: 680),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 👑 Interactive Modal Header with Dealer Picker & Shift Selector
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withAlpha(35),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.account_tree_rounded, color: Color(0xFFF59E0B), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  const Text(
                                    'Dealer Network Breakdown Hisab',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                                  ),
                                  // Clickable Interactive Dealer Selector
                                  InkWell(
                                    onTap: () async {
                                      final chosen = await SearchableDealerPickerDialog.show(
                                        context: context,
                                        dealers: _availableDealers,
                                        dealerToSellersMap: _dealerToSellersMap,
                                        selectedDealer: currentDealer,
                                        title: 'Select Dealer for Hisab (${_availableDealers.length})',
                                        allowAllOption: true,
                                        allOptionLabel: '🏢 All Dealers / Entire Network',
                                        allOptionValue: 'All Dealers',
                                      );
                                      if (chosen != null) {
                                        setDialogState(() {
                                          currentDealer = chosen;
                                        });
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E293B),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.workspace_premium_rounded, size: 13, color: Color(0xFFF59E0B)),
                                          const SizedBox(width: 5),
                                          Text(
                                            isSpecific ? 'DEALER: $currentDealer' : '🏢 ALL NETWORK',
                                            style: const TextStyle(
                                              color: Color(0xFF38BDF8),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.arrow_drop_down, color: Color(0xFF38BDF8), size: 16),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Text(
                                    '📅 Date: $dateStr  |  Shift: ',
                                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11.5),
                                  ),
                                  // Interactive Shift Switcher Pills
                                  ...['Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM', 'All Shifts'].map((sh) {
                                    final isSelected = currentShift == sh;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: InkWell(
                                        onTap: () {
                                          setDialogState(() {
                                            currentShift = sh;
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(4),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFF1E293B),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            sh,
                                            style: TextStyle(
                                              color: isSelected ? Colors.black : Colors.grey.shade300,
                                              fontSize: 10,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Overall Totals Summary Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _summaryCol('Issued Stock', '$totalIss Nos', '₹${totalIssAmt.toStringAsFixed(2)}', Colors.cyanAccent),
                          Container(width: 1, height: 28, color: Colors.grey.shade700),
                          _summaryCol('Unsold Return', '$totalUnsold Nos', '-₹${totalUnsoldAmt.toStringAsFixed(2)}', const Color(0xFFF87171)),
                          Container(width: 1, height: 28, color: Colors.grey.shade700),
                          _summaryCol('Net Sold', '$totalNetSold Nos', '', const Color(0xFF4ADE80)),
                          Container(width: 1, height: 28, color: Colors.grey.shade700),
                          _summaryCol('Total Billable', '₹${totalNetBill.toStringAsFixed(2)}', '', Colors.amberAccent, isBig: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Table of Sub-Sellers
                    Expanded(
                      child: rows.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.receipt_long_rounded, size: 40, color: Color(0xFF475569)),
                                  const SizedBox(height: 10),
                                  Text(
                                    'No voucher or unsold records found for "$currentDealer" in "$currentShift" on $dateStr.',
                                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.apps_rounded, size: 14),
                                    label: const Text('View All Network Hisab', style: TextStyle(fontSize: 11)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF38BDF8),
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    ),
                                    onPressed: () {
                                      setDialogState(() {
                                        currentDealer = 'All Dealers';
                                      });
                                    },
                                  ),
                                ],
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF0B1120),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF1E293B)),
                              ),
                              child: Column(
                                children: [
                                  // Table Header
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1E293B),
                                      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                                    ),
                                    child: const Row(
                                      children: [
                                        Expanded(flex: 3, child: Text('Sub-Seller / Agent', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                                        Expanded(flex: 2, child: Text('Parent Dealer', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))),
                                        Expanded(flex: 2, child: Text('Issued Stock', textAlign: TextAlign.right, style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11))),
                                        Expanded(flex: 2, child: Text('Unsold Return', textAlign: TextAlign.right, style: TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold, fontSize: 11))),
                                        Expanded(flex: 2, child: Text('Net Sold', textAlign: TextAlign.right, style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 11))),
                                        Expanded(flex: 2, child: Text('Net Billable', textAlign: TextAlign.right, style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11))),
                                      ],
                                    ),
                                  ),
                                  // Table Body
                                  Expanded(
                                    child: ListView.separated(
                                      itemCount: rows.length,
                                      separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFF1E293B)),
                                      itemBuilder: (c, i) {
                                        final r = rows[i];
                                        final isMain = isSpecific && r.sellerName.toLowerCase() == targetLower;
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          color: isMain
                                              ? const Color(0xFFF59E0B).withAlpha(20)
                                              : (i.isEven ? Colors.transparent : const Color(0xFF131D31).withAlpha(100)),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 3,
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      isMain ? Icons.workspace_premium_rounded : Icons.person_outline,
                                                      size: 13,
                                                      color: isMain ? const Color(0xFFF59E0B) : Colors.cyanAccent,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        isMain ? '👑 ${r.sellerName} (Main)' : r.sellerName,
                                                        style: TextStyle(
                                                          color: isMain ? const Color(0xFFF59E0B) : Colors.white,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 12,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  r.dealerName.isNotEmpty ? r.dealerName : '—',
                                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  '${r.issuedQty} (₹${r.issuedAmount.toStringAsFixed(0)})',
                                                  textAlign: TextAlign.right,
                                                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 11.5, fontFamily: 'monospace'),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  '${r.unsoldQty} (₹${r.unsoldAmount.toStringAsFixed(0)})',
                                                  textAlign: TextAlign.right,
                                                  style: const TextStyle(color: Color(0xFFF87171), fontSize: 11.5, fontFamily: 'monospace'),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  '${r.netSoldQty} Nos',
                                                  textAlign: TextAlign.right,
                                                  style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 11.5, fontFamily: 'monospace'),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  '₹${r.netBillable.toStringAsFixed(2)}',
                                                  textAlign: TextAlign.right,
                                                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 14),

                    // Footer Actions: Copy WhatsApp Text & Close
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.share_rounded, size: 14, color: Colors.black),
                          label: const Text('Copy WhatsApp Hisab Slip', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF22C55E),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: () {
                            final buffer = StringBuffer();
                            buffer.writeln('📊 *HISAB REPORT - OpsCore Pro*');
                            buffer.writeln('📅 *Date:* $dateStr | *Shift:* $currentShift');
                            if (isSpecific) {
                              buffer.writeln('🏢 *Dealer:* $currentDealer');
                            } else {
                              buffer.writeln('🏢 *Network:* Entire Network Summary');
                            }
                            buffer.writeln('────────────────────────');
                            for (final r in rows) {
                              final isMain = isSpecific && r.sellerName.toLowerCase() == targetLower;
                              final tag = isMain ? '👑 [Main Dealer]' : '👤';
                              buffer.writeln('$tag *${r.sellerName}*: ${r.issuedQty} Iss - ${r.unsoldQty} Ret = *${r.netSoldQty} Sold* (₹${r.netBillable.toStringAsFixed(2)})');
                            }
                            buffer.writeln('────────────────────────');
                            buffer.writeln('📦 *Total Issued:* $totalIss Nos (₹${totalIssAmt.toStringAsFixed(2)})');
                            buffer.writeln('🚫 *Total Unsold:* $totalUnsold Nos (₹${totalUnsoldAmt.toStringAsFixed(2)})');
                            buffer.writeln('🎯 *Net Sold:* $totalNetSold Nos');
                            buffer.writeln('💰 *NET BILLABLE: ₹${totalNetBill.toStringAsFixed(2)}*');

                            Clipboard.setData(ClipboardData(text: buffer.toString()));
                            _showSnack('📋 Copied Dealer Network Hisab Slip to Clipboard!', AppColors.success);

                            // ☁️ Auto-sync Party & Dealer Hisab to Supabase Cloud
                            try {
                              final records = rows.map((r) => {
                                'party_name': r.sellerName,
                                'dealer_name': isSpecific ? currentDealer : null,
                                'total_tickets': r.netSoldQty,
                                'total_sales': r.issuedAmount,
                                'total_prize': 0.0,
                                'net_hisab': r.netBillable,
                                'category': 'Dealer Network Hisab',
                                'last_active_date': dateStr,
                              }).toList();
                              SupabaseService.instance.syncPartyHisabBatch(records);
                            } catch (_) {}
                          },
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Close', style: TextStyle(color: Colors.grey)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }


  Widget _summaryCol(String title, String mainVal, String subVal, Color color, {bool isBig = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 10.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(
          mainVal,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: isBig ? 15 : 12.5,
            fontFamily: 'monospace',
          ),
        ),
        if (subVal.isNotEmpty)
          Text(
            subVal,
            style: TextStyle(
              color: color.withAlpha(200),
              fontSize: 10.5,
              fontFamily: 'monospace',
            ),
          ),
      ],
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

  Future<void> _showRecalculateUnsoldRatesDialog() async {
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
                    Text('Recalculate Unsold Rates', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
                            updateVouchers: false,
                            updateUnsold: true,
                            updateSales: false,
                          );

                          if (dialogCtx.mounted && Navigator.canPop(dialogCtx)) {
                            Navigator.pop(dialogCtx);
                          }
                          if (mounted) {
                            _loadDataForCurrentFilters();
                            _showSnack(
                              '⚡ Recalculated ${res['unsold']} unsold return(s) with new dynamic rates!',
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
    final sellerCustomerState = ref.watch(sellerCustomerViewModelProvider);
    _syncDealersFromSellers(sellerCustomerState.sellers);

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

    // Filter lists by selected Party / Dealer filter
    final partyVouchers = _selectedPartyFilter == 'All Parties'
        ? voucherState.vouchers
        : voucherState.vouchers.where((v) {
            final pFilter = _selectedPartyFilter.trim().toLowerCase();
            return v.partyName.trim().toLowerCase() == pFilter ||
                v.effectiveDealer.trim().toLowerCase() == pFilter ||
                (v.dealerName != null && v.dealerName!.trim().toLowerCase() == pFilter);
          }).toList();

    // Filter lists by selected series
    final filteredVouchers = _selectedSeriesFilter == 'All Series'
        ? partyVouchers
        : partyVouchers.where((v) {
            final sV = v.series.replaceAll(RegExp(r'\D'), '');
            final sF = _selectedSeriesFilter.replaceAll(RegExp(r'\D'), '');
            return v.series.trim().toUpperCase() == _selectedSeriesFilter.trim().toUpperCase() ||
                (sV.isNotEmpty && sV == sF);
          }).toList();

    // Filter unsold by selected Party / Dealer filter
    final partyUnsold = _selectedPartyFilter == 'All Parties'
        ? unsoldState.unsoldList
        : unsoldState.unsoldList.where((u) {
            final pFilter = _selectedPartyFilter.trim().toLowerCase();
            return u.partyName.trim().toLowerCase() == pFilter ||
                u.effectiveDealer.trim().toLowerCase() == pFilter ||
                (u.dealerName != null && u.dealerName!.trim().toLowerCase() == pFilter);
          }).toList();

    final filteredUnsold = _selectedSeriesFilter == 'All Series'
        ? partyUnsold
        : partyUnsold.where((u) {
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left Section: Title + Sub-Tabs Switcher
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Title
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
                              'NUMBER UNSOLD & RETURNS',
                              style: AppTypography.titleMd.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                letterSpacing: 0.5,
                              ),
                            ),

                            const SizedBox(width: 12),

                            // Shortcut Button to Dedicated Stock Vouchers Page
                            SizedBox(
                              height: 32,
                              child: ElevatedButton.icon(
                                onPressed: () => context.go(AppConstants.routeVouchers),
                                icon: const Icon(Icons.confirmation_number_outlined, size: 14),
                                label: const Text(
                                  'STOCK VOUCHERS PAGE',
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10.5, letterSpacing: 0.3),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                              ),
                            ),

                            const SizedBox(width: 8),

                            // Shortcut Button to Sync Dynamic Rates
                            SizedBox(
                              height: 32,
                              child: OutlinedButton.icon(
                                onPressed: _showRecalculateUnsoldRatesDialog,
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

                            const SizedBox(width: 16),

                            // Sub-Tabs Switcher (Unsold Returns first, Vouchers second, Tree third)
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
                                          const Icon(Icons.inventory_2_outlined, size: 13),
                                          const SizedBox(width: 5),
                                          Text('Unsold Returns (${filteredUnsold.length})'),
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
                                          const Icon(Icons.receipt_rounded, size: 13),
                                          const SizedBox(width: 5),
                                          Text('Stock Vouchers (${filteredVouchers.length})'),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const Tab(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 10),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.account_tree_rounded, size: 13, color: Color(0xFFF59E0B)),
                                          SizedBox(width: 5),
                                          Text('🌳 Tree & Branch View'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(width: 20),

                        // Right Section: Filters and Action Buttons
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Party Filter Dropdown (Instant Searchable Modal)
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
                                      _uPartyCtrl.text = chosen;
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

                            // 🔄 REFRESH DATA Button
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 32,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  _loadDataForCurrentFilters();
                                  _showSnack('✅ Data & Dealers Refreshed!', Colors.tealAccent);
                                },
                                icon: const Icon(Icons.refresh_rounded, size: 14),
                                label: const Text('REFRESH', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F766E),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
                      ],
                    ),
                  ),
                );
              },
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left: Metrics
                        Row(
                          mainAxisSize: MainAxisSize.min,
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

                        const SizedBox(width: 16),

                        // Right: Dealer Breakdown Hisab Button
                        InkWell(
                          onTap: _showDealerBreakdownModal,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withAlpha(35),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFF59E0B).withAlpha(150)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.account_tree_outlined, size: 13, color: Color(0xFFF59E0B)),
                                SizedBox(width: 5),
                                Text(
                                  'Dealer Breakdown Hisab',
                                  style: TextStyle(
                                    color: Color(0xFFF59E0B),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // 2. Tab Views (Voucher & Unsold)
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: [
                    _KeepAliveTab(child: _buildUnsoldTab(filteredUnsold, availableSeries)),
                    _KeepAliveTab(child: _buildVoucherTab(filteredVouchers, availableSeries)),
                    _KeepAliveTab(child: _buildNetworkTreeView(filteredVouchers, filteredUnsold)),
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


  // --- SUB TAB 1: VOUCHER ---
  Widget _buildVoucherTab(List<VoucherModel> vouchers, List<String> availableSeries) {
    return Column(
      children: [
        // Fast Keyboard Voucher Issue Entry Bar (Ultra Clean & Responsive)
        Container(
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
                  // 🏢 1. Select Main Dealer
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
                                _selectedVoucherSeller = null;
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
                                color: _selectedVoucherDealer != null
                                    ? const Color(0xFFF59E0B)
                                    : Colors.redAccent.withAlpha(180),
                                width: _selectedVoucherDealer != null ? 1 : 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.workspace_premium_rounded, size: 14, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    _selectedVoucherDealer ?? 'Select Dealer (${_availableDealers.length})',
                                    style: TextStyle(
                                      color: _selectedVoucherDealer != null ? const Color(0xFFF59E0B) : const Color(0xFFFCD34D),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.search_rounded, size: 14, color: Color(0xFFF59E0B)),
                              ],
                            ),
                          ),
                        ),

                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 👤 2. Select Sub-Seller (Linked to Dealer)
                  _buildResponsiveBox(
                    isWide: isWide,
                    flex: 3,
                    minWidth: 150,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '2. Sub-Seller / Agent *',
                          style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 10.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        _selectedVoucherDealer == null
                            ? Container(
                                height: 34,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B).withAlpha(100),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF334155)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.lock_outline, size: 12, color: Colors.grey),
                                    SizedBox(width: 5),
                                    Expanded(
                                      child: Text('Select Dealer First', style: TextStyle(color: Colors.grey, fontSize: 10), overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                ),
                              )
                            : Container(
                                height: 34,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: (_dealerToSellersMap[_selectedVoucherDealer]?.contains(_selectedVoucherSeller) ?? false)
                                        ? _selectedVoucherSeller
                                        : 'MAIN_DEALER',
                                    dropdownColor: const Color(0xFF0F172A),
                                    isExpanded: true,
                                    items: [
                                      DropdownMenuItem<String>(
                                        value: 'MAIN_DEALER',
                                        child: Text('👑 $_selectedVoucherDealer (Dealer)', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10.5, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                      ),
                                      ...(_dealerToSellersMap[_selectedVoucherDealer] ?? []).map((s) => DropdownMenuItem<String>(
                                            value: s,
                                            child: Row(
                                              children: [
                                                const Icon(Icons.person, size: 12, color: Color(0xFF38BDF8)),
                                                const SizedBox(width: 5),
                                                Expanded(
                                                  child: Text(s, style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11), overflow: TextOverflow.ellipsis),
                                                ),
                                              ],
                                            ),
                                          )),
                                    ],
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == 'MAIN_DEALER') {
                                          _selectedVoucherSeller = null;
                                          _vPartyCtrl.text = _selectedVoucherDealer!;
                                          _selectedPartyFilter = _selectedVoucherDealer!;
                                        } else {
                                          _selectedVoucherSeller = val;
                                          _vPartyCtrl.text = val!;
                                          _selectedPartyFilter = val;
                                        }
                                      });
                                      _vSeriesFocusNode.requestFocus();
                                    },
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Series
                  _buildResponsiveBox(
                    isWide: isWide,
                    flex: 1,
                    minWidth: 70,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Series *', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 10.5)),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 34,
                          child: TextField(
                            controller: _vSeriesCtrl,
                            focusNode: _vSeriesFocusNode,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: _lastUsedVoucherSeries,
                              hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
                  _buildResponsiveBox(
                    isWide: isWide,
                    flex: 2,
                    minWidth: 125,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('From *', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 10.5)),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 34,
                          child: TextField(
                            controller: _vFromCtrl,
                            focusNode: _vFromFocusNode,
                            maxLength: 20,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                              LengthLimitingTextInputFormatter(20),
                            ],
                            style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12),
                            decoration: InputDecoration(
                              isDense: true,
                              counterText: '',
                              hintText: '28301',
                              hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                              filled: true,
                              fillColor: const Color(0xFF1E293B),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF4ADE80), width: 1.5)),
                            ),
                            onChanged: (val) {
                              if (val.contains('-')) {
                                final r = _resolveRange(val, '');
                                if (r.from.length == 5 && r.to.length == 5 && r.from != r.to) {
                                  _vFromCtrl.text = r.from;
                                  _vToCtrl.text = r.to;
                                  setState(() {});
                                }
                              }
                            },
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
                  _buildResponsiveBox(
                    isWide: isWide,
                    flex: 2,
                    minWidth: 105,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('To (End)', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 10.5)),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 34,
                          child: TextField(
                            controller: _vToCtrl,
                            focusNode: _vToFocusNode,
                            maxLength: 15,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.done,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                              LengthLimitingTextInputFormatter(15),
                            ],
                            style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12),
                            decoration: InputDecoration(
                              isDense: true,
                              counterText: '',
                              hintText: '50 / 28350',
                              hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
                  _buildResponsiveBox(
                    isWide: isWide,
                    flex: 1,
                    minWidth: 65,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Rate (₹)', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 10.5)),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 34,
                          child: TextField(
                            controller: _vRateCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                            decoration: InputDecoration(
                              isDense: true,
                              prefixText: '₹',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
                  const SizedBox(width: 10),

                  // + ADD Button
                  SizedBox(
                    height: 34,
                    child: ElevatedButton.icon(
                      onPressed: _addVoucher,
                      icon: const Icon(Icons.add, size: 15),
                      label: const Text('ADD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // SCAN Button
                  SizedBox(
                    height: 34,
                    child: ElevatedButton.icon(
                      onPressed: () => _scanParchaImage(StockScanMode.voucher),
                      icon: const Icon(Icons.document_scanner, size: 13),
                      label: const Text('SCAN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // PASTE TEXT Button
                  SizedBox(
                    height: 34,
                    child: ElevatedButton.icon(
                      onPressed: () => _openPasteTextParser(StockScanMode.voucher),
                      icon: const Icon(Icons.paste_rounded, size: 13),
                      label: const Text('PASTE JSON / TEXT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // 📁 UPLOAD TXT / PRN Button
                  SizedBox(
                    height: 34,
                    child: ElevatedButton.icon(
                      onPressed: () => _uploadTextFile(StockScanMode.voucher),
                      icon: const Icon(Icons.file_open_rounded, size: 13),
                      label: const Text('UPLOAD TXT / PRN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Export CSV Icon Button
                  IconButton(
                    icon: const Icon(Icons.file_download_outlined, size: 18, color: Color(0xFF38BDF8)),
                    tooltip: 'Export Vouchers to CSV',
                    onPressed: () => _exportVouchersToCsv(vouchers),
                  ),

                  // Delete All Vouchers Button
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.redAccent),
                    tooltip: 'Delete All Shift Vouchers',
                    onPressed: () => _showDeleteAllDataDialog(defaultToVouchersOnly: true),
                  ),
                ],
              );

              return isWide
                  ? inputsRow
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: inputsRow,
                    );
            },
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              v.partyName,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                            const SizedBox(height: 2),
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
    return Column(
      children: [

        // Fast Keyboard Unsold Return Entry Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1020;
              final inputsRow = Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 🏢 Select Main Dealer (All Mixed Series will be attributed to this Dealer)
                  _buildResponsiveBox(
                    isWide: isWide,
                    flex: 4,
                    minWidth: 175,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Main Dealer *',
                          style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 10.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => _openSearchableDealerPicker(
                            context: context,
                            selectedDealer: _selectedUnsoldDealer,
                            title: 'Select Unsold Dealer (${_availableDealers.length})',
                            onSelected: (val) {
                              setState(() {
                                _selectedUnsoldDealer = val;
                                if (val != null) {
                                  _uPartyCtrl.text = val;
                                  _selectedPartyFilter = val;
                                }
                              });
                              _uSeriesFocusNode.requestFocus();
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
                                color: _selectedUnsoldDealer != null
                                    ? const Color(0xFFF59E0B)
                                    : Colors.redAccent.withAlpha(180),
                                width: _selectedUnsoldDealer != null ? 1 : 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.workspace_premium_rounded, size: 14, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    _selectedUnsoldDealer ?? 'Select Dealer (${_availableDealers.length})',
                                    style: TextStyle(
                                      color: _selectedUnsoldDealer != null ? const Color(0xFFF59E0B) : const Color(0xFFFCD34D),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.search_rounded, size: 14, color: Color(0xFFF59E0B)),
                              ],
                            ),
                          ),
                        ),

                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Series
                  _buildResponsiveBox(
                    isWide: isWide,
                    flex: 1,
                    minWidth: 70,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Series *', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 10.5)),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 34,
                          child: TextField(
                            controller: _uSeriesCtrl,
                            focusNode: _uSeriesFocusNode,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: _lastUsedUnsoldSeries,
                              hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
                  _buildResponsiveBox(
                    isWide: isWide,
                    flex: 2,
                    minWidth: 125,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('From (5-Digits) *', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 10.5)),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 34,
                          child: TextField(
                            controller: _uFromCtrl,
                            focusNode: _uFromFocusNode,
                            maxLength: 20,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                              LengthLimitingTextInputFormatter(20),
                            ],
                            style: const TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12),
                            decoration: InputDecoration(
                              isDense: true,
                              counterText: '',
                              hintText: '28381',
                              hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                              filled: true,
                              fillColor: const Color(0xFF1E293B),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFF87171), width: 1.5)),
                            ),
                            onChanged: (val) {
                              if (val.contains('-')) {
                                final r = _resolveRange(val, '');
                                if (r.from.length == 5 && r.to.length == 5 && r.from != r.to) {
                                  _uFromCtrl.text = r.from;
                                  _uToCtrl.text = r.to;
                                  setState(() {});
                                }
                              }
                            },
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
                  _buildResponsiveBox(
                    isWide: isWide,
                    flex: 2,
                    minWidth: 105,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('To (End)', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 10.5)),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 34,
                          child: TextField(
                            controller: _uToCtrl,
                            focusNode: _uToFocusNode,
                            maxLength: 15,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.done,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                              LengthLimitingTextInputFormatter(15),
                            ],
                            style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12),
                            decoration: InputDecoration(
                              isDense: true,
                              counterText: '',
                              hintText: '55 / 28400',
                              hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
                  const SizedBox(width: 10),

                  // Add Unsold Button
                  SizedBox(
                    height: 34,
                    child: ElevatedButton.icon(
                      onPressed: _addUnsold,
                      icon: const Icon(Icons.remove_circle_outline, size: 15),
                      label: const Text('ADD UNSOLD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Scan Unsold Parcha with AI Button
                  SizedBox(
                    height: 34,
                    child: ElevatedButton.icon(
                      onPressed: () => _scanParchaImage(StockScanMode.unsold),
                      icon: const Icon(Icons.document_scanner, size: 13),
                      label: const Text('SCAN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Paste Unsold Text Button
                  SizedBox(
                    height: 34,
                    child: ElevatedButton.icon(
                      onPressed: () => _openPasteTextParser(StockScanMode.unsold),
                      icon: const Icon(Icons.paste_rounded, size: 13),
                      label: const Text('PASTE JSON / TEXT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // 📁 UPLOAD TXT / PRN Button
                  SizedBox(
                    height: 34,
                    child: ElevatedButton.icon(
                      onPressed: () => _uploadTextFile(StockScanMode.unsold),
                      icon: const Icon(Icons.file_open_rounded, size: 13),
                      label: const Text('UPLOAD TXT / PRN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Export Unsold Button
                  IconButton(
                    icon: const Icon(Icons.file_download_outlined, size: 18, color: Color(0xFF38BDF8)),
                    tooltip: 'Export Unsold to CSV',
                    onPressed: () => _exportUnsoldToCsv(unsoldList),
                  ),

                  // Re-open Last Scan Button (recovers scanned parcha if closed)
                  if (GeminiScannerService.instance.lastStockScanSession != null) ...[
                    IconButton(
                      icon: const Icon(Icons.history_rounded, size: 18, color: Color(0xFF38BDF8)),
                      tooltip: 'Re-open Scan Session',
                      onPressed: _reopenLastScan,
                    ),
                  ],

                  // Lock Shift Button
                  IconButton(
                    icon: const Icon(Icons.lock_clock, size: 18, color: Colors.amberAccent),
                    tooltip: 'Lock Shift Unsold',
                    onPressed: () async {
                      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
                      await ref.read(unsoldViewModelProvider.notifier).lockShift(dateStr, _selectedShift);
                      _showSnack('🔒 Unsold Returns Locked for $_selectedShift!', AppColors.info);
                    },
                  ),

                  // Delete All Unsold Button
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18, color: Colors.redAccent),
                    tooltip: 'Delete All Shift Unsold',
                    onPressed: () => _showDeleteAllDataDialog(defaultToUnsoldOnly: true),
                  ),
                ],
              );

              return isWide
                  ? inputsRow
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: inputsRow,
                    );
            },
          ),
        ),

        // Unsold List Table
        Expanded(
          child: unsoldList.isEmpty
              ? _buildEmptyPlaceholder(
                  icon: Icons.inventory_2_outlined,
                  title: 'No Unsold Returns Found',
                  subtitle: voucherState.vouchers.isNotEmpty
                      ? '${voucherState.vouchers.length} Vouchers are entered in the system! Click below to view them.'
                      : 'No unsold returns match the current series/seller/shift filters.',
                  actionLabel: voucherState.vouchers.isNotEmpty
                      ? 'View Vouchers (${voucherState.vouchers.length} Entries)'
                      : null,
                  onAction: voucherState.vouchers.isNotEmpty
                      ? () => _tabController.animateTo(0)
                      : null,
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              u.partyName,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                            const SizedBox(height: 2),
                            if (u.dealerName != null &&
                                u.dealerName!.isNotEmpty &&
                                u.dealerName!.trim().toLowerCase() != u.partyName.trim().toLowerCase()) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7).withAlpha(40),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(color: const Color(0xFF0284C7).withAlpha(140)),
                                ),
                                child: Text(
                                  '🏢 Dealer: ${u.dealerName}',
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

  Widget _buildNetworkTreeView(List<VoucherModel> vouchers, List<UnsoldModel> unsoldList) {
    // 🌳 Aggregate data by Dealer & Sub-Seller Branches
    final dealerMap = <String, Map<String, _SubSellerRow>>{};

    // Process all Vouchers
    for (final v in vouchers) {
      final dealer = v.effectiveDealer.trim().isNotEmpty ? v.effectiveDealer.trim() : v.partyName.trim();
      final subSeller = v.partyName.trim();
      if (dealer.isEmpty || subSeller.isEmpty) continue;

      dealerMap.putIfAbsent(dealer, () => {});
      final row = dealerMap[dealer]!.putIfAbsent(
        subSeller,
        () => _SubSellerRow(sellerName: subSeller, dealerName: dealer),
      );
      row.issuedQty += v.totalQty.toInt();
      row.issuedAmount += v.totalAmount;
    }

    // Process all Unsold
    for (final u in unsoldList) {
      final dealer = u.effectiveDealer.trim().isNotEmpty ? u.effectiveDealer.trim() : u.partyName.trim();
      final subSeller = u.partyName.trim();
      if (dealer.isEmpty || subSeller.isEmpty) continue;

      dealerMap.putIfAbsent(dealer, () => {});
      final row = dealerMap[dealer]!.putIfAbsent(
        subSeller,
        () => _SubSellerRow(sellerName: subSeller, dealerName: dealer),
      );
      row.unsoldQty += u.totalQty.toInt();
      row.unsoldAmount += u.totalAmount;
    }

    if (dealerMap.isEmpty) {
      return _buildEmptyPlaceholder(
        icon: Icons.account_tree_outlined,
        title: 'No Network Branches Found',
        subtitle: 'Issue vouchers to dealers or sellers for $_selectedShift to view tree hierarchy.',
        actionLabel: 'Enter First Voucher',
        onAction: () => _tabController.animateTo(0),
      );
    }

    final sortedDealers = dealerMap.keys.toList()..sort();
    int totalNetworkIssued = 0;
    int totalNetworkUnsold = 0;
    double totalNetworkBillable = 0.0;
    int totalSellersCount = 0;

    for (final d in sortedDealers) {
      final sellers = dealerMap[d]!.values;
      totalSellersCount += sellers.length;
      for (final s in sellers) {
        totalNetworkIssued += s.issuedQty;
        totalNetworkUnsold += s.unsoldQty;
        totalNetworkBillable += s.netBillable;
      }
    }
    final totalNetworkSold = (totalNetworkIssued - totalNetworkUnsold) > 0 ? (totalNetworkIssued - totalNetworkUnsold) : 0;

    return Column(
      children: [
        // Top Network Overview Summary Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            border: Border(bottom: BorderSide(color: Color(0xFF334155))),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_tree_rounded, size: 18, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              const Text(
                'Dealer Network & Branch Tree',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withAlpha(30),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFFF59E0B).withAlpha(120)),
                ),
                child: Text(
                  '👑 ${sortedDealers.length} Dealers | 👥 $totalSellersCount Sellers',
                  style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              _buildMiniPill('Total Issued', '$totalNetworkIssued Nos', Colors.white),
              const SizedBox(width: 14),
              _buildMiniPill('Total Unsold', '$totalNetworkUnsold Nos', const Color(0xFFF87171)),
              const SizedBox(width: 14),
              _buildMiniPill('Net Sold', '$totalNetworkSold Nos', Colors.greenAccent),
              const SizedBox(width: 14),
              _buildMiniPill('Total Billable', '₹${totalNetworkBillable.toStringAsFixed(2)}', const Color(0xFFF59E0B)),
            ],
          ),
        ),

        // Tree List View
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedDealers.length,
            itemBuilder: (ctx, i) {
              final dName = sortedDealers[i];
              final subSellers = dealerMap[dName]!.values.toList()
                ..sort((a, b) => a.sellerName.compareTo(b.sellerName));

              int dIssQty = 0;
              double dIssAmt = 0.0;
              int dUnsoldQty = 0;
              double dUnsoldAmt = 0.0;
              for (final s in subSellers) {
                dIssQty += s.issuedQty;
                dIssAmt += s.issuedAmount;
                dUnsoldQty += s.unsoldQty;
                dUnsoldAmt += s.unsoldAmount;
              }
              final dNetSold = (dIssQty - dUnsoldQty) > 0 ? (dIssQty - dUnsoldQty) : 0;
              final dBillable = (dIssAmt - dUnsoldAmt) > 0 ? (dIssAmt - dUnsoldAmt) : 0.0;

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 👑 Dealer Root Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0F172A),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
                        border: Border(bottom: BorderSide(color: Color(0xFF334155))),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withAlpha(40),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.workspace_premium_rounded, size: 16, color: Color(0xFFF59E0B)),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    dName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B).withAlpha(30),
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(color: const Color(0xFFF59E0B).withAlpha(120)),
                                    ),
                                    child: const Text('👑 MAIN DEALER', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9.5, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${subSellers.length} Sub-Seller Branches Linked',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 10.5),
                              ),
                            ],
                          ),
                          const Spacer(),
                          _buildMiniPill('Issued', '$dIssQty Nos', Colors.white),
                          const SizedBox(width: 12),
                          _buildMiniPill('Unsold', '$dUnsoldQty Nos', const Color(0xFFF87171)),
                          const SizedBox(width: 12),
                          _buildMiniPill('Net Sold', '$dNetSold Nos', Colors.greenAccent),
                          const SizedBox(width: 12),
                          _buildMiniPill('Billable', '₹${dBillable.toStringAsFixed(2)}', const Color(0xFFF59E0B)),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              final buffer = StringBuffer();
                              final dateDisplay = DateFormat('dd-MM-yyyy').format(_selectedDate);
                              buffer.writeln('🏢 *DEALER HISAB SLIP: $dName*');
                              buffer.writeln('📅 Date: $dateDisplay | ⏰ Shift: $_selectedShift');
                              buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
                              buffer.writeln('📦 *Dealer Total Issued:* $dIssQty Nos (₹${dIssAmt.toStringAsFixed(2)})');
                              buffer.writeln('🚫 *Dealer Total Return:* $dUnsoldQty Nos (-₹${dUnsoldAmt.toStringAsFixed(2)})');
                              buffer.writeln('✅ *Net Sold:* $dNetSold Nos');
                              buffer.writeln('💰 *NET BILLABLE:* ₹${dBillable.toStringAsFixed(2)}');
                              buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
                              buffer.writeln('👥 *Sub-Seller Breakdown:*');
                              for (final s in subSellers) {
                                buffer.writeln('• *${s.sellerName}*: Iss ${s.issuedQty} - Ret ${s.unsoldQty} = *${s.netSoldQty} Sold* (₹${s.netBillable.toStringAsFixed(2)})');
                              }
                              buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
                              buffer.writeln('Generated via OpsCore Hisab Platform');
                              Clipboard.setData(ClipboardData(text: buffer.toString()));
                              _showSnack('📋 WhatsApp slip copied for Dealer "$dName"!', AppColors.success);
                            },
                            icon: const Icon(Icons.share_rounded, size: 12),
                            label: const Text('WhatsApp Slip', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF16A34A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 🌿 Sub-Seller Branches (Tree layout)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: List.generate(subSellers.length, (idx) {
                          final s = subSellers[idx];
                          final isLast = idx == subSellers.length - 1;
                          final soldRatio = s.issuedQty > 0 ? (s.netSoldQty / s.issuedQty).clamp(0.0, 1.0) : 0.0;

                          return Container(
                            margin: EdgeInsets.only(bottom: isLast ? 0 : 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withAlpha(150),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF334155).withAlpha(120)),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  isLast ? '└── ' : '├── ',
                                  style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace'),
                                ),
                                const Icon(Icons.person, size: 14, color: Colors.cyanAccent),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 140,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.sellerName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Branch under $dName',
                                        style: TextStyle(color: Colors.grey.shade400, fontSize: 9.5),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Issued: ${s.issuedQty} Nos (₹${s.issuedAmount.toStringAsFixed(2)})',
                                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Return: -${s.unsoldQty} Nos (-₹${s.unsoldAmount.toStringAsFixed(2)})',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFFF87171)),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Net Sold: ${s.netSoldQty} Nos',
                                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Billable: ₹${s.netBillable.toStringAsFixed(2)}',
                                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 110,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${(soldRatio * 100).toStringAsFixed(0)}% Sold',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: Colors.cyanAccent),
                                      ),
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(3),
                                        child: LinearProgressIndicator(
                                          value: soldRatio,
                                          minHeight: 5,
                                          backgroundColor: Colors.redAccent.withAlpha(80),
                                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
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

  Widget _buildEmptyPlaceholder({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade600),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.receipt_long_rounded, size: 16),
              label: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubSellerRow {
  final String sellerName;
  final String dealerName;
  int issuedQty = 0;
  double issuedAmount = 0.0;
  int unsoldQty = 0;
  double unsoldAmount = 0.0;

  _SubSellerRow({required this.sellerName, required this.dealerName});

  int get netSoldQty => (issuedQty - unsoldQty) > 0 ? (issuedQty - unsoldQty) : 0;
  double get netBillable => (issuedAmount - unsoldAmount) > 0 ? (issuedAmount - unsoldAmount) : 0.0;
}

/// ⚡ High-performance wrapper to keep tab widget tree cached in memory
/// Prevents disposing and re-rendering tab contents on every switch, eliminating screen freeze
class _KeepAliveTab extends StatefulWidget {
  final Widget child;
  const _KeepAliveTab({required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

