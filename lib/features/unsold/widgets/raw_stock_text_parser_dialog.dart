import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../bookings/services/gemini_scanner_service.dart';
import '../models/voucher_model.dart';
import '../models/unsold_model.dart';
import '../viewmodels/voucher_viewmodel.dart';
import '../viewmodels/unsold_viewmodel.dart';
import '../../../core/database/database_service.dart';
import 'ai_stock_scan_review_dialog.dart';

/// Real-time Syntax Highlighting Controller for Stock / Unsold / Voucher Parcha Text Input
class _StockSyntaxHighlightingController extends TextEditingController {
  _StockSyntaxHighlightingController();

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final rawText = text;
    if (rawText.isEmpty) {
      return TextSpan(style: style, text: '');
    }

    final List<TextSpan> spans = [];
    final lines = rawText.split('\n');
    String currentPrefix = '';

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isLastLine = i == lines.length - 1;
      final lineEnding = isLastLine ? '' : '\n';

      if (line.trim().isEmpty) {
        spans.add(TextSpan(text: line + lineEnding, style: style));
        continue;
      }

      final trimmed = line.trim();

      // 0. WhatsApp forwarded message header (Dim Grey)
      if (RegExp(r'^\s*(?:forwarded|forwarded message|fwd|forward|\*forwarded\*)\s*$', caseSensitive: false).hasMatch(trimmed)) {
        spans.add(TextSpan(
          text: line + lineEnding,
          style: (style ?? const TextStyle()).copyWith(
            color: Colors.grey.shade600,
            fontStyle: FontStyle.italic,
            fontSize: 11,
          ),
        ));
        continue;
      }

      // Check if line has a WhatsApp chat export / copy header
      final waHeaderMatch = RegExp(
        r'^(\s*\[[^\]]+\]\s*[^:\n]+:\s*|\s*\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4},?\s+\d{1,2}:\d{2}(?::\d{2})?\s*(?:am|pm|AM|PM)?\s*-\s*[^:\n]+:\s*)(.*)$',
        caseSensitive: false,
      ).firstMatch(line);

      String contentToHighlight = line;
      String? waHeaderPrefix;

      if (waHeaderMatch != null) {
        waHeaderPrefix = waHeaderMatch.group(1)!;
        contentToHighlight = waHeaderMatch.group(2)!;
      }

      final contentTrimmed = contentToHighlight.trim();

      // 1. Shift Tag (Cyan / Sky Highlight)
      if (RegExp(
        r'(?:=|\b)(?:dear\s*)?[168](?::00|\.00|\.)?\s*pm\b'
        r'|^\bmorning\b$|^\bday\b$|^\bnight\b$|^\bevening\b$'
        r'|^\s*dear\s*[168](?:\.00|:00|\.)?\s*(?:pm|baje)?\s*$'
        r'|^\s*[168](?:\.00|:00|\.)?\s*(?:pm|baje)\s*$',
        caseSensitive: false,
      ).hasMatch(contentTrimmed)) {
        final List<TextSpan> lineSpans = [];
        if (waHeaderPrefix != null) {
          lineSpans.add(TextSpan(text: waHeaderPrefix, style: (style ?? const TextStyle()).copyWith(color: const Color(0xFF94A3B8), fontSize: 11)));
        }
        lineSpans.add(TextSpan(
          text: contentToHighlight + lineEnding,
          style: (style ?? const TextStyle()).copyWith(
            color: const Color(0xFF38BDF8),
            backgroundColor: const Color(0xFF0369A1).withAlpha(90),
            fontWeight: FontWeight.bold,
          ),
        ));
        spans.add(TextSpan(children: lineSpans));
        continue;
      }

      // 2. Date Tag (Gold / Yellow Highlight)
      if (RegExp(r'\b(\d{1,2})[=\/\.-](\d{1,2})([=\/\.-]\d{2,4})?\b|\b(?:kal|tomorrow|aaj|today)\b', caseSensitive: false).hasMatch(contentTrimmed) &&
          !RegExp(r'\b\d{5}\b').hasMatch(contentTrimmed) && !contentTrimmed.contains('to') && !contentTrimmed.contains('-')) {
        final List<TextSpan> lineSpans = [];
        if (waHeaderPrefix != null) {
          lineSpans.add(TextSpan(text: waHeaderPrefix, style: (style ?? const TextStyle()).copyWith(color: const Color(0xFF94A3B8), fontSize: 11)));
        }
        lineSpans.add(TextSpan(
          text: contentToHighlight + lineEnding,
          style: (style ?? const TextStyle()).copyWith(
            color: const Color(0xFFFBBF24),
            backgroundColor: const Color(0xFF78350F).withAlpha(90),
            fontWeight: FontWeight.bold,
          ),
        ));
        spans.add(TextSpan(children: lineSpans));
        continue;
      }

      // 3. Standalone Series Tag (Purple / Magenta)
      final serMatch = RegExp(r'(?:^|[\s,;])[\(\[\{]?\s*(?:ser(?:ies)?)?\s*([0-9]{1,3}[A-Za-z]{0,4})\s*[\)\]\}]?(?:[\s:=]|$)', caseSensitive: false).firstMatch(contentTrimmed);
      if (serMatch != null && (contentTrimmed.startsWith('(') || contentTrimmed.startsWith('[') || contentTrimmed.toLowerCase().contains('ser') || contentTrimmed.length <= 6) && !RegExp(r'\b\d{5}\b').hasMatch(contentTrimmed)) {
        currentPrefix = '';
        final List<TextSpan> lineSpans = [];
        if (waHeaderPrefix != null) {
          lineSpans.add(TextSpan(text: waHeaderPrefix, style: (style ?? const TextStyle()).copyWith(color: const Color(0xFF94A3B8), fontSize: 11)));
        }
        lineSpans.add(TextSpan(
          text: contentToHighlight + lineEnding,
          style: (style ?? const TextStyle()).copyWith(
            color: const Color(0xFFC084FC),
            backgroundColor: const Color(0xFF6B21A8).withAlpha(90),
            fontWeight: FontWeight.bold,
          ),
        ));
        spans.add(TextSpan(children: lineSpans));
        continue;
      }

      // 4. Base 5-digit range e.g. 50271-274, 49750-753, 52150 to 950-999
      final baseMatch = RegExp(r'(?:^|[\s,;=])(?:([0-9]{1,3})\s*[:=]\s*)?(\d{2})(\d{3})\s*[-~to]+\s*(\d{1,5})', caseSensitive: false).firstMatch(contentTrimmed);
      if (baseMatch != null) {
        currentPrefix = baseMatch.group(2)!;
        final List<TextSpan> lineSpans = [];
        if (waHeaderPrefix != null) {
          lineSpans.add(TextSpan(text: waHeaderPrefix, style: (style ?? const TextStyle()).copyWith(color: const Color(0xFF94A3B8), fontSize: 11)));
        }
        lineSpans.add(TextSpan(
          text: contentToHighlight + lineEnding,
          style: (style ?? const TextStyle()).copyWith(
            color: const Color(0xFF4ADE80),
            backgroundColor: const Color(0xFF14532D).withAlpha(120),
            fontWeight: FontWeight.bold,
          ),
        ));
        spans.add(TextSpan(children: lineSpans));
        continue;
      }

      // 5. Subsequent 3-digit range e.g. 276-279, 481-483, 182-189
      final col3DigitRange = RegExp(r'(?:^|[\s,;])(\d{3})\s*[-~to]+\s*(\d{1,3})(?=[\s,;]|$)').firstMatch(contentTrimmed);
      if (col3DigitRange != null && currentPrefix.isNotEmpty) {
        final List<TextSpan> lineSpans = [];
        if (waHeaderPrefix != null) {
          lineSpans.add(TextSpan(text: waHeaderPrefix, style: (style ?? const TextStyle()).copyWith(color: const Color(0xFF94A3B8), fontSize: 11)));
        }
        lineSpans.add(TextSpan(
          text: contentToHighlight + lineEnding,
          style: (style ?? const TextStyle()).copyWith(
            color: const Color(0xFF34D399),
            backgroundColor: const Color(0xFF064E3B).withAlpha(120),
            fontWeight: FontWeight.bold,
          ),
        ));
        spans.add(TextSpan(children: lineSpans));
        continue;
      }

      // 6. Single 3-digit with dash e.g. 554-, 553-
      final single3Dash = RegExp(r'(?:^|[\s,;])(\d{3})\s*[-](?=[\s,;]|$)').firstMatch(contentTrimmed);
      if (single3Dash != null && currentPrefix.isNotEmpty) {
        final List<TextSpan> lineSpans = [];
        if (waHeaderPrefix != null) {
          lineSpans.add(TextSpan(text: waHeaderPrefix, style: (style ?? const TextStyle()).copyWith(color: const Color(0xFF94A3B8), fontSize: 11)));
        }
        lineSpans.add(TextSpan(
          text: contentToHighlight + lineEnding,
          style: (style ?? const TextStyle()).copyWith(
            color: const Color(0xFF34D399),
            backgroundColor: const Color(0xFF064E3B).withAlpha(120),
            fontWeight: FontWeight.bold,
          ),
        ));
        spans.add(TextSpan(children: lineSpans));
        continue;
      }

      // 6B. Trailing Series on 5-digit number e.g. 36963 -40, 52725-40, 85638*36, 85638=6
      final trailingSeriesMatch = RegExp(r'^(\d{5})\s*[-:,\/=\s._~|*xX#@+]+\s*([0-9]{1,3}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,3})$').firstMatch(contentTrimmed);
      if (trailingSeriesMatch != null) {
        currentPrefix = trailingSeriesMatch.group(1)!.substring(0, 2);
        final List<TextSpan> lineSpans = [];
        if (waHeaderPrefix != null) {
          lineSpans.add(TextSpan(text: waHeaderPrefix, style: (style ?? const TextStyle()).copyWith(color: const Color(0xFF94A3B8), fontSize: 11)));
        }
        lineSpans.add(TextSpan(
          text: contentToHighlight + lineEnding,
          style: (style ?? const TextStyle()).copyWith(
            color: const Color(0xFF4ADE80),
            backgroundColor: const Color(0xFF14532D).withAlpha(120),
            fontWeight: FontWeight.bold,
          ),
        ));
        spans.add(TextSpan(children: lineSpans));
        continue;
      }

      // 7. Direct 5-digit number or range e.g. 50271-50274, 50271
      final direct5s = RegExp(r'(?:([0-9]{1,3})\s*[:=]\s*)?(\d{5})(?:\s*[-~to]+\s*(\d{5}))?').firstMatch(contentTrimmed);
      if (direct5s != null) {
        currentPrefix = direct5s.group(2)!.substring(0, 2);
        final List<TextSpan> lineSpans = [];
        if (waHeaderPrefix != null) {
          lineSpans.add(TextSpan(text: waHeaderPrefix, style: (style ?? const TextStyle()).copyWith(color: const Color(0xFF94A3B8), fontSize: 11)));
        }
        lineSpans.add(TextSpan(
          text: contentToHighlight + lineEnding,
          style: (style ?? const TextStyle()).copyWith(
            color: const Color(0xFF4ADE80),
            backgroundColor: const Color(0xFF14532D).withAlpha(120),
            fontWeight: FontWeight.bold,
          ),
        ));
        spans.add(TextSpan(children: lineSpans));
        continue;
      }

      // 8. Unparsed / Unrecognized Line -> RED HIGHLIGHT WITH WAVY UNDERLINE
      spans.add(TextSpan(
        text: line + lineEnding,
        style: (style ?? const TextStyle()).copyWith(
          color: const Color(0xFFF87171),
          backgroundColor: const Color(0xFF7F1D1D).withAlpha(160),
          decoration: TextDecoration.underline,
          decorationColor: Colors.redAccent,
          decorationStyle: TextDecorationStyle.wavy,
          fontWeight: FontWeight.bold,
        ),
      ));
    }

    return TextSpan(children: spans);
  }
}

class RawStockTextParserDialog extends ConsumerStatefulWidget {
  final StockScanMode mode;
  final String activeShift;
  final DateTime activeDate;
  final String defaultParty;

  const RawStockTextParserDialog({
    super.key,
    required this.mode,
    required this.activeShift,
    required this.activeDate,
    required this.defaultParty,
  });

  @override
  ConsumerState<RawStockTextParserDialog> createState() => _RawStockTextParserDialogState();
}

class _RawStockTextParserDialogState extends ConsumerState<RawStockTextParserDialog> {
  final _StockSyntaxHighlightingController _rawTextCtrl = _StockSyntaxHighlightingController();
  final FocusNode _rawTextFocusNode = FocusNode();
  final ScrollController _rawTextScrollCtrl = ScrollController();
  final TextEditingController _partyCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  // Quick range entry row
  final TextEditingController _quickSeriesCtrl = TextEditingController(text: '12');
  final TextEditingController _quickFromCtrl = TextEditingController();
  final TextEditingController _quickToCtrl = TextEditingController();

  late String _selectedShift;
  late DateTime _selectedDate;
  List<GeminiScannedItem> _parsedItems = [];
  List<String> _unparsedLines = [];
  int _currentIssueIndex = 0;
  String _lastJumpedText = '';
  int _lastJumpedOccurrence = 0;
  int? _lastClickedGutterLine;

  bool _isSaving = false;
  String _selectedSeriesFilter = 'ALL';
  final String _selectedDateFilter = 'ALL';
  String _selectedShiftFilter = 'ALL';
  String _searchQuery = '';

  final Set<GeminiScannedItem> _selectedItems = {};
  int? _lastSelectedIdx;

  // 🏢 Dealer & Sub-Seller Network Hierarchy
  List<String> _availableDealers = [];
  Map<String, List<String>> _dealerToSellersMap = {};
  String? _selectedDealer;
  String? _selectedSubSeller;

  @override
  void initState() {
    super.initState();
    _selectedShift = widget.activeShift.isNotEmpty ? widget.activeShift : 'Dear 1 PM';
    _selectedDate = widget.activeDate;
    _partyCtrl.text = widget.defaultParty.isNotEmpty ? widget.defaultParty : 'Walk-in Party';

    _rawTextCtrl.addListener(_onTextChanged);
    _loadDealersAndSellers();
  }

  Future<void> _loadDealersAndSellers() async {
    final list = await DatabaseService.instance.getSellerCustomers();
    final dealers = <String>[];
    final map = <String, List<String>>{};

    for (final s in list) {
      if (s.isDealer) {
        if (!dealers.contains(s.name)) dealers.add(s.name);
        map.putIfAbsent(s.name, () => []);
      }
    }
    for (final s in list) {
      if (!s.isDealer && s.parentDealer != null && s.parentDealer!.isNotEmpty) {
        map.putIfAbsent(s.parentDealer!, () => []);
        if (!map[s.parentDealer!]!.contains(s.name)) {
          map[s.parentDealer!]!.add(s.name);
        }
      }
    }

    if (mounted) {
      setState(() {
        _availableDealers = dealers;
        _dealerToSellersMap = map;

        if (_partyCtrl.text.isNotEmpty) {
          final p = _partyCtrl.text.trim();
          if (dealers.contains(p)) {
            _selectedDealer = p;
            _selectedSubSeller = null;
          } else {
            for (final d in dealers) {
              if (map[d]?.contains(p) ?? false) {
                _selectedDealer = d;
                _selectedSubSeller = p;
                break;
              }
            }
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _rawTextCtrl.removeListener(_onTextChanged);
    _rawTextCtrl.dispose();
    _rawTextFocusNode.dispose();
    _rawTextScrollCtrl.dispose();
    _partyCtrl.dispose();
    _searchCtrl.dispose();
    _quickSeriesCtrl.dispose();
    _quickFromCtrl.dispose();
    _quickToCtrl.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _reparseText();
  }

  void _reparseText() {
    final text = _rawTextCtrl.text;
    if (text.trim().isEmpty) {
      setState(() {
        _parsedItems = [];
        _unparsedLines = [];
        _selectedItems.clear();
        _lastSelectedIdx = null;
      });
      return;
    }

    final party = _partyCtrl.text.trim().isNotEmpty ? _partyCtrl.text.trim() : widget.defaultParty;
    final parseResult = _parseRawStockText(
      text: text,
      defaultSeller: party,
      fallbackDate: DateFormat('yyyy-MM-dd').format(_selectedDate),
      mode: widget.mode,
    );

    setState(() {
      _parsedItems = GeminiScannerService.instance.condenseIntoRanges(parseResult.items);
      _unparsedLines = parseResult.unparsedLines;
      _recalculateAllPrices();
    });
  }

  ({List<GeminiScannedItem> items, List<String> unparsedLines}) _parseRawStockText({
    required String text,
    required String defaultSeller,
    required String fallbackDate,
    required StockScanMode mode,
  }) {
    final List<GeminiScannedItem> items = [];
    final List<String> unparsedLines = [];
    final lines = text.split(RegExp(r'\r?\n'));
    String currentSeries = '12';
    String currentPrefix = '';
    String currentPrefix3 = '';
    String? activeDate = fallbackDate;
    String? activeShift = _selectedShift;

    for (var rawLine in lines) {
      String l = rawLine.trim();
      if (l.isEmpty) continue;

      // 0. Skip forwarded headers
      if (RegExp(r'^\s*(?:forwarded|forwarded message|fwd|forward|\*forwarded\*)\s*$', caseSensitive: false).hasMatch(l)) {
        continue;
      }

      // Check for WhatsApp chat export prefix
      final waHeaderMatch = RegExp(
        r'^(\s*\[[^\]]+\]\s*[^:\n]+:\s*|\s*\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4},?\s+\d{1,2}:\d{2}(?::\d{2})?\s*(?:am|pm|AM|PM)?\s*-\s*[^:\n]+:\s*)(.*)$',
        caseSensitive: false,
      ).firstMatch(l);
      if (waHeaderMatch != null) {
        l = waHeaderMatch.group(2)!.trim();
        if (l.isEmpty) continue;
      }

      // 1. In-Message Shift IGNORED: Active shift remains strictly locked to _selectedShift!
      final detectedShift = GeminiScannerService.instance.detectShiftFromText(l);
      if (detectedShift != null) {
        continue; // Skip noise line
      }

      // 2. In-Message Date IGNORED: Active date remains strictly locked to selected date!
      final dateMatch = RegExp(r'\b(\d{1,2})[\/\-](\d{1,2})(?:[\/\-](\d{2,4}))?\b').firstMatch(l);
      final singleDateMatch = RegExp(r'^\s*(\d{1,2})[\/\-]\s*[:]?\s*$').firstMatch(l);
      if ((dateMatch != null && !l.contains('to') && !l.contains('-') && l.length <= 12) || singleDateMatch != null) {
        continue; // Skip noise line
      }

      // 3. Check for Series Header e.g. (12), (24), [36], SER 12, SERIES 20
      final serMatch = RegExp(r'(?:^|[\s,;])[\(\[\{]?\s*(?:ser(?:ies)?)?\s*([0-9]{1,3}[A-Za-z]{0,4})\s*[\)\]\}]?(?:[\s:=]|$)', caseSensitive: false).firstMatch(l);
      if (serMatch != null && (l.startsWith('(') || l.startsWith('[') || l.toLowerCase().contains('ser') || l.length <= 6) && !RegExp(r'\b\d{5}\b').hasMatch(l)) {
        final sDigits = serMatch.group(1)!.replaceAll(RegExp(r'\D'), '');
        if (sDigits.isNotEmpty && int.tryParse(sDigits) != null && int.parse(sDigits) <= 1000) {
          currentSeries = sDigits;
          currentPrefix = ''; // Reset prefix on new series
          currentPrefix3 = '';
          continue;
        }
      }

      // 4. Check for Full 5-Digit Range / Base Range e.g. 42370-71-2, 12345-55-10, 42980-1, 50271-274, 52150 to 950-999
      // Format: [series=]AAAAA-BB[-CC] where CC is written quantity (IGNORED)
      final baseMatch = RegExp(r'(?:^|[\s,;=])(?:([0-9]{1,3})\s*[:=]\s*)?(\d{2})(\d{3})\s*[-~to]+\s*(\d{1,5})(?:\s*[-~to]+\s*(\d+))?', caseSensitive: false).firstMatch(l);
      if (baseMatch != null) {
        final sOverride = baseMatch.group(1);
        final s = (sOverride != null && sOverride.isNotEmpty) ? sOverride : currentSeries;
        final prefix = baseMatch.group(2)!;
        final start3 = int.tryParse(baseMatch.group(3)!) ?? 0;
        final endRaw = baseMatch.group(4)!;
        final trailingQty = baseMatch.group(5);

        currentPrefix = prefix;
        currentPrefix3 = '$prefix${(start3 ~/ 100)}';

        // Check if single ticket with written qty e.g. 42980-1
        if (endRaw == '1' && trailingQty == null) {
          final fStr = '$prefix${start3.toString().padLeft(3, '0')}';
          items.add(GeminiScannedItem(
            series: s,
            ticketNo: fStr,
            fromTicket: fStr,
            toTicket: fStr,
            quantity: 1,
            amount: 0.0,
            sellerName: defaultSeller,
            targetDate: activeDate,
            drawShift: activeShift,
          ));
          continue;
        }

        int end3 = start3;
        if (endRaw.length == 5) {
          end3 = int.tryParse(endRaw.substring(2)) ?? start3;
        } else if (endRaw.length == 3) {
          end3 = int.tryParse(endRaw) ?? start3;
        } else if (endRaw.length == 2) {
          final hundreds = (start3 ~/ 100) * 100;
          end3 = hundreds + (int.tryParse(endRaw) ?? 0);
        } else if (endRaw.length == 1) {
          final tens = (start3 ~/ 10) * 10;
          end3 = tens + (int.tryParse(endRaw) ?? 0);
        }

        if (end3 >= start3 && end3 - start3 <= 1000) {
          final fromStr = '$prefix${start3.toString().padLeft(3, '0')}';
          final toStr = '$prefix${end3.toString().padLeft(3, '0')}';
          // ALWAYS calculate quantity from range! Trailing written quantity is IGNORED!
          final qty = (end3 - start3) + 1;

          items.add(GeminiScannedItem(
            series: s,
            ticketNo: qty > 1 ? '$fromStr - $toStr' : fromStr,
            fromTicket: fromStr,
            toTicket: toStr,
            quantity: qty,
            amount: 0.0,
            sellerName: defaultSeller,
            targetDate: activeDate,
            drawShift: activeShift,
          ));
          continue;
        }
      }

      // 5A. Subsequent 2-Digit Range under active 3-digit prefix e.g. 76-79-4, 73-75-3, 77-78-2, 65-67-3
      final col2DigitRange = RegExp(r'^\s*(\d{2})\s*[-~to]+\s*(\d{2})(?:\s*[-~to]+\s*(\d+))?\s*$').firstMatch(l);
      if (col2DigitRange != null && currentPrefix3.isNotEmpty) {
        final start2 = int.tryParse(col2DigitRange.group(1)!) ?? 0;
        final end2 = int.tryParse(col2DigitRange.group(2)!) ?? start2;
        if (end2 >= start2 && end2 - start2 <= 100) {
          final fromStr = '$currentPrefix3${start2.toString().padLeft(2, '0')}';
          final toStr = '$currentPrefix3${end2.toString().padLeft(2, '0')}';
          final qty = (end2 - start2) + 1;

          items.add(GeminiScannedItem(
            series: currentSeries,
            ticketNo: qty > 1 ? '$fromStr - $toStr' : fromStr,
            fromTicket: fromStr,
            toTicket: toStr,
            quantity: qty,
            amount: 0.0,
            sellerName: defaultSeller,
            targetDate: activeDate,
            drawShift: activeShift,
          ));
          continue;
        }
      }

      // 5B. Subsequent 2-Digit Single Ticket with written qty e.g. 74-1, 63-1, 69-1, 83-1, 99-1
      final col2DigitSingle = RegExp(r'^\s*(\d{2})\s*[-]\s*(\d{1,2})\s*$').firstMatch(l);
      if (col2DigitSingle != null && currentPrefix3.isNotEmpty) {
        final t2 = col2DigitSingle.group(1)!;
        final full5 = '$currentPrefix3$t2';
        items.add(GeminiScannedItem(
          series: currentSeries,
          ticketNo: full5,
          fromTicket: full5,
          toTicket: full5,
          quantity: 1,
          amount: 0.0,
          sellerName: defaultSeller,
          targetDate: activeDate,
          drawShift: activeShift,
        ));
        continue;
      }

      // 5C. Subsequent 3-Digit Range in Column with active prefix e.g. 276-279, 481-483, 182-189
      final col3DigitRange = RegExp(r'(?:^|[\s,;])(\d{3})\s*[-~to]+\s*(\d{1,3})(?=[\s,;]|$)').firstMatch(l);
      if (col3DigitRange != null && currentPrefix.isNotEmpty) {
        final start3 = int.tryParse(col3DigitRange.group(1)!) ?? 0;
        final endRaw = col3DigitRange.group(2)!;
        int end3 = start3;
        if (endRaw.length == 3) {
          end3 = int.tryParse(endRaw) ?? start3;
        } else if (endRaw.length == 2) {
          final hundreds = (start3 ~/ 100) * 100;
          end3 = hundreds + (int.tryParse(endRaw) ?? 0);
        } else if (endRaw.length == 1) {
          final tens = (start3 ~/ 10) * 10;
          end3 = tens + (int.tryParse(endRaw) ?? 0);
        }

        if (end3 >= start3 && end3 - start3 <= 500) {
          final fromStr = '$currentPrefix${start3.toString().padLeft(3, '0')}';
          final toStr = '$currentPrefix${end3.toString().padLeft(3, '0')}';
          final qty = (end3 - start3) + 1;

          items.add(GeminiScannedItem(
            series: currentSeries,
            ticketNo: qty > 1 ? '$fromStr - $toStr' : fromStr,
            fromTicket: fromStr,
            toTicket: toStr,
            quantity: qty,
            amount: 0.0,
            sellerName: defaultSeller,
            targetDate: activeDate,
            drawShift: activeShift,
          ));
          continue;
        }
      }

      // 6. Single 3-Digit ticket with dash under active column prefix e.g. 554-, 553-, 556-
      final single3Dash = RegExp(r'(?:^|[\s,;])(\d{3})\s*[-](?=[\s,;]|$)').firstMatch(l);
      if (single3Dash != null && currentPrefix.isNotEmpty) {
        final t3 = single3Dash.group(1)!;
        final full5 = '$currentPrefix$t3';
        items.add(GeminiScannedItem(
          series: currentSeries,
          ticketNo: full5,
          fromTicket: full5,
          toTicket: full5,
          quantity: 1,
          amount: 0.0,
          sellerName: defaultSeller,
          targetDate: activeDate,
          drawShift: activeShift,
        ));
        continue;
      }

      // 6B. Trailing Series on 5-digit number e.g. 36963 -40, 52725-40, 85638*36, 85638=6
      final trailingSeriesMatch = RegExp(
        r'(?:^|[\s,;])(\d{5})\s*[-:,\/=\s._~|*xX#@+]+\s*([0-9]{1,3}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,3})(?=[\s,;]|$)',
        caseSensitive: false,
      ).allMatches(l);

      if (trailingSeriesMatch.isNotEmpty) {
        for (final m in trailingSeriesMatch) {
          final fTkt = m.group(1)!;
          final rawS = m.group(2)!.replaceAll(RegExp(r'\D'), '');
          final s = rawS.isNotEmpty ? rawS : currentSeries;
          currentSeries = s;
          currentPrefix = fTkt.substring(0, 2);

          items.add(GeminiScannedItem(
            series: s,
            ticketNo: fTkt,
            fromTicket: fTkt,
            toTicket: fTkt,
            quantity: 1,
            amount: 0.0,
            sellerName: defaultSeller,
            targetDate: activeDate,
            drawShift: activeShift,
          ));
        }
        continue;
      }

      // 7. Direct 5-Digit numbers or 5-digit ranges e.g. 50271, 50271-50274, 12=50271
      final direct5s = RegExp(r'(?:([0-9]{1,3})\s*[:=]\s*)?(\d{5})(?:\s*[-~to]+\s*(\d{5}))?').allMatches(l);
      if (direct5s.isNotEmpty) {
        for (final m in direct5s) {
          final s = m.group(1) ?? currentSeries;
          final fTkt = m.group(2)!;
          final tTkt = m.group(3) ?? fTkt;
          final fNum = int.tryParse(fTkt) ?? 0;
          final tNum = int.tryParse(tTkt) ?? fNum;
          final qty = (tNum >= fNum) ? (tNum - fNum) + 1 : 1;

          currentPrefix = fTkt.substring(0, 2);

          items.add(GeminiScannedItem(
            series: s,
            ticketNo: qty > 1 ? '$fTkt - $tTkt' : fTkt,
            fromTicket: fTkt,
            toTicket: tTkt,
            quantity: qty,
            amount: 0.0,
            sellerName: defaultSeller,
            targetDate: activeDate,
            drawShift: activeShift,
          ));
        }
        continue;
      }

      // 8. Line could not be recognized / parsed -> add to unparsed list!
      unparsedLines.add(rawLine.trim());
    }

    return (items: items, unparsedLines: unparsedLines);
  }

  /// Jump cursor directly to the unparsed/error line in text box
  void _jumpToUnparsedLine(String targetLine) {
    final fullText = _rawTextCtrl.text;
    if (fullText.isEmpty) return;

    final lines = fullText.split('\n');
    final List<int> matchOffsets = [];
    final List<int> matchLengths = [];

    int currentOffset = 0;
    for (final line in lines) {
      if (line.trim() == targetLine.trim()) {
        matchOffsets.add(currentOffset);
        matchLengths.add(line.length);
      }
      currentOffset += line.length + 1;
    }

    if (matchOffsets.isEmpty) return;

    int idx = 0;
    if (_lastJumpedText == targetLine.trim()) {
      idx = (_lastJumpedOccurrence + 1) % matchOffsets.length;
    }
    _lastJumpedText = targetLine.trim();
    _lastJumpedOccurrence = idx;

    final start = matchOffsets[idx];
    final length = matchLengths[idx];

    _rawTextFocusNode.requestFocus();
    _rawTextCtrl.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + length,
    );
  }

  void _jumpToNextIssue() {
    if (_unparsedLines.isEmpty) return;
    _currentIssueIndex = (_currentIssueIndex + 1) % _unparsedLines.length;
    _jumpToUnparsedLine(_unparsedLines[_currentIssueIndex]);
  }

  /// Multi-Line Selection / Shift+Click Line Gutter action
  void _handleLineGutterClick(int clickedLineIdx) {
    final text = _rawTextCtrl.text;
    if (text.isEmpty) return;
    final lines = text.split('\n');
    if (clickedLineIdx < 0 || clickedLineIdx >= lines.length) return;

    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isShift && _lastClickedGutterLine != null) {
      final startLine = _lastClickedGutterLine! < clickedLineIdx ? _lastClickedGutterLine! : clickedLineIdx;
      final endLine = _lastClickedGutterLine! > clickedLineIdx ? _lastClickedGutterLine! : clickedLineIdx;

      int startOffset = 0;
      for (int i = 0; i < startLine; i++) {
        startOffset += lines[i].length + 1;
      }
      int endOffset = startOffset;
      for (int i = startLine; i <= endLine; i++) {
        endOffset += lines[i].length + (i == lines.length - 1 ? 0 : 1);
      }

      _rawTextFocusNode.requestFocus();
      _rawTextCtrl.selection = TextSelection(baseOffset: startOffset, extentOffset: endOffset);
    } else {
      int lineOffset = 0;
      for (int i = 0; i < clickedLineIdx; i++) {
        lineOffset += lines[i].length + 1;
      }
      _lastClickedGutterLine = clickedLineIdx;
      _rawTextFocusNode.requestFocus();
      _rawTextCtrl.selection = TextSelection(
        baseOffset: lineOffset,
        extentOffset: lineOffset + lines[clickedLineIdx].length,
      );
    }
    setState(() {});
  }

  /// Multi-Line Batch Tool: Prepend Series/Prefix to selected lines or all lines
  void _applyMultiLinePrefix(String prefix) {
    final text = _rawTextCtrl.text;
    if (text.isEmpty) return;

    final sel = _rawTextCtrl.selection;
    if (sel.isValid && !sel.isCollapsed) {
      final before = text.substring(0, sel.start);
      final selectedText = text.substring(sel.start, sel.end);
      final after = text.substring(sel.end);

      final modifiedLines = selectedText.split('\n').map((l) {
        if (l.trim().isEmpty) return l;
        return '$prefix$l';
      }).join('\n');

      _rawTextCtrl.text = '$before$modifiedLines$after';
      _rawTextCtrl.selection = TextSelection(
        baseOffset: sel.start,
        extentOffset: sel.start + modifiedLines.length,
      );
    } else {
      // Prepend to all non-empty lines
      final modified = text.split('\n').map((l) {
        if (l.trim().isEmpty) return l;
        return '$prefix$l';
      }).join('\n');
      _rawTextCtrl.text = modified;
    }
    _reparseText();
  }

  /// Multi-Line Batch Tool: Append suffix to selected lines
  void _applyMultiLineSuffix(String suffix) {
    final text = _rawTextCtrl.text;
    if (text.isEmpty) return;

    final sel = _rawTextCtrl.selection;
    if (sel.isValid && !sel.isCollapsed) {
      final before = text.substring(0, sel.start);
      final selectedText = text.substring(sel.start, sel.end);
      final after = text.substring(sel.end);

      final modifiedLines = selectedText.split('\n').map((l) {
        if (l.trim().isEmpty) return l;
        return '$l$suffix';
      }).join('\n');

      _rawTextCtrl.text = '$before$modifiedLines$after';
      _rawTextCtrl.selection = TextSelection(
        baseOffset: sel.start,
        extentOffset: sel.start + modifiedLines.length,
      );
    } else {
      final modified = text.split('\n').map((l) {
        if (l.trim().isEmpty) return l;
        return '$l$suffix';
      }).join('\n');
      _rawTextCtrl.text = modified;
    }
    _reparseText();
  }

  /// Insert Quick Range into text box
  void _insertQuickRange() {
    final s = _quickSeriesCtrl.text.trim();
    final f = _quickFromCtrl.text.trim();
    final t = _quickToCtrl.text.trim();

    if (f.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please enter a ticket number in From box'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    String lineToInsert;
    if (t.isNotEmpty) {
      lineToInsert = '${s.isNotEmpty ? '($s) ' : ''}$f-$t';
    } else {
      lineToInsert = '${s.isNotEmpty ? '($s) ' : ''}$f';
    }

    final currentText = _rawTextCtrl.text;
    final newText = currentText.isEmpty ? lineToInsert : '$currentText\n$lineToInsert';
    _rawTextCtrl.text = newText;
    _quickFromCtrl.clear();
    _quickToCtrl.clear();
    _reparseText();
  }

  void _recalculateAllPrices() {
    for (final item in _parsedItems) {
      final rate = _getPriceForSeries(item.series);
      item.amount = rate * (item.quantity > 0 ? item.quantity : 1);
    }
  }

  double _getPriceForSeries(String series) {
    switch (series.trim()) {
      case '12': return 4.50;
      case '20': return 7.50;
      case '24': return 9.00;
      case '36': return 13.50;
      case '40': return 15.00;
      case '50': return 18.75;
      case '60': return 22.50;
      case '84': return 31.50;
      case '100': return 37.50;
      default: return 4.50;
    }
  }

  List<GeminiScannedItem> get _displayedItems {
    var filtered = _parsedItems;
    if (_selectedSeriesFilter != 'ALL') {
      filtered = filtered.where((it) => it.series == _selectedSeriesFilter).toList();
    }
    if (_selectedDateFilter != 'ALL') {
      filtered = filtered.where((it) => it.targetDate == _selectedDateFilter).toList();
    }
    if (_selectedShiftFilter != 'ALL') {
      filtered = filtered.where((it) {
        final sh = (it.drawShift != null && it.drawShift!.isNotEmpty) ? it.drawShift! : _selectedShift;
        return sh == _selectedShiftFilter;
      }).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((it) =>
          it.ticketNo.toLowerCase().contains(q) ||
          it.series.toLowerCase().contains(q) ||
          (it.targetDate != null && it.targetDate!.contains(q))).toList();
    }
    return filtered;
  }

  int get _totalTickets => _parsedItems.fold(0, (sum, it) => sum + it.quantity);
  double get _totalAmount => _parsedItems.fold(0.0, (sum, it) => sum + it.amount);

  Set<String> get _availableSeriesList {
    final s = <String>{};
    for (final it in _parsedItems) {
      if (it.series.isNotEmpty) s.add(it.series);
    }
    return s;
  }

  List<String> get _availableShiftsList {
    final s = <String>{};
    for (final it in _parsedItems) {
      final sh = (it.drawShift != null && it.drawShift!.isNotEmpty) ? it.drawShift! : _selectedShift;
      s.add(sh);
    }
    final list = s.toList();
    list.sort((a, b) => a.compareTo(b));
    return list;
  }

  void _handleRowTap(int idx, GeminiScannedItem item) {
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    setState(() {
      if (isShift && _lastSelectedIdx != null) {
        final displayed = _displayedItems;
        final start = _lastSelectedIdx! < idx ? _lastSelectedIdx! : idx;
        final end = _lastSelectedIdx! > idx ? _lastSelectedIdx! : idx;
        for (int i = start; i <= end && i < displayed.length; i++) {
          _selectedItems.add(displayed[i]);
        }
      } else {
        if (_selectedItems.contains(item)) {
          _selectedItems.remove(item);
        } else {
          _selectedItems.add(item);
        }
        _lastSelectedIdx = idx;
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      final displayed = _displayedItems;
      if (_selectedItems.containsAll(displayed) && _selectedItems.isNotEmpty) {
        _selectedItems.removeAll(displayed);
      } else {
        _selectedItems.addAll(displayed);
      }
    });
  }

  void _applySeriesToSelected(String series) {
    if (_selectedItems.isEmpty) return;
    final clean = series.trim().toUpperCase();
    if (clean.isEmpty) return;
    setState(() {
      for (final it in _selectedItems) {
        it.series = clean;
      }
      _recalculateAllPrices();
    });
  }

  Future<void> _applyDateToSelected() async {
    if (_selectedItems.isEmpty) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: _selectedDate.subtract(const Duration(days: 30)),
      lastDate: _selectedDate.add(const Duration(days: 30)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF3B82F6),
            surface: Color(0xFF1E293B),
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFF0F172A),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final formatted = DateFormat('yyyy-MM-dd').format(picked);
      setState(() {
        for (final it in _selectedItems) {
          it.targetDate = formatted;
        }
      });
    }
  }

  void _deleteSelectedItems() {
    if (_selectedItems.isEmpty) return;
    setState(() {
      _parsedItems.removeWhere((it) => _selectedItems.contains(it));
      _selectedItems.clear();
      _lastSelectedIdx = null;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      _rawTextCtrl.text = data.text!;
      _reparseText();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📋 Pasted text from Clipboard and parsed!'),
            backgroundColor: Color(0xFF166534),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _exportScannedEntries() async {
    if (_parsedItems.isEmpty) return;
    try {
      final isVoucher = widget.mode == StockScanMode.voucher;
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final defaultFileName = isVoucher ? 'voucher_paste_$dateStr.csv' : 'unsold_paste_$dateStr.csv';
      final partyName = _partyCtrl.text.trim().isNotEmpty ? _partyCtrl.text.trim() : widget.defaultParty;

      String? filePath = await FilePicker.platform.saveFile(
        dialogTitle: isVoucher ? 'Export Parsed Vouchers CSV' : 'Export Parsed Unsold CSV',
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
      buffer.writeln('No,Date,Party/Seller,Series,Ticket Range,From Ticket,To Ticket,Quantity,Amount (Rs)');

      for (int i = 0; i < _parsedItems.length; i++) {
        final it = _parsedItems[i];
        final tDate = it.targetDate ?? DateFormat('yyyy-MM-dd').format(_selectedDate);
        buffer.writeln(
          '${i + 1},"$tDate","$partyName","${it.series}","${it.ticketNo}","${it.fromTicket}","${it.toTicket}",${it.quantity},${it.amount.toStringAsFixed(2)}',
        );
      }

      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      await Clipboard.setData(ClipboardData(text: buffer.toString()));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📊 Exported ${_parsedItems.length} records to: $filePath (Copied to Clipboard)'),
            backgroundColor: const Color(0xFF166534),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  String _sanitizeTargetDate(String? rawDate, String fallbackDate) {
    if (rawDate == null || rawDate.trim().isEmpty) return fallbackDate;
    final clean = rawDate.trim().replaceAll(RegExp(r'[^\d\/\-]'), '');
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(clean)) return clean;
    final dmy = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$').firstMatch(clean);
    if (dmy != null) {
      return '${dmy.group(3)}-${dmy.group(2)!.padLeft(2, '0')}-${dmy.group(1)!.padLeft(2, '0')}';
    }
    final dm = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-]?$').firstMatch(clean);
    if (dm != null) {
      final now = DateTime.now();
      return '${now.year}-${dm.group(2)!.padLeft(2, '0')}-${dm.group(1)!.padLeft(2, '0')}';
    }
    final dOnly = RegExp(r'^(\d{1,2})[\/\-]?$').firstMatch(clean);
    if (dOnly != null) {
      final d = int.tryParse(dOnly.group(1)!);
      if (d != null && d >= 1 && d <= 31) {
        final now = DateTime.now();
        return '${now.year}-${now.month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      }
    }
    return fallbackDate;
  }

  Future<void> _saveAllParsedEntries() async {
    if (_parsedItems.isEmpty) return;

    setState(() => _isSaving = true);
    final partyName = _partyCtrl.text.trim().isNotEmpty ? _partyCtrl.text.trim() : widget.defaultParty;
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    try {
      if (widget.mode == StockScanMode.voucher) {
        final List<VoucherModel> vouchersToSave = [];
        for (int i = 0; i < _parsedItems.length; i++) {
          final it = _parsedItems[i];
          final voucherNo = 'VOUCH-${DateFormat('HHmmss').format(now)}-$i';
          final rate = it.amount / (it.quantity > 0 ? it.quantity : 1);
          final fTkt = it.fromTicket.isNotEmpty ? it.fromTicket : (it.ticketNo.contains('-') ? it.ticketNo.split('-').first.trim() : it.ticketNo);
          final tTkt = it.toTicket.isNotEmpty ? it.toTicket : (it.ticketNo.contains('-') ? it.ticketNo.split('-').last.trim() : it.ticketNo);
          final entryDate = _sanitizeTargetDate(it.targetDate, dateStr);

          final itemShift = (it.drawShift != null && it.drawShift!.isNotEmpty) ? it.drawShift! : _selectedShift;
          vouchersToSave.add(
            VoucherModel(
              id: 'vouch_${now.microsecondsSinceEpoch}_$i',
              voucherNo: voucherNo,
              date: entryDate,
              drawShift: itemShift,
              partyName: partyName,
              series: it.series.isNotEmpty ? it.series : '12',
              fromTicket: fTkt,
              toTicket: tTkt,
              totalQty: it.quantity > 0 ? it.quantity : 1,
              pricePerTicket: rate,
              totalAmount: it.amount,
              createdAt: now,
            ),
          );
        }
        await ref.read(voucherViewModelProvider.notifier).addVouchersBatch(vouchersToSave);
      } else {
        final List<UnsoldModel> unsoldToSave = [];
        for (int i = 0; i < _parsedItems.length; i++) {
          final it = _parsedItems[i];
          final returnNo = 'RET-${DateFormat('HHmmss').format(now)}-$i';
          final rate = it.amount / (it.quantity > 0 ? it.quantity : 1);
          final fTkt = it.fromTicket.isNotEmpty ? it.fromTicket : (it.ticketNo.contains('-') ? it.ticketNo.split('-').first.trim() : it.ticketNo);
          final tTkt = it.toTicket.isNotEmpty ? it.toTicket : (it.ticketNo.contains('-') ? it.ticketNo.split('-').last.trim() : it.ticketNo);
          final entryDate = _sanitizeTargetDate(it.targetDate, dateStr);
          final itemShift = (it.drawShift != null && it.drawShift!.isNotEmpty) ? it.drawShift! : _selectedShift;

          unsoldToSave.add(
            UnsoldModel(
              id: 'unsold_${now.microsecondsSinceEpoch}_$i',
              returnNo: returnNo,
              date: entryDate,
              drawShift: itemShift,
              partyName: partyName,
              series: it.series.isNotEmpty ? it.series : '12',
              fromTicket: fTkt,
              toTicket: tTkt,
              totalQty: it.quantity > 0 ? it.quantity : 1,
              pricePerTicket: rate,
              totalAmount: it.amount,
              createdAt: now,
            ),
          );
        }
        await ref.read(unsoldViewModelProvider.notifier).addUnsoldBatch(unsoldToSave);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error saving entries: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Widget _statPill(String value, String label, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textCol.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: textCol)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 9.5, color: textCol.withAlpha(180))),
        ],
      ),
    );
  }

  void _autoFixMalformedRanges() {
    final targetList = _selectedItems.isNotEmpty ? _selectedItems.toList() : _parsedItems;
    int fixedCount = 0;
    setState(() {
      final List<GeminiScannedItem> newSplitItems = [];
      for (final it in targetList) {
        final parts = it.ticketNo.split('-');
        if (parts.length == 2) {
          final fStr = parts[0].trim();
          final tStr = parts[1].trim();
          if (tStr.length == 7 && fStr.length == 5) {
            final prefix1 = fStr.substring(0, 2);
            final prefix2 = tStr.substring(2, 4);
            final last3 = tStr.substring(4);

            final newTo1 = '$prefix1$last3';
            it.ticketNo = '$fStr - $newTo1';
            it.fromTicket = fStr;
            it.toTicket = newTo1;
            final fNum = int.tryParse(fStr) ?? 0;
            final tNum = int.tryParse(newTo1) ?? fNum;
            it.quantity = (tNum >= fNum) ? (tNum - fNum) + 1 : 50;
            fixedCount++;

            if (int.tryParse(prefix2) != null) {
              final start3 = fStr.substring(2);
              final newFrom2 = '$prefix2$start3';
              final newTo2 = '$prefix2$last3';
              final clone = GeminiScannedItem(
                series: it.series,
                ticketNo: '$newFrom2 - $newTo2',
                fromTicket: newFrom2,
                toTicket: newTo2,
                quantity: it.quantity,
                amount: it.amount,
                sellerName: it.sellerName,
                targetDate: it.targetDate,
                drawShift: it.drawShift,
              );
              newSplitItems.add(clone);
            }
          } else if (tStr.length > 5 && fStr.length == 5) {
            final prefix = fStr.substring(0, 2);
            final last3 = tStr.substring(tStr.length - 3);
            final newTo = '$prefix$last3';
            it.ticketNo = '$fStr - $newTo';
            it.fromTicket = fStr;
            it.toTicket = newTo;
            final fNum = int.tryParse(fStr) ?? 0;
            final tNum = int.tryParse(newTo) ?? fNum;
            it.quantity = (tNum >= fNum) ? (tNum - fNum) + 1 : 1;
            fixedCount++;
          }
        }
      }
      if (newSplitItems.isNotEmpty) {
        _parsedItems.addAll(newSplitItems);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✂️ Auto-fixed $fixedCount ranges to valid 50-ticket ranges!'),
        backgroundColor: const Color(0xFF166534),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildReviewBulkActionBar() {
    if (_selectedItems.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B4B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigoAccent.withAlpha(180), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.indigoAccent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_selectedItems.length} Selected (Shift+Click)',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
            ),
          ),
          const SizedBox(width: 8),
          const Text('Set:', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          ...['12', '20', '24', '36', '40', '60'].map((s) => Padding(
            padding: const EdgeInsets.only(right: 3),
            child: InkWell(
              onTap: () => _applySeriesToSelected(s),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF818CF8)),
                ),
                child: Text('Ser $s', style: const TextStyle(color: Color(0xFFC7D2FE), fontWeight: FontWeight.bold, fontSize: 9.5)),
              ),
            ),
          )),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: _applyDateToSelected,
            icon: const Icon(Icons.calendar_month, size: 11, color: Color(0xFFFBBF24)),
            label: const Text('Date', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFBBF24))),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFBBF24)),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: const Size(50, 22),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            tooltip: 'Set Shift for selected',
            onSelected: (shift) {
              setState(() {
                for (final it in _selectedItems) {
                  it.drawShift = shift;
                }
              });
            },
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'Dear 1 PM',
                child: Text('Dear 1 PM', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11)),
              ),
              const PopupMenuItem(
                value: 'Dear 6 PM',
                child: Text('Dear 6 PM', style: TextStyle(color: Color(0xFFA78BFA), fontWeight: FontWeight.bold, fontSize: 11)),
              ),
              const PopupMenuItem(
                value: 'Dear 8 PM',
                child: Text('Dear 8 PM', style: TextStyle(color: Color(0xFFF472B6), fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFA78BFA)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time_rounded, size: 11, color: Color(0xFFA78BFA)),
                  SizedBox(width: 3),
                  Text('Shift ▾', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFA78BFA))),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton.icon(
            onPressed: _autoFixMalformedRanges,
            icon: const Icon(Icons.auto_fix_high_rounded, size: 11, color: Color(0xFFFBBF24)),
            label: const Text('✂️ Fix Bad Ranges', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFDE68A))),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF78350F),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: const Size(50, 22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: const BorderSide(color: Color(0xFFFBBF24)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton.icon(
            onPressed: _deleteSelectedItems,
            icon: const Icon(Icons.delete_outline, size: 11),
            label: const Text('Delete', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: const Size(50, 22),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Deselect All',
            icon: const Icon(Icons.close, size: 13, color: Colors.white70),
            onPressed: () => setState(() {
              _selectedItems.clear();
              _lastSelectedIdx = null;
            }),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVoucher = widget.mode == StockScanMode.voucher;
    final primaryColor = isVoucher ? const Color(0xFF3B82F6) : const Color(0xFFEF4444);
    final primaryGlow = isVoucher ? const Color(0xFF1D4ED8) : const Color(0xFFDC2626);
    final modeTitle = isVoucher ? 'PASTE & PARSE VOUCHER PARCHA' : 'PASTE & PARSE UNSOLD RETURN';

    final textLines = _rawTextCtrl.text.split('\n');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF080C1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: primaryColor.withAlpha(80), width: 1.5),
          boxShadow: [
            BoxShadow(color: primaryGlow.withAlpha(60), blurRadius: 60, spreadRadius: 0),
            BoxShadow(color: Colors.black.withAlpha(240), blurRadius: 30, spreadRadius: 10),
          ],
        ),
        child: Column(
          children: [
            // ── TOP HEADER ────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor.withAlpha(30), const Color(0xFF0F172A)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: primaryColor.withAlpha(40))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [primaryColor, primaryGlow]),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: primaryColor.withAlpha(120), blurRadius: 10)],
                    ),
                    child: const Icon(Icons.paste_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(modeTitle,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13.5, color: Colors.white, letterSpacing: 0.8)),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Shift Selector
                          Container(
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: primaryColor.withAlpha(120)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedShift,
                                dropdownColor: const Color(0xFF0F172A),
                                icon: Icon(Icons.arrow_drop_down, color: primaryColor, size: 14),
                                style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 10.5),
                                items: const [
                                  DropdownMenuItem(value: 'Dear 1 PM', child: Text('Dear 1 PM')),
                                  DropdownMenuItem(value: 'Dear 6 PM', child: Text('Dear 6 PM')),
                                  DropdownMenuItem(value: 'Dear 8 PM', child: Text('Dear 8 PM')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedShift = val);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Date Picker button
                          InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setState(() => _selectedDate = picked);
                                _reparseText();
                              }
                            },
                            child: Row(
                              children: [
                                Icon(Icons.calendar_month, size: 12, color: Colors.grey.shade400),
                                const SizedBox(width: 3),
                                Text(
                                  DateFormat('dd-MM-yyyy').format(_selectedDate),
                                  style: TextStyle(color: Colors.grey.shade300, fontSize: 10.5, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),

                  // Stats Pills
                  _statPill('${_parsedItems.length}', 'Ranges', const Color(0xFF334155), Colors.white70),
                  const SizedBox(width: 6),
                  _statPill('$_totalTickets', 'Tickets', const Color(0xFF1E3A5F), const Color(0xFF60A5FA)),
                  const SizedBox(width: 6),

                  // Issues Pill Button (Click to Jump)
                  if (_unparsedLines.isNotEmpty)
                    InkWell(
                      onTap: _jumpToNextIssue,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF450A0A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFF87171)),
                          boxShadow: [
                            BoxShadow(color: Colors.red.withAlpha(80), blurRadius: 6),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 13, color: Color(0xFFF87171)),
                            const SizedBox(width: 4),
                            Text(
                              '${_unparsedLines.length} Issues ➔',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Color(0xFFF87171)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_unparsedLines.isNotEmpty) const SizedBox(width: 6),

                  _statPill(
                    '₹${_totalAmount >= 100000 ? '${(_totalAmount / 100000).toStringAsFixed(1)}L' : _totalAmount.toStringAsFixed(0)}',
                    'Value',
                    const Color(0xFF1C1A05),
                    const Color(0xFFFBBF24),
                  ),

                  const Spacer(),

                  // 🏢 1. Dealer Selector
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B).withAlpha(140)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _availableDealers.contains(_selectedDealer) ? _selectedDealer : null,
                        hint: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.workspace_premium_rounded, size: 14, color: Color(0xFFF59E0B)),
                            SizedBox(width: 4),
                            Text('Select Dealer', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        dropdownColor: const Color(0xFF1E293B),
                        items: [
                          const DropdownMenuItem<String>(
                            value: 'All Dealers',
                            child: Text('🏢 All Dealers / Direct', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
                          ),
                          ..._availableDealers.map((d) => DropdownMenuItem<String>(
                                value: d,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.workspace_premium_rounded, size: 13, color: Color(0xFFF59E0B)),
                                    const SizedBox(width: 6),
                                    Text(d, style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11.5, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              )),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedDealer = (val == 'All Dealers' || val == null) ? null : val;
                            _selectedSubSeller = null;
                            if (_selectedDealer != null) {
                              _partyCtrl.text = _selectedDealer!;
                            }
                            _reparseText();
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 👤 2. Sub-Seller Selector (Linked to Dealer)
                  if (_selectedDealer != null && (_dealerToSellersMap[_selectedDealer]?.isNotEmpty ?? false)) ...[
                    Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF38BDF8).withAlpha(140)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: (_dealerToSellersMap[_selectedDealer]?.contains(_selectedSubSeller) ?? false) ? _selectedSubSeller : 'MAIN_DEALER',
                          dropdownColor: const Color(0xFF1E293B),
                          items: [
                            DropdownMenuItem<String>(
                              value: 'MAIN_DEALER',
                              child: Text('👑 $_selectedDealer (Main Dealer)', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            ...(_dealerToSellersMap[_selectedDealer] ?? []).map((s) => DropdownMenuItem<String>(
                                  value: s,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.person, size: 13, color: Color(0xFF38BDF8)),
                                      const SizedBox(width: 5),
                                      Text(s, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                )),
                          ],
                          onChanged: (val) {
                            setState(() {
                              if (val == 'MAIN_DEALER') {
                                _selectedSubSeller = null;
                                _partyCtrl.text = _selectedDealer!;
                              } else {
                                _selectedSubSeller = val;
                                _partyCtrl.text = val!;
                              }
                              _reparseText();
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // 3. Editable Party Name Input
                  Container(
                    width: 170,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: primaryColor.withAlpha(80)),
                    ),
                    child: TextField(
                      controller: _partyCtrl,
                      style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 11.5),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Party / Seller Name',
                        labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 9.5),
                        prefixIcon: Icon(Icons.person_outline_rounded, size: 14, color: primaryColor),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                      ),
                      onChanged: (_) => _reparseText(),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Close button
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 18),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),

            // ── SPLIT BODY: LEFT (RAW TEXT) | RIGHT (PARSED TABLE) ──
            Expanded(
              child: Row(
                children: [
                  // ══ LEFT PANE: RAW TEXT INPUT ═════════════════════════════
                  Expanded(
                    flex: 4,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFF070B16),
                        border: Border(right: BorderSide(color: Color(0xFF1E293B), width: 1.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Action Bar: Paste & Clear & Issues
                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: _pasteFromClipboard,
                                icon: const Icon(Icons.content_paste_rounded, size: 13),
                                label: const Text('PASTE CLIPBOARD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0284C7),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                              ),
                              const SizedBox(width: 6),
                              OutlinedButton.icon(
                                onPressed: () {
                                  _rawTextCtrl.clear();
                                  _reparseText();
                                },
                                icon: const Icon(Icons.delete_sweep_rounded, size: 13, color: Colors.grey),
                                label: const Text('CLEAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: Colors.grey)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF334155)),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                              ),
                              const Spacer(),
                              if (_unparsedLines.isNotEmpty)
                                InkWell(
                                  onTap: _jumpToNextIssue,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7F1D1D),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Jump to Issue (${_unparsedLines.length}) ➔',
                                      style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // Multi-Cursor / Multi-Line Batch Tools Bar
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B1220),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF1E293B)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.flash_on_rounded, size: 13, color: Color(0xFFFBBF24)),
                                const SizedBox(width: 4),
                                const Text('Multi-Line Prefix:', style: TextStyle(color: Colors.grey, fontSize: 9.5, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 4),
                                ...['(12) ', '(20) ', '(24) ', '(36) ', '(40) ', '(60) '].map((s) => Padding(
                                  padding: const EdgeInsets.only(right: 3),
                                  child: InkWell(
                                    onTap: () => _applyMultiLinePrefix(s),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E1B4B),
                                        borderRadius: BorderRadius.circular(3),
                                        border: Border.all(color: const Color(0xFF818CF8)),
                                      ),
                                      child: Text(s.trim(), style: const TextStyle(color: Color(0xFFC7D2FE), fontSize: 9, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                )),
                                const Spacer(),
                                InkWell(
                                  onTap: () => _applyMultiLineSuffix('-'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F2B1D),
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(color: const Color(0xFF34D399)),
                                    ),
                                    child: const Text('Add -', style: TextStyle(color: Color(0xFF34D399), fontSize: 9, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Quick 3-Box Entry Row
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF1E293B)),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 50,
                                  height: 24,
                                  child: TextField(
                                    controller: _quickSeriesCtrl,
                                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText: 'Ser',
                                      hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 9.5),
                                      filled: true,
                                      fillColor: const Color(0xFF0B1120),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  flex: 3,
                                  child: SizedBox(
                                    height: 24,
                                    child: TextField(
                                      controller: _quickFromCtrl,
                                      style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText: 'From (50271)',
                                        hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 9.5),
                                        filled: true,
                                        fillColor: const Color(0xFF0B1120),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      ),
                                      onSubmitted: (_) => _insertQuickRange(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  flex: 2,
                                  child: SizedBox(
                                    height: 24,
                                    child: TextField(
                                      controller: _quickToCtrl,
                                      style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText: 'To (274)',
                                        hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 9.5),
                                        filled: true,
                                        fillColor: const Color(0xFF0B1120),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      ),
                                      onSubmitted: (_) => _insertQuickRange(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ElevatedButton(
                                  onPressed: _insertQuickRange,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    minimumSize: const Size(40, 24),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  ),
                                  child: const Text('➕ Add', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Text Area with Line Numbers Gutter (Supports Shift+Click Multi-Line Selection)
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _unparsedLines.isNotEmpty ? Colors.redAccent.withAlpha(120) : const Color(0xFF1E293B),
                                  width: _unparsedLines.isNotEmpty ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Line Numbers Gutter (Click or Shift+Click to select lines)
                                  Container(
                                    width: 34,
                                    padding: const EdgeInsets.only(top: 12, bottom: 12),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF070B16),
                                      borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
                                      border: Border(right: BorderSide(color: Color(0xFF1E293B))),
                                    ),
                                    child: ListView.builder(
                                      controller: _rawTextScrollCtrl,
                                      itemCount: textLines.isEmpty ? 1 : textLines.length,
                                      itemBuilder: (ctx, i) {
                                        return InkWell(
                                          onTap: () => _handleLineGutterClick(i),
                                          child: Container(
                                            height: 18.1,
                                            alignment: Alignment.centerRight,
                                            padding: const EdgeInsets.only(right: 6),
                                            child: Text(
                                              '${i + 1}',
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 9.5,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),

                                  // Actual Text Field
                                  Expanded(
                                    child: TextField(
                                      controller: _rawTextCtrl,
                                      focusNode: _rawTextFocusNode,
                                      maxLines: null,
                                      expands: true,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12.5,
                                        color: Color(0xFFE2E8F0),
                                        height: 1.45,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: isVoucher
                                            ? 'Paste voucher parcha text here...\nExample:\n(12) 52150 to 950-999\n25/08: 52\n26/08: 55\n\nOr 12=50271-274...'
                                            : 'Paste unsold parcha text here...\nExample:\n(12)\n50271-274\n276-279\n481-483\n554-\n558-559\n\nOr 50271 to 50274...',
                                        hintStyle: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                                        border: InputBorder.none,
                                        contentPadding: const EdgeInsets.all(12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Color Legend Key at bottom of left pane
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _legendItem('Series (12)', const Color(0xFFC084FC)),
                              _legendItem('5-Digit Ticket', const Color(0xFF4ADE80)),
                              _legendItem('3-Digit Range', const Color(0xFF34D399)),
                              _legendItem('Shift / Date', const Color(0xFFFBBF24)),
                              _legendItem('Issue (Unparsed)', const Color(0xFFF87171)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ══ RIGHT PANE: LIVE PARSED TABLE ══════════════════════════
                  Expanded(
                    flex: 6,
                    child: Column(
                      children: [
                        // Right Filter Bar
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          color: const Color(0xFF0B1120),
                          child: Row(
                            children: [
                              // Series filter pills
                              const Text('Series:', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 6),
                              Wrap(
                                spacing: 4,
                                children: ['ALL', ..._availableSeriesList].map((s) {
                                  final isSel = _selectedSeriesFilter == s;
                                  return InkWell(
                                    onTap: () => setState(() => _selectedSeriesFilter = s),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isSel ? primaryColor : const Color(0xFF1E293B),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(s, style: TextStyle(color: isSel ? Colors.white : Colors.grey.shade400, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  );
                                }).toList(),
                              ),
                              if (_availableShiftsList.length > 1) ...[
                                const SizedBox(width: 12),
                                const Text('Shift:', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 6),
                                Wrap(
                                  spacing: 4,
                                  children: ['ALL', ..._availableShiftsList].map((sh) {
                                    final isSel = _selectedShiftFilter == sh;
                                    final label = sh == 'ALL' ? 'ALL' : sh.replaceAll('Dear ', '');
                                    return InkWell(
                                      onTap: () => setState(() => _selectedShiftFilter = sh),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isSel ? const Color(0xFF5B21B6) : const Color(0xFF1E293B),
                                          borderRadius: BorderRadius.circular(4),
                                          border: isSel ? Border.all(color: const Color(0xFFA78BFA)) : null,
                                        ),
                                        child: Text(
                                          label,
                                          style: TextStyle(
                                            color: isSel ? Colors.white : const Color(0xFFA78BFA),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                              const Spacer(),

                              // Search
                              SizedBox(
                                width: 160,
                                height: 28,
                                child: TextField(
                                  controller: _searchCtrl,
                                  style: const TextStyle(fontSize: 10.5, color: Colors.white),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'Search ticket...',
                                    hintStyle: TextStyle(color: Colors.grey.shade700, fontSize: 10),
                                    prefixIcon: const Icon(Icons.search_rounded, size: 13, color: Color(0xFF475569)),
                                    filled: true,
                                    fillColor: const Color(0xFF0F172A),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(color: Color(0xFF1E293B)),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  ),
                                  onChanged: (val) => setState(() => _searchQuery = val),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Bulk Action Bar (when selected)
                        _buildReviewBulkActionBar(),

                        // Table Header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          color: const Color(0xFF0F172A),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 36,
                                child: Row(
                                  children: [
                                    InkWell(
                                      onTap: _toggleSelectAll,
                                      child: Icon(
                                        _displayedItems.isNotEmpty && _selectedItems.containsAll(_displayedItems)
                                            ? Icons.check_box_rounded
                                            : (_selectedItems.isNotEmpty ? Icons.indeterminate_check_box_rounded : Icons.check_box_outline_blank_rounded),
                                        size: 14,
                                        color: _selectedItems.isNotEmpty ? Colors.indigoAccent : const Color(0xFF475569),
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    const Text('#', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 10)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 58, child: Text('DATE ✎', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 10))),
                              const SizedBox(width: 4),
                              const SizedBox(width: 58, child: Center(child: Text('SHIFT', style: TextStyle(color: Color(0xFFA78BFA), fontWeight: FontWeight.bold, fontSize: 10)))),
                              const SizedBox(width: 4),
                              const SizedBox(width: 54, child: Text('SERIES', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 10))),
                              const Expanded(child: Text('TICKET RANGE', style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 10))),
                              const SizedBox(width: 48, child: Text('QTY', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 10))),
                              const SizedBox(width: 70, child: Text('AMOUNT', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 10))),
                              const SizedBox(width: 60, child: Center(child: Text('ACTIONS', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 10)))),
                            ],
                          ),
                        ),
                        Container(height: 1, color: const Color(0xFF1E293B)),

                        // Table Body
                        Expanded(
                          child: _displayedItems.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.text_snippet_outlined, size: 36, color: Colors.grey.shade700),
                                      const SizedBox(height: 8),
                                      Text('Paste text on the left to see live parsed tickets here.',
                                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _displayedItems.length,
                                  itemBuilder: (ctx, idx) {
                                    final item = _displayedItems[idx];
                                    final isSelected = _selectedItems.contains(item);

                                    return InkWell(
                                      onTap: () => _handleRowTap(idx, item),
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xFF312E81).withAlpha(180)
                                              : (idx.isEven ? const Color(0xFF0B1120) : Colors.transparent),
                                          borderRadius: BorderRadius.circular(4),
                                          border: isSelected ? Border.all(color: Colors.indigoAccent) : null,
                                        ),
                                        child: Row(
                                          children: [
                                            // Checkbox & Row
                                            SizedBox(
                                              width: 36,
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                                    size: 13,
                                                    color: isSelected ? Colors.indigoAccent : Colors.grey.shade700,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text('${idx + 1}', style: TextStyle(color: isSelected ? Colors.white : Colors.grey.shade700, fontSize: 9.5)),
                                                ],
                                              ),
                                            ),

                                            // Date Pill
                                            SizedBox(
                                              width: 58,
                                              child: InkWell(
                                                onTap: () async {
                                                  final picked = await showDatePicker(
                                                    context: context,
                                                    initialDate: _selectedDate,
                                                    firstDate: DateTime(2020),
                                                    lastDate: DateTime(2035),
                                                  );
                                                  if (picked != null) {
                                                    setState(() => item.targetDate = DateFormat('yyyy-MM-dd').format(picked));
                                                  }
                                                },
                                                child: Text(
                                                  item.targetDate != null
                                                      ? item.targetDate!.split('-').skip(1).join('/')
                                                      : DateFormat('dd/MM').format(_selectedDate),
                                                  style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 9.5, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),

                                            // Shift Pill
                                            SizedBox(
                                              width: 58,
                                              child: GestureDetector(
                                                onTap: () {
                                                  final cur = (item.drawShift != null && item.drawShift!.isNotEmpty) ? item.drawShift! : _selectedShift;
                                                  final next = cur.contains('1') ? 'Dear 6 PM' : (cur.contains('6') ? 'Dear 8 PM' : 'Dear 1 PM');
                                                  setState(() => item.drawShift = next);
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2.5),
                                                  decoration: BoxDecoration(
                                                    color: ((item.drawShift ?? _selectedShift).contains('1'))
                                                        ? const Color(0xFF0F2942)
                                                        : ((item.drawShift ?? _selectedShift).contains('6') ? const Color(0xFF2E1065) : const Color(0xFF3F1D38)),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(
                                                      color: ((item.drawShift ?? _selectedShift).contains('1'))
                                                          ? const Color(0xFF38BDF8).withAlpha(150)
                                                          : ((item.drawShift ?? _selectedShift).contains('6') ? const Color(0xFFA78BFA).withAlpha(150) : const Color(0xFFF472B6).withAlpha(150)),
                                                    ),
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      (item.drawShift != null && item.drawShift!.isNotEmpty ? item.drawShift! : _selectedShift).replaceAll('Dear ', ''),
                                                      style: TextStyle(
                                                        color: ((item.drawShift ?? _selectedShift).contains('1'))
                                                            ? const Color(0xFF38BDF8)
                                                            : ((item.drawShift ?? _selectedShift).contains('6') ? const Color(0xFFA78BFA) : const Color(0xFFF472B6)),
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),

                                            // Series (Editable)
                                            SizedBox(
                                              width: 50,
                                              height: 24,
                                              child: TextField(
                                                controller: TextEditingController(text: item.series),
                                                style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 10.5),
                                                decoration: InputDecoration(
                                                  isDense: true,
                                                  filled: true,
                                                  fillColor: const Color(0xFF0F172A),
                                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                ),
                                                onChanged: (val) {
                                                  item.series = val.trim();
                                                  _recalculateAllPrices();
                                                  setState(() {});
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 6),

                                            // Ticket Range (Editable)
                                            Expanded(
                                              child: SizedBox(
                                                height: 24,
                                                child: TextField(
                                                  controller: TextEditingController(text: item.ticketNo),
                                                  style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 11),
                                                  decoration: InputDecoration(
                                                    isDense: true,
                                                    filled: true,
                                                    fillColor: const Color(0xFF071A0E),
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                  ),
                                                  onChanged: (val) {
                                                    item.ticketNo = val.trim();
                                                    if (val.contains('-')) {
                                                      final parts = val.split('-');
                                                      item.fromTicket = parts.first.trim();
                                                      item.toTicket = parts.last.trim();
                                                      final f = int.tryParse(item.fromTicket);
                                                      final t = int.tryParse(item.toTicket);
                                                      if (f != null && t != null && t >= f) {
                                                        item.quantity = (t - f) + 1;
                                                      }
                                                    } else {
                                                      item.fromTicket = val.trim();
                                                      item.toTicket = val.trim();
                                                      item.quantity = 1;
                                                    }
                                                    _recalculateAllPrices();
                                                    setState(() {});
                                                  },
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),

                                            // Quantity
                                            SizedBox(
                                              width: 48,
                                              child: Text('${item.quantity} Nos', style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),

                                            // Amount
                                            SizedBox(
                                              width: 70,
                                              child: Text('₹${item.amount.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 10.5, fontWeight: FontWeight.bold)),
                                            ),

                                            // Delete Action
                                            SizedBox(
                                              width: 36,
                                              child: IconButton(
                                                icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFF87171)),
                                                onPressed: () => setState(() => _parsedItems.remove(item)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),

                        // Bottom Unparsed Lines Banner (Clickable chips that jump cursor to exact line)
                        if (_unparsedLines.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            color: const Color(0xFF2A0A0A),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, size: 13, color: Color(0xFFF87171)),
                                const SizedBox(width: 6),
                                Text(
                                  'Unrecognized (${_unparsedLines.length}):',
                                  style: const TextStyle(color: Color(0xFFF87171), fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: _unparsedLines.map((unparsed) {
                                        return Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: InkWell(
                                            onTap: () => _jumpToUnparsedLine(unparsed),
                                            borderRadius: BorderRadius.circular(4),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF450A0A),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: const Color(0xFFF87171).withAlpha(150)),
                                              ),
                                              child: Text(
                                                unparsed,
                                                style: const TextStyle(color: Colors.white, fontSize: 9.5, fontFamily: 'monospace'),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── BOTTOM FOOTER ─────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF0F172A), primaryColor.withAlpha(20)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                border: Border(top: BorderSide(color: primaryColor.withAlpha(40))),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_totalTickets Tickets • ${_parsedItems.length} Ranges',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                      Text(
                        'Total Value: ₹${_totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w700, fontSize: 11.5),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // Export CSV Button
                  OutlinedButton.icon(
                    onPressed: _exportScannedEntries,
                    icon: const Icon(Icons.file_download_outlined, size: 14, color: Color(0xFF38BDF8)),
                    label: const Text('EXPORT CSV', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 10.5)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                      backgroundColor: const Color(0xFF0C2433),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Cancel Button
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade400,
                      side: BorderSide(color: Colors.grey.shade700),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('CANCEL', style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(width: 8),

                  // Save Button
                  ElevatedButton.icon(
                    onPressed: _isSaving || _parsedItems.isEmpty ? null : _saveAllParsedEntries,
                    icon: _isSaving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_rounded, size: 15),
                    label: Text(
                      isVoucher ? 'SAVE ALL VOUCHERS' : 'SAVE ALL UNSOLD',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, letterSpacing: 0.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 9.5)),
      ],
    );
  }
}
