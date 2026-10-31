import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/database/database_service.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../services/booking_pdf_service.dart';

class BookingHistoryDialog extends StatefulWidget {
  final DateTime initialDate;

  const BookingHistoryDialog({
    super.key,
    required this.initialDate,
  });

  @override
  State<BookingHistoryDialog> createState() => _BookingHistoryDialogState();
}

class _BookingHistoryDialogState extends State<BookingHistoryDialog> {
  late DateTime _selectedDate;
  DateTime? _rangeStartDate;
  DateTime? _rangeEndDate;
  bool _isLoading = true;
  String _loadingStatus = 'Fetching booking records...';
  List<TicketSaleModel> _allDateSales = [];
  String _exportRange = 'Today'; // Options: 'Today', 'Weekly', 'Monthly', 'Custom'
  String _selectedShiftFilter = 'All'; // 'All', 'Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'
  String _selectedCustomerFilter = 'All'; // 'All' or specific customer/seller name
  bool _isExporting = false;

  // 🚀 SMOOTH CHUNK LOADING & CACHING (Zero UI freeze)
  int _displayedLimit = 100;
  int _activeBodyTab = 0;
  final ScrollController _listScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _seriesScrollController = ScrollController();
  bool _isLoadingMore = false;

  // Precomputed customer lookups to prevent UI freezing in build()
  List<String> _cachedCustomerList = ['All'];
  Map<String, int> _customerQtyMap = {'All': 0};
  Map<String, int> _customerRecordsMap = {'All': 0};

  List<TicketSaleModel> _customerSales = [];
  List<TicketSaleModel> _filteredSales = [];
  List<_LocalSeriesSummary> _sortedSeriesList = [];
  int _count1PM = 0, _count6PM = 0, _count8PM = 0;
  double _total1PM = 0, _total6PM = 0, _total8PM = 0;
  int _grandQty = 0;
  double _grandAmt = 0;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _listScrollController.addListener(_onListScroll);
    _loadSalesForDate();
  }

  @override
  void dispose() {
    _listScrollController.removeListener(_onListScroll);
    _listScrollController.dispose();
    _horizontalScrollController.dispose();
    _seriesScrollController.dispose();
    super.dispose();
  }

  void _onListScroll() {
    if (!_listScrollController.hasClients || _isLoadingMore) return;
    if (_listScrollController.position.pixels >= _listScrollController.position.maxScrollExtent - 250) {
      _loadMoreChunks();
    }
  }

  void _loadMoreChunks() {
    if (_isLoadingMore) return;
    if (_displayedLimit >= _filteredSales.length) return;
    _isLoadingMore = true;
    setState(() {
      _displayedLimit = math.min(_displayedLimit + 250, _filteredSales.length);
    });
    Future.microtask(() {
      if (mounted) _isLoadingMore = false;
    });
  }

  /// Single-pass O(N) customer aggregation (avoids quadratic scanning in build())
  void _computeCustomerStats() {
    final Map<String, int> qtyMap = {};
    final Map<String, int> countMap = {};
    final Set<String> customers = {'All'};

    int totalQtyAll = 0;
    for (final s in _allDateSales) {
      final name = s.buyerName.trim();
      totalQtyAll += s.quantity;
      if (name.isNotEmpty) {
        customers.add(name);
        qtyMap[name] = (qtyMap[name] ?? 0) + s.quantity;
        countMap[name] = (countMap[name] ?? 0) + 1;
      }
    }
    qtyMap['All'] = totalQtyAll;
    countMap['All'] = _allDateSales.length;

    final sortedCust = customers.toList()
      ..sort((a, b) {
        if (a == 'All') return -1;
        if (b == 'All') return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    _cachedCustomerList = sortedCust;
    _customerQtyMap = qtyMap;
    _customerRecordsMap = countMap;
  }

  void _recomputeFilteredSales() {
    // 1. Customer filter
    if (_selectedCustomerFilter == 'All') {
      _customerSales = List.of(_allDateSales);
    } else {
      final target = _selectedCustomerFilter.trim().toLowerCase();
      _customerSales = _allDateSales
          .where((s) => s.buyerName.trim().toLowerCase() == target)
          .toList();
    }

    // 2. Shift filter
    final list = _customerSales.where((s) {
      if (_selectedShiftFilter == 'All') return true;
      return _getShift(s.drawName) == _selectedShiftFilter;
    }).toList();

    // 3. Structured sort: Shift (1 PM -> 6 PM -> 8 PM), then Series, then Ticket No
    list.sort((a, b) {
      final aSer = a.ticketSeries;
      final bSer = b.ticketSeries;
      final aMissing = aSer == '?' || aSer.isEmpty || aSer == 'MISSING' || aSer == 'UNKNOWN' || aSer == '—' || aSer == '-';
      final bMissing = bSer == '?' || bSer.isEmpty || bSer == 'MISSING' || bSer == 'UNKNOWN' || bSer == '—' || bSer == '-';

      if (aMissing && !bMissing) return -1;
      if (!aMissing && bMissing) return 1;

      // 1. When All shifts are selected, sort chronologically: 1 PM -> 6 PM -> 8 PM
      if (_selectedShiftFilter == 'All') {
        final shiftA = _getShiftOrder(a.drawName);
        final shiftB = _getShiftOrder(b.drawName);
        if (shiftA != shiftB) {
          return shiftA.compareTo(shiftB);
        }
      }

      // 2. Series order
      final serComp = a.ticketSeries.compareTo(b.ticketSeries);
      if (serComp != 0) return serComp;

      // 3. Ticket number numeric order
      final numA = int.tryParse(a.ticketNumber.trim()) ?? -1;
      final numB = int.tryParse(b.ticketNumber.trim()) ?? -1;
      if (numA != -1 && numB != -1 && numA != numB) {
        return numA.compareTo(numB);
      }

      return b.saleDate.compareTo(a.saleDate);
    });
    _filteredSales = list;

    // 4. Precompute Shift-wise totals
    _count1PM = 0;
    _count6PM = 0;
    _count8PM = 0;
    _total1PM = 0.0;
    _total6PM = 0.0;
    _total8PM = 0.0;

    for (final sale in _customerSales) {
      final shift = _getShift(sale.drawName);
      if (shift == 'Dear 1 PM') {
        _count1PM += sale.quantity;
        _total1PM += sale.totalAmount;
      } else if (shift == 'Dear 6 PM') {
        _count6PM += sale.quantity;
        _total6PM += sale.totalAmount;
      } else if (shift == 'Dear 8 PM') {
        _count8PM += sale.quantity;
        _total8PM += sale.totalAmount;
      }
    }

    _grandQty = _count1PM + _count6PM + _count8PM;
    _grandAmt = _total1PM + _total6PM + _total8PM;

    // 5. Precompute Series Summary
    final Map<String, _LocalSeriesSummary> seriesMap = {};
    for (final sale in _filteredSales) {
      final ser = sale.ticketSeries.toUpperCase();
      final existing = seriesMap[ser];
      if (existing == null) {
        seriesMap[ser] = _LocalSeriesSummary(
          series: ser,
          quantity: sale.quantity,
          rate: sale.pricePerTicket,
          totalAmount: sale.totalAmount,
        );
      } else {
        existing.quantity += sale.quantity;
        existing.totalAmount += sale.totalAmount;
      }
    }
    _sortedSeriesList = seriesMap.values.toList()
      ..sort((a, b) => a.series.compareTo(b.series));
  }

  Future<void> _loadSalesForDate() async {
    setState(() {
      _isLoading = true;
      _loadingStatus = 'Fetching records from database...';
    });
    try {
      List<TicketSaleModel> sales = [];
      if (_exportRange == 'Today') {
        sales = await DatabaseService.instance.getTicketSalesByDate(_selectedDate);
      } else if (_exportRange == 'Weekly') {
        final start = _selectedDate.subtract(const Duration(days: 6));
        sales = await DatabaseService.instance.getTicketSalesByDateRange(start, _selectedDate);
      } else if (_exportRange == 'Monthly') {
        final start = _selectedDate.subtract(const Duration(days: 29));
        sales = await DatabaseService.instance.getTicketSalesByDateRange(start, _selectedDate);
      } else if (_exportRange == 'Custom' && _rangeStartDate != null && _rangeEndDate != null) {
        sales = await DatabaseService.instance.getTicketSalesByDateRange(_rangeStartDate!, _rangeEndDate!);
      } else {
        sales = await DatabaseService.instance.getTicketSalesByDate(_selectedDate);
      }

      if (!mounted) return;
      setState(() {
        _loadingStatus = 'Organizing ${sales.length} booking records...';
      });
      // Yield execution so the UI thread updates the progress message cleanly
      await Future.delayed(const Duration(milliseconds: 15));

      if (mounted) {
        _allDateSales = sales;
        _computeCustomerStats();
        _recomputeFilteredSales();
        setState(() {
          _displayedLimit = 100;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load history: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _pickDate() async {
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
              surface: AppColors.surfaceContainerHigh,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _exportRange = 'Today';
        _rangeStartDate = null;
        _rangeEndDate = null;
      });
      _loadSalesForDate();
    }
  }

  Future<void> _pickDateRange() async {
    final initialRange = DateTimeRange(
      start: _rangeStartDate ?? _selectedDate.subtract(const Duration(days: 6)),
      end: _rangeEndDate ?? _selectedDate,
    );

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'Select Custom Date Range for Hisab & PDF',
      cancelText: 'Cancel',
      confirmText: 'Apply Range',
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: Colors.black,
              surface: AppColors.surfaceContainerHigh,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _exportRange = 'Custom';
        _rangeStartDate = picked.start;
        _rangeEndDate = picked.end;
        _selectedDate = picked.end;
      });
      _loadSalesForDate();
    }
  }

  Future<bool> _hasDeclaredResultForDateAndShift(DateTime date, String shift) async {
    try {
      final results = await DatabaseService.instance.getLotteryResults();
      final dateStr1 = DateFormat('dd/MM/yyyy').format(date);
      final dateStr2 = DateFormat('yyyy-MM-dd').format(date);

      for (final r in results) {
        final dDateStr = r['drawDateStr']?.toString() ?? '';
        final dName = (r['drawName']?.toString() ?? '').toLowerCase();
        final matchDate = dDateStr == dateStr1 || dDateStr == dateStr2 || dDateStr.contains(dateStr1);

        if (matchDate) {
          if (shift == 'All') return true;
          final s = shift.toLowerCase();
          if (s.contains('1') || s.contains('morning')) {
            if (dName.contains('1:00') || dName.contains('1 pm') || dName.contains('1pm') || dName.contains('morning')) return true;
          } else if (s.contains('6') || s.contains('day')) {
            if (dName.contains('6:00') || dName.contains('6 pm') || dName.contains('6pm') || dName.contains('day')) return true;
          } else if (s.contains('8') || s.contains('night') || s.contains('evening')) {
            if (dName.contains('8:00') || dName.contains('8 pm') || dName.contains('8pm') || dName.contains('night') || dName.contains('evening')) return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  void _showResultPendingModal(BuildContext context, String shift, DateTime date) {
    final dateFormatted = DateFormat('dd/MM/yyyy').format(date);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withValues(alpha: 0.25),
                blurRadius: 36,
                spreadRadius: 6,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.4), width: 2),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 40),
              ),
              const SizedBox(height: 18),
              const Text(
                'Result Entry Pending',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'Official Lottery Sambad results for $dateFormatted (${shift == 'All' ? 'All Shifts' : shift}) have not been entered yet.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  '🔒 Export Lock Active: Final settled hisab & winning inami payouts can only be exported after official result numbers are entered in Result Entry.',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 12, height: 1.4),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancel'),
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
                      icon: const Icon(Icons.edit_note_rounded, size: 18),
                      label: const Text('ENTER RESULT NOW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).pop(); // close history dialog
                        context.go(AppConstants.routeResultEntry);
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

  Future<void> _handlePdfExport({
    required bool isSummaryOnly,
    required int grandQty,
    required double grandAmt,
  }) async {
    if (_isExporting || _filteredSales.isEmpty) return;

    if (!mounted) return;
    setState(() => _isExporting = true);

    bool dialogOpen = true;
    double currentProgress = 0.05;
    String currentStatus = 'Checking results & initializing engine...';
    StateSetter? dialogSetState;

    try {
      final suffix = isSummaryOnly ? ' (SUMMARY ONLY)' : '';
      String dateRangeLabel = '';
      if (_exportRange == 'Today') {
        dateRangeLabel = DateFormat('dd/MM/yyyy').format(_selectedDate);
      } else if (_exportRange == 'Weekly') {
        final start = _selectedDate.subtract(const Duration(days: 6));
        dateRangeLabel = '${DateFormat('dd/MM/yyyy').format(start)} TO ${DateFormat('dd/MM/yyyy').format(_selectedDate)} (WEEKLY)';
      } else if (_exportRange == 'Monthly') {
        final start = _selectedDate.subtract(const Duration(days: 29));
        dateRangeLabel = '${DateFormat('dd/MM/yyyy').format(start)} TO ${DateFormat('dd/MM/yyyy').format(_selectedDate)} (MONTHLY)';
      } else if (_exportRange == 'Custom' && _rangeStartDate != null && _rangeEndDate != null) {
        dateRangeLabel = '${DateFormat('dd/MM/yyyy').format(_rangeStartDate!)} TO ${DateFormat('dd/MM/yyyy').format(_rangeEndDate!)}';
      } else {
        dateRangeLabel = DateFormat('dd/MM/yyyy').format(_selectedDate);
      }

      final rangeTitle = _selectedCustomerFilter == 'All'
          ? 'BOOKINGS & HISAB REPORT [$dateRangeLabel]$suffix'
          : '$_selectedCustomerFilter - HISAB REPORT [$dateRangeLabel]$suffix';

      // Show live loading progress dialog immediately (Zero click lag)
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogCtx) {
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              dialogSetState = setModalState;
              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(horizontal: 32),
                child: Container(
                  width: 440,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 1.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.picture_as_pdf_rounded,
                              color: AppColors.primary,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isSummaryOnly ? 'Generating Summary PDF' : 'Generating Full PDF Report',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Processing ${_filteredSales.length} tickets step-by-step',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${(currentProgress * 100).toInt()}%',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: currentProgress > 0 ? currentProgress : null,
                          minHeight: 10,
                          backgroundColor: const Color(0xFF334155),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              currentStatus,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '⚡ Rendering one chunk at a time to prevent UI lag',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      // Allow dialog to mount and display smoothly
      await Future.delayed(const Duration(milliseconds: 60));

      if (mounted && dialogSetState != null) {
        dialogSetState!(() {
          currentProgress = 0.08;
          currentStatus = 'Verifying lottery results lock...';
        });
      }

      // 🔒 Check if Result Entry has been completed for this date/shift
      final hasResult = await _hasDeclaredResultForDateAndShift(_selectedDate, _selectedShiftFilter);
      if (!hasResult) {
        if (dialogOpen && mounted) {
          dialogOpen = false;
          Navigator.of(context, rootNavigator: true).pop();
        }
        if (mounted) {
          setState(() => _isExporting = false);
          _showResultPendingModal(context, _selectedShiftFilter, _selectedDate);
        }
        return;
      }

      if (mounted && dialogSetState != null) {
        dialogSetState!(() {
          currentProgress = 0.10;
          currentStatus = 'Preparing ticket data & shifts...';
        });
      }

      // 1. Generate & Save PDF to C:\Lottery_Reports step-by-step
      final res = await BookingPdfService.instance.savePdfToDisk(
        date: _selectedDate,
        sales: _filteredSales,
        customerName: _selectedCustomerFilter == 'All' ? null : _selectedCustomerFilter,
        rangeTitle: rangeTitle,
        isSummaryOnly: isSummaryOnly,
        onProgress: (progress, status) {
          if (mounted && dialogSetState != null) {
            dialogSetState!(() {
              currentProgress = progress;
              currentStatus = status;
            });
          }
        },
      );

      // Close loading dialog before opening options modal
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }

      final savedPath = res['filePath'] as String;
      final fileName = res['fileName'] as String;
      final pdfBytes = res['bytes'];
      final custName = res['customerName'] as String;

      if (!mounted) return;

      // 2. Open action modal with Open, Share WhatsApp, Print Preview, and Explorer
      _showPdfExportOptionsModal(
        filePath: savedPath,
        fileName: fileName,
        bytes: pdfBytes,
        customerName: custName,
        totalTickets: grandQty,
        totalSales: grandAmt,
      );
    } catch (err) {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ PDF Export Note: $err'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  String _getShift(String drawName) {
    return BookingPdfService.instance.getDrawShift(drawName);
  }

  int _getShiftOrder(String drawName) {
    final s = _getShift(drawName).toLowerCase();
    if (s.contains('1')) return 1;
    if (s.contains('6')) return 2;
    if (s.contains('8')) return 3;
    return 4;
  }

  List<String> get _availableCustomers => _cachedCustomerList;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd-MM-yyyy (EEEE)');
    final dateStr = dateFormat.format(_selectedDate);

    final screenSize = MediaQuery.of(context).size;
    final dialogW = math.min(1300.0, screenSize.width * 0.96);
    final dialogH = math.min(880.0, screenSize.height * 0.94);
    final isCompact = dialogW < 1120;
    final isNarrow = dialogW < 960;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Container(
        width: dialogW,
        height: dialogH,
        padding: EdgeInsets.all(isNarrow ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── TOP HEADER BAR (RESPONSIVE) ─────────────────────────────────
            if (isCompact) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.history_rounded, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Booking History & Audit',
                      style: AppTypography.titleMd.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildPdfButtons(),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Open Reports Folder',
                    icon: const Icon(Icons.folder_open_rounded, color: AppColors.primary, size: 20),
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: () => BookingPdfService.instance.openReportsFolder(),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildRangeChipContainer(),
            ] else ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.history_rounded, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Booking History & Shift Summary',
                          style: AppTypography.titleMd.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Date-by-date ticket sales audit & PDF exporter',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildRangeChipContainer(),
                  const SizedBox(width: 8),
                  _buildPdfButtons(),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Open Reports Folder',
                    icon: const Icon(Icons.folder_open_rounded, color: AppColors.primary, size: 20),
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: () => BookingPdfService.instance.openReportsFolder(),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),

            // ─── SHIFT SUMMARY STAT CARDS (RESPONSIVE) ───────────────────────
            if (isNarrow) ...[
              Row(
                children: [
                  _buildStatCard(title: '1 PM (Morning)', qty: _count1PM, amount: _total1PM, color: Colors.amber, icon: Icons.wb_sunny_rounded),
                  const SizedBox(width: 8),
                  _buildStatCard(title: '6 PM (Day)', qty: _count6PM, amount: _total6PM, color: Colors.orangeAccent, icon: Icons.wb_twilight_rounded),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildStatCard(title: '8 PM (Night)', qty: _count8PM, amount: _total8PM, color: Colors.purpleAccent, icon: Icons.nightlight_round),
                  const SizedBox(width: 8),
                  _buildStatCard(title: _selectedCustomerFilter == 'All' ? 'Total All Shifts' : 'Total ($_selectedCustomerFilter)', qty: _grandQty, amount: _grandAmt, color: AppColors.success, icon: Icons.account_balance_wallet_rounded, isHighlight: true),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  _buildStatCard(title: '1 PM Shift (Morning)', qty: _count1PM, amount: _total1PM, color: Colors.amber, icon: Icons.wb_sunny_rounded),
                  const SizedBox(width: 12),
                  _buildStatCard(title: '6 PM Shift (Day)', qty: _count6PM, amount: _total6PM, color: Colors.orangeAccent, icon: Icons.wb_twilight_rounded),
                  const SizedBox(width: 12),
                  _buildStatCard(title: '8 PM Shift (Night)', qty: _count8PM, amount: _total8PM, color: Colors.purpleAccent, icon: Icons.nightlight_round),
                  const SizedBox(width: 12),
                  _buildStatCard(title: _selectedCustomerFilter == 'All' ? 'Total All Shifts' : 'Total ($_selectedCustomerFilter)', qty: _grandQty, amount: _grandAmt, color: AppColors.success, icon: Icons.account_balance_wallet_rounded, isHighlight: true),
                ],
              ),
            ],
            const SizedBox(height: 12),

            // ─── FILTER CONTROLS: SHIFT TABS + CUSTOMER SELECTOR (RESPONSIVE WRAP) ───
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Shift:', style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    ...['All', 'Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'].map((shiftName) {
                      final isSelected = _selectedShiftFilter == shiftName;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          selected: isSelected,
                          label: Text(shiftName),
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.surfaceContainerLow,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : AppColors.textSecondary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                          onSelected: (val) {
                            setState(() {
                              _selectedShiftFilter = shiftName;
                              _displayedLimit = 100;
                              _recomputeFilteredSales();
                            });
                          },
                        ),
                      );
                    }),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Customer:', style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _selectedCustomerFilter != 'All' ? AppColors.primary : AppColors.border,
                          width: _selectedCustomerFilter != 'All' ? 1.5 : 1.0,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _availableCustomers.contains(_selectedCustomerFilter)
                              ? _selectedCustomerFilter
                              : 'All',
                          dropdownColor: AppColors.surfaceContainerHigh,
                          icon: const Icon(Icons.arrow_drop_down_rounded, color: AppColors.primary, size: 22),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedCustomerFilter = val;
                                _displayedLimit = 100;
                                _recomputeFilteredSales();
                              });
                            }
                          },
                          items: _cachedCustomerList.map((cust) {
                            final totalQty = _customerQtyMap[cust] ?? 0;
                            final totalRecords = _customerRecordsMap[cust] ?? 0;
                            return DropdownMenuItem<String>(
                              value: cust,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    cust == 'All' ? Icons.people_alt_rounded : Icons.person_rounded,
                                    size: 16,
                                    color: cust == 'All' ? AppColors.textSecondary : AppColors.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(cust == 'All'
                                      ? 'All Customers ($totalQty tkts / $totalRecords rec)'
                                      : '$cust ($totalQty tkts)'),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    'Showing ${math.min(_displayedLimit, _filteredSales.length)} of ${_filteredSales.length} records ($_grandQty total tkts)',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),

            if (isNarrow) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      avatar: const Icon(Icons.table_chart_rounded, size: 16),
                      label: Text('Bookings List (${_filteredSales.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      selected: _activeBodyTab == 0,
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(color: _activeBodyTab == 0 ? Colors.black : AppColors.textSecondary),
                      onSelected: (_) => setState(() => _activeBodyTab = 0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      avatar: const Icon(Icons.pie_chart_outline_rounded, size: 16),
                      label: Text('Series Summary (${_sortedSeriesList.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      selected: _activeBodyTab == 1,
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(color: _activeBodyTab == 1 ? Colors.black : AppColors.textSecondary),
                      onSelected: (_) => setState(() => _activeBodyTab = 1),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),

            // ─── BODY CONTENT: SERIES SUMMARY + SALES DATA TABLE ────────────
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _loadingStatus,
                              style: AppTypography.titleMd.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Optimizing view and calculating live aggregates...',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _filteredSales.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.find_in_page_rounded,
                                size: 50,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No bookings recorded for $dateStr ($_selectedShiftFilter)',
                                style: AppTypography.bodyMd.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : isNarrow
                          ? (_activeBodyTab == 0 ? _buildBookingsTable(isNarrow: true) : _buildSeriesSummary())
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: math.min(310.0, dialogW * 0.28),
                                  child: _buildSeriesSummary(),
                                ),
                                const SizedBox(width: 14),
                                Expanded(child: _buildBookingsTable(isNarrow: false)),
                              ],
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.info,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: _isExporting
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.picture_as_pdf_rounded, size: 15),
          label: Text(
            _isExporting ? 'Exporting...' : 'Full PDF',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
          ),
          onPressed: (_filteredSales.isEmpty || _isExporting)
              ? null
              : () => _handlePdfExport(
                    isSummaryOnly: false,
                    grandQty: _grandQty,
                    grandAmt: _grandAmt,
                  ),
        ),
        const SizedBox(width: 6),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D9488),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: _isExporting
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.analytics_rounded, size: 15),
          label: Text(
            _isExporting ? 'Exporting...' : 'Summary PDF',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
          ),
          onPressed: (_filteredSales.isEmpty || _isExporting)
              ? null
              : () => _handlePdfExport(
                    isSummaryOnly: true,
                    grandQty: _grandQty,
                    grandAmt: _grandAmt,
                  ),
        ),
      ],
    );
  }

  Widget _buildRangeChipContainer() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChoiceChip(
              visualDensity: VisualDensity.compact,
              label: const Text('Today', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              selected: _exportRange == 'Today',
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(color: _exportRange == 'Today' ? Colors.white : AppColors.textSecondary),
              onSelected: (sel) {
                if (sel) {
                  setState(() {
                    _exportRange = 'Today';
                    _selectedDate = DateTime.now();
                    _rangeStartDate = null;
                    _rangeEndDate = null;
                  });
                  _loadSalesForDate();
                }
              },
            ),
            const SizedBox(width: 3),
            ChoiceChip(
              visualDensity: VisualDensity.compact,
              label: const Text('Weekly (7D)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              selected: _exportRange == 'Weekly',
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(color: _exportRange == 'Weekly' ? Colors.white : AppColors.textSecondary),
              onSelected: (sel) {
                if (sel) {
                  setState(() {
                    _exportRange = 'Weekly';
                    _rangeStartDate = null;
                    _rangeEndDate = null;
                  });
                  _loadSalesForDate();
                }
              },
            ),
            const SizedBox(width: 3),
            ChoiceChip(
              visualDensity: VisualDensity.compact,
              label: const Text('Monthly (30D)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              selected: _exportRange == 'Monthly',
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(color: _exportRange == 'Monthly' ? Colors.white : AppColors.textSecondary),
              onSelected: (sel) {
                if (sel) {
                  setState(() {
                    _exportRange = 'Monthly';
                    _rangeStartDate = null;
                    _rangeEndDate = null;
                  });
                  _loadSalesForDate();
                }
              },
            ),
            const SizedBox(width: 3),
            ActionChip(
              visualDensity: VisualDensity.compact,
              backgroundColor: _exportRange == 'Custom' ? AppColors.primary.withAlpha(40) : null,
              side: _exportRange == 'Custom' ? const BorderSide(color: AppColors.primary, width: 1.5) : null,
              avatar: Icon(
                Icons.date_range_rounded,
                size: 14,
                color: _exportRange == 'Custom' ? AppColors.primary : AppColors.textSecondary,
              ),
              label: Text(
                (_exportRange == 'Custom' && _rangeStartDate != null && _rangeEndDate != null)
                    ? '${DateFormat('dd/MM').format(_rangeStartDate!)} - ${DateFormat('dd/MM/yy').format(_rangeEndDate!)}'
                    : 'Custom Range 📅',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: _exportRange == 'Custom' ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
              onPressed: _pickDateRange,
            ),
            const SizedBox(width: 3),
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.calendar_month_rounded, size: 14, color: AppColors.primary),
              label: Text(
                DateFormat('dd/MM/yyyy').format(_selectedDate),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textPrimary),
              ),
              onPressed: _pickDate,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeriesSummary() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pie_chart_outline_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Series Rate Summary',
                style: AppTypography.titleMd.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          Expanded(
            child: Scrollbar(
              controller: _seriesScrollController,
              thumbVisibility: true,
              child: ListView.separated(
                controller: _seriesScrollController,
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                itemCount: _sortedSeriesList.length,
                separatorBuilder: (_, _) =>
                    const Divider(color: AppColors.border, height: 1),
                itemBuilder: (context, idx) {
                  final item = _sortedSeriesList[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Series ${item.series}',
                              style: AppTypography.bodyMd
                                  .copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Rate: ₹${item.rate.toStringAsFixed(2)} / tkt',
                              style: AppTypography.bodySm
                                  .copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${item.quantity} Tkts',
                              style: AppTypography.bodyMd
                                  .copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '₹${item.totalAmount.toStringAsFixed(2)}',
                              style: AppTypography.bodySm
                                  .copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Series: ${_sortedSeriesList.length}',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '₹${_sortedSeriesList.fold<double>(0, (sum, e) => sum + e.totalAmount).toStringAsFixed(2)}',
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBookingsTable({required bool isNarrow}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          final tableW = math.max(680.0, box.maxWidth);
          return Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableW,
                child: Column(
                  children: [
                    // Sticky Header Row
                    Container(
                      color: AppColors.surfaceContainerHigh,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      child: const Row(
                        children: [
                          SizedBox(width: 45, child: Text('#', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12))),
                          SizedBox(width: 90, child: Text('Shift', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12))),
                          SizedBox(width: 80, child: Text('Series', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12))),
                          SizedBox(width: 115, child: Text('Ticket No.', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12))),
                          SizedBox(width: 55, child: Text('Qty', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12))),
                          SizedBox(width: 90, child: Text('Rate (₹)', textAlign: TextAlign.right, style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12))),
                          SizedBox(width: 95, child: Text('Total (₹)', textAlign: TextAlign.right, style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12))),
                          SizedBox(width: 16),
                          Expanded(child: Text('Seller / Customer', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12))),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    // High-Performance Virtualized Scroll List with itemExtent: 38.0 (Butter-smooth 60/120 FPS)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final visibleCount = math.min(_displayedLimit, _filteredSales.length);

                          return Scrollbar(
                            controller: _listScrollController,
                            thumbVisibility: true,
                            child: ListView.builder(
                              controller: _listScrollController,
                              itemCount: visibleCount,
                              itemExtent: 38.0,
                              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                              itemBuilder: (context, idx) {
                                final sale = _filteredSales[idx];
                                final shift = _getShift(sale.drawName);
                                final isNoSeries = sale.ticketSeries == '?' ||
                                    sale.ticketSeries.isEmpty ||
                                    sale.ticketSeries == 'UNKNOWN' ||
                                    sale.ticketSeries == 'MISSING';

                                return Container(
                                  height: 38.0,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: idx.isEven ? Colors.transparent : AppColors.surfaceContainerHighest.withAlpha(25),
                                    border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(width: 45, child: Text('${idx + 1}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                                      SizedBox(
                                        width: 90,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: shift.contains('1 PM')
                                                ? Colors.amber.withValues(alpha: 0.18)
                                                : shift.contains('6 PM')
                                                    ? Colors.orange.withValues(alpha: 0.18)
                                                    : Colors.purple.withValues(alpha: 0.18),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            shift,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: shift.contains('1 PM')
                                                  ? Colors.amber
                                                  : shift.contains('6 PM')
                                                      ? Colors.orangeAccent
                                                      : Colors.purpleAccent,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 80,
                                        child: isNoSeries
                                            ? Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber.withValues(alpha: 0.25),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: Colors.amber, width: 1),
                                                ),
                                                child: const Text('NO SER', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 9.5)),
                                              )
                                            : Text(
                                                sale.ticketSeries,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary),
                                              ),
                                      ),
                                      SizedBox(
                                        width: 115,
                                        child: Text(
                                          sale.ticketNumber,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 55,
                                        child: sale.quantity > 1
                                            ? Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber.withValues(alpha: 0.25),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: Colors.amber, width: 1.0),
                                                ),
                                                child: Text(
                                                  '${sale.quantity}',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.amber),
                                                ),
                                              )
                                            : Text(
                                                '${sale.quantity}',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary),
                                              ),
                                      ),
                                      SizedBox(
                                        width: 90,
                                        child: Text(
                                          '₹${sale.pricePerTicket.toStringAsFixed(2)}',
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 95,
                                        child: Text(
                                          '₹${sale.totalAmount.toStringAsFixed(2)}',
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppColors.success),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          sale.buyerName.isNotEmpty ? sale.buyerName : sale.agentName,
                                          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    // Bottom Sticky Pagination Toolbar (Zero Scroll Jitter)
                    Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        border: Border(top: BorderSide(color: AppColors.border)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.list_alt_rounded, size: 16, color: AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Text(
                                'Showing ${math.min(_displayedLimit, _filteredSales.length)} of ${_filteredSales.length} records ($_grandQty total tkts)',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          if (_displayedLimit < _filteredSales.length) ...[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  icon: const Icon(Icons.arrow_downward_rounded, size: 14),
                                  label: const Text('Load +250 More', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  onPressed: _loadMoreChunks,
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    side: const BorderSide(color: AppColors.primary),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  icon: const Icon(Icons.all_inclusive_rounded, size: 14),
                                  label: Text('Load All (${_filteredSales.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  onPressed: () {
                                    setState(() {
                                      _displayedLimit = _filteredSales.length;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.success.withAlpha(25),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.success.withAlpha(80)),
                              ),
                              child: const Text(
                                'All records loaded',
                                style: TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required int qty,
    required double amount,
    required Color color,
    required IconData icon,
    bool isHighlight = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isHighlight
              ? color.withValues(alpha: 0.12)
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isHighlight ? color : AppColors.border,
            width: isHighlight ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTypography.labelSm.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$qty Tkts',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '₹${amount.toStringAsFixed(0)}',
                        style: AppTypography.bodyMd.copyWith(
                          color: isHighlight ? color : AppColors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPdfExportOptionsModal({
    required String filePath,
    required String fileName,
    required Uint8List bytes,
    required String customerName,
    required int totalTickets,
    required double totalSales,
  }) {
    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: math.min(540.0, MediaQuery.of(dialogCtx).size.width * 0.94),
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 36,
                spreadRadius: 8,
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
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PDF Exported & Ready!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Saved automatically to: C:\\Lottery_Reports\\',
                          style: TextStyle(
                            color: AppColors.textSecondary.withValues(alpha: 0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 14),

              // File & Sales Summary Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_rounded, color: AppColors.primary, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              customerName,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$totalTickets Tkts • ₹${totalSales.toStringAsFixed(2)}',
                            style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                    if (_sortedSeriesList.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'Series Sold: ${_sortedSeriesList.map((s) => "Ser ${s.series} (${s.quantity} tkts)").join(" • ")}',
                          style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.insert_drive_file_outlined, color: AppColors.textSecondary, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 4 Action Buttons
              // 1. Open PDF
              _buildPdfActionCard(
                icon: Icons.open_in_new_rounded,
                iconColor: const Color(0xFF38BDF8),
                title: 'Open PDF File (Default Viewer)',
                subtitle: 'Directly open in Adobe Acrobat, Edge, or Chrome',
                btnLabel: 'OPEN PDF',
                btnColor: const Color(0xFF0284C7),
                onPressed: () {
                  BookingPdfService.instance.openPdfFile(filePath);
                },
              ),
              const SizedBox(height: 10),

              // 2. Share on WhatsApp
              _buildPdfActionCard(
                icon: Icons.chat_bubble_rounded,
                iconColor: const Color(0xFF22C55E),
                title: 'Share on WhatsApp',
                subtitle: 'Send sales summary & hisab breakdown to seller',
                btnLabel: 'SHARE WHATSAPP',
                btnColor: const Color(0xFF16A34A),
                btnTextColor: Colors.white,
                onPressed: () {
                  BookingPdfService.instance.shareOnWhatsApp(
                    filePath: filePath,
                    customerName: customerName,
                    totalTickets: totalTickets,
                    totalSales: totalSales,
                  );
                },
              ),
              const SizedBox(height: 10),

              // 3. Print / Layout Preview
              _buildPdfActionCard(
                icon: Icons.print_rounded,
                iconColor: const Color(0xFF818CF8),
                title: 'Print Preview & Setup',
                subtitle: 'Open Windows print dialog, layout, and paper settings',
                btnLabel: 'PRINT / PREVIEW',
                btnColor: const Color(0xFF4F46E5),
                onPressed: () {
                  BookingPdfService.instance.printPdfLayout(bytes, fileName);
                },
              ),
              const SizedBox(height: 10),

              // 4. Show in Explorer
              _buildPdfActionCard(
                icon: Icons.folder_open_rounded,
                iconColor: const Color(0xFFFBBF24),
                title: 'Show in Windows Folder',
                subtitle: 'Open C:\\Lottery_Reports\\ and highlight file',
                btnLabel: 'OPEN FOLDER',
                btnColor: const Color(0xFF374151),
                onPressed: () {
                  BookingPdfService.instance.showInExplorer(filePath);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPdfActionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String btnLabel,
    required Color btnColor,
    Color btnTextColor = Colors.white,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: btnColor,
              foregroundColor: btnTextColor,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 2,
            ),
            onPressed: onPressed,
            child: Text(
              btnLabel,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalSeriesSummary {
  final String series;
  int quantity;
  double rate;
  double totalAmount;

  _LocalSeriesSummary({
    required this.series,
    required this.quantity,
    required this.rate,
    required this.totalAmount,
  });
}
