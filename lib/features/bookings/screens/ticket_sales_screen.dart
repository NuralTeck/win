import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
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
import '../../../core/services/pattern_matcher_service.dart';
import '../viewmodels/ticket_sales_viewmodel.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../../settings/viewmodels/series_price_viewmodel.dart';
import '../../sellers/viewmodels/seller_customer_viewmodel.dart';
import '../../settings/viewmodels/draw_time_viewmodel.dart';
import '../widgets/booking_history_dialog.dart';
import '../widgets/ai_photo_review_dialog.dart';
import '../widgets/raw_text_ticket_parser_dialog.dart';
import '../widgets/bulk_chat_ticket_importer_dialog.dart';
import '../widgets/pattern_resolver_dialog.dart';
import '../widgets/voice_booking_dialog.dart';
import '../services/gemini_scanner_service.dart';

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
  final FocusNode _toTicketNoFocusNode = FocusNode();
  String _selectedSeriesFilter = 'All';
  Set<String> _selectedRowIds = {};
  List<Map<String, dynamic>> _pendingPhotos = [];
  Timer? _pendingPhotosTimer;

  // 📌 Floating Draggable & Resizable Summary / Number List Card
  bool _showFloatingSummary = true;
  bool _isFloatingSummaryMinimized = false;
  Offset _floatingSummaryOffset = const Offset(24, 90);
  double _floatingSummaryWidth = 360;
  double _floatingSummaryHeight = 440;

  @override
  void initState() {
    super.initState();
    PatternMatcherService.instance.initialize();
    _loadPendingPhotos();
    _pendingPhotosTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _loadPendingPhotos();
    });
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

  Future<void> _loadPendingPhotos() async {
    try {
      final photos = await DatabaseService.instance.getPendingPhotoBookings();
      if (mounted && photos.length != _pendingPhotos.length) {
        setState(() {
          _pendingPhotos = photos;
        });
      }
    } catch (e) {
      debugPrint('Error loading pending photos: $e');
    }
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

    // 🎯 Prioritize missing/empty series tickets at the VERY TOP
    newRows.sort((a, b) {
      final aMissing = a.series == '?' || a.series.trim().isEmpty || a.series.toUpperCase() == 'MISSING' || a.series.toUpperCase() == 'UNKNOWN' || a.series == '—' || a.series == '-' || a.series.toLowerCase() == 'none';
      final bMissing = b.series == '?' || b.series.trim().isEmpty || b.series.toUpperCase() == 'MISSING' || b.series.toUpperCase() == 'UNKNOWN' || b.series == '—' || b.series == '-' || b.series.toLowerCase() == 'none';

      if (aMissing && !bMissing) return -1;
      if (!aMissing && bMissing) return 1;
      return 0;
    });

    // Re-assign Sl numbers sequentially after sorting
    for (int i = 0; i < newRows.length; i++) {
      newRows[i] = newRows[i].copyWith(sl: i + 1);
    }

    if (_bookingRows.length == newRows.length &&
        _bookingRows.isNotEmpty &&
        newRows.isNotEmpty &&
        _bookingRows.first.id == newRows.first.id) {
      return; // Already in sync, avoid needless table repaint
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

  Future<void> _openVoiceBookingDialog() async {
    final targetCustomer = _sellerName.trim().isNotEmpty ? _sellerName.trim() : 'Walk-in Customer';
    final effectiveLottery = _selectedLottery == 'All Shifts' ? 'Dear 1 PM' : _selectedLottery;

    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => VoiceBookingDialog(
        activeShift: effectiveLottery,
        activeDate: _selectedDate,
        defaultSeller: targetCustomer,
      ),
    );

    if (saved == true && mounted) {
      await _loadExistingSalesIntoTable();
    }
  }

  // Top Metadata State
  String _selectedShift = 'All Shifts';
  String _selectedLottery = 'Dear 1 PM';
  DateTime _selectedDate = DateTime.now();
  String _sellerName = '';

  // Input Field Controllers
  final TextEditingController _sellerInputCtrl = TextEditingController();
  final TextEditingController _seriesInputCtrl = TextEditingController();
  final TextEditingController _ticketNoCtrl = TextEditingController();
  final TextEditingController _toTicketNoCtrl = TextEditingController();
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
    _pendingPhotosTimer?.cancel();
    _keyboardFocusNode.dispose();
    _sellerFocusNode.dispose();
    _seriesFocusNode.dispose();
    _ticketNoFocusNode.dispose();
    _toTicketNoFocusNode.dispose();
    _sellerInputCtrl.dispose();
    _seriesInputCtrl.dispose();
    _ticketNoCtrl.dispose();
    _toTicketNoCtrl.dispose();
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

  double _calculatePriceForSeries(String val) {
    final seriesEntered = val.trim().toUpperCase();
    if (seriesEntered.isEmpty) return 0.0;

    final seriesState = ref.read(seriesPriceViewModelProvider);
    double calculatedPrice = seriesState.getPriceForSeries(seriesEntered);

    if (calculatedPrice <= 0) {
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

      final singleSeriesRate = config100Price > 0
          ? (config100Price >= 100 ? (config100Price / 100.0) : config100Price)
          : 6.0; // Standard Dear Lottery rate ₹6/ticket

      final digits = seriesEntered.replaceAll(RegExp(r'\D'), '');
      final multiplier = double.tryParse(digits) ?? 1.0;
      calculatedPrice = (multiplier > 0 ? multiplier : 1.0) * singleSeriesRate;
    }
    return calculatedPrice;
  }

  void _updatePriceForSeries(String val) {
    final calculatedPrice = _calculatePriceForSeries(val);
    if (calculatedPrice > 0) {
      _amountCtrl.text = _formatPrice(calculatedPrice);
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

  // Add new booking entry with Series Validation, 5-Digit restriction, and Range expansion
  Future<void> _addBookingRow() async {
    String fromText = _ticketNoCtrl.text.trim();
    String toText = _toTicketNoCtrl.text.trim();
    String seriesEntered = _seriesInputCtrl.text.trim().toUpperCase();

    // 💡 Auto-parse parenthesized format e.g. "(24)86286" or "(24) 86286"
    final parenMatch = RegExp(r'^\(([A-Za-z0-9]{1,4})\)\s*(\d{5})$').firstMatch(fromText.isEmpty ? seriesEntered : fromText);
    if (parenMatch != null) {
      seriesEntered = parenMatch.group(1)!.toUpperCase();
      fromText = parenMatch.group(2)!;
      _seriesInputCtrl.text = seriesEntered;
      _ticketNoCtrl.text = fromText;
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

    if (fromText.isEmpty) {
      _showSnackbar('Please enter 5-digit Ticket Number!', AppColors.warning);
      _ticketNoFocusNode.requestFocus();
      return;
    }

    if (fromText.length != 5 || int.tryParse(fromText) == null) {
      _showSnackbar('Ticket Number must be exactly 5 digits (00000 - 99999)!', AppColors.warning);
      _ticketNoFocusNode.requestFocus();
      return;
    }

    final int startNum = int.parse(fromText);
    final List<String> generatedNumbers = [];

    if (toText.isNotEmpty) {
      int? endNum;
      if (toText.length == 5) {
        endNum = int.tryParse(toText);
      } else if (toText.length < 5) {
        final resolvedToStr = fromText.substring(0, 5 - toText.length) + toText;
        endNum = int.tryParse(resolvedToStr);
      }

      if (endNum == null) {
        _showSnackbar('Range End number must be valid digits!', AppColors.warning);
        _toTicketNoFocusNode.requestFocus();
        return;
      }

      if (endNum < startNum) {
        _showSnackbar('End number ($toText) cannot be smaller than Start number ($fromText)!', AppColors.warning);
        _toTicketNoFocusNode.requestFocus();
        return;
      }

      final totalRangeCount = (endNum - startNum) + 1;
      if (totalRangeCount > 500) {
        _showSnackbar('Range too large ($totalRangeCount tickets). Max 500 tickets allowed at once.', AppColors.warning);
        return;
      }

      for (int n = startNum; n <= endNum; n++) {
        generatedNumbers.add(n.toString().padLeft(5, '0'));
      }
    } else {
      generatedNumbers.add(fromText);
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

    double amount = _calculatePriceForSeries(seriesEntered);
    if (amount <= 0) {
      amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    }

    // Dynamically fetch typed customer/seller name from input field
    final typedSeller = _sellerInputCtrl.text.trim();
    if (typedSeller.isNotEmpty) {
      _sellerName = typedSeller;
    }
    final activeSellerName = _sellerName.isNotEmpty ? _sellerName : 'Walk-in Customer';

    final nowTime = DateFormat('HH:mm').format(DateTime.now());
    final uniqueMicro = DateTime.now().microsecondsSinceEpoch;

    final List<CounterBookingRow> newRowsToAdd = [];
    final List<TicketSaleModel> salesToAdd = [];

    for (int i = 0; i < generatedNumbers.length; i++) {
      final tNo = generatedNumbers[i];
      final saleId = 'tkt_counter_${uniqueMicro}_${seriesEntered}_${tNo}_${_bookingRows.length + i + 1}';
      
      final row = CounterBookingRow(
        id: saleId,
        sl: _bookingRows.length + i + 1,
        series: seriesEntered,
        ticketNo: tNo,
        amount: amount,
        time: nowTime,
        sellerName: activeSellerName,
      );
      newRowsToAdd.add(row);

      final sale = TicketSaleModel(
        id: saleId,
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
      salesToAdd.add(sale);
    }

    setState(() {
      _lastUsedSeries = seriesEntered;
      if (newRowsToAdd.isNotEmpty) {
        _lastAddedRow = newRowsToAdd.last;
      }
      for (final r in newRowsToAdd) {
        _bookingRows.insert(0, r);
      }
      _reindexRows();
      _ticketNoCtrl.clear();
      _toTicketNoCtrl.clear();
    });

    for (final sale in salesToAdd) {
      ref.read(ticketSalesViewModelProvider.notifier).addTicketSale(sale);
    }

    _ticketNoFocusNode.requestFocus();

    if (generatedNumbers.length == 1) {
      _showSnackbar(
        '✅ Saved Ticket #$seriesEntered-$fromText to Database! (₹${_formatPrice(amount)})',
        AppColors.success,
      );
    } else {
      _showSnackbar(
        '🎉 Saved ${generatedNumbers.length} Range Tickets (#$fromText to #${generatedNumbers.last}) | Total: ₹${_formatPrice(amount * generatedNumbers.length)}',
        AppColors.success,
      );
    }
  }

  Future<void> _editRow(CounterBookingRow row) async {
    final initialSeries = row.series == '?' ? '' : row.series;
    final initialPrice = row.amount > 0 ? row.amount : (initialSeries.isNotEmpty ? _calculatePriceForSeries(initialSeries) : 0.0);
    final seriesCtrl = TextEditingController(text: initialSeries);
    final ticketNoCtrl = TextEditingController(text: row.ticketNo);
    final sellerCtrl = TextEditingController(text: row.sellerName);
    final amountCtrl = TextEditingController(text: _formatPrice(initialPrice));
    String? dialogError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.border),
            ),
            title: Row(
              children: [
                const Icon(Icons.edit_note_rounded, color: AppColors.primary, size: 24),
                const SizedBox(width: 10),
                const Text('Edit Booked Ticket Entry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (dialogError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                      ),
                      child: Text(dialogError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        flex: 40,
                        child: TextField(
                          controller: seriesCtrl,
                          style: AppTypography.bodySm,
                          decoration: const InputDecoration(
                            labelText: 'Series *',
                            hintText: 'e.g. 12 or 6',
                            prefixIcon: Icon(Icons.confirmation_number_outlined, size: 18),
                          ),
                          onChanged: (val) {
                            final calcPrice = _calculatePriceForSeries(val);
                            if (calcPrice > 0) {
                              amountCtrl.text = _formatPrice(calcPrice);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 60,
                        child: TextField(
                          controller: ticketNoCtrl,
                          maxLength: 5,
                          style: AppTypography.bodySm,
                          decoration: const InputDecoration(
                            labelText: 'Ticket Number (5-Digits) *',
                            hintText: 'e.g. 69476',
                            prefixIcon: Icon(Icons.numbers, size: 18),
                            counterText: '',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sellerCtrl,
                    style: AppTypography.bodySm,
                    decoration: const InputDecoration(
                      labelText: 'Customer / Seller Name *',
                      prefixIcon: Icon(Icons.person_outline, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    style: AppTypography.bodySm,
                    decoration: const InputDecoration(
                      labelText: 'Rate / Amount (₹) *',
                      prefixIcon: Icon(Icons.currency_rupee, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final newSeries = seriesCtrl.text.trim().toUpperCase();
                  final newTicketNo = ticketNoCtrl.text.trim();
                  final newSeller = sellerCtrl.text.trim();
                  final newAmt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;

                  if (newTicketNo.length != 5) {
                    setDialogState(() => dialogError = 'Ticket Number must be exactly 5 digits!');
                    return;
                  }
                  if (newSeller.isEmpty) {
                    setDialogState(() => dialogError = 'Customer / Seller name cannot be empty.');
                    return;
                  }

                  // Update SQLite only
                  await DatabaseService.instance.updateTicketSaleFields(
                    id: row.id,
                    oldSeries: row.series,
                    oldTicketNo: row.ticketNo,
                    newSeries: newSeries.isNotEmpty ? newSeries : '?',
                    newTicketNo: newTicketNo,
                    newSellerName: newSeller,
                    newAmount: newAmt,
                  );

                  // Update local state list
                  setState(() {
                    final idx = _bookingRows.indexWhere((r) => r.id == row.id || (r.series == row.series && r.ticketNo == row.ticketNo));
                    if (idx != -1) {
                      _bookingRows[idx] = _bookingRows[idx].copyWith(
                        series: newSeries.isNotEmpty ? newSeries : '?',
                        ticketNo: newTicketNo,
                        sellerName: newSeller,
                        amount: newAmt,
                      );
                    }
                  });

                  await ref.read(ticketSalesViewModelProvider.notifier).loadSales();

                  if (ctx.mounted) Navigator.pop(ctx);
                  _showSnackbar('✅ Updated Ticket #$newSeries-$newTicketNo successfully!', AppColors.success);
                },
                child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteRow(CounterBookingRow row) async {
    setState(() {
      _selectedRowIds.remove(row.id);
      _bookingRows.removeWhere((r) => r.id == row.id || (r.series == row.series && r.ticketNo == row.ticketNo));
      _reindexRows();
    });

    // 🗑️ DELETE FROM SQLITE DB ONLY
    await DatabaseService.instance.deleteTicketSale(row.id);
    await DatabaseService.instance.deleteTicketSaleBySeriesAndNumber(row.series, row.ticketNo);
    await ref.read(ticketSalesViewModelProvider.notifier).loadSales();

    _showSnackbar('🗑️ Ticket #${row.series}-${row.ticketNo} deleted permanently from Database!', AppColors.info);
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

      // 🗑️ DELETE FROM SQLITE ONLY
      await DatabaseService.instance.deleteTicketSalesByIds(idsToDelete);
      for (final row in selectedRows) {
        await DatabaseService.instance.deleteTicketSaleBySeriesAndNumber(row.series, row.ticketNo);
      }
      await ref.read(ticketSalesViewModelProvider.notifier).loadSales();

      _showSnackbar('🗑️ Deleted $count selected ticket(s) permanently from Database!', AppColors.success);
    }
  }

  bool _rowHasMissingSeries(CounterBookingRow r) {
    return r.series == '?' ||
        r.series.trim().isEmpty ||
        r.series.toUpperCase() == 'MISSING' ||
        r.series.toUpperCase() == 'UNKNOWN' ||
        r.series == '—' ||
        r.series == '-' ||
        r.series.toLowerCase() == 'none';
  }

  int get _missingSeriesCount => _bookingRows.where(_rowHasMissingSeries).length;

  void _selectAllMissingSeries() {
    setState(() {
      final missingIds = _bookingRows.where(_rowHasMissingSeries).map((r) => r.id).toSet();
      _selectedRowIds = missingIds;
    });
    _showSnackbar('Selected ${_selectedRowIds.length} tickets with missing series!', AppColors.info);
  }

  Future<void> _bulkSetSeriesDialog() async {
    if (_selectedRowIds.isEmpty) {
      _showSnackbar('Please select at least one ticket first!', AppColors.warning);
      return;
    }

    final seriesState = ref.read(seriesPriceViewModelProvider);
    final availableSeries = seriesState.availableSeriesNames;
    String selectedSeries = availableSeries.isNotEmpty ? availableSeries.first : '12';
    final customSeriesCtrl = TextEditingController(text: selectedSeries);
    final count = _selectedRowIds.length;
    String? dialogError;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 520,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.85),
                    blurRadius: 36,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Icon(Icons.flash_on_rounded, color: Colors.amberAccent, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'BULK SET SERIES',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Assign Series to $count selected tickets in 1-Click',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 20),

                  // Quick Series Chips
                  Text(
                    'Select Target Series:',
                    style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: availableSeries.map((s) {
                      final isSel = selectedSeries.toUpperCase() == s.toUpperCase();
                      return ChoiceChip(
                        label: Text(s, style: TextStyle(fontWeight: FontWeight.bold, color: isSel ? Colors.black : Colors.white)),
                        selected: isSel,
                        selectedColor: Colors.amberAccent,
                        backgroundColor: AppColors.surfaceContainerHigh,
                        onSelected: (val) {
                          if (val) {
                            setDialogState(() {
                              selectedSeries = s;
                              customSeriesCtrl.text = s;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Custom Series Text Field
                  Text(
                    'Or Type Series Name / Code:',
                    style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: customSeriesCtrl,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'e.g. 12, 24, 83L, 60...',
                      filled: true,
                      fillColor: AppColors.surfaceContainerLow,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.amberAccent, width: 2),
                      ),
                    ),
                    onChanged: (val) {
                      setDialogState(() {
                        selectedSeries = val.trim().toUpperCase();
                      });
                    },
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Text(dialogError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ],
                  const SizedBox(height: 24),

                  // Apply Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 20),
                    label: Text(
                      'APPLY SERIES "${selectedSeries.isEmpty ? '?' : selectedSeries}" TO ALL $count TICKETS',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: () async {
                      final finalSeries = customSeriesCtrl.text.trim().toUpperCase();
                      if (finalSeries.isEmpty) {
                        setDialogState(() => dialogError = 'Please enter a valid series name!');
                        return;
                      }

                      final targetIds = _selectedRowIds.toList();
                      final calculatedPrice = _calculatePriceForSeries(finalSeries);

                      // Bulk update in SQLite only
                      await DatabaseService.instance.updateTicketSalesSeriesBulk(
                        ids: targetIds,
                        newSeries: finalSeries,
                        newPricePerTicket: calculatedPrice > 0 ? calculatedPrice : null,
                      );

                      // Reload in table
                      await ref.read(ticketSalesViewModelProvider.notifier).loadSales();

                      setState(() {
                        _selectedRowIds.clear();
                      });

                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      _showSnackbar('🎉 Successfully updated Series to "$finalSeries" for $count tickets!', AppColors.success);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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

  void _resetFormInputs(List<String> availableSeries) {
    setState(() {
      _ticketNoCtrl.clear();
      _toTicketNoCtrl.clear();
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
                        'PHANTOM MANAGEMENT',
                        style: AppTypography.labelMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        'Official POS Booking Counter',
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Draw Shift: $_selectedLottery',
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

  Future<void> _scanTicketPhotoWithAi(String effectiveLottery) async {
    try {
      // Step 1: Prompt for Customer / Party Name if not already set on counter
      String targetCustomer = _sellerName.trim();
      if (targetCustomer.isEmpty) {
        final sellerState = ref.read(sellerCustomerViewModelProvider);
        final sellers = sellerState.sellers.where((s) => s.isActive).toList();
        final nameCtrl = TextEditingController();
        if (!mounted) return;

        final chosenCustomer = await showDialog<String>(
          context: context,
          useRootNavigator: true,
          builder: (dialogCtx) => AlertDialog(
            backgroundColor: AppColors.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.border),
            ),
            title: const Row(
              children: [
                Icon(Icons.person_pin_rounded, color: AppColors.primary, size: 24),
                SizedBox(width: 10),
                Text('Customer / Party Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kripya is photo/parche ke customer/seller ka naam select ya type karein:',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  Autocomplete<String>(
                    optionsBuilder: (textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return sellers.map((s) => s.name);
                      }
                      final q = textEditingValue.text.toLowerCase();
                      return sellers
                          .where((s) => s.name.toLowerCase().contains(q) || s.accessKey.toLowerCase().contains(q))
                          .map((s) => s.name);
                    },
                    onSelected: (selection) {
                      nameCtrl.text = selection;
                    },
                    fieldViewBuilder: (ctx, fieldCtrl, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: fieldCtrl,
                        focusNode: focusNode,
                        autofocus: true,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'e.g. Sanjit ji',
                          filled: true,
                          fillColor: AppColors.surfaceContainerLowest,
                          prefixIcon: const Icon(Icons.person, color: AppColors.primary, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (val) => nameCtrl.text = val,
                        onSubmitted: (_) {
                          Navigator.pop(dialogCtx, nameCtrl.text.trim());
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, 'Walk-in Customer'),
                child: const Text('Walk-in Customer', style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Continue to Scan Photo', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  final n = nameCtrl.text.trim();
                  Navigator.pop(dialogCtx, n.isNotEmpty ? n : 'Walk-in Customer');
                },
              ),
            ],
          ),
        );

        if (chosenCustomer == null) return; // User cancelled
        targetCustomer = chosenCustomer;
      }

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
        _showSnackbar('Could not read image file bytes.', AppColors.error);
        return;
      }

      if (!mounted) return;

      List<GeminiScannedItem> scannedTickets = [];
      final ValueNotifier<String> scanProgressNotifier = ValueNotifier<String>(
        allFilesBytes.length > 1
            ? 'Scanning 1 of ${allFilesBytes.length} Photos...'
            : 'Scanning Photo with Gemini Vision AI...',
      );

      BuildContext? progressDialogCtx;
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (ctx) {
          progressDialogCtx = ctx;
          return Dialog(
            backgroundColor: AppColors.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.purpleAccent),
                  const SizedBox(width: 20),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ValueListenableBuilder<String>(
                        valueListenable: scanProgressNotifier,
                        builder: (_, msg, _) => Text(
                          msg,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Extracting 5-digit numbers and series...',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
            scanProgressNotifier.value = 'Scanning Photo ${i + 1} of ${allFilesBytes.length}...';
          }
          final items = await GeminiScannerService.instance.scanImage(
            imageBytes: allFilesBytes[i],
            defaultSeller: targetCustomer,
          );
          scannedTickets.addAll(items);
        }
      } catch (scanErr) {
        debugPrint('⚠️ [SCAN NOTE] Online Gemini scan error: $scanErr');
      } finally {
        if (progressDialogCtx != null && progressDialogCtx!.mounted) {
          Navigator.of(progressDialogCtx!, rootNavigator: true).pop();
        }
      }

      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;

      // Open Confirmation & Review Modal (Works 100% Offline with full Image preview & editing)
      final saved = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AiPhotoReviewDialog(
          imageBytes: allFilesBytes.first,
          allImageBytes: allFilesBytes,
          initialItems: scannedTickets,
          activeShift: effectiveLottery,
          activeDate: _selectedDate,
          defaultSeller: targetCustomer,
        ),
      );

      if (saved == true && mounted) {
        await _loadExistingSalesIntoTable();
      }
    } catch (e) {
      if (mounted) {
        _showSnackbar('Error picking image: $e', AppColors.error);
      }
    }
  }

  Future<void> _openPendingPhotoReview(Map<String, dynamic> photoData) async {
    try {
      final String photoId = photoData['id'] ?? '';
      final String imageBase64 = photoData['imageBase64'] ?? '';
      final String buyerName = photoData['buyerName'] ?? 'Walk-in Customer';
      final String drawShift = photoData['drawShift'] ?? _selectedLottery;
      final String rawJson = photoData['parsedTicketsJson'] ?? '[]';

      if (imageBase64.isEmpty) {
        _showSnackbar('No image data found for this photo.', AppColors.error);
        return;
      }

      final imageBytes = base64Decode(imageBase64);
      final List<GeminiScannedItem> items = [];

      try {
        final List dynamicList = jsonDecode(rawJson);
        for (final d in dynamicList) {
          final tkt = d['ticketNo']?.toString() ?? '';
          final ser = d['series']?.toString() ?? '12';
          final amt = (d['amount'] as num?)?.toDouble() ?? 0.0;
          final qty = (d['quantity'] as num?)?.toInt() ?? 1;
          items.add(GeminiScannedItem(
            series: ser,
            ticketNo: tkt,
            amount: amt,
            quantity: qty,
            sellerName: buyerName,
          ));
        }
      } catch (jsonErr) {
        debugPrint('JSON parse error for pending photo: $jsonErr');
      }

      if (!mounted) return;

      final saved = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AiPhotoReviewDialog(
          imageBytes: imageBytes,
          initialItems: items,
          activeShift: drawShift,
          activeDate: _selectedDate,
          defaultSeller: buyerName,
          pendingPhotoId: photoId,
        ),
      );

      await _loadPendingPhotos();
      if (saved == true && mounted) {
        await _loadExistingSalesIntoTable();
      }
    } catch (e) {
      if (mounted) {
        _showSnackbar('Error reviewing photo: $e', AppColors.error);
      }
    }
  }

  Future<void> _openPendingPhotoApprovalQueue() async {
    await _loadPendingPhotos();
    if (!mounted) return;

    if (_pendingPhotos.isEmpty) {
      _showSnackbar('No pending photos in WhatsApp queue.', AppColors.info);
      return;
    }

    if (_pendingPhotos.length == 1) {
      // Directly open review modal for the 1 photo
      await _openPendingPhotoReview(_pendingPhotos.first);
      return;
    }

    // Multiple photos pending -> show queue selection list
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.photo_library_rounded, color: Colors.amber, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'Pending WhatsApp Photos (${_pendingPhotos.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 380,
          child: ListView.separated(
            itemCount: _pendingPhotos.length,
            separatorBuilder: (_, _) => const Divider(color: AppColors.border, height: 1),
            itemBuilder: (ctx, i) {
              final p = _pendingPhotos[i];
              final buyer = p['buyerName'] ?? 'Walk-in Customer';
              final shift = p['drawShift'] ?? 'Dear 1 PM';
              final phone = p['senderPhone'] ?? '';
              final timeStr = p['createdAt'] != null ? DateFormat('hh:mm a').format(DateTime.tryParse(p['createdAt']) ?? DateTime.now()) : '';

              return ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: p['imageBase64'] != null && (p['imageBase64'] as String).isNotEmpty
                      ? Image.memory(base64Decode(p['imageBase64']), fit: BoxFit.cover)
                      : const Icon(Icons.image, color: AppColors.textSecondary),
                ),
                title: Text(
                  buyer,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  'Shift: $shift | $phone | $timeStr',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                trailing: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.visibility, size: 14),
                  label: const Text('Review', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    _openPendingPhotoReview(p);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 16),
            label: const Text('Reject All Photos', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  backgroundColor: AppColors.surfaceContainerHigh,
                  title: const Text('Reject All Pending Photos?'),
                  content: Text('Are you sure you want to dismiss all ${_pendingPhotos.length} pending photos?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Reject All'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                for (final p in _pendingPhotos) {
                  final pid = p['id']?.toString();
                  if (pid != null && pid.isNotEmpty) {
                    await DatabaseService.instance.updatePendingPhotoStatus(pid, 'rejected');
                  }
                }
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                await _loadPendingPhotos();
                if (mounted) _showSnackbar('All pending photos dismissed.', AppColors.info);
              }
            },
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Close', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Future<void> _openPatternResolverDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => PatternResolverDialog(
        onTicketsResolved: (resolvedTickets, sender, senderName) async {
          final effectiveCustomer = (senderName != null && senderName.isNotEmpty)
              ? senderName
              : (sender.isNotEmpty ? 'Party $sender' : (_sellerName.isNotEmpty ? _sellerName : 'Walk-in Customer'));
          final drawCode = _selectedLottery.replaceAll(RegExp(r'\s+'), '-').toUpperCase();
          final List<TicketSaleModel> sales = [];
          int index = 0;
          for (final t in resolvedTickets) {
            index++;
            final price = _calculatePriceForSeries(t.series);
            final uniqueSalt = math.Random().toString().substring(2, 8);
            sales.add(TicketSaleModel(
              id: 'tkt_wa_res_${DateTime.now().millisecondsSinceEpoch}_${uniqueSalt}_${t.series}_${t.ticketNo}_$index',
              receiptNumber: 'REC-${t.series}-${t.ticketNo}',
              buyerName: effectiveCustomer,
              buyerPhone: sender,
              agentCode: 'AG-WA',
              agentName: effectiveCustomer,
              drawCode: drawCode,
              drawName: _selectedLottery,
              ticketSeries: t.series,
              ticketNumber: '${t.series} ${t.ticketNo}',
              quantity: t.quantity,
              pricePerTicket: price,
              totalAmount: price * t.quantity,
              commissionAmount: (price * t.quantity) * 0.05,
              status: TicketStatus.sold,
              paymentMode: PaymentMode.cash,
              saleDate: DateTime.now(),
              drawDate: _selectedDate,
            ));
          }
          await ref.read(ticketSalesViewModelProvider.notifier).addTicketSalesBulk(sales);
          await _loadExistingSalesIntoTable();
          await PatternMatcherService.instance.refreshPendingCount();
          _showSnackbar('✅ Booked ${resolvedTickets.length} ticket(s) from WhatsApp Review!', AppColors.success);
        },
      ),
    );
    await PatternMatcherService.instance.refreshPendingCount();
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
                : 'Switched to Number Booking Counter View (F2)',
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

    // 🎯 Series Count Breakdown
    final Map<String, int> seriesBreakdown = {};
    for (final r in _bookingRows) {
      final s = (r.series.trim().isEmpty || r.series == '?' || r.series.toUpperCase() == 'MISSING') ? 'No Series' : r.series;
      seriesBreakdown[s] = (seriesBreakdown[s] ?? 0) + (r.quantity > 0 ? r.quantity : 1);
    }

    // 🎯 Safe List of Filter Options (Prevents DropdownButton crash)
    final List<String> seriesFilterOptions = ['All'];
    for (final s in availableSeries) {
      if (!seriesFilterOptions.contains(s)) seriesFilterOptions.add(s);
    }
    for (final s in seriesBreakdown.keys) {
      if (!seriesFilterOptions.contains(s)) seriesFilterOptions.add(s);
    }

    final effectiveSeriesFilter = seriesFilterOptions.contains(_selectedSeriesFilter)
        ? _selectedSeriesFilter
        : 'All';

    // 🎯 Step 1: Filter by Series
    final seriesFiltered = effectiveSeriesFilter == 'All'
        ? _bookingRows
        : _bookingRows.where((row) {
            if (effectiveSeriesFilter == 'No Series') {
              return row.series == '?' || row.series.trim().isEmpty || row.series.toUpperCase() == 'MISSING' || row.series.toUpperCase() == 'UNKNOWN';
            }
            return row.series.trim().toLowerCase() == effectiveSeriesFilter.trim().toLowerCase();
          }).toList();

    // 🎯 Step 2: Filter by Search Query
    final rawFiltered = _tableSearchQuery.isEmpty
        ? seriesFiltered
        : seriesFiltered.where((row) {
            final q = _tableSearchQuery.toLowerCase();
            final seriesMatch = row.series.toLowerCase().contains(q);
            final tktMatch = row.ticketNo.toLowerCase().contains(q);
            final sellerMatch = row.sellerName.toLowerCase().contains(q);
            final combinedMatch = '${row.series} ${row.ticketNo}'.toLowerCase().contains(q);
            return seriesMatch || tktMatch || sellerMatch || combinedMatch;
          }).toList();

    // 🎯 Keep missing/empty series at the VERY TOP of the display table
    final filteredBookingRows = List<CounterBookingRow>.from(rawFiltered)..sort((a, b) {
      final aMissing = a.series == '?' || a.series.trim().isEmpty || a.series.toUpperCase() == 'MISSING' || a.series.toUpperCase() == 'UNKNOWN' || a.series == '—' || a.series == '-' || a.series.toLowerCase() == 'none';
      final bMissing = b.series == '?' || b.series.trim().isEmpty || b.series.toUpperCase() == 'MISSING' || b.series.toUpperCase() == 'UNKNOWN' || b.series == '—' || b.series == '-' || b.series.toLowerCase() == 'none';

      if (aMissing && !bMissing) return -1;
      if (!aMissing && bMissing) return 1;
      return 0;
    });

    return Stack(
      children: [
        KeyboardListener(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          onKeyEvent: (evt) => _handleKeyEvent(evt, availableSeries),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Container(
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Sleek Compact Header & Action Toolbar (Overflow-Safe & Responsive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(14),
                      ),
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        // Left: Title + Shift + Date
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: AppColors.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.confirmation_number_outlined, color: AppColors.onPrimaryContainer, size: 15),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'NUMBER BOOKING COUNTER',
                              style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.w900, letterSpacing: 0.5, color: AppColors.textPrimary, fontSize: 13.5),
                            ),
                            const SizedBox(width: 10),
                            // Draw Shift Selector
                            Container(
                              height: 30,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: effectiveSelectedLottery,
                                  dropdownColor: AppColors.surfaceContainerHighest,
                                  icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary, size: 16),
                                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11.5),
                                  items: lotteryList.map((lot) => DropdownMenuItem(value: lot, child: Text(lot))).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _selectedLottery = val;
                                        if (val.contains('1')) { _selectedShift = 'Morning'; }
                                        else if (val.contains('6')) { _selectedShift = 'Day'; }
                                        else if (val.contains('8')) { _selectedShift = 'Night'; }
                                      });
                                      _loadExistingSalesIntoTable();
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Date Picker
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
                              child: Container(
                                height: 30,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.calendar_today, size: 12, color: AppColors.textSecondary),
                                    const SizedBox(width: 5),
                                    Text(DateFormat('dd-MM-yyyy').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textPrimary)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Right: Action Buttons
                        Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ValueListenableBuilder<int>(
                              valueListenable: PatternMatcherService.instance.pendingUnparsedCountNotifier,
                              builder: (context, count, _) {
                                if (count <= 0) return const SizedBox.shrink();
                                return _compactActionButton(
                                  '⚠️ $count Undefined Review',
                                  Colors.amberAccent,
                                  Colors.black,
                                  _openPatternResolverDialog,
                                );
                              },
                            ),
                            if (_pendingPhotos.isNotEmpty)
                              _compactActionButton('📸 ${_pendingPhotos.length} Photos', Colors.amberAccent, Colors.black, _openPendingPhotoApprovalQueue),
                            _compactActionButton('📸 AI Scan', Colors.purple.shade700, Colors.white, () => _scanTicketPhotoWithAi(effectiveSelectedLottery)),
                            _compactActionButton('📁 Bulk Chat', Colors.teal.shade800, Colors.white, () async {
                              final saved = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => BulkChatTicketImporterDialog(
                                  initialShift: effectiveSelectedLottery,
                                  initialDate: _selectedDate,
                                  defaultSeller: _sellerInputCtrl.text.trim(),
                                ),
                              );
                              if (saved == true && mounted) {
                                await _loadExistingSalesIntoTable();
                              }
                            }),
                            _compactActionButton('📋 Paste Text', const Color(0xFF0284C7), Colors.white, () async {
                              await showDialog(
                                context: context,
                                builder: (ctx) => RawTextTicketParserDialog(
                                  activeShift: effectiveSelectedLottery,
                                  activeDate: _selectedDate,
                                  defaultSeller: _sellerInputCtrl.text.trim(),
                                ),
                              );
                              if (mounted) {
                                await _loadExistingSalesIntoTable();
                              }
                            }),
                            _compactActionButton('🎙️ Voice', const Color(0xFF7C3AED), Colors.white, _openVoiceBookingDialog),
                            _compactOutlineButton('History', Icons.picture_as_pdf_rounded, Colors.cyanAccent, () {
                              showDialog(
                                context: context,
                                builder: (ctx) => BookingHistoryDialog(initialDate: _selectedDate),
                              );
                            }),
                            _compactOutlineButton(_showLedgerHistory ? 'Counter' : 'Ledger', _showLedgerHistory ? Icons.calculate : Icons.history, AppColors.primary, () {
                              setState(() => _showLedgerHistory = !_showLedgerHistory);
                            }),
                            _compactOutlineButton('Clean Dupes', Icons.cleaning_services_rounded, Colors.orangeAccent, () async {
                              final count = await DatabaseService.instance.cleanAllDuplicates();
                              await _loadExistingSalesIntoTable();
                              _showSnackbar(
                                count > 0 
                                    ? '🧹 Cleaned $count duplicate numbers from Database!'
                                    : '✅ No duplicate numbers found in this shift.',
                                count > 0 ? AppColors.success : AppColors.info,
                              );
                            }),
                            _compactOutlineButton('📌 Float', Icons.push_pin_rounded, _showFloatingSummary ? Colors.amberAccent : Colors.grey, () {
                              setState(() => _showFloatingSummary = !_showFloatingSummary);
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 2. Clean, Compact Full-Width Quick Entry Form (Edge-to-Edge)
                  if (!_showLedgerHistory)
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHighest.withAlpha(100),
                        border: Border(bottom: BorderSide(color: AppColors.border)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Field 1: Customer / Seller
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Customer / Seller *', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11.5)),
                                const SizedBox(height: 4),
                                SizedBox(
                                  height: 36,
                                  child: TextField(
                                    controller: _sellerInputCtrl,
                                    focusNode: _sellerFocusNode,
                                    autofocus: true,
                                    textInputAction: TextInputAction.next,
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 13),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText: _sellerName.isNotEmpty ? _sellerName : 'Type Seller / Key',
                                      hintStyle: TextStyle(color: AppColors.textSecondary.withAlpha(120), fontSize: 12),
                                      prefixIcon: const Icon(Icons.person_outline, size: 16, color: AppColors.primary),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      filled: true,
                                      fillColor: AppColors.surfaceContainerLow,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.border)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.border)),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                                    ),
                                    onChanged: (val) {
                                      final trimmed = val.trim();
                                      if (trimmed.isNotEmpty) _sellerName = trimmed;
                                    },
                                    onSubmitted: (val) => _onSellerSubmitted(val),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Field 2: Series
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Series *', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11.5)),
                                const SizedBox(height: 4),
                                SizedBox(
                                  height: 36,
                                  child: TextField(
                                    controller: _seriesInputCtrl,
                                    focusNode: _seriesFocusNode,
                                    textInputAction: TextInputAction.next,
                                    textCapitalization: TextCapitalization.characters,
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 13),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText: _lastUsedSeries.isNotEmpty ? 'Auto: $_lastUsedSeries' : 'Series (12)',
                                      hintStyle: TextStyle(color: AppColors.textSecondary.withAlpha(100), fontSize: 12),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      filled: true,
                                      fillColor: AppColors.surfaceContainerLow,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.border)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.border)),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                                    ),
                                    onChanged: (val) => _updatePriceForSeries(val),
                                    onSubmitted: (val) => _onSeriesSubmitted(val),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Field 3: Start 5-Digit Number
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('From (5-Digits) *', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11.5)),
                                const SizedBox(height: 4),
                                SizedBox(
                                  height: 36,
                                  child: TextField(
                                    controller: _ticketNoCtrl,
                                    focusNode: _ticketNoFocusNode,
                                    maxLength: 5,
                                    textInputAction: TextInputAction.next,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(5),
                                    ],
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppColors.textPrimary, fontSize: 13.5),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      counterText: '',
                                      hintText: 'e.g. 28311',
                                      hintStyle: TextStyle(color: AppColors.textSecondary.withAlpha(100), fontSize: 12),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      filled: true,
                                      fillColor: AppColors.surfaceContainerLow,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.border)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.border)),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                                    ),
                                    onSubmitted: (_) {
                                      if (_toTicketNoCtrl.text.isNotEmpty) {
                                        _addBookingRow();
                                      } else {
                                        _toTicketNoFocusNode.requestFocus();
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Field 4: Optional End Number for Range
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('To (Range End)', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11.5)),
                                const SizedBox(height: 4),
                                SizedBox(
                                  height: 36,
                                  child: TextField(
                                    controller: _toTicketNoCtrl,
                                    focusNode: _toTicketNoFocusNode,
                                    maxLength: 5,
                                    textInputAction: TextInputAction.done,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(5),
                                    ],
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppColors.primary, fontSize: 13.5),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      counterText: '',
                                      hintText: 'e.g. 28315 / 15',
                                      hintStyle: TextStyle(color: AppColors.textSecondary.withAlpha(100), fontSize: 12),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      filled: true,
                                      fillColor: AppColors.surfaceContainerLow,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.border)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.border)),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                                    ),
                                    onSubmitted: (_) => _addBookingRow(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Field 5: Amount
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Amount (₹)', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11.5)),
                                const SizedBox(height: 4),
                                SizedBox(
                                  height: 36,
                                  child: TextField(
                                    controller: _amountCtrl,
                                    readOnly: true,
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.tertiary, fontSize: 13),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      prefixText: '₹',
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      filled: true,
                                      fillColor: AppColors.surfaceContainerLow,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.border)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.border)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Add Button
                          SizedBox(
                            height: 36,
                            child: ElevatedButton.icon(
                              onPressed: _addBookingRow,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('ADD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.6)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryContainer,
                                foregroundColor: AppColors.onPrimaryContainer,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                          ),
                          // Inline Latest Saved Entry Indicator
                          if (_lastAddedRow != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.success, width: 1.2),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Saved: #${_lastAddedRow!.ticketNo}',
                                    style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                  // 3. Search & Bulk Actions Header
                  if (!_showLedgerHistory) ...[
                    if (_selectedRowIds.isNotEmpty || _missingSeriesCount > 0)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: AppDecorations.radiusDefault,
                          border: Border.all(
                            color: _selectedRowIds.isNotEmpty ? Colors.amberAccent : Colors.amber.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
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
                                  _selectedRowIds.isNotEmpty
                                      ? '${_selectedRowIds.length} of ${_bookingRows.length} Numbers Selected'
                                      : 'Quick Actions:',
                                  style: AppTypography.titleMd.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (_missingSeriesCount > 0) ...[
                                  const SizedBox(width: 12),
                                  ActionChip(
                                    avatar: const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amberAccent),
                                    label: Text(
                                      'Select All $_missingSeriesCount No-Series Numbers',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amberAccent),
                                    ),
                                    backgroundColor: Colors.amber.withValues(alpha: 0.15),
                                    side: BorderSide(color: Colors.amberAccent.withValues(alpha: 0.5)),
                                    onPressed: _selectAllMissingSeries,
                                  ),
                                ],
                              ],
                            ),
                            if (_selectedRowIds.isNotEmpty)
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.amberAccent,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    ),
                                    icon: const Icon(Icons.flash_on_rounded, size: 16),
                                    label: Text('BULK SET SERIES (${_selectedRowIds.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    onPressed: _bulkSetSeriesDialog,
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    ),
                                    icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                                    label: Text('DELETE (${_selectedRowIds.length})'),
                                    onPressed: _bulkDeleteSelected,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),

                    // Search & Filter Row
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow.withAlpha(220),
                        border: Border(bottom: BorderSide(color: AppColors.border)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 34,
                              child: TextField(
                                controller: _tableSearchCtrl,
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: '🔍 Search Number or Series (e.g. 78476 or 12)...',
                                  hintStyle: TextStyle(
                                    color: AppColors.textSecondary.withAlpha(140),
                                    fontSize: 12,
                                  ),
                                  prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.primary),
                                  suffixIcon: _tableSearchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.close_rounded, size: 15, color: AppColors.textSecondary),
                                          onPressed: () {
                                            _tableSearchCtrl.clear();
                                            setState(() => _tableSearchQuery = '');
                                          },
                                        )
                                      : null,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  filled: true,
                                  fillColor: AppColors.surfaceContainerHigh,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(color: AppColors.border),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                                  ),
                                ),
                                onChanged: (val) {
                                  setState(() => _tableSearchQuery = val.trim().toLowerCase());
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Series Filter Dropdown
                          Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _selectedSeriesFilter != 'All' ? AppColors.primary : AppColors.border,
                                width: _selectedSeriesFilter != 'All' ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.filter_list_rounded, size: 15, color: AppColors.primary),
                                const SizedBox(width: 6),
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: effectiveSeriesFilter,
                                    dropdownColor: AppColors.surfaceContainerHighest,
                                    icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary, size: 16),
                                    style: AppTypography.bodySm.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5,
                                      color: effectiveSeriesFilter != 'All' ? AppColors.primary : AppColors.textPrimary,
                                    ),
                                    items: seriesFilterOptions.map((ser) {
                                      final count = ser == 'All' ? _bookingRows.length : (seriesBreakdown[ser] ?? 0);
                                      return DropdownMenuItem<String>(
                                        value: ser,
                                        child: Text(ser == 'All' ? 'All Series ($count)' : 'Series $ser ($count)'),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _selectedSeriesFilter = val);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 4. Expanded Table Section (Fills ALL Remaining Vertical Space)
                    Expanded(
                      child: Column(
                        children: [
                          // Sticky Fixed Table Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: const BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              border: Border(bottom: BorderSide(color: AppColors.border, width: 1.2)),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 36,
                                  child: Checkbox(
                                    value: _isAllSelected,
                                    onChanged: filteredBookingRows.isNotEmpty ? (_) => _toggleSelectAll() : null,
                                    activeColor: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 40, child: Text('Sl', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
                                const Expanded(flex: 3, child: Text('Customer / Seller', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
                                const Expanded(flex: 2, child: Text('Series', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
                                const Expanded(flex: 2, child: Text('Number', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
                                const Expanded(flex: 2, child: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
                                const Expanded(flex: 2, child: Text('Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary))),
                                const SizedBox(width: 80, child: Center(child: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textSecondary)))),
                              ],
                            ),
                          ),
                          // Scrollable Table Rows / Empty State
                          Expanded(
                            child: filteredBookingRows.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          _tableSearchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.inbox_outlined,
                                          size: 38,
                                          color: AppColors.textSecondary.withAlpha(100),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          _tableSearchQuery.isNotEmpty
                                              ? 'No numbers matching "${_tableSearchCtrl.text}"'
                                              : 'No numbers booked in this shift yet',
                                          style: AppTypography.bodySm.copyWith(
                                            color: AppColors.textSecondary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Type 5-digit number above & press Enter to quickly add',
                                          style: AppTypography.labelSm.copyWith(
                                            color: AppColors.textSecondary.withAlpha(110),
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: filteredBookingRows.length,
                                    itemExtent: 40,
                                    padding: EdgeInsets.zero,
                                    physics: const ClampingScrollPhysics(),
                                    itemBuilder: (context, index) {
                                      final row = filteredBookingRows[index];
                                      final isNewest = index == 0;
                                      final isSelected = _selectedRowIds.contains(row.id);
                                      final isMissingSeries = row.series.trim().isEmpty;

                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppColors.primary.withAlpha(25)
                                              : (isNewest
                                                  ? AppColors.primaryContainer.withAlpha(20)
                                                  : (index.isEven ? AppColors.surfaceContainerLowest : AppColors.surfaceContainerLow)),
                                          border: Border(bottom: BorderSide(color: AppColors.border.withAlpha(80))),
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 36,
                                              child: Checkbox(
                                                value: isSelected,
                                                onChanged: (_) => _toggleSelectRow(row.id),
                                                activeColor: AppColors.primary,
                                              ),
                                            ),
                                            SizedBox(
                                              width: 40,
                                              child: Text('${index + 1}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                                            ),
                                            Expanded(
                                              flex: 3,
                                              child: Text(
                                                row.sellerName.isNotEmpty ? row.sellerName : 'Direct Counter',
                                                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 12),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: isMissingSeries
                                                  ? Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(color: Colors.amber.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                                                      child: const Text('⚠️ NO SERIES', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent, fontSize: 10)),
                                                    )
                                                  : Text(
                                                      row.series,
                                                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12),
                                                    ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                row.ticketNo,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppColors.textPrimary, fontSize: 12.5),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                '₹${_formatPrice(row.amount)}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success, fontSize: 12),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                row.time,
                                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 80,
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.edit_outlined, size: 15, color: AppColors.primary),
                                                    tooltip: 'Edit',
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(),
                                                    onPressed: () => _editRow(row),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  IconButton(
                                                    icon: const Icon(Icons.delete_outline, size: 15, color: AppColors.error),
                                                    tooltip: 'Delete',
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(),
                                                    onPressed: () => _deleteRow(row),
                                                  ),
                                                ],
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

                    // 5. Unified Responsive Footer Bar (Live Metrics + Shortcuts in One Slim Line)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(14),
                          bottomRight: Radius.circular(14),
                        ),
                        border: Border(
                          top: BorderSide(
                            color: AppColors.primaryContainer.withAlpha(100),
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Left: Summary Badges & Series Pills (Safe scrollable)
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Total Count Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withAlpha(25),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.primary.withAlpha(80)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.confirmation_number_outlined, size: 13, color: AppColors.primary),
                                        const SizedBox(width: 5),
                                        Text(
                                          'Total: $_totalBookingCount Nos',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.primary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Total Amount Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withAlpha(25),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.success.withAlpha(100)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.currency_rupee_outlined, size: 13, color: AppColors.success),
                                        const SizedBox(width: 4),
                                        Text(
                                          '₹${_formatPrice(_totalAmount)}',
                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.success),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (seriesBreakdown.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    ...seriesBreakdown.entries.take(6).map((e) {
                                      final isMissing = e.key == 'No Series';
                                      final isSelected = _selectedSeriesFilter == e.key;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: InkWell(
                                          onTap: () {
                                            setState(() {
                                              _selectedSeriesFilter = _selectedSeriesFilter == e.key ? 'All' : e.key;
                                            });
                                          },
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? AppColors.primary.withAlpha(50)
                                                  : (isMissing ? Colors.amber.withAlpha(25) : AppColors.surfaceContainerLow),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isSelected
                                                    ? AppColors.primary
                                                    : (isMissing ? Colors.amberAccent.withAlpha(120) : AppColors.border),
                                              ),
                                            ),
                                            child: Text(
                                              isMissing ? '⚠️ Missing: ${e.value}' : 'Ser ${e.key}: ${e.value}',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: isMissing ? Colors.amberAccent : (isSelected ? AppColors.primary : AppColors.textSecondary),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Right: Keyboard Shortcuts (Flexible and scrollable to never overflow)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _shortcutKeyButton('F1-New', Icons.add_circle_outline, () => _resetFormInputs(availableSeries)),
                                _shortcutKeyDivider(),
                                _shortcutKeyButton('F2-Search', Icons.search, () {
                                  setState(() => _showLedgerHistory = !_showLedgerHistory);
                                }),
                                _shortcutKeyDivider(),
                                _shortcutKeyButton('F3-Prices', Icons.sell_outlined, () {
                                  _showSnackbar('Use Price & Series Setup tab on sidebar to edit rates', AppColors.info);
                                }),
                                _shortcutKeyDivider(),
                                _shortcutKeyButton('F4-Save', Icons.save_outlined, _saveSessionBookings, isPrimary: true),
                                _shortcutKeyDivider(),
                                _shortcutKeyButton('F5-Print', Icons.print_outlined, _printReceipt),
                                _shortcutKeyDivider(),
                                _shortcutKeyButton('Esc-Clear', Icons.clear_all, _clearAllRows, isDanger: true),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: SingleChildScrollView(
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
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_showFloatingSummary)
          _buildFloatingSummaryOverlay(availableSeries, seriesBreakdown),
      ],
    );
  }

  Widget _compactActionButton(String label, Color bg, Color fg, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 1,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
    );
  }

  Widget _compactOutlineButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11.5)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.6)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTypography.labelSm.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 11,
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
      margin: const EdgeInsets.symmetric(horizontal: 4),
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

  // 📌 FLOATING & RESIZABLE LIVE SUMMARY OVERLAY
  Widget _buildFloatingSummaryOverlay(List<String> availableSeries, Map<String, int> seriesBreakdown) {
    return Positioned(
      left: _floatingSummaryOffset.dx,
      top: _floatingSummaryOffset.dy,
      child: Material(
        color: Colors.transparent,
        elevation: 16,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: _isFloatingSummaryMinimized ? 290 : _floatingSummaryWidth,
          height: _isFloatingSummaryMinimized ? 48 : _floatingSummaryHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.amberAccent.withValues(alpha: 0.7),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Draggable Window Header Bar
                  GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _floatingSummaryOffset = Offset(
                          (_floatingSummaryOffset.dx + details.delta.dx).clamp(0.0, 1600.0),
                          (_floatingSummaryOffset.dy + details.delta.dy).clamp(0.0, 1000.0),
                        );
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: _isFloatingSummaryMinimized ? const Radius.circular(12) : Radius.zero,
                          bottomRight: _isFloatingSummaryMinimized ? const Radius.circular(12) : Radius.zero,
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color: _isFloatingSummaryMinimized ? Colors.transparent : const Color(0xFF334155),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.drag_indicator_rounded, size: 16, color: Colors.amberAccent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _isFloatingSummaryMinimized
                                  ? '📌 Summary: $_totalBookingCount Nos (₹${_formatPrice(_totalAmount)})'
                                  : '📌 LIVE BOOKING WATCHER',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _isFloatingSummaryMinimized ? Icons.open_in_full_rounded : Icons.close_fullscreen_rounded,
                              size: 15,
                              color: Colors.amberAccent,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: _isFloatingSummaryMinimized ? 'Expand Panel' : 'Minimize Panel',
                            onPressed: () => setState(() => _isFloatingSummaryMinimized = !_isFloatingSummaryMinimized),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Close Floating Card',
                            onPressed: () => setState(() => _showFloatingSummary = false),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 2. Expanded Content
                  if (!_isFloatingSummaryMinimized) ...[
                    // KPI Row
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF131D2E),
                        border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 0.8)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('TOTAL NUMBERS', style: TextStyle(color: Colors.grey, fontSize: 9.5, fontWeight: FontWeight.bold)),
                              Text('$_totalBookingCount', style: const TextStyle(color: Colors.amberAccent, fontSize: 15, fontWeight: FontWeight.w900)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('TOTAL AMOUNT', style: TextStyle(color: Colors.grey, fontSize: 9.5, fontWeight: FontWeight.bold)),
                              Text('₹${_formatPrice(_totalAmount)}', style: const TextStyle(color: Colors.greenAccent, fontSize: 15, fontWeight: FontWeight.w900)),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Series Breakdown Chips
                    if (seriesBreakdown.isNotEmpty)
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        color: const Color(0xFF0F172A),
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: seriesBreakdown.entries.map((e) {
                            return Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF334155)),
                              ),
                              child: Text(
                                '${e.key}: ${e.value}',
                                style: const TextStyle(color: Colors.cyanAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                    // Live Number Booking List
                    Expanded(
                      child: _bookingRows.isEmpty
                          ? const Center(
                              child: Text(
                                'No numbers booked yet',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(8, 6, 8, 20),
                              itemCount: _bookingRows.length,
                              separatorBuilder: (_, _) => const Divider(color: Color(0xFF1E293B), height: 1),
                              itemBuilder: (ctx, idx) {
                                final row = _bookingRows[_bookingRows.length - 1 - idx];
                                return Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.18),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          row.series,
                                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        row.ticketNo,
                                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          row.sellerName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                                        ),
                                      ),
                                      Text(
                                        '₹${_formatPrice(row.amount)}',
                                        style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () => _deleteRow(row),
                                        child: const Icon(Icons.delete_outline_rounded, size: 15, color: Colors.redAccent),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ],
              ),

              // 3. Corner Resize Handle (Bottom-Right)
              if (!_isFloatingSummaryMinimized)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _floatingSummaryWidth = (_floatingSummaryWidth + details.delta.dx).clamp(280.0, 750.0);
                        _floatingSummaryHeight = (_floatingSummaryHeight + details.delta.dy).clamp(200.0, 850.0);
                      });
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.bottomRight,
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.only(bottomRight: Radius.circular(14)),
                      ),
                      child: const Icon(Icons.south_east_rounded, size: 14, color: Colors.amberAccent),
                    ),
                  ),
                ),
            ],
          ),
        ),
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
