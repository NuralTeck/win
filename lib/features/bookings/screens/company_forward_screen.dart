import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/glass_card.dart';
import '../viewmodels/ticket_sales_viewmodel.dart';
import '../../shared/models/ticket_sale_model.dart';

class CompanyForwardScreen extends ConsumerStatefulWidget {
  const CompanyForwardScreen({super.key});

  @override
  ConsumerState<CompanyForwardScreen> createState() => _CompanyForwardScreenState();
}

class _CompanyForwardScreenState extends ConsumerState<CompanyForwardScreen> {
  DateTime _selectedDate = DateTime.now();
  String _selectedShift = 'All';
  String _searchQuery = '';
  bool _filterByDate = true;

  Timer? _liveClockTimer;
  Timer? _autoFetchTimer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();

    // 1. Live Ticking Clock (Updates UI every 1 second)
    _liveClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });

    // 2. Automatic System Data Fetch from Cloud/Database (Every 3 seconds)
    _autoFetchTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        ref.read(ticketSalesViewModelProvider.notifier).loadSales();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ticketSalesViewModelProvider.notifier).loadSales();
    });
  }

  @override
  void dispose() {
    _liveClockTimer?.cancel();
    _autoFetchTimer?.cancel();
    super.dispose();
  }

  void _showSnackbar(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: bg,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Real-Time Clock & Cutoff Countdown Banner Widget ────────────────────
  Widget _buildRealtimeClockBanner() {
    final timeStr = DateFormat('HH:mm:ss').format(_currentTime);
    final dateStr = DateFormat('EEEE, dd MMMM yyyy').format(_currentTime);
    final totalMins = _currentTime.hour * 60 + _currentTime.minute;

    String currentDraw = '1:00 PM MORNING DRAW';
    String cutoffStr = '12:55 PM';
    int minsLeft = 775 - totalMins;
    Color drawColor = Colors.amber;

    if (totalMins >= 1195 || totalMins < 775) {
      currentDraw = '1:00 PM MORNING DRAW';
      cutoffStr = '12:55 PM';
      minsLeft = totalMins >= 1195 ? (1440 - totalMins + 775) : (775 - totalMins);
      drawColor = Colors.amber;
    } else if (totalMins < 1075) {
      currentDraw = '6:00 PM DAY DRAW';
      cutoffStr = '5:55 PM';
      minsLeft = 1075 - totalMins;
      drawColor = Colors.lightBlueAccent;
    } else {
      currentDraw = '8:00 PM NIGHT DRAW';
      cutoffStr = '7:55 PM';
      minsLeft = 1195 - totalMins;
      drawColor = Colors.purpleAccent;
    }

    final hoursLeft = minsLeft ~/ 60;
    final remainingMins = minsLeft % 60;
    final countdownStr = hoursLeft > 0 ? '${hoursLeft}h ${remainingMins}m remaining' : '${remainingMins}m remaining';

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: drawColor.withAlpha(40),
              shape: BoxShape.circle,
              border: Border.all(color: drawColor.withAlpha(120), width: 2),
            ),
            child: Icon(Icons.timer_outlined, color: drawColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'REAL-TIME SYSTEM CLOCK',
                      style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.greenAccent, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.fiber_manual_record, color: Colors.greenAccent, size: 8),
                          SizedBox(width: 4),
                          Text('AUTO LIVE SYNC', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontFamily: 'monospace'),
                ),
                Text(dateStr, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: drawColor.withAlpha(25),
              borderRadius: AppDecorations.radiusDefault,
              border: Border.all(color: drawColor.withAlpha(100)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('ACTIVE FORWARDING CYCLE', style: AppTypography.labelSm.copyWith(color: drawColor, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(currentDraw, style: TextStyle(color: drawColor, fontWeight: FontWeight.bold, fontSize: 15)),
                Text('Cut-off $cutoffStr ($countdownStr)', style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Ticket Bookings Export ───────────────────────────────────────────────
  Future<void> _exportToExcelCsv(List<TicketSaleModel> sales) async {
    if (sales.isEmpty) {
      _showSnackbar('No ticket bookings available to export!', AppColors.warning);
      return;
    }

    try {
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final String? filePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Today Bookings for Company Forwarding',
        fileName: 'company_forward_bookings_$dateStr.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (filePath == null) return;

      final buffer = StringBuffer();
      // Excel/CSV Header: Series, Ticket No, Seller Name, Draw Name, Booking Time
      buffer.writeln('Series,Ticket No,Seller Name,Draw Name,Booking Time');

      for (final s in sales) {
        final parts = s.ticketNumber.trim().split(' ');
        final ticketNo = parts.length > 1 ? parts.last : s.ticketNumber;
        final sellerName = s.agentName.isNotEmpty ? s.agentName : s.buyerName;
        final timeStr = DateFormat('HH:mm dd/MM/yyyy').format(s.saleDate);
        buffer.writeln('"${s.ticketSeries}","$ticketNo","$sellerName","${s.drawName}","$timeStr"');
      }

      final file = File(filePath);
      await file.writeAsString(buffer.toString());

      _showSnackbar('📊 Exported ${sales.length} tickets to Excel/CSV file at $filePath', AppColors.success);
    } catch (e) {
      _showSnackbar('Error exporting file: $e', AppColors.error);
    }
  }

  void _copyForwardText(List<TicketSaleModel> sales) {
    if (sales.isEmpty) {
      _showSnackbar('No ticket bookings available to copy!', AppColors.warning);
      return;
    }
    final buffer = StringBuffer();
    buffer.writeln('📋 COMPANY FORWARDING TICKET LIST (${sales.length} Tickets)');
    buffer.writeln('--------------------------------------------------');
    for (final s in sales) {
      final parts = s.ticketNumber.trim().split(' ');
      final ticketNo = parts.length > 1 ? parts.last : s.ticketNumber;
      final sellerName = s.agentName.isNotEmpty ? s.agentName : s.buyerName;
      buffer.writeln('${s.ticketSeries} $ticketNo | Seller: $sellerName | Draw: ${s.drawName}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    _showSnackbar('📋 Copied ${sales.length} tickets with Seller details to Clipboard!', AppColors.success);
  }

  @override
  Widget build(BuildContext context) {
    final allSales = ref.watch(ticketSalesViewModelProvider).sales;
    final selectedDateStr = DateFormat('dd/MM/yyyy').format(_selectedDate);

    bool matchesShift(String drawName, String selectedShift) {
      if (selectedShift == 'All') return true;
      final d = drawName.toLowerCase();
      final s = selectedShift.toLowerCase();

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

    // Filter Sales
    final filteredSales = allSales.where((s) {
      if (_filterByDate) {
        final sDateStr = DateFormat('dd/MM/yyyy').format(s.drawDate);
        if (sDateStr != selectedDateStr) return false;
      }
      if (_selectedShift != 'All') {
        if (!matchesShift(s.drawName, _selectedShift)) {
          return false;
        }
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchSeries = s.ticketSeries.toLowerCase().contains(q);
        final matchTicket = s.ticketNumber.toLowerCase().contains(q);
        final matchSeller = s.agentName.toLowerCase().contains(q);
        if (!matchSeries && !matchTicket && !matchSeller) return false;
      }
      return true;
    }).toList();

    final uniqueSeriesCount = filteredSales.map((e) => e.ticketSeries).toSet().length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Real-Time Clock & Cutoff Countdown Banner ────────────────────
          _buildRealtimeClockBanner(),
          const SizedBox(height: 20),

          // ── Navigation Header ───────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(30),
                      borderRadius: AppDecorations.radiusLg,
                      border: Border.all(color: Colors.green.withAlpha(80)),
                    ),
                    child: const Icon(
                      Icons.forward_to_inbox,
                      color: Colors.greenAccent,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TODAY BOOKINGS — COMPANY FORWARDING',
                        style: AppTypography.headlineLg.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Live auto-fetched seller bookings formatted for main company submission',
                        style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Filter Controls & Actions Bar ────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: AppDecorations.radiusLg,
              border: Border.all(color: AppColors.border),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Date Filter Chip
                    ChoiceChip(
                      label: Text(_filterByDate ? 'Date: $selectedDateStr' : 'All Dates', style: const TextStyle(fontWeight: FontWeight.bold)),
                      selected: _filterByDate,
                      onSelected: (val) => setState(() => _filterByDate = val),
                      selectedColor: AppColors.primaryContainer,
                    ),
                    if (_filterByDate)
                      IconButton(
                        icon: const Icon(Icons.calendar_month, color: AppColors.primary),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) setState(() => _selectedDate = picked);
                        },
                        tooltip: 'Select Date',
                      ),
                    const SizedBox(width: 8),

                    // Shift Filter Dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: AppDecorations.radiusDefault,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedShift,
                          items: [
                            'All',
                            'Morning',
                            'Day',
                            'Evening',
                          ]
                              .map((s) {
                                String label = s;
                                if (s == 'Morning') label = '1:00 PM (12:55 PM Cut-off)';
                                if (s == 'Day') label = '6:00 PM (5:55 PM Cut-off)';
                                if (s == 'Evening') label = '8:00 PM (7:55 PM Cut-off)';
                                return DropdownMenuItem(value: s, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)));
                              })
                              .toList(),
                          onChanged: (v) => setState(() => _selectedShift = v!),
                        ),
                      ),
                    ),
                  ],
                ),

                // Actions for Forwarding
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Search Input
                    SizedBox(
                      width: 200,
                      height: 38,
                      child: TextField(
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Search Series / Ticket...',
                          prefixIcon: const Icon(Icons.search, size: 16),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                          border: OutlineInputBorder(
                            borderRadius: AppDecorations.radiusDefault,
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),

                    ElevatedButton.icon(
                      onPressed: () async {
                        await ref.read(ticketSalesViewModelProvider.notifier).loadSales();
                        _showSnackbar('🔄 Fetched latest seller bookings from Mobile App!', AppColors.success);
                      },
                      icon: const Icon(Icons.cloud_download, color: Colors.white, size: 16),
                      label: const Text('FETCH FROM APP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                    ),

                    ElevatedButton.icon(
                      onPressed: () => _exportToExcelCsv(filteredSales),
                      icon: const Icon(Icons.description, color: Colors.white),
                      label: const Text('EXPORT TO EXCEL (.CSV)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                    ),

                    OutlinedButton.icon(
                      onPressed: () => _copyForwardText(filteredSales),
                      icon: const Icon(Icons.copy, size: 16, color: AppColors.primary),
                      label: const Text('Copy List Text', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.primary), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // ── 3 Daily Draw Cut-off Cards ─────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: '1:00 PM MORNING DRAW',
                  value: '${filteredSales.where((s) {
                    final d = s.drawName.toLowerCase();
                    return d.contains('1:00') || d.contains('1 pm') || d.contains('1pm') || d.contains('morning');
                  }).length} Tickets',
                  subtitle: 'Forwarding Cut-off: 12:55 PM',
                  icon: Icons.wb_sunny_outlined,
                  color: Colors.amber,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _KpiCard(
                  title: '6:00 PM DAY DRAW',
                  value: '${filteredSales.where((s) {
                    final d = s.drawName.toLowerCase();
                    return d.contains('6:00') || d.contains('6 pm') || d.contains('6pm') || d.contains('day');
                  }).length} Tickets',
                  subtitle: 'Forwarding Cut-off: 5:55 PM',
                  icon: Icons.wb_twilight,
                  color: Colors.lightBlueAccent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _KpiCard(
                  title: '8:00 PM NIGHT DRAW',
                  value: '${filteredSales.where((s) {
                    final d = s.drawName.toLowerCase();
                    return d.contains('8:00') || d.contains('8 pm') || d.contains('8pm') || d.contains('evening') || d.contains('night');
                  }).length} Tickets',
                  subtitle: 'Forwarding Cut-off: 7:55 PM',
                  icon: Icons.nights_stay_outlined,
                  color: Colors.purpleAccent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _KpiCard(
                  title: 'TOTAL TO FORWARD',
                  value: '${filteredSales.length} Tickets',
                  subtitle: 'Unique Series: $uniqueSeriesCount',
                  icon: Icons.check_circle_outline,
                  color: filteredSales.isNotEmpty ? Colors.greenAccent : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Minimal Table (Series & Ticket No ONLY)
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'COMPANY FORWARDING TICKET LIST',
                    style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  if (filteredSales.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(
                        child: Text(
                          'No tickets available for Company Forwarding for selected date/shift.',
                          style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: AppDecorations.radiusDefault,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(12),
                                topRight: Radius.circular(12),
                              ),
                              border: Border(bottom: BorderSide(color: AppColors.border)),
                            ),
                            child: Row(
                              children: [
                                Expanded(flex: 1, child: Text('SL', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold, color: AppColors.textSecondary))),
                                Expanded(flex: 3, child: Text('SELLER NAME', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold, color: AppColors.textSecondary))),
                                Expanded(flex: 3, child: Text('SERIES', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold, color: AppColors.textSecondary))),
                                Expanded(flex: 4, child: Text('TICKET NO', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold, color: AppColors.textSecondary))),
                                Expanded(flex: 3, child: Text('DRAW / SHIFT', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold, color: AppColors.textSecondary))),
                                Expanded(flex: 3, child: Text('TIME', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold, color: AppColors.textSecondary))),
                              ],
                            ),
                          ),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredSales.length,
                            separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                            itemBuilder: (context, idx) {
                              final s = filteredSales[idx];
                              final parts = s.ticketNumber.trim().split(' ');
                              final tNo = parts.length > 1 ? parts.last : s.ticketNumber;
                              final sellerName = s.agentName.isNotEmpty ? s.agentName : s.buyerName;

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                color: idx % 2 == 0 ? AppColors.surfaceContainerLow : AppColors.surfaceContainerHigh.withAlpha(40),
                                child: Row(
                                  children: [
                                    Expanded(flex: 1, child: Text('${idx + 1}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        sellerName,
                                        style: AppTypography.bodyMd.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amberAccent,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        s.ticketSeries,
                                        style: AppTypography.bodyMd.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        tNo,
                                        style: AppTypography.bodyMd.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.greenAccent,
                                          fontSize: 16,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                    ),
                                    Expanded(flex: 3, child: Text(s.drawName, style: const TextStyle(fontSize: 13))),
                                    Expanded(flex: 3, child: Text(DateFormat('HH:mm (dd/MM)').format(s.saleDate), style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
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
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: AppDecorations.radiusDefault,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1),
                  const SizedBox(height: 2),
                  Text(value, style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis, maxLines: 1),
                  Text(subtitle, style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary), overflow: TextOverflow.ellipsis, maxLines: 1),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
