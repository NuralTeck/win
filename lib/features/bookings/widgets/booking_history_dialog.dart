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
  List<TicketSaleModel> _allDateSales = [];
  String _exportRange = 'Today'; // Options: 'Today', 'Weekly', 'Monthly', 'Custom'
  String _selectedShiftFilter = 'All'; // 'All', 'Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'
  String _selectedCustomerFilter = 'All'; // 'All' or specific customer/seller name
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _loadSalesForDate();
  }

  Future<void> _loadSalesForDate() async {
    setState(() => _isLoading = true);
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

      if (mounted) {
        setState(() {
          _allDateSales = sales;
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

    // 🔒 Check if Result Entry has been completed for this date/shift
    final hasResult = await _hasDeclaredResultForDateAndShift(_selectedDate, _selectedShiftFilter);
    if (!hasResult) {
      if (!mounted) return;
      _showResultPendingModal(context, _selectedShiftFilter, _selectedDate);
      return;
    }

    setState(() => _isExporting = true);

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

      // 1. Generate & Save PDF to C:\Lottery_Reports
      final res = await BookingPdfService.instance.savePdfToDisk(
        date: _selectedDate,
        sales: _filteredSales,
        customerName: _selectedCustomerFilter == 'All' ? null : _selectedCustomerFilter,
        rangeTitle: rangeTitle,
        isSummaryOnly: isSummaryOnly,
      );

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ PDF Export Note: $err'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  String _getShift(String drawName) {
    return BookingPdfService.instance.getDrawShift(drawName);
  }

  List<String> get _availableCustomers {
    final Set<String> customers = {'All'};
    for (var s in _allDateSales) {
      final name = s.buyerName.trim();
      if (name.isNotEmpty) {
        customers.add(name);
      }
    }
    final list = customers.toList();
    list.sort((a, b) {
      if (a == 'All') return -1;
      if (b == 'All') return 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return list;
  }

  List<TicketSaleModel> get _customerSales {
    if (_selectedCustomerFilter == 'All') return _allDateSales;
    return _allDateSales
        .where((s) => s.buyerName.trim().toLowerCase() == _selectedCustomerFilter.trim().toLowerCase())
        .toList();
  }

  List<TicketSaleModel> get _filteredSales {
    final list = _customerSales.where((s) {
      if (_selectedShiftFilter == 'All') return true;
      return _getShift(s.drawName) == _selectedShiftFilter;
    }).toList();

    // 🎯 Prioritize missing/empty series tickets at the VERY TOP
    list.sort((a, b) {
      final aMissing = a.ticketSeries == '?' || a.ticketSeries.trim().isEmpty || a.ticketSeries.toUpperCase() == 'MISSING' || a.ticketSeries.toUpperCase() == 'UNKNOWN' || a.ticketSeries == '—' || a.ticketSeries == '-' || a.ticketSeries.toLowerCase() == 'none';
      final bMissing = b.ticketSeries == '?' || b.ticketSeries.trim().isEmpty || b.ticketSeries.toUpperCase() == 'MISSING' || b.ticketSeries.toUpperCase() == 'UNKNOWN' || b.ticketSeries == '—' || b.ticketSeries == '-' || b.ticketSeries.toLowerCase() == 'none';

      if (aMissing && !bMissing) return -1; // A comes first (top)
      if (!aMissing && bMissing) return 1;  // B comes first (top)
      return b.saleDate.compareTo(a.saleDate); // Newer tickets first otherwise
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd-MM-yyyy (EEEE)');
    final dateStr = dateFormat.format(_selectedDate);

    // Calculate Shift-wise summary for selected customer
    int count1PM = 0, count6PM = 0, count8PM = 0;
    double total1PM = 0, total6PM = 0, total8PM = 0;

    for (var sale in _customerSales) {
      final shift = _getShift(sale.drawName);
      if (shift == 'Dear 1 PM') {
        count1PM += sale.quantity;
        total1PM += sale.totalAmount;
      } else if (shift == 'Dear 6 PM') {
        count6PM += sale.quantity;
        total6PM += sale.totalAmount;
      } else if (shift == 'Dear 8 PM') {
        count8PM += sale.quantity;
        total8PM += sale.totalAmount;
      }
    }

    int grandQty = count1PM + count6PM + count8PM;
    double grandAmt = total1PM + total6PM + total8PM;

    // Series Summary map
    final Map<String, _LocalSeriesSummary> seriesMap = {};
    for (var sale in _filteredSales) {
      final ser = sale.ticketSeries.toUpperCase();
      if (!seriesMap.containsKey(ser)) {
        seriesMap[ser] = _LocalSeriesSummary(
          series: ser,
          quantity: 0,
          rate: sale.pricePerTicket,
          totalAmount: 0.0,
        );
      }
      seriesMap[ser]!.quantity += sale.quantity;
      seriesMap[ser]!.totalAmount += sale.totalAmount;
    }
    final sortedSeriesList = seriesMap.values.toList()
      ..sort((a, b) => a.series.compareTo(b.series));

    return Dialog(
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Container(
        width: 1200,
        height: 750,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── TOP HEADER BAR (COMPACT & RESPONSIVE) ───────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
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
                // Filter Range Options (Today, Weekly, Monthly, Custom Range, Date)
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
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
                const SizedBox(width: 8),
                // 1. Export Full Detailed PDF (With Tickets)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.info,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: _isExporting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.picture_as_pdf_rounded, size: 15),
                  label: Text(
                    _isExporting ? 'Exporting...' : 'Full PDF',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                  onPressed: (_filteredSales.isEmpty || _isExporting)
                      ? null
                      : () => _handlePdfExport(
                            isSummaryOnly: false,
                            grandQty: grandQty,
                            grandAmt: grandAmt,
                          ),
                ),
                const SizedBox(width: 6),
                // 2. Export Summary-Only PDF (Without Ticket Numbers)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: _isExporting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.analytics_rounded, size: 15),
                  label: Text(
                    _isExporting ? 'Exporting...' : 'Summary PDF',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                  onPressed: (_filteredSales.isEmpty || _isExporting)
                      ? null
                      : () => _handlePdfExport(
                            isSummaryOnly: true,
                            grandQty: grandQty,
                            grandAmt: grandAmt,
                          ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Open Reports Folder in Windows Explorer',
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
            const SizedBox(height: 18),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 16),

            // ─── SHIFT SUMMARY STAT CARDS ────────────────────────────────────
            Row(
              children: [
                _buildStatCard(
                  title: '1 PM Shift (Morning)',
                  qty: count1PM,
                  amount: total1PM,
                  color: Colors.amber,
                  icon: Icons.wb_sunny_rounded,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  title: '6 PM Shift (Day)',
                  qty: count6PM,
                  amount: total6PM,
                  color: Colors.orangeAccent,
                  icon: Icons.wb_twilight_rounded,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  title: '8 PM Shift (Night)',
                  qty: count8PM,
                  amount: total8PM,
                  color: Colors.purpleAccent,
                  icon: Icons.nightlight_round,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  title: _selectedCustomerFilter == 'All' ? 'Total All Shifts' : 'Total ($_selectedCustomerFilter)',
                  qty: grandQty,
                  amount: grandAmt,
                  color: AppColors.success,
                  icon: Icons.account_balance_wallet_rounded,
                  isHighlight: true,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ─── FILTER CONTROLS: SHIFT TABS + CUSTOMER SELECTOR ─────────────
            Row(
              children: [
                Text(
                  'Shift:',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                        setState(() => _selectedShiftFilter = shiftName);
                      },
                    ),
                  );
                }),
                const SizedBox(width: 16),
                Container(
                  height: 24,
                  width: 1,
                  color: AppColors.border,
                ),
                const SizedBox(width: 16),
                // Customer Filter Dropdown
                Text(
                  'Customer:',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                          setState(() => _selectedCustomerFilter = val);
                        }
                      },
                      items: _availableCustomers.map((cust) {
                        final count = cust == 'All'
                            ? _allDateSales.length
                            : _allDateSales
                                .where((s) => s.buyerName.trim().toLowerCase() == cust.trim().toLowerCase())
                                .length;
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
                              Text(cust == 'All' ? 'All Customers ($count)' : '$cust ($count tkts)'),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Showing ${_filteredSales.length} records',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ─── BODY CONTENT: SERIES SUMMARY + SALES DATA TABLE ────────────
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
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
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // LEFT SIDE: SERIES SUMMARY BREAKDOWN
                            Container(
                              width: 320,
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
                                    child: ListView.separated(
                                      itemCount: sortedSeriesList.length,
                                      separatorBuilder: (_, _) =>
                                          const Divider(color: AppColors.border, height: 1),
                                      itemBuilder: (context, idx) {
                                        final item = sortedSeriesList[idx];
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
                                  const Divider(color: AppColors.border, height: 1),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Total Series: ${sortedSeriesList.length}',
                                        style: AppTypography.bodySm.copyWith(
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '₹${seriesMap.values.fold<double>(0, (sum, e) => sum + e.totalAmount).toStringAsFixed(2)}',
                                        style: AppTypography.bodyMd.copyWith(
                                          color: AppColors.success,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),

                            // RIGHT SIDE: BOOKINGS DETAILED TABLE (HIGH-PERFORMANCE VIRTUALIZED LIST)
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.border),
                                ),
                                clipBehavior: Clip.antiAlias,
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
                                    // Virtualized Scroll List (Only renders visible rows — Zero Hang / 60 FPS)
                                    Expanded(
                                      child: ListView.separated(
                                        itemCount: _filteredSales.length,
                                        separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.border),
                                        itemBuilder: (context, idx) {
                                          final sale = _filteredSales[idx];
                                          final shift = _getShift(sale.drawName);
                                          final isNoSeries = sale.ticketSeries == '?' ||
                                              sale.ticketSeries.isEmpty ||
                                              sale.ticketSeries == 'UNKNOWN' ||
                                              sale.ticketSeries == 'MISSING';

                                          return Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            color: idx.isEven ? Colors.transparent : AppColors.surfaceContainerHighest.withAlpha(25),
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
                                                  child: Text(
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
          width: 540,
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
