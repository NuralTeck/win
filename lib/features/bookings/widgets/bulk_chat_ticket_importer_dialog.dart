import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../settings/viewmodels/series_price_viewmodel.dart';
import '../viewmodels/ticket_sales_viewmodel.dart';
import '../../shared/models/ticket_sale_model.dart';

class BulkParsedTicket {
  String series;
  String ticketNo;
  int quantity;
  double pricePerTicket;

  BulkParsedTicket({
    required this.series,
    required this.ticketNo,
    this.quantity = 1,
    this.pricePerTicket = 0.0,
  });

  double get totalAmount => pricePerTicket * quantity;
}

class BulkShiftGroup {
  String shiftName;
  DateTime drawDate;
  String buyerName;
  List<BulkParsedTicket> tickets;

  BulkShiftGroup({
    required this.shiftName,
    required this.drawDate,
    required this.buyerName,
    required this.tickets,
  });

  int get totalTickets => tickets.fold(0, (sum, t) => sum + t.quantity);
  double get totalAmount => tickets.fold(0.0, (sum, t) => sum + t.totalAmount);
}

class BulkChatTicketImporterDialog extends ConsumerStatefulWidget {
  final String initialShift;
  final DateTime initialDate;
  final String defaultSeller;

  const BulkChatTicketImporterDialog({
    super.key,
    this.initialShift = 'Dear 1 PM',
    required this.initialDate,
    this.defaultSeller = '',
  });

  @override
  ConsumerState<BulkChatTicketImporterDialog> createState() =>
      _BulkChatTicketImporterDialogState();
}

class _BulkChatTicketImporterDialogState
    extends ConsumerState<BulkChatTicketImporterDialog> {
  String _operationMode = 'auto';
  bool _enforceStrictTargetDate = false;

  String _targetShift = 'Dear 1 PM';
  DateTime _targetDate = DateTime.now();
  final TextEditingController _buyerCtrl = TextEditingController();

  final TextEditingController _chatInputCtrl = TextEditingController();
  final ScrollController _inputScrollCtrl = ScrollController();

  List<BulkShiftGroup> _parsedGroups = [];
  final Set<int> _selectedGroupIndices = {};

  bool _isParsing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _targetShift = widget.initialShift.isNotEmpty ? widget.initialShift : 'Dear 1 PM';
    _targetDate = widget.initialDate;
    _buyerCtrl.text = widget.defaultSeller.isNotEmpty ? widget.defaultSeller : 'Party';
  }

  @override
  void dispose() {
    _buyerCtrl.dispose();
    _chatInputCtrl.dispose();
    _inputScrollCtrl.dispose();
    super.dispose();
  }

  double _getPriceForSeries(String series) {
    final clean = series.replaceAll(RegExp(r'\D'), '');
    if (clean.isEmpty) return 27.0; // 12 Series standard fallback
    try {
      final seriesState = ref.read(seriesPriceViewModelProvider);
      double price = seriesState.getPriceForSeries(clean);
      if (price > 0) return price;
    } catch (_) {}
    final mult = double.tryParse(clean) ?? 12.0;
    return (mult > 0 ? mult : 12.0) * 2.25;
  }

  String _cleanSeries(String raw, {String fallback = '12'}) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty && digits.length <= 4) return digits;
    return digits.isNotEmpty ? digits.substring(0, 3) : fallback;
  }

  bool _isSameDay(DateTime d1, DateTime d2) {
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  DateTime? _parseCustomDate(String dStr) {
    try {
      final clean = dStr.replaceAll(RegExp(r'[^\d\/\.-]'), '');
      final parts = clean.split(RegExp(r'[\/\.-]'));
      if (parts.length >= 3) {
        int day = int.parse(parts[0]);
        int month = int.parse(parts[1]);
        int year = int.parse(parts[2]);
        if (year < 100) year += 2000;
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return null;
  }

  bool _isPureSeriesLine(String line) {
    final clean = line.replaceAll(RegExp(r'[^\w]'), '').trim();
    if (clean.isEmpty) return false;
    final digits = clean.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty && digits.length <= 3) {
      final val = int.tryParse(digits) ?? 0;
      return val > 0 && val <= 120;
    }
    return false;
  }

  List<String> _splitIntoWhatsAppMessages(String rawText) {
    final List<String> messages = [];
    final lines = rawText.split(RegExp(r'[\r\n]+'));
    StringBuffer currentMessage = StringBuffer();

    final waHeaderPattern = RegExp(
      r'^(?:\[\d{1,2}:\d{2}\s*(?:[aApP][mM])?,\s*\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4}\]|\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4},\s*[\d:]+\s*(?:[^\x00-\x7F]|\s)*(?:AM|PM|am|pm)?\s*-)\s*[^:]+:',
    );

    for (final line in lines) {
      if (waHeaderPattern.hasMatch(line.trim())) {
        if (currentMessage.isNotEmpty) {
          messages.add(currentMessage.toString().trim());
          currentMessage = StringBuffer();
        }
      }
      currentMessage.writeln(line);
    }

    if (currentMessage.isNotEmpty) {
      messages.add(currentMessage.toString().trim());
    }

    return messages.isNotEmpty ? messages : lines;
  }

  Future<void> _parseBulkChat() async {
    if (_isParsing) return;

    setState(() {
      _isParsing = true;
    });

    await Future.delayed(const Duration(milliseconds: 20));

    final rawText = _chatInputCtrl.text;
    if (rawText.trim().isEmpty) {
      setState(() {
        _parsedGroups = [];
        _selectedGroupIndices.clear();
        _isParsing = false;
      });
      return;
    }

    try {
      final Map<String, BulkShiftGroup> groupMap = {};
      final String userDefinedBuyer = _buyerCtrl.text.trim().isNotEmpty ? _buyerCtrl.text.trim() : 'Party';

      String currentShift = _targetShift;
      DateTime currentDate = _targetDate;
      bool isSessionActive = true;

      final messageBlocks = _splitIntoWhatsAppMessages(rawText);

      for (final msgBlock in messageBlocks) {
        final rawLines = msgBlock.split(RegExp(r'[\r\n]+'));
        final List<String> cleanLines = [];

        for (String rLine in rawLines) {
          String l = rLine.trim();
          if (l.isEmpty) continue;
          if (RegExp(r'^[-=_*#]{3,}$').hasMatch(l)) continue;

          // Strip WhatsApp Header
          final bracketHeader = RegExp(r'^\[\d{1,2}:\d{2}\s*(?:[aApP][mM])?,\s*\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4}\]\s*[^:]+:\s*(.*)$').firstMatch(l);
          if (bracketHeader != null) {
            l = bracketHeader.group(1)!.trim();
          } else {
            final stdHeader = RegExp(r'^\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4},\s*[\d:]+\s*(?:[^\x00-\x7F]|\s)*(?:AM|PM|am|pm)?\s*-\s*([^:]+):\s*(.*)$').firstMatch(l);
            if (stdHeader != null) {
              l = stdHeader.group(2)!.trim();
            }
          }

          if (l.isEmpty) continue;

          // Ignore noise lines & forwarded tags
          if (RegExp(r'^\s*(?:forwarded|this message was forwarded)\s*$', caseSensitive: false).hasMatch(l) ||
              l.contains('Messages and calls are end-to-end encrypted') ||
              l.contains('file attached') ||
              l.contains('<Media omitted>') ||
              l.contains('This message was deleted') ||
              l.contains('You deleted this message') ||
              l.contains('.pdf') ||
              l.contains('.jpg') ||
              l.contains('.webp') ||
              l.contains('.opus')) {
            continue;
          }

          cleanLines.add(l);
        }

        if (cleanLines.isEmpty) continue;

        // Session triggers
        final firstLine = cleanLines.first;
        final startMatch = RegExp(
          r'^\s*start\s+([168])\s*(?::\s*)?(?:pm|am|qm|gm)?\s+(\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4})',
          caseSensitive: false,
        ).firstMatch(firstLine);

        if (startMatch != null) {
          final sNum = startMatch.group(1);
          if (sNum == '1') currentShift = 'Dear 1 PM';
          if (sNum == '6') currentShift = 'Dear 6 PM';
          if (sNum == '8') currentShift = 'Dear 8 PM';

          final parsedD = _parseCustomDate(startMatch.group(2)!);
          if (parsedD != null) currentDate = parsedD;

          isSessionActive = true;
          cleanLines.removeAt(0);
        }

        if (cleanLines.any((l) => RegExp(r'^\s*end\s*$', caseSensitive: false).hasMatch(l))) {
          isSessionActive = false;
        }

        if (!isSessionActive && startMatch == null) continue;

        // Mama2 boundary trigger
        final boundaryMatch = RegExp(
          r'([168])\s*(?::\s*)?(?:pm|am|qm|gm)?\s*booking\s*(?:ab\s*)?jayega(?:\s+(\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4}))?',
          caseSensitive: false,
        ).firstMatch(firstLine);

        if (boundaryMatch != null) {
          if (_operationMode == 'auto') {
            final sNum = boundaryMatch.group(1);
            if (sNum == '1') currentShift = 'Dear 1 PM';
            if (sNum == '6') currentShift = 'Dear 6 PM';
            if (sNum == '8') currentShift = 'Dear 8 PM';

            final dateStr = boundaryMatch.group(2);
            if (dateStr != null) {
              final parsed = _parseCustomDate(dateStr);
              if (parsed != null) currentDate = parsed;
            }
          }
          cleanLines.removeAt(0);
        }

        final effectiveDate = _enforceStrictTargetDate ? _targetDate : currentDate;
        if (_enforceStrictTargetDate && !_isSameDay(currentDate, _targetDate)) {
          continue;
        }

        final effectiveShift = _operationMode == 'fixed' ? _targetShift : currentShift;
        final effectiveBuyer = userDefinedBuyer;

        // =========================================================================
        // HAR NAYE MESSAGE BLOCK ME STRICTLY RESET TO '12'
        // Pichhle message ki series bilkul nahi aayegi!
        // =========================================================================
        String messageScopedSeries = '12';

        // 1. Agar message ki shuruat me series likhi ho (e.g. "40" ya "6")
        if (cleanLines.isNotEmpty && _isPureSeriesLine(cleanLines.first)) {
          messageScopedSeries = _cleanSeries(cleanLines.first, fallback: '12');
          cleanLines.removeAt(0);
        }
        // 2. Agar message ke aakhiri line par series likhi ho (e.g. "12")
        else if (cleanLines.isNotEmpty && _isPureSeriesLine(cleanLines.last)) {
          messageScopedSeries = _cleanSeries(cleanLines.last, fallback: '12');
          cleanLines.removeLast();
        }

        final groupKey = '${DateFormat('yyyy-MM-dd').format(effectiveDate)}_${effectiveShift}_$effectiveBuyer';
        if (!groupMap.containsKey(groupKey)) {
          groupMap[groupKey] = BulkShiftGroup(
            shiftName: effectiveShift,
            drawDate: effectiveDate,
            buyerName: effectiveBuyer,
            tickets: [],
          );
        }
        final targetGroup = groupMap[groupKey]!;

        // Parse remaining lines in this message
        for (final line in cleanLines) {
          if (_isPureSeriesLine(line)) {
            messageScopedSeries = _cleanSeries(line, fallback: '12');
            continue;
          }

          // Har line parse hogi - agar line par prefix/suffix na ho to strictly messageScopedSeries hi lagegi
          final parsedTickets = _parseLineTickets(line, fallbackSeries: messageScopedSeries);
          if (parsedTickets.isNotEmpty) {
            for (final t in parsedTickets) {
              targetGroup.tickets.add(t);
            }
          }
        }
      }

      final resultList = groupMap.values.where((g) => g.tickets.isNotEmpty).toList();

      setState(() {
        _parsedGroups = resultList;
        _selectedGroupIndices.clear();
        for (int i = 0; i < resultList.length; i++) {
          _selectedGroupIndices.add(i);
        }
        _isParsing = false;
      });
    } catch (e) {
      setState(() {
        _isParsing = false;
      });
    }
  }

  List<BulkParsedTicket> _parseLineTickets(String rawLine, {String fallbackSeries = '12'}) {
    final List<BulkParsedTicket> result = [];
    final String defaultSeries = fallbackSeries.isNotEmpty ? fallbackSeries : '12';

    String line = rawLine.replaceAll(RegExp(r'\b(?:vijay|sanni\s*kumar|rustam\s*g|sk|ck|irfan|ajmal|laddu|updated|booking|bipin|ibran|series|sirij|forwarded)\b', caseSensitive: false), ' ');
    line = line.replaceAll(RegExp(r'\b\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4}\b'), ' ');
    line = line.replaceAll(RegExp(r'\b\d{1,2}\.\.\d{1,2}\.\.\d{2,4}\b'), ' ');
    line = line.replaceAll(RegExp(r'(?<=\s|^)[168]\s*(?::\s*00)?\s*(?:pm|am|qm|gm)(?=\s|$)', caseSensitive: false), ' ');
    line = line.trim();
    if (line.isEmpty) return result;

    // Pattern A: Comma range e.g. 40350,,59,,10go,, 6c
    final commaRangeMatch = RegExp(r'(\d{5})\s*,,+\s*(\d{1,3})\s*,,+.*?(?:([0-9]{1,3})c|c\s*([0-9]{1,3}))?', caseSensitive: false).firstMatch(line);
    if (commaRangeMatch != null) {
      final startTktStr = commaRangeMatch.group(1)!;
      final endPartStr = commaRangeMatch.group(2)!;
      final serStr = commaRangeMatch.group(3) ?? commaRangeMatch.group(4);
      final s = serStr != null ? _cleanSeries(serStr, fallback: defaultSeries) : defaultSeries;
      final startNum = int.tryParse(startTktStr) ?? 0;
      final prefix = startTktStr.substring(0, 5 - endPartStr.length);
      final endNum = int.tryParse(prefix + endPartStr) ?? startNum;

      if (endNum >= startNum && endNum - startNum <= 100) {
        final price = _getPriceForSeries(s);
        for (int n = startNum; n <= endNum; n++) {
          result.add(BulkParsedTicket(
            series: s,
            ticketNo: n.toString().padLeft(5, '0'),
            pricePerTicket: price,
          ));
        }
        return result;
      }
    }

    // Pattern B: Triplet Range e.g. 62759-83-25, 40280-289-10
    final tripletMatch = RegExp(r'(?:([0-9]{1,3})\s*[:=/]\s*)?(\d{5})\s*[-~to]+\s*(\d{1,5})\s*[-=x*,\s]+\s*(\d+)', caseSensitive: false).firstMatch(line);
    if (tripletMatch != null) {
      final seriesPart = tripletMatch.group(1);
      final startTkt = tripletMatch.group(2)!;
      final count = int.tryParse(tripletMatch.group(4)!) ?? 1;
      final s = seriesPart != null ? _cleanSeries(seriesPart, fallback: defaultSeries) : defaultSeries;
      final startNum = int.tryParse(startTkt) ?? 0;

      if (count > 0 && count <= 150) {
        final price = _getPriceForSeries(s);
        for (int i = 0; i < count; i++) {
          result.add(BulkParsedTicket(
            series: s,
            ticketNo: (startNum + i).toString().padLeft(5, '0'),
            pricePerTicket: price,
          ));
        }
        return result;
      }
    }

    // Pattern C: Hyphen range e.g. 50170-189
    final hyphenRangeMatch = RegExp(r'(?:([0-9]{1,3})\s*[:=/]\s*)?(\d{5})\s*[-~to]+\s*(\d{1,5})', caseSensitive: false).firstMatch(line);
    if (hyphenRangeMatch != null) {
      final seriesPart = hyphenRangeMatch.group(1);
      final startTkt = hyphenRangeMatch.group(2)!;
      final endPart = hyphenRangeMatch.group(3)!;
      final s = seriesPart != null ? _cleanSeries(seriesPart, fallback: defaultSeries) : defaultSeries;
      final startNum = int.tryParse(startTkt) ?? 0;
      final prefix = startTkt.substring(0, 5 - endPart.length);
      final fullEndNum = int.tryParse(prefix + endPart) ?? startNum;

      if (fullEndNum >= startNum && fullEndNum - startNum <= 150) {
        final price = _getPriceForSeries(s);
        for (int n = startNum; n <= fullEndNum; n++) {
          result.add(BulkParsedTicket(
            series: s,
            ticketNo: n.toString().padLeft(5, '0'),
            pricePerTicket: price,
          ));
        }
        return result;
      }
    }

    // Pattern D: Suffix format e.g. 36963 -40, 19576=18
    final suffixMatch = RegExp(r'^(\d{5})\s*[-:,\/=\s._~|*xX#@+]+\s*([0-9]{1,3}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,3})$').firstMatch(line);
    if (suffixMatch != null) {
      final tNo = suffixMatch.group(1)!;
      final s = _cleanSeries(suffixMatch.group(2)!, fallback: defaultSeries);
      final price = _getPriceForSeries(s);
      result.add(BulkParsedTicket(
        series: s,
        ticketNo: tNo,
        pricePerTicket: price,
      ));
      return result;
    }

    // Pattern E: Prefix format e.g. 24=62676, 12=36773, 24=54036
    final prefixMatch = RegExp(r'^(?:[\(\[]\s*([0-9]{1,3}[A-Za-z]?)\s*[\)\]]|([0-9]{1,3}[A-Za-z]?)\s*[:=/\-._~*#@+]+)\s*(\d{5})$').firstMatch(line);
    if (prefixMatch != null) {
      final rawS = prefixMatch.group(1) ?? prefixMatch.group(2) ?? defaultSeries;
      final s = _cleanSeries(rawS, fallback: defaultSeries);
      final tNo = prefixMatch.group(3)!;
      final price = _getPriceForSeries(s);
      result.add(BulkParsedTicket(
        series: s,
        ticketNo: tNo,
        pricePerTicket: price,
      ));
      return result;
    }

    // Pattern F: Direct 5-digit number without any series -> STRICT DEFAULT 12
    final matches5 = RegExp(r'\b\d{5}\b').allMatches(line);
    if (matches5.isNotEmpty) {
      final price = _getPriceForSeries(defaultSeries);
      for (final m in matches5) {
        result.add(BulkParsedTicket(
          series: defaultSeries,
          ticketNo: m.group(0)!,
          pricePerTicket: price,
        ));
      }
    }

    return result;
  }

  void _showEditTicketDialog(BulkShiftGroup group, BulkParsedTicket ticket, int ticketIndex) {
    final seriesCtrl = TextEditingController(text: ticket.series);
    final ticketCtrl = TextEditingController(text: ticket.ticketNo);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Edit Ticket', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: seriesCtrl,
              decoration: const InputDecoration(labelText: 'Series / Rate (Default: 12)', isDense: true),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ticketCtrl,
              decoration: const InputDecoration(labelText: '5-Digit Ticket Number', isDense: true),
              keyboardType: TextInputType.number,
              maxLength: 5,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                group.tickets.removeAt(ticketIndex);
                if (group.tickets.isEmpty) {
                  final idx = _parsedGroups.indexOf(group);
                  _parsedGroups.remove(group);
                  _selectedGroupIndices.remove(idx);
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            onPressed: () {
              final newSeries = _cleanSeries(seriesCtrl.text.trim(), fallback: '12');
              final newTkt = ticketCtrl.text.trim();
              if (newTkt.isNotEmpty) {
                setState(() {
                  ticket.series = newSeries.isNotEmpty ? newSeries : '12';
                  ticket.ticketNo = newTkt.padLeft(5, '0');
                  ticket.pricePerTicket = _getPriceForSeries(ticket.series);
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndBookAll() async {
    final selectedGroups = _selectedGroupIndices.map((i) => _parsedGroups[i]).toList();
    if (selectedGroups.isEmpty) return;

    final totalTicketsCount = selectedGroups.fold(0, (sum, g) => sum + g.totalTickets);
    final totalSalesValue = selectedGroups.fold(0.0, (sum, g) => sum + g.totalAmount);
    final partyName = _buyerCtrl.text.trim().isNotEmpty ? _buyerCtrl.text.trim() : 'Party';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.rocket_launch_rounded, color: AppColors.primary, size: 24),
            SizedBox(width: 10),
            Text('Confirm Selected Import', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Party "$partyName" ke liye ${selectedGroups.length} shift groups me $totalTicketsCount tickets save honge:',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Party Name:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(partyName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Tickets:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('$totalTicketsCount Tkts', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.greenAccent)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Gross Value:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('₹${totalSalesValue.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.amberAccent)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Confirm & Book $totalTicketsCount Tkts'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      final List<TicketSaleModel> allSales = [];
      int counter = 0;

      for (final group in selectedGroups) {
        final drawCode = group.shiftName.replaceAll(RegExp(r'\s+'), '-').toUpperCase();
        for (final t in group.tickets) {
          counter++;
          final uniqueSalt = math.Random().toString().substring(2, 8);
          allSales.add(TicketSaleModel(
            id: 'tkt_bulk_chat_${DateTime.now().millisecondsSinceEpoch}_${uniqueSalt}_${t.series}_${t.ticketNo}_$counter',
            receiptNumber: 'REC-${t.series}-${t.ticketNo}',
            buyerName: partyName,
            buyerPhone: 'WhatsApp Chat',
            agentCode: 'AG-BULK',
            agentName: partyName,
            drawCode: drawCode,
            drawName: group.shiftName,
            ticketSeries: t.series,
            ticketNumber: '${t.series} ${t.ticketNo}',
            quantity: t.quantity,
            pricePerTicket: t.pricePerTicket,
            totalAmount: t.totalAmount,
            commissionAmount: t.totalAmount * 0.05,
            status: TicketStatus.sold,
            paymentMode: PaymentMode.cash,
            saleDate: DateTime.now(),
            drawDate: group.drawDate,
          ));
        }
      }

      await ref.read(ticketSalesViewModelProvider.notifier).addTicketSalesBulk(allSales);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Booked $totalTicketsCount tickets for $partyName successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _pickChatFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv', 'log'],
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      String content = '';
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      }
      if (content.isNotEmpty) {
        _chatInputCtrl.text = content;
        _parseBulkChat();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedGroups = _selectedGroupIndices.map((i) => _parsedGroups[i]).toList();
    final selectedTicketsCount = selectedGroups.fold(0, (sum, g) => sum + g.totalTickets);
    final selectedTotalAmount = selectedGroups.fold(0.0, (sum, g) => sum + g.totalAmount);

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Container(
        width: 1100,
        height: 740,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.withAlpha(40),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.tealAccent.withAlpha(120)),
                  ),
                  child: const Icon(Icons.mark_chat_read_rounded, color: Colors.tealAccent, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Universal WhatsApp Chat & Card Importer',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      Text(
                        'Har message ki alag series check hoti hai, bina series wale tickets strictly 12 me jate hain',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Controls Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Strict Date Lock:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(width: 6),
                      Switch.adaptive(
                        value: _enforceStrictTargetDate,
                        activeTrackColor: Colors.teal.shade700,
                        onChanged: (val) {
                          setState(() => _enforceStrictTargetDate = val);
                          _parseBulkChat();
                        },
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _targetDate,
                        firstDate: DateTime(2025),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) {
                        setState(() => _targetDate = d);
                        _parseBulkChat();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amberAccent.withAlpha(120)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.amberAccent),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('dd/MM/yyyy').format(_targetDate),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amberAccent),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChoiceChip(
                        label: const Text('Auto AI Shift', style: TextStyle(fontSize: 11)),
                        selected: _operationMode == 'auto',
                        onSelected: (val) {
                          if (val && _operationMode != 'auto') {
                            setState(() => _operationMode = 'auto');
                            _parseBulkChat();
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Fixed Shift', style: TextStyle(fontSize: 11)),
                        selected: _operationMode == 'fixed',
                        onSelected: (val) {
                          if (val && _operationMode != 'fixed') {
                            setState(() => _operationMode = 'fixed');
                            _parseBulkChat();
                          }
                        },
                      ),
                    ],
                  ),
                  if (_operationMode == 'fixed')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.tealAccent),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _targetShift,
                          dropdownColor: AppColors.surfaceContainerHigh,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.tealAccent),
                          items: ['Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (v) {
                            if (v != null && v != _targetShift) {
                              setState(() => _targetShift = v);
                              _parseBulkChat();
                            }
                          },
                        ),
                      ),
                    ),

                  // Party Name Field
                  SizedBox(
                    width: 140,
                    height: 34,
                    child: TextField(
                      controller: _buyerCtrl,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                      decoration: InputDecoration(
                        labelText: 'Party / Buyer',
                        labelStyle: const TextStyle(fontSize: 11, color: Colors.white70),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        filled: true,
                        fillColor: AppColors.surfaceContainerLowest,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                      ),
                      onSubmitted: (_) => _parseBulkChat(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Workspace
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Paste WhatsApp Chat Text:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.amberAccent),
                                    tooltip: 'Reparse text',
                                    onPressed: _parseBulkChat,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.paste_rounded, size: 18, color: AppColors.primary),
                                    onPressed: () async {
                                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                                      if (data?.text != null) {
                                        _chatInputCtrl.text = data!.text!;
                                        _parseBulkChat();
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.folder_open_rounded, size: 18, color: Colors.cyanAccent),
                                    onPressed: _pickChatFile,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.clear_all_rounded, size: 18, color: Colors.redAccent),
                                    onPressed: () {
                                      _chatInputCtrl.clear();
                                      _parseBulkChat();
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Expanded(
                            child: TextField(
                              controller: _chatInputCtrl,
                              scrollController: _inputScrollCtrl,
                              maxLines: null,
                              expands: true,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.textPrimary),
                              decoration: const InputDecoration(
                                hintText: 'WhatsApp chat paste karein...',
                                border: InputBorder.none,
                              ),
                              onChanged: (_) => _parseBulkChat(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 6,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
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
                                  Text(
                                    'Parsed Cards (${_parsedGroups.length}):',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(width: 8),
                                  if (_parsedGroups.isNotEmpty)
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          if (_selectedGroupIndices.length == _parsedGroups.length) {
                                            _selectedGroupIndices.clear();
                                          } else {
                                            _selectedGroupIndices.clear();
                                            for (int i = 0; i < _parsedGroups.length; i++) {
                                              _selectedGroupIndices.add(i);
                                            }
                                          }
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceContainerHigh,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          _selectedGroupIndices.length == _parsedGroups.length ? 'Deselect All' : 'Select All',
                                          style: const TextStyle(fontSize: 10, color: Colors.tealAccent, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (_selectedGroupIndices.isNotEmpty)
                                Text(
                                  'Selected: $selectedTicketsCount Tkts • ₹${selectedTotalAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amberAccent),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_isParsing)
                            const Expanded(child: Center(child: CircularProgressIndicator()))
                          else if (_parsedGroups.isEmpty)
                            Expanded(
                              child: Center(
                                child: Text(
                                  _enforceStrictTargetDate
                                      ? 'Date ${DateFormat('dd/MM/yyyy').format(_targetDate)} ke liye koi ticket nahi mila.'
                                      : 'No tickets parsed yet.',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: ListView.separated(
                                itemCount: _parsedGroups.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 8),
                                itemBuilder: (ctx, index) {
                                  final group = _parsedGroups[index];
                                  final isSelected = _selectedGroupIndices.contains(index);
                                  return _buildGroupCard(group, index, isSelected);
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
            const SizedBox(height: 14),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.analytics_rounded, color: Colors.tealAccent, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Selected Cards: ${_selectedGroupIndices.length} / ${_parsedGroups.length} | Tickets: $selectedTicketsCount | Gross: ₹${selectedTotalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedGroupIndices.isEmpty ? Colors.grey : Colors.tealAccent.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    ),
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(_isSaving ? 'Booking...' : 'Book Selected ($selectedTicketsCount Tkts)'),
                    onPressed: (_isSaving || _selectedGroupIndices.isEmpty) ? null : _saveAndBookAll,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(BulkShiftGroup group, int groupIndex, bool isSelected) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isSelected ? Colors.tealAccent : AppColors.border, width: isSelected ? 1.5 : 1.0),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: isSelected,
              activeColor: Colors.tealAccent,
              checkColor: Colors.black,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedGroupIndices.add(groupIndex);
                  } else {
                    _selectedGroupIndices.remove(groupIndex);
                  }
                });
              },
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.teal.withAlpha(50),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.tealAccent),
              ),
              child: Text(group.shiftName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.tealAccent)),
            ),
          ],
        ),
        title: Text(
          '${DateFormat('dd/MM/yyyy').format(group.drawDate)} • ${group.buyerName}',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isSelected ? Colors.white : AppColors.textSecondary),
        ),
        trailing: Text(
          '${group.totalTickets} Tkts • ₹${group.totalAmount.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amberAccent),
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: AppColors.surfaceContainerLowest,
            constraints: const BoxConstraints(maxHeight: 240),
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: group.tickets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 3.2,
              ),
              itemBuilder: (ctx, ticketIndex) {
                final t = group.tickets[ticketIndex];
                return InkWell(
                  onTap: () => _showEditTicketDialog(group, t, ticketIndex),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            '${t.series} #${t.ticketNo}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.edit_outlined, size: 11, color: Colors.white54),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}