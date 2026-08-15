import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/database/database_service.dart';
import '../../../core/database/supabase_service.dart';
import '../../../core/services/pattern_matcher_service.dart';
import '../viewmodels/ticket_sales_viewmodel.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../../settings/viewmodels/series_price_viewmodel.dart';
import '../../sellers/viewmodels/seller_customer_viewmodel.dart';
import '../../settings/viewmodels/draw_time_viewmodel.dart';
import '../widgets/booking_history_dialog.dart';
import '../widgets/pattern_resolver_dialog.dart';

/// Data structure for live Counter Booking items
class CounterBookingRow {
  final String id;
  final int sl;
  final String series;
  final String ticketNo;
  final double amount;
  final String time;
  final String sellerName;
  final int quantity;

  CounterBookingRow({
    String? id,
    required this.sl,
    required this.series,
    required this.ticketNo,
    required this.amount,
    required this.time,
    required this.sellerName,
    this.quantity = 1,
  }) : id = id ?? 'row_${series}_${ticketNo}_${time}_$sl';

  int get qty => quantity;
  String get mode => 'Cash';
  String get remark => '';
  double get total => amount * quantity;

  CounterBookingRow copyWith({
    String? id,
    int? sl,
    String? series,
    String? ticketNo,
    double? amount,
    String? time,
    String? sellerName,
    int? quantity,
  }) {
    return CounterBookingRow(
      id: id ?? this.id,
      sl: sl ?? this.sl,
      series: series ?? this.series,
      ticketNo: ticketNo ?? this.ticketNo,
      amount: amount ?? this.amount,
      time: time ?? this.time,
      sellerName: sellerName ?? this.sellerName,
      quantity: quantity ?? this.quantity,
    );
  }
}

class TicketSalesScreen extends ConsumerStatefulWidget {
  const TicketSalesScreen({super.key});

  @override
  ConsumerState<TicketSalesScreen> createState() => _TicketSalesScreenState();
}

class _TicketSalesScreenState extends ConsumerState<TicketSalesScreen> {
  final FocusNode _keyboardFocusNode = FocusNode();
  final FocusNode _sellerFocusNode = FocusNode();
  final FocusNode _seriesFocusNode = FocusNode();
  final FocusNode _ticketNoFocusNode = FocusNode();
  Set<String> _selectedRowIds = {};

  @override
  void initState() {
    super.initState();
    PatternMatcherService.instance.initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final sellerState = ref.read(sellerCustomerViewModelProvider);
        if (sellerState.sellers.isNotEmpty) {
          setState(() {
            _sellerName = sellerState.sellers.first.name;
            _sellerInputCtrl.text = _sellerName;
          });
        }
        await _loadExistingSalesIntoTable();
        if (_sellerFocusNode.canRequestFocus) {
          _sellerFocusNode.requestFocus();
        }
      }
    });
  }

  bool _matchesShift(String drawName, String selectedShift) {
    if (selectedShift == 'All' || selectedShift == 'All Shifts') return true;
    final d = drawName.toLowerCase();
    final s = selectedShift.toLowerCase();

    if (s.contains('morning') || s.contains('1')) {
      return d.contains('1:00') || d.contains('morning') || d.contains('1 pm') || d.contains('1pm') || d.contains('1-pm') || d.contains('1_pm') || d.contains('dear 1') || d.contains('dear-1');
    }
    if (s.contains('day') || s.contains('6')) {
      return d.contains('6:00') || d.contains('day') || d.contains('6 pm') || d.contains('6pm') || d.contains('6-pm') || d.contains('6_pm') || d.contains('dear 6') || d.contains('dear-6');
    }
    if (s.contains('night') || s.contains('8')) {
      return d.contains('8:00') || d.contains('night') || d.contains('8 pm') || d.contains('8pm') || d.contains('8-pm') || d.contains('8_pm') || d.contains('dear 8') || d.contains('dear-8') || d.contains('evening');
    }
    if (s.contains('evening')) {
      return d.contains('8:00') || d.contains('evening') || d.contains('night') || d.contains('8 pm') || d.contains('8pm') || d.contains('6:00') || d.contains('6 pm') || d.contains('6pm');
    }
    return d.contains(s);
  }

  void _syncSalesListToTableRows(List<TicketSaleModel> sales) {
    if (!mounted) return;
    final targetYmd = "${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";

    final List<CounterBookingRow> newRows = [];
    int slCounter = 1;

    for (int i = 0; i < sales.length; i++) {
      final s = sales[i];
      final sDate = s.drawDate.toLocal();
      final rawIso = s.drawDate.toIso8601String();
      final rawYmd = rawIso.length >= 10 ? rawIso.substring(0, 10) : '';

      final saleDateLocal = s.saleDate.toLocal();
      final saleRawIso = s.saleDate.toIso8601String();
      final saleRawYmd = saleRawIso.length >= 10 ? saleRawIso.substring(0, 10) : '';

      // Strictly match by Draw Date only (so tickets for 13/8 or 14/8 only appear on their respective draw dates)
      final isSameDate = (sDate.year == _selectedDate.year &&
              sDate.month == _selectedDate.month &&
              sDate.day == _selectedDate.day) ||
          (rawYmd == targetYmd);

      if (!isSameDate) continue;
      if (!_matchesShift(s.drawName, _selectedShift)) continue;

      final parts = s.ticketNumber.trim().split(' ');
      final tNo = parts.length > 1 ? parts.last : s.ticketNumber;

      String cleanSeller = s.agentName.isNotEmpty ? s.agentName : (s.buyerName.isNotEmpty ? s.buyerName : 'Walk-in Customer');
      if (cleanSeller.contains('(')) {
        cleanSeller = cleanSeller.replaceAll(RegExp(r'\(.*?\)'), '').trim();
      }
      if (cleanSeller.startsWith('WA:')) {
        cleanSeller = cleanSeller.replaceFirst(RegExp(r'^WA:\s*', caseSensitive: false), '').trim();
      }
      if (cleanSeller.isEmpty) {
        cleanSeller = 'Walk-in Customer';
      }

      newRows.add(CounterBookingRow(
        id: s.id,
        sl: slCounter++,
        series: s.ticketSeries,
        ticketNo: tNo,
        amount: s.pricePerTicket,
        time: DateFormat('HH:mm').format(s.saleDate.toLocal()),
        sellerName: cleanSeller,
        quantity: s.quantity,
      ));
    }

    setState(() {
      _bookingRows.clear();
      _bookingRows.addAll(newRows);
    });
  }

  Future<void> _loadExistingSalesIntoTable() async {
    if (!mounted) return;
    await ref.read(ticketSalesViewModelProvider.notifier).loadSales();
    if (!mounted) return;
    final sales = ref.read(ticketSalesViewModelProvider).sales;
    _syncSalesListToTableRows(sales);
  }

  void _showPatternResolverDialog() {
    showDialog(
      context: context,
      builder: (ctx) => PatternResolverDialog(
        onTicketsResolved: (tickets, sender, senderName) {
          _handleResolvedTickets(tickets, sender, senderName);
        },
      ),
    );
  }

  Future<void> _handleResolvedTickets(List<ParsedTicketItem> tickets, String sender, String? senderName) async {
    if (!mounted) return;
    final seriesState = ref.read(seriesPriceViewModelProvider);
    final agentName = senderName ?? 'WA: $sender';
    int addedCount = 0;

    for (final t in tickets) {
      if (!mounted) return;

      double ticketPrice = seriesState.getPriceForSeries(t.series);
      if (ticketPrice <= 0) {
        final digits = t.series.replaceAll(RegExp(r'\D'), '');
        ticketPrice = double.tryParse(digits) ?? (double.tryParse(_amountCtrl.text) ?? 100.0);
      }
      final totalAmount = ticketPrice * t.quantity;
      final uniqueMicro = DateTime.now().microsecondsSinceEpoch;

      final newSale = TicketSaleModel(
        id: 'tkt_res_${uniqueMicro}_${t.series}_${t.ticketNo}_$addedCount',
        receiptNumber: 'REC-${t.series}-${t.ticketNo}',
        buyerName: agentName,
        buyerPhone: sender,
        agentCode: 'AG-WA',
        agentName: agentName,
        drawCode: _selectedLottery.replaceAll(' ', '-').toUpperCase(),
        drawName: _selectedLottery,
        ticketSeries: t.series,
        ticketNumber: '${t.series} ${t.ticketNo}',
        quantity: t.quantity,
        pricePerTicket: ticketPrice,
        totalAmount: totalAmount,
        commissionAmount: totalAmount * 0.05,
        status: TicketStatus.sold,
        paymentMode: PaymentMode.cash,
        saleDate: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, DateTime.now().hour, DateTime.now().minute, DateTime.now().second),
        drawDate: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 12, 0, 0),
      );

      await ref.read(ticketSalesViewModelProvider.notifier).addTicketSale(newSale);
      addedCount++;
    }
    if (!mounted) return;
    await _loadExistingSalesIntoTable();
    if (!mounted) return;
    if (addedCount > 0) {
      _showSnackbar('🎯 Added $addedCount ticket(s) to Counter Table with Series Pricing!', AppColors.success);
    }
  }


  // Top Metadata State
  String _selectedShift = 'All Shifts';
  String _selectedLottery = 'Dear 1 PM';
  DateTime _selectedDate = DateTime.now();
  String _sellerName = '';

  // Available options
  final List<String> _shiftList = ['All Shifts', 'Morning', 'Day', 'Evening', 'Night'];
  // Input Field Controllers
  final TextEditingController _sellerInputCtrl = TextEditingController();
  final TextEditingController _seriesInputCtrl = TextEditingController();
  final TextEditingController _ticketNoCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController(text: '100');
  final TextEditingController _tableSearchCtrl = TextEditingController();
  String _tableSearchQuery = '';

  // Live Booking Table List & Last Added Entry Reference
  final List<CounterBookingRow> _bookingRows = [];
  CounterBookingRow? _lastAddedRow;
  String _lastUsedSeries = '';

  // View Mode: POS Counter vs Sales History Ledger
  bool _showLedgerHistory = false;

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    _sellerFocusNode.dispose();
    _seriesFocusNode.dispose();
    _ticketNoFocusNode.dispose();
    _sellerInputCtrl.dispose();
    _seriesInputCtrl.dispose();
    _ticketNoCtrl.dispose();
    _amountCtrl.dispose();
    _tableSearchCtrl.dispose();
    super.dispose();
  }

  // Summary getters
  int get _totalBookingCount => _bookingRows.length;
  double get _totalAmount =>
      _bookingRows.fold(0.0, (sum, row) => sum + row.total);

  // Inline Seller match handler — No popup needed!
  void _onSellerSubmitted(String val) {
    String query = val.trim().toLowerCase();
    final sellerState = ref.read(sellerCustomerViewModelProvider);
    final sellers = sellerState.sellers.where((s) => s.isActive).toList();

    if (query.isEmpty) {
      if (_sellerName.isEmpty && sellers.isNotEmpty) {
        _sellerName = sellers.first.name;
      }
      _sellerInputCtrl.text = _sellerName;
      _seriesFocusNode.requestFocus();
      return;
    }

    final matches = sellers.where((s) {
      return s.name.toLowerCase().contains(query) ||
          s.accessKey.toLowerCase().contains(query) ||
          s.phone.contains(query);
    }).toList();

    if (matches.isNotEmpty) {
      final matched = matches.first;
      setState(() {
        _sellerName = matched.name;
        _sellerInputCtrl.text = matched.name;
      });
      _showSnackbar('Seller: ${matched.name} (${matched.accessKey})', AppColors.success);
      _seriesFocusNode.requestFocus();
    } else {
      final customName = val.trim();
      setState(() {
        _sellerName = customName.isNotEmpty ? customName : 'Walk-in Customer';
        _sellerInputCtrl.text = _sellerName;
      });
      _showSnackbar('Customer / Seller set to "$_sellerName"', AppColors.success);
      _seriesFocusNode.requestFocus();
    }
  }

  String _formatPrice(double price) {
    if (price % 1 == 0) {
      return price.toInt().toString();
    }
    return price.toStringAsFixed(2);
  }

  void _updatePriceForSeries(String val) {
    final seriesEntered = val.trim().toUpperCase();
    if (seriesEntered.isEmpty) return;

    final seriesState = ref.read(seriesPriceViewModelProvider);
    double calculatedPrice = seriesState.getPriceForSeries(seriesEntered);

    if (calculatedPrice <= 0) {
      // Fetch Series 100 price dynamically from System Configuration database (No hardcoding!)
      double config100Price = 0.0;
      final activeSeries = seriesState.seriesList.where((s) => s.isActive).toList();
      if (activeSeries.isNotEmpty) {
        final s100 = activeSeries.where((s) => s.seriesName.trim() == '100');
        if (s100.isNotEmpty && s100.first.ticketPrice > 0) {
          config100Price = s100.first.ticketPrice;
        } else {
          config100Price = activeSeries.first.ticketPrice;
        }
      }

      if (config100Price > 0) {
        final singleSeriesRate = config100Price >= 100 ? (config100Price / 100.0) : config100Price;
        final digits = seriesEntered.replaceAll(RegExp(r'\D'), '');
        final multiplier = double.tryParse(digits) ?? 1.0;
        calculatedPrice = (multiplier > 0 ? multiplier : 1.0) * singleSeriesRate;
      }
    }

    if (calculatedPrice > 0) {
      setState(() {
        _amountCtrl.text = _formatPrice(calculatedPrice);
      });
    }
  }

  // Validate Series and shift focus to Ticket No
  void _onSeriesSubmitted(String val) {
    String seriesEntered = val.trim().toUpperCase();
    if (seriesEntered.isEmpty) {
      if (_lastUsedSeries.isNotEmpty) {
        seriesEntered = _lastUsedSeries.toUpperCase();
      } else {
        final seriesState = ref.read(seriesPriceViewModelProvider);
        if (seriesState.availableSeriesNames.isNotEmpty) {
          seriesEntered = seriesState.availableSeriesNames.first.toUpperCase();
        }
      }
    }

    if (seriesEntered.isEmpty) {
      _showSnackbar('Please enter Series name!', AppColors.warning);
      _seriesFocusNode.requestFocus();
      return;
    }

    _updatePriceForSeries(seriesEntered);
    _lastUsedSeries = seriesEntered;
    _seriesInputCtrl.text = seriesEntered;

    // Focus shifts to Ticket No
    _ticketNoFocusNode.requestFocus();
  }

  // Add new booking entry with Series Validation & Auto-Reuse of Last Series
  void _addBookingRow() {
    String ticketNo = _ticketNoCtrl.text.trim();
    String seriesEntered = _seriesInputCtrl.text.trim().toUpperCase();

    // 💡 Auto-parse parenthesized format e.g. "(24)86286" or "(24) 86286"
    final parenMatch = RegExp(r'^\(([A-Za-z0-9]{1,4})\)\s*(\d{5})$').firstMatch(ticketNo.isEmpty ? seriesEntered : ticketNo);
    if (parenMatch != null) {
      seriesEntered = parenMatch.group(1)!.toUpperCase();
      ticketNo = parenMatch.group(2)!;
      _seriesInputCtrl.text = seriesEntered;
      _ticketNoCtrl.text = ticketNo;
    }

    // Auto-reuse LAST ENTERED SERIES if operator leaves Series empty!
    if (seriesEntered.isEmpty) {
      if (_lastUsedSeries.isNotEmpty) {
        seriesEntered = _lastUsedSeries.toUpperCase();
      } else {
        final seriesState = ref.read(seriesPriceViewModelProvider);
        if (seriesState.availableSeriesNames.isNotEmpty) {
          seriesEntered = seriesState.availableSeriesNames.first.toUpperCase();
        }
      }
    }

    if (seriesEntered.isEmpty) {
      _showSnackbar('Please enter Series name first!', AppColors.warning);
      _seriesFocusNode.requestFocus();
      return;
    }

    if (ticketNo.length != 5) {
      _showSnackbar(
        'Ticket Number must be exactly 5 digits!',
        AppColors.warning,
      );
      _ticketNoFocusNode.requestFocus();
      return;
    }

    // Ensure System Configuration has active series pricing configured
    final seriesState = ref.read(seriesPriceViewModelProvider);
    final activeMasterSeries = seriesState.seriesList.where((s) => s.isActive).toList();

    if (activeMasterSeries.isEmpty) {
      _showSnackbar(
        'System Configuration series price is missing! Please set Series 100 price in System Configuration first.',
        AppColors.error,
      );
      _seriesFocusNode.requestFocus();
      return;
    }

    final double amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;

    // User Directive: Allow all ticket entries unconditionally (even for duplicate ticket numbers or names)

    // Dynamically fetch typed customer/seller name from input field
    final typedSeller = _sellerInputCtrl.text.trim();
    if (typedSeller.isNotEmpty) {
      _sellerName = typedSeller;
    }
    final activeSellerName = _sellerName.isNotEmpty ? _sellerName : 'Walk-in Customer';

    final nowTime = DateFormat('HH:mm').format(DateTime.now());
    final uniqueMicro = DateTime.now().microsecondsSinceEpoch;
    final saleId = 'tkt_counter_${uniqueMicro}_${seriesEntered}_${ticketNo}_${_bookingRows.length + 1}';
    final newRow = CounterBookingRow(
      id: saleId,
      sl: _bookingRows.length + 1,
      series: seriesEntered,
      ticketNo: ticketNo,
      amount: amount,
      time: nowTime,
      sellerName: activeSellerName,
    );

    setState(() {
      _lastUsedSeries = seriesEntered; // Remember last used series for fast reuse!
      _lastAddedRow = newRow;
      _bookingRows.insert(0, newRow); // Insert at TOP so newest is always visible!
      _reindexRows();
      _ticketNoCtrl.clear();
      _seriesInputCtrl.clear();
    });

    // INSTANT PERMANENT SAVE TO SQLITE DATABASE (opscore_pro.db)
    final sale = TicketSaleModel(
      id: saleId,
      receiptNumber: 'REC-${newRow.series}-${newRow.ticketNo}',
      buyerName: newRow.sellerName.isNotEmpty ? newRow.sellerName : 'Walk-in Customer',
      buyerPhone: '+91 9876543210',
      agentCode: 'AG-POS',
      agentName: newRow.sellerName.isNotEmpty ? newRow.sellerName : 'Walk-in Customer',
      drawCode: _selectedLottery.replaceAll(' ', '-').toUpperCase(),
      drawName: _selectedLottery,
      ticketSeries: newRow.series,
      ticketNumber: '${newRow.series} ${newRow.ticketNo}',
      quantity: newRow.qty,
      pricePerTicket: newRow.amount,
      totalAmount: newRow.total,
      commissionAmount: newRow.total * 0.05,
      status: TicketStatus.sold,
      paymentMode: _paymentModeFromString(newRow.mode),
      saleDate: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, DateTime.now().hour, DateTime.now().minute, DateTime.now().second),
      drawDate: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 12, 0, 0),
    );
    ref.read(ticketSalesViewModelProvider.notifier).addTicketSale(sale);

    // Auto focus back to Series field after saving
    _seriesFocusNode.requestFocus();

    _showSnackbar(
      '✅ Saved Ticket #${newRow.series}-$ticketNo to Database permanently! (₹${_formatPrice(amount)})',
      AppColors.success,
    );
  }

  Future<void> _deleteRow(CounterBookingRow row) async {
    setState(() {
      _selectedRowIds.remove(row.id);
      _bookingRows.removeWhere((r) => r.id == row.id || (r.series == row.series && r.ticketNo == row.ticketNo));
      _reindexRows();
    });

    // 🗑️ PERMANENT DELETE FROM SQLITE DB AND SUPABASE CLOUD DB
    await DatabaseService.instance.deleteTicketSale(row.id);
    await SupabaseService.instance.deleteCloudTicketSale(row.id);
    await DatabaseService.instance.deleteTicketSaleBySeriesAndNumber(row.series, row.ticketNo);
    await SupabaseService.instance.deleteCloudTicketSaleBySeriesAndNumber(row.series, row.ticketNo);
    await ref.read(ticketSalesViewModelProvider.notifier).loadSales();

    _showSnackbar('🗑️ Ticket #${row.series}-${row.ticketNo} deleted permanently from Database & Cloud!', AppColors.info);
  }

  bool get _isAllSelected =>
      _bookingRows.isNotEmpty && _selectedRowIds.length == _bookingRows.length;

  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected) {
        _selectedRowIds.clear();
      } else {
        _selectedRowIds = _bookingRows.map((r) => r.id).toSet();
      }
    });
  }

  void _toggleSelectRow(String id) {
    setState(() {
      if (_selectedRowIds.contains(id)) {
        _selectedRowIds.remove(id);
      } else {
        _selectedRowIds.add(id);
      }
    });
  }

  Future<void> _bulkDeleteSelected() async {
    if (_selectedRowIds.isEmpty) return;

    final count = _selectedRowIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 26),
            const SizedBox(width: 10),
            Text('Bulk Delete $count Ticket(s)', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
          ],
        ),
        content: Text(
          'Are you sure you want to PERMANENTLY DELETE $count selected ticket bookings from Database & Cloud?',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            icon: const Icon(Icons.delete_sweep, color: Colors.white),
            label: const Text('DELETE SELECTED PERMANENTLY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final selectedRows = _bookingRows.where((r) => _selectedRowIds.contains(r.id)).toList();
      final idsToDelete = selectedRows.map((r) => r.id).where((id) => id.isNotEmpty).toList();

      setState(() {
        _bookingRows.removeWhere((r) => _selectedRowIds.contains(r.id));
        _selectedRowIds.clear();
        _reindexRows();
      });

      // 🗑️ PERMANENT DELETE FROM SQLITE DB AND SUPABASE CLOUD DB FOR ALL SELECTED ROWS
      await DatabaseService.instance.deleteTicketSalesByIds(idsToDelete);
      await SupabaseService.instance.deleteCloudTicketSalesByIds(idsToDelete);
      for (final row in selectedRows) {
        await DatabaseService.instance.deleteTicketSaleBySeriesAndNumber(row.series, row.ticketNo);
        await SupabaseService.instance.deleteCloudTicketSaleBySeriesAndNumber(row.series, row.ticketNo);
      }
      await ref.read(ticketSalesViewModelProvider.notifier).loadSales();

      _showSnackbar('🗑️ Deleted $count selected ticket(s) permanently from Database & Cloud!', AppColors.success);
    }
  }

  void _reindexRows() {
    for (int i = 0; i < _bookingRows.length; i++) {
      _bookingRows[i] = _bookingRows[i].copyWith(sl: i + 1);
    }
  }

  void _clearAllRows() {
    if (_bookingRows.isEmpty) return;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Clear All Session Bookings?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to clear all current counter entries?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
            },
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              setState(() {
                _bookingRows.clear();
              });
              if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
              _showSnackbar('All counter entries cleared', AppColors.warning);
            },
            child: const Text(
              'Clear All',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // Search & Select Customer / Seller Modal Dialog
  void _openSellerSearchDialog() {
    final sellerState = ref.read(sellerCustomerViewModelProvider);
    final sellers = sellerState.sellers.where((s) => s.isActive).toList();
    final searchCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(160),
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final query = searchCtrl.text.toLowerCase().trim();
            final filtered = query.isEmpty
                ? sellers
                : sellers.where((s) {
                    return s.name.toLowerCase().contains(query) ||
                        s.accessKey.toLowerCase().contains(query) ||
                        s.phone.contains(query);
                  }).toList();

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
                      color: AppColors.primaryContainer,
                      borderRadius: AppDecorations.radiusDefault,
                    ),
                    child: const Icon(
                      Icons.person_search_outlined,
                      color: AppColors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Select Customer / Seller',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                height: 380,
                child: Column(
                  children: [
                    TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Type to search Seller Name or Key...',
                        hintStyle: TextStyle(
                            color: AppColors.textSecondary.withAlpha(120)),
                        prefixIcon: const Icon(Icons.search,
                            color: AppColors.textSecondary),
                        filled: true,
                        fillColor: AppColors.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: AppDecorations.radiusDefault,
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'No matching seller found!',
                                style: TextStyle(
                                    color: AppColors.textSecondary
                                        .withAlpha(150)),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1, color: AppColors.border),
                              itemBuilder: (ctx, idx) {
                                final s = filtered[idx];
                                final isSelected = _sellerName == s.name;

                                return ListTile(
                                  dense: true,
                                  tileColor: isSelected
                                      ? AppColors.primaryContainer.withAlpha(40)
                                      : null,
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected
                                        ? AppColors.primary
                                        : AppColors.surfaceContainerHighest,
                                    child: Text(
                                      s.name.substring(0, 1).toUpperCase(),
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    s.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Key: ${s.accessKey} | Phone: ${s.phone.isNotEmpty ? s.phone : "N/A"}',
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12),
                                  ),
                                  trailing: isSelected
                                      ? const Icon(Icons.check_circle,
                                          color: AppColors.primary)
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      _sellerName = s.name;
                                    });
                                    Navigator.pop(dialogCtx);
                                    _seriesFocusNode.requestFocus();
                                    _showSnackbar(
                                      'Selected Seller: ${s.name} (${s.accessKey})',
                                      AppColors.success,
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _resetFormInputs(List<String> availableSeries) {
    setState(() {
      _ticketNoCtrl.clear();
      _seriesInputCtrl.clear();
    });
    _seriesFocusNode.requestFocus();
    _showSnackbar('Form reset for new entry (F1)', AppColors.info);
  }

  void _saveSessionBookings() {
    if (_bookingRows.isEmpty) {
      _showSnackbar('No entries to save!', AppColors.warning);
      return;
    }

    for (final row in _bookingRows) {
      final sale = TicketSaleModel(
        id: 'tkt_counter_${DateTime.now().millisecondsSinceEpoch}_${row.sl}',
        receiptNumber: 'REC-${row.series}-${row.ticketNo}',
        buyerName: row.sellerName,
        buyerPhone: '+91 9876543210',
        agentCode: 'AG-POS',
        agentName: row.sellerName,
        drawCode: _selectedLottery.replaceAll(' ', '-').toUpperCase(),
        drawName: _selectedLottery,
        ticketSeries: row.series,
        ticketNumber: '${row.series} ${row.ticketNo}',
        quantity: row.qty,
        pricePerTicket: row.amount,
        totalAmount: row.total,
        commissionAmount: row.total * 0.05,
        status: TicketStatus.sold,
        paymentMode: _paymentModeFromString(row.mode),
        saleDate: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, DateTime.now().hour, DateTime.now().minute, DateTime.now().second),
        drawDate: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 12, 0, 0),
      );
      ref.read(ticketSalesViewModelProvider.notifier).addTicketSale(sale);
    }

    _showSnackbar(
      'Successfully saved $_totalBookingCount bookings (Total: ₹${_totalAmount.toStringAsFixed(0)})',
      AppColors.success,
    );
  }

  PaymentMode _paymentModeFromString(String m) {
    switch (m.toLowerCase()) {
      case 'upi':
        return PaymentMode.upi;
      case 'card':
        return PaymentMode.card;
      case 'credit':
        return PaymentMode.netBanking;
      default:
        return PaymentMode.cash;
    }
  }

  void _printReceipt() {
    if (_bookingRows.isEmpty) {
      _showSnackbar('No ticket entries to print!', AppColors.warning);
      return;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.print, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Text(
                        'Print Counter Receipt',
                        style: AppTypography.titleLg.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () {
                      if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
                    },
                  ),
                ],
              ),
              const Divider(color: AppColors.border, height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: AppDecorations.radiusDefault,
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'NAGALAND TICKETCORE',
                        style: AppTypography.labelMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        'Official Lottery POS Counter',
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Lottery: $_selectedLottery',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Shift: $_selectedShift | Seller: $_sellerName',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      'Date: ${DateFormat('dd-MM-yyyy').format(_selectedDate)}',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Divider(color: AppColors.border, height: 16),
                    ..._bookingRows.map(
                      (r) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${r.sl}. Series ${r.series} #${r.ticketNo}',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              '₹${_formatPrice(r.amount)}',
                              style: AppTypography.bodySm.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(color: AppColors.border, height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Items: $_totalBookingCount',
                          style: AppTypography.bodySm.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Total: ₹${_formatPrice(_totalAmount)}',
                          style: AppTypography.headlineMd.copyWith(
                            color: AppColors.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppSecondaryButton(
                    label: 'Close',
                    onPressed: () {
                      if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
                    },
                  ),
                  const SizedBox(width: 12),
                  AppPrimaryButton(
                    label: 'Send to Printer',
                    icon: Icons.print_rounded,
                    onPressed: () {
                      if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
                      _showSnackbar(
                        'Receipt printed successfully! (F5)',
                        AppColors.success,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndParseCsvFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = file.bytes;
        String csvContent = '';
        
        if (bytes != null) {
          csvContent = utf8.decode(bytes);
        } else if (file.path != null) {
          csvContent = await File(file.path!).readAsString();
        }

        if (csvContent.isEmpty) return;

        final lines = csvContent.split('\n');
        int addedCount = 0;
        final seriesState = ref.read(seriesPriceViewModelProvider);

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;

          // Skip header row if it looks like a header
          if (i == 0 && line.toLowerCase().contains('series')) continue;

          final columns = line.split(',');
          if (columns.length >= 2) {
            final seriesEntered = columns[0].trim().toUpperCase();
            final ticketNo = columns[1].trim();
            
            if (seriesEntered.isEmpty || ticketNo.length != 5) continue;

            final matchingSeriesList = seriesState.seriesList.where(
              (s) => s.seriesName.trim().toUpperCase() == seriesEntered && s.isActive,
            ).toList();

            if (matchingSeriesList.isEmpty) continue;

            final matched = matchingSeriesList.first;

            double amount = matched.ticketPrice;
            if (columns.length >= 3) {
              final customAmt = double.tryParse(columns[2].trim());
              if (customAmt != null && customAmt > 0) amount = customAmt;
            }

            final nowTime = DateFormat('HH:mm').format(DateTime.now());
            final uniqueMicro = DateTime.now().microsecondsSinceEpoch;
            final newRow = CounterBookingRow(
              sl: _bookingRows.length + 1,
              series: matched.seriesName,
              ticketNo: ticketNo,
              amount: amount,
              time: nowTime,
              sellerName: _sellerName.isNotEmpty ? _sellerName : 'Bulk Upload',
            );
            
            _bookingRows.insert(0, newRow);
            addedCount++;

            // INSTANT PERMANENT SAVE TO SQLITE DATABASE (opscore_pro.db)
            final sale = TicketSaleModel(
              id: 'tkt_csv_${uniqueMicro}_${i}_${newRow.series}_${newRow.ticketNo}_$addedCount',
              receiptNumber: 'REC-${newRow.series}-${newRow.ticketNo}',
              buyerName: newRow.sellerName,
              buyerPhone: '+91 9876543210',
              agentCode: 'AG-POS',
              agentName: newRow.sellerName,
              drawCode: _selectedLottery.replaceAll(' ', '-').toUpperCase(),
              drawName: _selectedLottery,
              ticketSeries: newRow.series,
              ticketNumber: '${newRow.series} ${newRow.ticketNo}',
              quantity: newRow.qty,
              pricePerTicket: newRow.amount,
              totalAmount: newRow.total,
              commissionAmount: newRow.total * 0.05,
              status: TicketStatus.sold,
              paymentMode: PaymentMode.cash,
              saleDate: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, DateTime.now().hour, DateTime.now().minute, DateTime.now().second),
              drawDate: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 12, 0, 0),
            );
            ref.read(ticketSalesViewModelProvider.notifier).addTicketSale(sale);
          }
        }
        
        if (addedCount > 0) {
          setState(() {
            _reindexRows();
          });
          _showSnackbar('Successfully added $addedCount bookings from CSV', AppColors.success);
        } else {
          _showSnackbar('No valid bookings found in CSV. Make sure format is: Series,TicketNo', AppColors.warning);
        }
      }
    } catch (e) {
      _showSnackbar('Error reading CSV: $e', AppColors.error);
    }
  }

  void _showSnackbar(String msg, Color bg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: bg,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event, List<String> availableSeries) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.f1:
          _resetFormInputs(availableSeries);
          break;
        case LogicalKeyboardKey.f2:
          setState(() => _showLedgerHistory = !_showLedgerHistory);
          _showSnackbar(
            _showLedgerHistory
                ? 'Switched to Sales Ledger View (F2)'
                : 'Switched to Booking Counter View (F2)',
            AppColors.info,
          );
          break;
        case LogicalKeyboardKey.f3:
          _showSnackbar(
            'Press Series & Price Setup tab on left sidebar (F3)',
            AppColors.info,
          );
          break;
        case LogicalKeyboardKey.f4:
          _saveSessionBookings();
          break;
        case LogicalKeyboardKey.f5:
          _printReceipt();
          break;
        case LogicalKeyboardKey.escape:
          _clearAllRows();
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ⚡ Reactive Live Real-Time Listener (Instant Table Sync on WebSocket Event)
    ref.listen<TicketSalesState>(ticketSalesViewModelProvider, (prev, next) {
      if (mounted) {
        _syncSalesListToTableRows(next.sales);
      }
    });

    final seriesState = ref.watch(seriesPriceViewModelProvider);
    final availableSeries = seriesState.availableSeriesNames;

    final drawTimeState = ref.watch(drawTimeViewModelProvider);
    final lotteryList = drawTimeState.activeTimeLabels.isNotEmpty
        ? drawTimeState.activeTimeLabels
        : ['Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'];

    final effectiveSelectedLottery = lotteryList.contains(_selectedLottery)
        ? _selectedLottery
        : lotteryList.first;

    final filteredBookingRows = _tableSearchQuery.isEmpty
        ? _bookingRows
        : _bookingRows.where((row) {
            final q = _tableSearchQuery.toLowerCase();
            final seriesMatch = row.series.toLowerCase().contains(q);
            final tktMatch = row.ticketNo.toLowerCase().contains(q);
            final sellerMatch = row.sellerName.toLowerCase().contains(q);
            final combinedMatch = '${row.series} ${row.ticketNo}'.toLowerCase().contains(q);
            return seriesMatch || tktMatch || sellerMatch || combinedMatch;
          }).toList();

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (evt) => _handleKeyEvent(evt, availableSeries),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: AppDecorations.radiusLg,
                border: Border.all(
                  color: AppColors.primaryContainer.withAlpha(80),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(80),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 1. Header Bar: Title + Shift Selector
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                      border: Border(
                        bottom: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primaryContainer,
                                borderRadius: AppDecorations.radiusDefault,
                              ),
                              child: const Icon(
                                Icons.confirmation_number_outlined,
                                color: AppColors.onPrimaryContainer,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'LOTTERY BOOKING COUNTER',
                                  style: AppTypography.titleLg.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  'Fast POS Ticket Sales & Session Counter',
                                  style: AppTypography.labelSm.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => BookingHistoryDialog(
                                    initialDate: _selectedDate,
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.picture_as_pdf_rounded,
                                size: 16,
                                color: Colors.cyanAccent,
                              ),
                              label: Text(
                                'Booking History & PDF',
                                style: AppTypography.labelSm.copyWith(
                                  color: Colors.cyanAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: Colors.cyanAccent.withValues(alpha: 0.6),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(
                                  () =>
                                      _showLedgerHistory = !_showLedgerHistory,
                                );
                              },
                              icon: Icon(
                                _showLedgerHistory
                                    ? Icons.calculate
                                    : Icons.history,
                                size: 16,
                                color: AppColors.primary,
                              ),
                              label: Text(
                                _showLedgerHistory
                                    ? 'Counter POS'
                                    : 'View Ledger History',
                                style: AppTypography.labelSm.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: AppColors.primary.withAlpha(120),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _pickAndParseCsvFile,
                              icon: const Icon(Icons.upload_file, size: 16, color: Colors.green),
                              label: Text(
                                'Bulk Upload',
                                style: AppTypography.labelSm.copyWith(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.green.withAlpha(120)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final count = await DatabaseService.instance.cleanAllDuplicates();
                                await _loadExistingSalesIntoTable();
                                _showSnackbar(
                                  count > 0 
                                      ? '🧹 Cleaned $count duplicate tickets from Database!'
                                      : '✅ Database is clean! (0 duplicates found)',
                                  count > 0 ? AppColors.success : AppColors.info,
                                );
                              },
                              icon: const Icon(Icons.cleaning_services, size: 16, color: Colors.orangeAccent),
                              label: Text(
                                'Clean Duplicates',
                                style: AppTypography.labelSm.copyWith(
                                  color: Colors.orangeAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.orangeAccent.withAlpha(120)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                            ValueListenableBuilder<int>(
                              valueListenable: PatternMatcherService.instance.pendingUnparsedCountNotifier,
                              builder: (context, unparsedCount, _) {
                                if (unparsedCount == 0) return const SizedBox.shrink();
                                return OutlinedButton.icon(
                                  onPressed: _showPatternResolverDialog,
                                  icon: const Icon(Icons.psychology_rounded, size: 16, color: AppColors.warning),
                                  label: Text(
                                    '⚠️ $unparsedCount Unparsed (Resolve)',
                                    style: AppTypography.labelSm.copyWith(
                                      color: AppColors.warning,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: AppColors.warning.withAlpha(180), width: 1.5),
                                    backgroundColor: AppColors.warning.withAlpha(25),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  ),
                                );
                              },
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLow,
                                borderRadius: AppDecorations.radiusPill,
                                border: Border.all(
                                  color: AppColors.tertiary.withAlpha(150),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.wb_sunny_outlined,
                                    size: 16,
                                    color: AppColors.tertiary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Shift : ',
                                    style: AppTypography.labelSm.copyWith(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedShift,
                                      dropdownColor:
                                          AppColors.surfaceContainerHigh,
                                      isDense: true,
                                      icon: const Icon(
                                        Icons.arrow_drop_down,
                                        color: AppColors.tertiary,
                                      ),
                                      style: AppTypography.labelSm.copyWith(
                                        color: AppColors.tertiary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      items: _shiftList.map((shift) {
                                        return DropdownMenuItem(
                                          value: shift,
                                          child: Text(shift),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() => _selectedShift = val);
                                          _loadExistingSalesIntoTable();
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 2. Top Filter / Meta Bar (Lottery, Date, Seller)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow.withAlpha(180),
                      border: Border(
                        bottom: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Lottery : ',
                              style: AppTypography.bodySm.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerHigh,
                                borderRadius: AppDecorations.radiusDefault,
                                border: Border.all(color: AppColors.border),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: effectiveSelectedLottery,
                                  dropdownColor:
                                      AppColors.surfaceContainerHighest,
                                  icon: const Icon(
                                    Icons.arrow_drop_down,
                                    color: AppColors.primary,
                                  ),
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  items: lotteryList.map((lot) {
                                    return DropdownMenuItem(
                                      value: lot,
                                      child: Text(lot),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _selectedLottery = val;
                                        if (val.contains('1')) {
                                          _selectedShift = 'Morning';
                                        } else if (val.contains('6')) {
                                          _selectedShift = 'Day';
                                        } else if (val.contains('8')) {
                                          _selectedShift = 'Night';
                                        }
                                      });
                                      _loadExistingSalesIntoTable();
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
                            Text(
                              'Date : ',
                              style: AppTypography.bodySm.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setState(() => _selectedDate = picked);
                                  _loadExistingSalesIntoTable();
                                }
                              },
                              borderRadius: AppDecorations.radiusDefault,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerHigh,
                                  borderRadius: AppDecorations.radiusDefault,
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      size: 15,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      DateFormat(
                                        'dd-MM-yyyy',
                                      ).format(_selectedDate),
                                      style: AppTypography.bodySm.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Seller : ',
                              style: AppTypography.bodySm.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _openSellerSearchDialog,
                              borderRadius: AppDecorations.radiusDefault,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerHigh,
                                  borderRadius: AppDecorations.radiusDefault,
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.person_outline,
                                      size: 15,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _sellerName,
                                      style: AppTypography.bodySm.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.arrow_drop_down,
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 3. Entry Form Section (POS Quick Input Row)
                  if (!_showLedgerHistory)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHighest.withAlpha(120),
                        border: Border(
                          bottom: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'QUICK ENTRY FORM',
                                style: AppTypography.labelSm.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.flash_on,
                                size: 14,
                                color: AppColors.tertiary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // 0. Customer / Seller Field (INLINE TYPEABLE SEARCH — No popup!)
                              SizedBox(
                                width: 220,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Customer / Seller *',
                                      style: AppTypography.labelSm.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      height: 40,
                                      child: TextField(
                                        controller: _sellerInputCtrl,
                                        focusNode: _sellerFocusNode,
                                        autofocus: true,
                                        textInputAction: TextInputAction.next,
                                        style: AppTypography.bodySm.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                          fontSize: 14,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          hintText: _sellerName.isNotEmpty
                                              ? 'Seller: $_sellerName'
                                              : 'Type Seller / Key',
                                          hintStyle: TextStyle(
                                            color: AppColors.textSecondary.withAlpha(120),
                                            fontSize: 12,
                                          ),
                                          prefixIcon: const Icon(
                                            Icons.person_outline,
                                            size: 16,
                                            color: AppColors.primary,
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 10,
                                          ),
                                          filled: true,
                                          fillColor: AppColors.surfaceContainerLow,
                                          border: OutlineInputBorder(
                                            borderRadius: AppDecorations.radiusDefault,
                                            borderSide: BorderSide(color: AppColors.border),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: AppDecorations.radiusDefault,
                                            borderSide: BorderSide(color: AppColors.border),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: AppDecorations.radiusDefault,
                                            borderSide: BorderSide(
                                              color: AppColors.primary,
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                         onChanged: (val) {
                                           final trimmed = val.trim();
                                           if (trimmed.isNotEmpty) {
                                             setState(() => _sellerName = trimmed);
                                           }
                                         },
                                         onSubmitted: (val) => _onSellerSubmitted(val),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // 1. Series Input (FIRST FIELD — Type Series or press Enter for Last Used Series)
                              SizedBox(
                                width: 140,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Series *',
                                      style: AppTypography.labelSm.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      height: 40,
                                      child: TextField(
                                        controller: _seriesInputCtrl,
                                        focusNode: _seriesFocusNode,
                                        autofocus: true,
                                        textInputAction: TextInputAction.next,
                                        textCapitalization: TextCapitalization.characters,
                                        style: AppTypography.bodySm.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                          fontSize: 15,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          hintText: _lastUsedSeries.isNotEmpty
                                              ? 'Auto: $_lastUsedSeries'
                                              : 'Series (e.g. 12)',
                                          hintStyle: TextStyle(
                                            color: AppColors.textSecondary.withAlpha(100),
                                            fontSize: 12,
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          filled: true,
                                          fillColor: AppColors.surfaceContainerLow,
                                          border: OutlineInputBorder(
                                            borderRadius: AppDecorations.radiusDefault,
                                            borderSide: BorderSide(color: AppColors.border),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: AppDecorations.radiusDefault,
                                            borderSide: BorderSide(color: AppColors.border),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: AppDecorations.radiusDefault,
                                            borderSide: BorderSide(
                                              color: AppColors.primary,
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                         onChanged: (val) => _updatePriceForSeries(val),
                                         onSubmitted: (val) => _onSeriesSubmitted(val),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),

                              // 2. Ticket No Field (SECOND FIELD — 5 Digits Max, Enter auto saves & keeps focus for fast repeat)
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ticket No (5 Digits) *',
                                      style: AppTypography.labelSm.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      height: 40,
                                      child: TextField(
                                        controller: _ticketNoCtrl,
                                        focusNode: _ticketNoFocusNode,
                                        keyboardType: TextInputType.number,
                                        textInputAction: TextInputAction.done,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                          LengthLimitingTextInputFormatter(5),
                                        ],
                                        style: AppTypography.bodySm.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'monospace',
                                          color: AppColors.textPrimary,
                                          fontSize: 15,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          hintText: '5 Digits (e.g. 28311)',
                                          hintStyle: TextStyle(
                                            color: AppColors.textSecondary.withAlpha(100),
                                            fontSize: 12,
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          filled: true,
                                          fillColor: AppColors.surfaceContainerLow,
                                          border: OutlineInputBorder(
                                            borderRadius: AppDecorations.radiusDefault,
                                            borderSide: BorderSide(color: AppColors.border),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: AppDecorations.radiusDefault,
                                            borderSide: BorderSide(color: AppColors.border),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: AppDecorations.radiusDefault,
                                            borderSide: BorderSide(
                                              color: AppColors.primary,
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                        onSubmitted: (_) => _addBookingRow(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 110,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Amount (₹)',
                                      style: AppTypography.labelSm.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      height: 40,
                                      child: TextField(
                                         controller: _amountCtrl,
                                         readOnly: true,
                                         keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                         inputFormatters: [
                                           FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                                         ],
                                        style: AppTypography.bodySm.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.tertiary,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          hintText: '100',
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 10,
                                              ),
                                          filled: true,
                                          fillColor:
                                              AppColors.surfaceContainerLow,
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                AppDecorations.radiusDefault,
                                            borderSide: BorderSide(
                                              color: AppColors.border,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                AppDecorations.radiusDefault,
                                            borderSide: BorderSide(
                                              color: AppColors.border,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                AppDecorations.radiusDefault,
                                            borderSide: BorderSide(
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                        onSubmitted: (_) => _addBookingRow(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                height: 40,
                                child: ElevatedButton.icon(
                                  onPressed: _addBookingRow,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text(
                                    'ADD',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryContainer,
                                    foregroundColor:
                                        AppColors.onPrimaryContainer,
                                    elevation: 2,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          AppDecorations.radiusDefault,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  // 4. Live Just Saved Ticket Alert Banner (BIG & PROMINENT CARD)
                  if (_lastAddedRow != null && !_showLedgerHistory)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.success.withAlpha(25),
                        borderRadius: AppDecorations.radiusDefault,
                        border: Border.all(color: AppColors.success, width: 2.0),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.success.withAlpha(50),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.success.withAlpha(40),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.success,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'LATEST SAVED ENTRY ⚡',
                                style: AppTypography.labelSm.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                  color: AppColors.success,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_lastAddedRow!.time} hrs',
                                style: AppTypography.labelSm.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 24),
                          // Seller Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primary.withAlpha(150), width: 1.5),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.person_outline, size: 16, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Text(
                                  _lastAddedRow!.sellerName,
                                  style: AppTypography.titleMd.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Series Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primary, width: 1.5),
                            ),
                            child: Row(
                              children: [
                                Text('SERIES: ', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontSize: 12)),
                                Text(
                                  _lastAddedRow!.series,
                                  style: AppTypography.titleMd.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.primary,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Ticket No Badge (EXTRA BIG MONOSPACE)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.tertiary, width: 1.5),
                            ),
                            child: Row(
                              children: [
                                Text('TICKET #: ', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontSize: 12)),
                                Text(
                                  _lastAddedRow!.ticketNo,
                                  style: AppTypography.titleLg.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    color: AppColors.textPrimary,
                                    fontSize: 20,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Amount Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.success.withAlpha(30),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.success, width: 1.5),
                            ),
                            child: Text(
                              '₹${_formatPrice(_lastAddedRow!.amount)}',
                              style: AppTypography.titleMd.copyWith(
                                fontWeight: FontWeight.w900,
                                color: AppColors.success,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // 5. Booking Items Data Table (UNLIMITED MULTI-ROW SUPPORT WITH BULK SELECTION)
                  if (!_showLedgerHistory) ...[
                    if (_selectedRowIds.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(30),
                          borderRadius: AppDecorations.radiusDefault,
                          border: Border.all(color: Colors.redAccent, width: 1.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: _isAllSelected,
                                  onChanged: (_) => _toggleSelectAll(),
                                  activeColor: AppColors.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_selectedRowIds.length} of ${_bookingRows.length} Tickets Selected',
                                  style: AppTypography.titleMd.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              icon: const Icon(Icons.delete_sweep_rounded),
                              label: Text('BULK DELETE (${_selectedRowIds.length})'),
                              onPressed: _bulkDeleteSelected,
                            ),
                          ],
                        ),
                      ),
                    // 5. Booking Search Bar Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow.withAlpha(220),
                        border: Border(bottom: BorderSide(color: AppColors.border)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 38,
                              child: TextField(
                                controller: _tableSearchCtrl,
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: '🔍 Search Ticket No or Series (e.g. 78476 or 12)...',
                                  hintStyle: TextStyle(
                                    color: AppColors.textSecondary.withAlpha(140),
                                    fontSize: 13,
                                  ),
                                  prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.primary),
                                  suffixIcon: _tableSearchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textSecondary),
                                          onPressed: () {
                                            _tableSearchCtrl.clear();
                                            setState(() => _tableSearchQuery = '');
                                          },
                                        )
                                      : null,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  filled: true,
                                  fillColor: AppColors.surfaceContainerHigh,
                                  border: OutlineInputBorder(
                                    borderRadius: AppDecorations.radiusDefault,
                                    borderSide: BorderSide(color: AppColors.border),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: AppDecorations.radiusDefault,
                                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                                  ),
                                ),
                                onChanged: (val) {
                                  setState(() => _tableSearchQuery = val.trim().toLowerCase());
                                },
                              ),
                            ),
                          ),
                          if (_tableSearchQuery.isNotEmpty) ...[
                            const SizedBox(width: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withAlpha(30),
                                borderRadius: AppDecorations.radiusPill,
                                border: Border.all(color: AppColors.primary.withAlpha(100)),
                              ),
                              child: Text(
                                'Found ${filteredBookingRows.length} entry(ies)',
                                style: AppTypography.labelSm.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      constraints: const BoxConstraints(
                        minHeight: 300,
                        maxHeight: 850,
                      ),
                      child: filteredBookingRows.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(40.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _tableSearchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.inbox,
                                      size: 48,
                                      color: AppColors.textSecondary.withAlpha(
                                        100,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _tableSearchQuery.isNotEmpty
                                          ? 'No booked tickets matching "${_tableSearchCtrl.text}"'
                                          : 'No tickets booked in this session yet',
                                      style: AppTypography.titleMd.copyWith(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _tableSearchQuery.isNotEmpty
                                          ? 'Check ticket number or clear search filter'
                                          : 'Enter 5-digit Ticket No -> Type Series to Add',
                                      style: AppTypography.labelSm.copyWith(
                                        color: AppColors.textSecondary
                                            .withAlpha(120),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                              child: Table(
                                columnWidths: const {
                                  0: FlexColumnWidth(0.5),
                                  1: FlexColumnWidth(0.6),
                                  2: FlexColumnWidth(2.2),
                                  3: FlexColumnWidth(1.6),
                                  4: FlexColumnWidth(1.8),
                                  5: FlexColumnWidth(1.4),
                                  6: FlexColumnWidth(1.2),
                                  7: FlexColumnWidth(1.0),
                                },
                                border: const TableBorder(
                                  horizontalInside: BorderSide(
                                    color: AppColors.border,
                                    width: 0.8,
                                  ),
                                ),
                                children: [
                                  TableRow(
                                    decoration: const BoxDecoration(
                                      color: AppColors.surfaceContainerHigh,
                                    ),
                                    children: [
                                      Container(
                                        alignment: Alignment.center,
                                        child: Checkbox(
                                          value: _isAllSelected,
                                          onChanged: (_) => _toggleSelectAll(),
                                          activeColor: AppColors.primary,
                                        ),
                                      ),
                                      _tableHeaderCell('Sl'),
                                      _tableHeaderCell('Customer / Seller'),
                                      _tableHeaderCell('Series'),
                                      _tableHeaderCell('Ticket No'),
                                      _tableHeaderCell('Amount'),
                                      _tableHeaderCell('Time'),
                                      _tableHeaderCell(
                                        'Delete',
                                        alignment: Alignment.center,
                                      ),
                                    ],
                                  ),
                                  ...filteredBookingRows.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final row = entry.value;
                                    final isNewest = index == 0;
                                    final isSelected = _selectedRowIds.contains(row.id);

                                    return TableRow(
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppColors.primaryContainer.withAlpha(120)
                                            : (isNewest
                                                ? AppColors.primaryContainer.withAlpha(80)
                                                : (index % 2 == 0
                                                    ? AppColors.surfaceContainerLow
                                                    : AppColors.surfaceContainer)),
                                      ),
                                      children: [
                                        Container(
                                          alignment: Alignment.center,
                                          child: Checkbox(
                                            value: isSelected,
                                            onChanged: (_) => _toggleSelectRow(row.id),
                                            activeColor: AppColors.primary,
                                          ),
                                        ),
                                        _tableDataCell(
                                          row.sl.toString(),
                                          isBold: isNewest,
                                        ),
                                        _tableDataCell(
                                          row.sellerName,
                                          isBold: true,
                                        ),
                                        _tableDataCell(
                                          row.series,
                                          isBold: true,
                                          color: AppColors.primary,
                                        ),
                                        _tableDataCell(
                                          row.ticketNo,
                                          isMonospace: true,
                                          isBold: true,
                                        ),
                                        _tableDataCell(
                                          '₹${_formatPrice(row.amount)}',
                                          isBold: true,
                                          color: AppColors.success,
                                        ),
                                        _tableDataCell(
                                          row.time,
                                          color: AppColors.textSecondary,
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Center(
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                                color: AppColors.error,
                                              ),
                                              tooltip: 'Delete row',
                                              onPressed: () =>
                                                  _deleteRow(row),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ),
                    ),

                    // 5. Footer Summary Bar
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        border: Border(
                          top: BorderSide(
                            color: AppColors.primaryContainer.withAlpha(100),
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _summaryBadge(
                            label: 'Total Booking',
                            value: '$_totalBookingCount items',
                            icon: Icons.confirmation_number_outlined,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 48),
                          Container(
                            width: 1,
                            height: 28,
                            color: AppColors.border,
                          ),
                          const SizedBox(width: 48),
                          _summaryBadge(
                            label: 'Total Amount',
                            value: '₹${_formatPrice(_totalAmount)}',
                            icon: Icons.currency_rupee_outlined,
                            color: AppColors.success,
                            isBig: true,
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'All Saved Ticket Sales Ledger',
                            style: AppTypography.titleLg.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildLedgerTable(),
                        ],
                      ),
                    ),
                  ],

                  // 6. Keyboard Shortcuts Footer Bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _shortcutKeyButton(
                            'F1-New',
                            Icons.add_circle_outline,
                            () => _resetFormInputs(availableSeries),
                          ),
                          _shortcutKeyDivider(),
                          _shortcutKeyButton('F2-Search', Icons.search, () {
                            setState(
                              () => _showLedgerHistory = !_showLedgerHistory,
                            );
                          }),
                          _shortcutKeyDivider(),
                          _shortcutKeyButton(
                            'F3-Prices',
                            Icons.sell_outlined,
                            () {
                              _showSnackbar(
                                'Use Price & Series Setup tab on sidebar to edit master rates',
                                AppColors.info,
                              );
                            },
                          ),
                          _shortcutKeyDivider(),
                          _shortcutKeyButton(
                            'F4-Save',
                            Icons.save_outlined,
                            _saveSessionBookings,
                            isPrimary: true,
                          ),
                          _shortcutKeyDivider(),
                          _shortcutKeyButton(
                            'F5-Print',
                            Icons.print_outlined,
                            _printReceipt,
                          ),
                          _shortcutKeyDivider(),
                          _shortcutKeyButton(
                            'Esc-Clear',
                            Icons.clear_all,
                            _clearAllRows,
                            isDanger: true,
                          ),
                        ],
                      ),
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

  // Helpers
  Widget _tableHeaderCell(
    String label, {
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      alignment: alignment,
      child: Text(
        label,
        style: AppTypography.labelSm.copyWith(
          fontWeight: FontWeight.bold,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _tableDataCell(
    String text, {
    bool isBold = false,
    bool isMonospace = false,
    Color? color,
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      alignment: alignment,
      child: Text(
        text,
        style: AppTypography.bodySm.copyWith(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontFamily: isMonospace ? 'monospace' : null,
          color: color ?? AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _summaryBadge({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    bool isBig = false,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: isBig ? 24 : 20),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTypography.labelSm.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              value,
              style: (isBig ? AppTypography.titleLg : AppTypography.bodyMd)
                  .copyWith(fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
      ],
    );
  }

  Widget _shortcutKeyButton(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool isPrimary = false,
    bool isDanger = false,
  }) {
    final color = isDanger
        ? AppColors.error
        : isPrimary
        ? AppColors.primary
        : AppColors.textPrimary;

    return InkWell(
      onTap: onTap,
      borderRadius: AppDecorations.radiusDefault,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isPrimary
              ? AppColors.primaryContainer.withAlpha(40)
              : Colors.transparent,
          borderRadius: AppDecorations.radiusDefault,
          border: Border.all(
            color: isPrimary ? AppColors.primary : AppColors.border,
            width: isPrimary ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.labelSm.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shortcutKeyDivider() {
    return Container(
      height: 16,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: AppColors.border,
    );
  }

  Widget _buildLedgerTable() {
    final state = ref.watch(ticketSalesViewModelProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppDecorations.radiusDefault,
        border: Border.all(color: AppColors.border),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.5),
          1: FlexColumnWidth(2.0),
          2: FlexColumnWidth(1.5),
          3: FlexColumnWidth(1.0),
          4: FlexColumnWidth(1.2),
          5: FlexColumnWidth(1.2),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerHigh,
            ),
            children: [
              _tableHeaderCell('Receipt #'),
              _tableHeaderCell('Draw Name'),
              _tableHeaderCell('Ticket #'),
              _tableHeaderCell('Qty'),
              _tableHeaderCell('Total'),
              _tableHeaderCell('Date'),
            ],
          ),
          ...state.sales.map(
            (s) => TableRow(
              children: [
                _tableDataCell(
                  s.receiptNumber,
                  isBold: true,
                  color: AppColors.primary,
                ),
                _tableDataCell(s.drawName),
                _tableDataCell(s.ticketNumber, isMonospace: true),
                _tableDataCell(s.quantity.toString()),
                _tableDataCell(
                  '₹${s.totalAmount.toStringAsFixed(0)}',
                  isBold: true,
                  color: AppColors.success,
                ),
                _tableDataCell(
                  DateFormat('dd-MM HH:mm').format(s.saleDate),
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 🎟️ NEW TICKET SALE DIALOG
class NewTicketSaleDialog extends ConsumerStatefulWidget {
  const NewTicketSaleDialog({super.key});

  @override
  ConsumerState<NewTicketSaleDialog> createState() =>
      _NewTicketSaleDialogState();
}

class _NewTicketSaleDialogState extends ConsumerState<NewTicketSaleDialog> {
  final _buyerNameCtrl = TextEditingController();
  final _buyerPhoneCtrl = TextEditingController();
  final _ticketNumberCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController(text: '12');
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController(text: '100');
  final PaymentMode _paymentMode = PaymentMode.cash;
  bool _isSaving = false;

  double get _totalAmount {
    final qty = int.tryParse(_qtyCtrl.text) ?? 0;
    final priceFor100Series = double.tryParse(_priceCtrl.text) ?? 0.0;
    final singleSeriesPrice = (priceFor100Series > 0 ? priceFor100Series : 100.0) / 100.0;
    return qty * singleSeriesPrice;
  }

  @override
  void dispose() {
    _buyerNameCtrl.dispose();
    _buyerPhoneCtrl.dispose();
    _ticketNumberCtrl.dispose();
    _seriesCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_ticketNumberCtrl.text.trim().isEmpty) {
      return;
    }
    setState(() => _isSaving = true);

    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    final priceFor100Series = double.tryParse(_priceCtrl.text) ?? 100.0;
    final singleSeriesPrice = (priceFor100Series > 0 ? priceFor100Series : 100.0) / 100.0;
    final calculatedTotal = qty * singleSeriesPrice;
    final bName = _buyerNameCtrl.text.trim();

    final sale = TicketSaleModel(
      id: 'tk_${DateTime.now().millisecondsSinceEpoch}',
      receiptNumber:
          'TKT-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch % 100000}',
      buyerName: bName.isNotEmpty ? bName : 'Walk-in Customer',
      buyerPhone: _buyerPhoneCtrl.text.trim(),
      agentCode: 'AG-POS',
      agentName: bName.isNotEmpty ? bName : 'Walk-in Customer',
      drawCode: 'NL-DR-2026',
      drawName: 'Dear 1 PM',
      ticketSeries: _seriesCtrl.text.trim().toUpperCase(),
      ticketNumber:
          '${_seriesCtrl.text.trim().toUpperCase()} ${_ticketNumberCtrl.text.trim()}',
      quantity: qty,
      pricePerTicket: singleSeriesPrice,
      totalAmount: calculatedTotal,
      commissionAmount: calculatedTotal * 0.05,
      status: TicketStatus.sold,
      paymentMode: _paymentMode,
      saleDate: DateTime.now(),
      drawDate: DateTime.now(),
    );

    ref.read(ticketSalesViewModelProvider.notifier).addTicketSale(sale);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ticket ${sale.receiptNumber} booked for ${sale.buyerName}',
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg),
      child: Container(
        width: 620,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'New Ticket Booking Entry',
                  style: AppTypography.titleLg.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(color: AppColors.border, height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _buyerNameCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Buyer Name *',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _buyerPhoneCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Mobile Number',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _seriesCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Series',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _ticketNumberCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Ticket Number *',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total: ₹${_totalAmount.toStringAsFixed(0)}',
                  style: AppTypography.titleLg.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    AppSecondaryButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    AppPrimaryButton(
                      label: 'Book Ticket',
                      isLoading: _isSaving,
                      onPressed: _save,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
