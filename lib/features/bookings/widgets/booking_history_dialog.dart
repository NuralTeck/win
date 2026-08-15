import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  bool _isLoading = true;
  List<TicketSaleModel> _allDateSales = [];
  String _exportRange = 'Today'; // Options: 'Today', 'Weekly'
  String _selectedShiftFilter = 'All'; // 'All', 'Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'

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
      } else {
        // Weekly range: past 7 days up to selected date
        final Map<String, TicketSaleModel> uniqueMap = {};
        for (int i = 0; i < 7; i++) {
          final d = _selectedDate.subtract(Duration(days: i));
          final daySales = await DatabaseService.instance.getTicketSalesByDate(d);
          for (var s in daySales) {
            uniqueMap[s.id] = s;
          }
        }
        sales = uniqueMap.values.toList();
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

    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadSalesForDate();
    }
  }

  String _getShift(String drawName) {
    return BookingPdfService.instance.getDrawShift(drawName);
  }

  List<TicketSaleModel> get _filteredSales {
    if (_selectedShiftFilter == 'All') return _allDateSales;
    return _allDateSales
        .where((s) => _getShift(s.drawName) == _selectedShiftFilter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd-MM-yyyy (EEEE)');
    final dateStr = dateFormat.format(_selectedDate);

    // Calculate Shift-wise summary
    int count1PM = 0, count6PM = 0, count8PM = 0;
    double total1PM = 0, total6PM = 0, total8PM = 0;

    for (var sale in _allDateSales) {
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
            // ─── TOP HEADER BAR ──────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    color: AppColors.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Booking History & Shift Summary',
                      style: AppTypography.headlineMd.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Date-by-date ticket sales audit & PDF exporter',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Filter Range Options (PURELY Today and Weekly as requested)
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Today', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        selected: _exportRange == 'Today',
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: _exportRange == 'Today' ? Colors.white : AppColors.textSecondary),
                        onSelected: (sel) {
                          if (sel) {
                            setState(() {
                              _exportRange = 'Today';
                              _selectedDate = DateTime.now();
                            });
                            _loadSalesForDate();
                          }
                        },
                      ),
                      const SizedBox(width: 4),
                      ChoiceChip(
                        label: const Text('Weekly (7 Days)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        selected: _exportRange == 'Weekly',
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: _exportRange == 'Weekly' ? Colors.white : AppColors.textSecondary),
                        onSelected: (sel) {
                          if (sel) {
                            setState(() {
                              _exportRange = 'Weekly';
                            });
                            _loadSalesForDate();
                          }
                        },
                      ),
                      const SizedBox(width: 4),
                      ActionChip(
                        avatar: const Icon(Icons.calendar_month_rounded, size: 16, color: AppColors.primary),
                        label: Text(
                          DateFormat('dd/MM/yyyy').format(_selectedDate),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary),
                        ),
                        onPressed: _pickDate,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Export PDF Button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.info,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: Text('Export PDF ($_exportRange)', style: const TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _allDateSales.isEmpty
                      ? null
                      : () async {
                          await BookingPdfService.instance.exportAndPrintPdf(
                            date: _selectedDate,
                            sales: _filteredSales,
                            rangeTitle: _exportRange == 'Today' 
                                ? 'TODAY BOOKINGS & WINNING PRIZE REPORT' 
                                : 'WEEKLY BOOKINGS & WINNING PRIZE REPORT (PAST 7 DAYS)',
                          );
                        },
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
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
                  title: 'Total All Shifts',
                  qty: grandQty,
                  amount: grandAmt,
                  color: AppColors.success,
                  icon: Icons.account_balance_wallet_rounded,
                  isHighlight: true,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ─── SHIFT FILTER TABS ──────────────────────────────────────────
            Row(
              children: [
                Text(
                  'Filter Shift:',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 12),
                ...['All', 'Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'].map((shiftName) {
                  final isSelected = _selectedShiftFilter == shiftName;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(shiftName),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surfaceContainerLow,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.black : AppColors.textSecondary,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (val) {
                        setState(() => _selectedShiftFilter = shiftName);
                      },
                    ),
                  );
                }),
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

                            // RIGHT SIDE: BOOKINGS DETAILED TABLE
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.border),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: SingleChildScrollView(
                                  child: DataTable(
                                    columnSpacing: 16,
                                    headingRowColor: WidgetStateProperty.all(
                                      AppColors.surfaceContainerHigh,
                                    ),
                                    headingTextStyle: AppTypography.bodySm
                                        .copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                                    dataTextStyle: AppTypography.bodySm.copyWith(
                                      color: AppColors.textPrimary,
                                    ),
                                    columns: const [
                                      DataColumn(label: Text('#')),
                                      DataColumn(label: Text('Shift')),
                                      DataColumn(label: Text('Series')),
                                      DataColumn(label: Text('Ticket No.')),
                                      DataColumn(label: Text('Qty')),
                                      DataColumn(label: Text('Rate (₹)')),
                                      DataColumn(label: Text('Total (₹)')),
                                      DataColumn(label: Text('Seller/Buyer')),
                                    ],
                                    rows: List.generate(_filteredSales.length, (idx) {
                                      final sale = _filteredSales[idx];
                                      final shift = _getShift(sale.drawName);
                                      return DataRow(
                                        cells: [
                                          DataCell(Text('${idx + 1}')),
                                          DataCell(
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: shift.contains('1 PM')
                                                    ? Colors.amber.withValues(alpha: 0.2)
                                                    : shift.contains('6 PM')
                                                        ? Colors.orange.withValues(alpha: 0.2)
                                                        : Colors.purple.withValues(alpha: 0.2),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                shift,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: shift.contains('1 PM')
                                                      ? Colors.amber
                                                      : shift.contains('6 PM')
                                                          ? Colors.orangeAccent
                                                          : Colors.purpleAccent,
                                                ),
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              sale.ticketSeries,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          DataCell(Text(sale.ticketNumber)),
                                          DataCell(Text('${sale.quantity}')),
                                          DataCell(
                                            Text('₹${sale.pricePerTicket.toStringAsFixed(2)}'),
                                          ),
                                          DataCell(
                                            Text(
                                              '₹${sale.totalAmount.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                color: AppColors.success,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              sale.buyerName.isNotEmpty
                                                  ? sale.buyerName
                                                  : sale.agentName,
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                  ),
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
