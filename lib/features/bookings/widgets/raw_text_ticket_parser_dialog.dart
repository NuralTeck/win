import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/database_service.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../../sellers/models/seller_customer_model.dart';
import '../viewmodels/ticket_sales_viewmodel.dart';
import '../../settings/viewmodels/series_price_viewmodel.dart';
import '../../sellers/viewmodels/seller_customer_viewmodel.dart';

/// Parsed ticket item model for the Raw Text Parser
class _ParsedItem {
  String series;
  String ticketNo;
  int quantity;
  double pricePerTicket;

  _ParsedItem({
    required this.series,
    required this.ticketNo,
    this.quantity = 1,
    this.pricePerTicket = 45.0,
  });

  double get totalAmount => pricePerTicket * quantity;
}

/// Real-time Visual Syntax Highlighting Controller for Ticket Text Input
class _TicketSyntaxHighlightingController extends TextEditingController {
  _TicketSyntaxHighlightingController();

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

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isLastLine = i == lines.length - 1;
      final lineEnding = isLastLine ? '' : '\n';

      if (line.trim().isEmpty) {
        spans.add(TextSpan(text: line + lineEnding, style: style));
        continue;
      }

      final trimmed = line.trim();

      // 0. WhatsApp forwarded message header (Ignored / Dim Grey)
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

      // 1. Check for Invalid long digit numbers (> 5 continuous digits without separator)
      final hasTooLongDigits = RegExp(r'\b\d{6,}\b').hasMatch(contentTrimmed);
      if (hasTooLongDigits) {
        final List<TextSpan> lineSpans = [];
        if (waHeaderPrefix != null) {
          lineSpans.add(TextSpan(
            text: waHeaderPrefix,
            style: (style ?? const TextStyle()).copyWith(color: const Color(0xFF94A3B8), fontSize: 11),
          ));
        }
        lineSpans.add(TextSpan(
          text: contentToHighlight + lineEnding,
          style: (style ?? const TextStyle()).copyWith(
            color: const Color(0xFFF87171),
            backgroundColor: const Color(0xFF7F1D1D).withAlpha(150),
            decoration: TextDecoration.underline,
            decorationColor: Colors.redAccent,
            decorationStyle: TextDecorationStyle.wavy,
            fontWeight: FontWeight.bold,
          ),
        ));
        spans.add(TextSpan(children: lineSpans));
        continue;
      }

      // 2. Shift Tag (Cyan Highlight)
      if (RegExp(
        r'(?:=|\b)(?:dear\s*)?[168](?::00|\.00|\.)?\s*pm\b'
        r'|^\bmorning\b$|^\bday\b$|^\bnight\b$|^\bevening\b$'
        r'|^\s*dear\s*[168](?:\.00|:00|\.)?\s*(?:pm|baje)?\s*$'
        r'|^\s*[168](?:\.00|:00|\.)?\s*(?:pm|baje)\s*$',
        caseSensitive: false,
      ).hasMatch(contentTrimmed)) {
        final List<TextSpan> lineSpans = [];
        if (waHeaderPrefix != null) {
          lineSpans.add(TextSpan(
            text: waHeaderPrefix,
            style: (style ?? const TextStyle()).copyWith(color: const Color(0xFF94A3B8), fontSize: 11),
          ));
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

      // 3. Date Tag (Indigo / Blue Highlight)
      if (RegExp(r'\b(\d{1,2})[=\/\.-](\d{1,2})([=\/\.-]\d{2,4})?\b|\b(?:kal|tomorrow|aaj|today)\b', caseSensitive: false).hasMatch(contentTrimmed) &&
          !RegExp(r'\b\d{5}\b').hasMatch(contentTrimmed)) {
        final List<TextSpan> lineSpans = [];
        if (waHeaderPrefix != null) {
          lineSpans.add(TextSpan(
            text: waHeaderPrefix,
            style: (style ?? const TextStyle()).copyWith(color: const Color(0xFF94A3B8), fontSize: 11),
          ));
        }
        lineSpans.add(TextSpan(
          text: contentToHighlight + lineEnding,
          style: (style ?? const TextStyle()).copyWith(
            color: const Color(0xFF818CF8),
            backgroundColor: const Color(0xFF3730A3).withAlpha(90),
            fontWeight: FontWeight.bold,
          ),
        ));
        spans.add(TextSpan(children: lineSpans));
        continue;
      }

      // 4. Standalone Series Tag (Purple)
      if (RegExp(r'^\s*(?:series|serial|sere|sereis)?\s*[:=-]?\s*\(?\d{1,4}[a-z.]?\)?\s*[:=-]?\s*$', caseSensitive: false).hasMatch(contentTrimmed) &&
          !RegExp(r'\b\d{5}\b').hasMatch(contentTrimmed)) {
        final List<TextSpan> lineSpans = [];
        if (waHeaderPrefix != null) {
          lineSpans.add(TextSpan(
            text: waHeaderPrefix,
            style: (style ?? const TextStyle()).copyWith(color: const Color(0xFF94A3B8), fontSize: 11),
          ));
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

      // 5. Metadata / Note lines
      if (RegExp(r'^\s*(?:wakil|sk|booking|bokakg|updated|note|total)\b', caseSensitive: false).hasMatch(contentTrimmed) &&
          !RegExp(r'\b\d{5}\b').hasMatch(contentTrimmed)) {
        spans.add(TextSpan(
          text: line + lineEnding,
          style: (style ?? const TextStyle()).copyWith(
            color: Colors.lightBlueAccent.shade100,
            fontStyle: FontStyle.italic,
          ),
        ));
        continue;
      }

      // 6. Valid 5-Digit Ticket Line
      final hasExact5Digits = RegExp(r'\b\d{5}\b').hasMatch(contentTrimmed);
      final isRangeFormat = RegExp(r'\d{5}\s*(?:--|\s+to\s+|-)\s*\d{1,5}', caseSensitive: false).hasMatch(contentTrimmed);

      if (hasExact5Digits || isRangeFormat) {
        const purpleStyle = TextStyle(
          color: Color(0xFFC084FC),
          backgroundColor: Color(0x806B21A8),
          fontWeight: FontWeight.bold,
        );
        const greenStyle = TextStyle(
          color: Color(0xFF4ADE80),
          backgroundColor: Color(0x7814532D),
          fontWeight: FontWeight.bold,
        );

        final List<TextSpan> lineSpans = [];
        if (waHeaderPrefix != null) {
          lineSpans.add(TextSpan(
            text: waHeaderPrefix,
            style: (style ?? const TextStyle()).copyWith(color: const Color(0xFF94A3B8), fontSize: 11),
          ));
        }

        final fiveDigitMatchInContent = RegExp(r'\d{5}').firstMatch(contentToHighlight);

        if (fiveDigitMatchInContent != null) {
          final beforeTicket = contentToHighlight.substring(0, fiveDigitMatchInContent.start);
          final fromTicket = contentToHighlight.substring(fiveDigitMatchInContent.start);

          final isSeriesPrefix = beforeTicket.trim().isNotEmpty &&
              RegExp(r'^\s*\(?\d{1,4}[a-z]?\)?\s*[=\-*\/#:\._,~@|\\!\$%\^&+\s]*\s*$', caseSensitive: false).hasMatch(beforeTicket);

          final suffixMatchInLine = RegExp(r'^(\d{5})((?:[=\-*\/#:\._,~@|\\!\$%\^&+\s]+\s*\(?\d{1,4}[a-z]?\)?).*)$', caseSensitive: false).firstMatch(fromTicket);
          final isSeriesSuffix = !isSeriesPrefix && suffixMatchInLine != null;

          if (isSeriesPrefix) {
            lineSpans.add(TextSpan(text: beforeTicket, style: (style ?? const TextStyle()).merge(purpleStyle)));
            lineSpans.add(TextSpan(text: fromTicket + lineEnding, style: (style ?? const TextStyle()).merge(greenStyle)));
          } else if (isSeriesSuffix) {
            lineSpans.add(TextSpan(text: suffixMatchInLine.group(1)!, style: (style ?? const TextStyle()).merge(greenStyle)));
            lineSpans.add(TextSpan(text: suffixMatchInLine.group(2)! + lineEnding, style: (style ?? const TextStyle()).merge(purpleStyle)));
          } else {
            lineSpans.add(TextSpan(
              text: contentToHighlight + lineEnding,
              style: (style ?? const TextStyle()).merge(greenStyle),
            ));
          }
        } else {
          lineSpans.add(TextSpan(
            text: contentToHighlight + lineEnding,
            style: (style ?? const TextStyle()).merge(greenStyle),
          ));
        }
        spans.add(TextSpan(children: lineSpans));
        continue;
      }

      // 7. Error / Unrecognized Line
      spans.add(TextSpan(
        text: line + lineEnding,
        style: (style ?? const TextStyle()).copyWith(
          color: const Color(0xFFF87171),
          backgroundColor: const Color(0xFF7F1D1D).withAlpha(140),
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

class RawTextTicketParserDialog extends ConsumerStatefulWidget {
  final String activeShift;
  final DateTime activeDate;
  final String defaultSeller;

  const RawTextTicketParserDialog({
    super.key,
    required this.activeShift,
    required this.activeDate,
    required this.defaultSeller,
  });

  @override
  ConsumerState<RawTextTicketParserDialog> createState() => _RawTextTicketParserDialogState();
}

class _RawTextTicketParserDialogState extends ConsumerState<RawTextTicketParserDialog> {
  final _TicketSyntaxHighlightingController _rawTextCtrl = _TicketSyntaxHighlightingController();
  final FocusNode _rawTextFocusNode = FocusNode();
  final ScrollController _rawTextScrollCtrl = ScrollController();
  final TextEditingController _customerCtrl = TextEditingController();
  final TextEditingController _leftSearchCtrl = TextEditingController();
  late String _selectedShift;
  late DateTime _selectedDate;
  String _fallbackSeries = '12';
  List<_ParsedItem> _parsedItems = [];
  bool _isSaving = false;
  String _selectedSeriesFilter = 'All';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  bool _autoDetectShift = true;
  bool _autoDetectDate = true;

  int _lastJumpedOccurrence = 0;
  String _lastJumpedText = '';

  int _leftSearchMatchCount = 0;
  int _currentLeftSearchIndex = 0;

  final TextEditingController _quickSeriesCtrl = TextEditingController();
  final TextEditingController _quickFromTicketCtrl = TextEditingController();
  final TextEditingController _quickToRangeCtrl = TextEditingController();
  final FocusNode _quickFromTicketFocusNode = FocusNode();
  final FocusNode _quickToRangeFocusNode = FocusNode();
  final FocusNode _quickSeriesFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _selectedShift = widget.activeShift.isNotEmpty ? widget.activeShift : 'Dear 1 PM';
    _selectedDate = widget.activeDate;
    _customerCtrl.text = widget.defaultSeller.isNotEmpty ? widget.defaultSeller : 'Sk';

    _rawTextCtrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _rawTextCtrl.removeListener(_onTextChanged);
    _rawTextCtrl.dispose();
    _rawTextFocusNode.dispose();
    _rawTextScrollCtrl.dispose();
    _customerCtrl.dispose();
    _leftSearchCtrl.dispose();
    _searchCtrl.dispose();
    _quickSeriesCtrl.dispose();
    _quickFromTicketCtrl.dispose();
    _quickToRangeCtrl.dispose();
    _quickFromTicketFocusNode.dispose();
    _quickToRangeFocusNode.dispose();
    _quickSeriesFocusNode.dispose();
    super.dispose();
  }

  /// Add quick 2-box range or single ticket directly into the parser text box
  void _addQuickRangeToParser() {
    final fromText = _quickFromTicketCtrl.text.trim();
    if (fromText.isEmpty || fromText.length != 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ First box requires an exact 5-digit number (e.g. 28311)'),
          backgroundColor: Colors.orangeAccent,
          duration: Duration(seconds: 2),
        ),
      );
      _quickFromTicketFocusNode.requestFocus();
      return;
    }

    final seriesVal = _quickSeriesCtrl.text.trim().isNotEmpty
        ? _quickSeriesCtrl.text.trim().toUpperCase()
        : _fallbackSeries;
    _fallbackSeries = seriesVal;
    _quickSeriesCtrl.text = seriesVal;

    final toText = _quickToRangeCtrl.text.trim();

    String lineToAdd = '';
    if (toText.isNotEmpty) {
      // Range format e.g. "12- 28311-15" or "12- 28311-315"
      lineToAdd = '$seriesVal- $fromText-$toText';
    } else {
      // Single 5-digit format e.g. "12- 28311"
      lineToAdd = '$seriesVal- $fromText';
    }

    final currentText = _rawTextCtrl.text;
    final newText = currentText.isEmpty
        ? lineToAdd
        : (currentText.endsWith('\n') ? '$currentText$lineToAdd' : '$currentText\n$lineToAdd');

    _rawTextCtrl.text = newText;
    _quickFromTicketCtrl.clear();
    _quickToRangeCtrl.clear();
    
    // Focus returns to Series field pre-filled so operator can press Enter to keep it or type new series!
    _quickSeriesFocusNode.requestFocus();
    _quickSeriesCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _quickSeriesCtrl.text.length,
    );
  }

  /// Open Modal to edit an existing parsed ticket entry
  Future<void> _editParsedItem(_ParsedItem item) async {
    final seriesCtrl = TextEditingController(text: item.series);
    final ticketNoCtrl = TextEditingController(text: item.ticketNo);
    final qtyCtrl = TextEditingController(text: item.quantity.toString());
    final priceCtrl = TextEditingController(text: item.pricePerTicket.toStringAsFixed(0));

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF334155))),
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: Colors.cyanAccent, size: 22),
              const SizedBox(width: 8),
              const Text('Edit Ticket Entry', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: seriesCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    labelText: 'Series',
                    labelStyle: TextStyle(color: Colors.grey),
                    isDense: true,
                    filled: true,
                    fillColor: Color(0xFF0F172A),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ticketNoCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: '5-Digit Ticket No',
                    labelStyle: TextStyle(color: Colors.grey),
                    counterText: '',
                    isDense: true,
                    filled: true,
                    fillColor: Color(0xFF0F172A),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                          labelStyle: TextStyle(color: Colors.grey),
                          isDense: true,
                          filled: true,
                          fillColor: Color(0xFF0F172A),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Price (₹)',
                          labelStyle: TextStyle(color: Colors.grey),
                          isDense: true,
                          filled: true,
                          fillColor: Color(0xFF0F172A),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: () {
                if (ticketNoCtrl.text.trim().isNotEmpty) {
                  Navigator.of(ctx).pop(true);
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      setState(() {
        item.series = _cleanSeries(seriesCtrl.text.trim(), fallback: item.series);
        item.ticketNo = ticketNoCtrl.text.trim().padLeft(5, '0');
        item.quantity = int.tryParse(qtyCtrl.text.trim()) ?? item.quantity;
        item.pricePerTicket = double.tryParse(priceCtrl.text.trim()) ?? item.pricePerTicket;
      });
    }
  }

  /// Perform search & navigation in left text editor
  void _performLeftSearch(String query, {bool jumpNext = true}) {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _leftSearchMatchCount = 0;
        _currentLeftSearchIndex = 0;
      });
      return;
    }

    final text = _rawTextCtrl.text;
    final matches = RegExp(RegExp.escape(q), caseSensitive: false).allMatches(text).toList();

    if (matches.isEmpty) {
      setState(() {
        _leftSearchMatchCount = 0;
        _currentLeftSearchIndex = 0;
      });
      return;
    }

    final offsets = matches.map((m) => m.start).toList();
    int nextIdx = _currentLeftSearchIndex;
    if (jumpNext) {
      nextIdx = (_currentLeftSearchIndex + 1) % offsets.length;
    } else {
      nextIdx = (_currentLeftSearchIndex - 1 + offsets.length) % offsets.length;
    }

    setState(() {
      _leftSearchMatchCount = offsets.length;
      _currentLeftSearchIndex = nextIdx;
    });

    final targetOffset = offsets[nextIdx];
    _rawTextFocusNode.requestFocus();
    _rawTextCtrl.selection = TextSelection(
      baseOffset: targetOffset,
      extentOffset: targetOffset + q.length,
    );
  }

  /// Jump cursor and select the clicked unrecognized/invalid line in the left text editor
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

  void _updateLeftSearchCountOnly(String query) {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _leftSearchMatchCount = 0;
        _currentLeftSearchIndex = 0;
      });
      return;
    }
    final text = _rawTextCtrl.text;
    final matches = RegExp(RegExp.escape(q), caseSensitive: false).allMatches(text).toList();
    setState(() {
      _leftSearchMatchCount = matches.length;
      if (_currentLeftSearchIndex >= matches.length) {
        _currentLeftSearchIndex = 0;
      }
    });
  }

  void _onTextChanged() {
    _parseRawText(_rawTextCtrl.text);
    if (_leftSearchCtrl.text.isNotEmpty) {
      _updateLeftSearchCountOnly(_leftSearchCtrl.text);
    }
  }

  String _cleanSeries(String raw, {String fallback = '12'}) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty && digits.length <= 4) {
      return digits;
    }
    return digits.isNotEmpty ? digits.substring(0, 3) : fallback;
  }

  double _getPriceForSeries(String series) {
    final state = ref.read(seriesPriceViewModelProvider);
    final calculated = state.getPriceForSeries(series);
    if (calculated > 0) return calculated;

    final cleanDigits = _cleanSeries(series);
    final numVal = double.tryParse(cleanDigits) ?? 12.0;
    return numVal * 3.75;
  }

  List<String>? _expandTicketRange(String startTkt, String endPart) {
    if (startTkt.length != 5) return null;

    final startFull = int.tryParse(startTkt);
    if (startFull == null) return null;

    int? endFull;
    if (endPart.length == 1) {
      final prefix = startTkt.substring(0, 4);
      final lastDigit = int.tryParse(endPart);
      if (lastDigit == null) return null;
      endFull = int.tryParse('$prefix$lastDigit');
    } else if (endPart.length == 2) {
      final prefix = startTkt.substring(0, 3);
      final last2 = int.tryParse(endPart);
      if (last2 == null) return null;
      endFull = int.tryParse('$prefix$endPart');
    } else if (endPart.length == 3) {
      final prefix = startTkt.substring(0, 2);
      final last3 = int.tryParse(endPart);
      if (last3 == null) return null;
      endFull = int.tryParse('$prefix$endPart');
    } else if (endPart.length == 4 || endPart.length == 5) {
      endFull = int.tryParse(endPart.padLeft(5, '0'));
    }

    if (endFull == null || endFull < startFull || (endFull - startFull) > 200) {
      return null;
    }

    final List<String> result = [];
    for (int i = startFull; i <= endFull; i++) {
      result.add(i.toString().padLeft(5, '0'));
    }
    return result;
  }

  List<String> _unparsedLines = [];

  void _parseRawText(String text) {
    if (text.trim().isEmpty) {
      setState(() {
        _parsedItems = [];
        _unparsedLines = [];
      });
      return;
    }

    String detectedShift = _selectedShift;
    DateTime detectedDate = _selectedDate;

    final rawLines = text.split(RegExp(r'[\r\n]+'));
    final List<String> lines = [];
    for (final rLine in rawLines) {
      final t = rLine.trim();
      if (t.isEmpty) continue;
      if (RegExp(r'^\s*(?:forwarded|forwarded message|fwd|forward|\*forwarded\*)\s*$', caseSensitive: false).hasMatch(t)) {
        continue;
      }
      lines.add(t);
    }

    final List<_ParsedItem> items = [];
    final List<String> unparsed = [];
    String currentSeries = _fallbackSeries;

    final standardShares = {'1', '2', '3', '4', '5', '6', '10', '12', '18', '20', '24', '25', '30', '36', '40', '50', '60', '100'};

    for (int i = 0; i < lines.length; i++) {
      var line = lines[i];

      final waHeader = RegExp(
        r'^\s*\[([^\]]+)\]\s*([^:\n]+):\s*(.*)$',
        caseSensitive: false,
      ).firstMatch(line) ?? RegExp(
        r'^\s*(\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4},?\s+\d{1,2}:\d{2}(?::\d{2})?\s*(?:am|pm|AM|PM)?)\s*-\s*([^:\n]+):\s*(.*)$',
        caseSensitive: false,
      ).firstMatch(line);

      if (waHeader != null) {
        final metaPart = waHeader.group(1) ?? '';
        final bodyPart = waHeader.group(3) ?? '';

        if (_autoDetectDate) {
          final dateMatch = RegExp(r'\b(\d{1,2})[=\/\.-](\d{1,2})[=\/\.-](\d{2,4})\b').firstMatch(metaPart);
          if (dateMatch != null) {
            final day = int.tryParse(dateMatch.group(1) ?? '') ?? 1;
            final month = int.tryParse(dateMatch.group(2) ?? '') ?? 1;
            int year = int.tryParse(dateMatch.group(3) ?? '') ?? DateTime.now().year;
            if (year < 100) year += 2000;
            if (day >= 1 && day <= 31 && month >= 1 && month <= 12) {
              detectedDate = DateTime(year, month, day);
            }
          }
        }

        line = bodyPart.trim();
        if (line.isEmpty) continue;
      }

      // STRICT INVALIDATION: Any unbroken number with more than 5 digits is immediately invalid!
      if (RegExp(r'\b\d{6,}\b').hasMatch(line)) {
        unparsed.add(line);
        continue;
      }

      final has5Digits = RegExp(r'\b\d{5}\b').hasMatch(line);
      final isSeriesOnly = RegExp(r'^\s*\(?\d{1,4}[a-z]?\)?\s*[:=-]?\s*$', caseSensitive: false).hasMatch(line);
      if (has5Digits || isSeriesOnly) {
        line = line.replaceFirst(RegExp(r'\s+\d{1,2}:\d{2}\s*(?:am|pm)\b', caseSensitive: false), '').trim();
      }

      bool isDateOrShiftHeader = false;

      // 1. Shift Tag
      if (_autoDetectShift) {
        if (RegExp(r'(?:=|\b)(?:dear\s*)?1(?:\.00|:00|\.)?\s*pm\b|morning|^\s*dear\s*1(?:\.00|:00|\.)?\s*(?:pm|baje)?\s*$|^\s*1(?:\.00|:00|\.)?\s*(?:pm|baje)\s*$', caseSensitive: false).hasMatch(line)) {
          detectedShift = 'Dear 1 PM';
          isDateOrShiftHeader = true;
        } else if (RegExp(r'(?:=|\b)(?:dear\s*)?6(?:\.00|:00|\.)?\s*pm\b|^\bday\b$|^\s*dear\s*6(?:\.00|:00|\.)?\s*(?:pm|baje)?\s*$|^\s*6(?:\.00|:00|\.)?\s*(?:pm|baje)\s*$', caseSensitive: false).hasMatch(line)) {
          detectedShift = 'Dear 6 PM';
          isDateOrShiftHeader = true;
        } else if (RegExp(r'(?:=|\b)(?:dear\s*)?8(?:\.00|:00|\.)?\s*pm\b|^\b(?:night|evening)\b$|^\s*dear\s*8(?:\.00|:00|\.)?\s*(?:pm|baje)?\s*$|^\s*8(?:\.00|:00|\.)?\s*(?:pm|baje)\s*$', caseSensitive: false).hasMatch(line)) {
          detectedShift = 'Dear 8 PM';
          isDateOrShiftHeader = true;
        }
      }

      // 2. Date Tag
      if (_autoDetectDate) {
        final fullDateMatch = RegExp(r'\b(\d{1,2})[=\/\.-](\d{1,2})[=\/\.-](\d{2,4})\b').firstMatch(line);
        final shortDateMatch = RegExp(r'\b(\d{1,2})[=\/\.-](\d{1,2})\b').firstMatch(line);
        final dateMatch = fullDateMatch ?? shortDateMatch;
        if (dateMatch != null) {
          final day = int.tryParse(dateMatch.group(1) ?? '') ?? 1;
          final month = int.tryParse(dateMatch.group(2) ?? '') ?? 1;
          int year = dateMatch.groupCount >= 3 && dateMatch.group(3) != null
              ? (int.tryParse(dateMatch.group(3)!) ?? DateTime.now().year)
              : DateTime.now().year;
          if (year < 100) year += 2000;
          if (day >= 1 && day <= 31 && month >= 1 && month <= 12) {
            detectedDate = DateTime(year, month, day);
            isDateOrShiftHeader = true;
          }
        } else if (RegExp(r'\b(?:kal|tomorrow)\b', caseSensitive: false).hasMatch(line)) {
          detectedDate = DateTime.now().add(const Duration(days: 1));
          isDateOrShiftHeader = true;
        } else if (RegExp(r'\b(?:aaj|today)\b', caseSensitive: false).hasMatch(line)) {
          detectedDate = DateTime.now();
          isDateOrShiftHeader = true;
        }
      }

      // Skip party/metadata lines without tickets
      if (RegExp(r'^\s*(?:wakil|sk|booking|bokakg|updated|note|total)\b', caseSensitive: false).hasMatch(line) &&
          !RegExp(r'\b\d{5}\b').hasMatch(line)) {
        continue;
      }

      if (isDateOrShiftHeader && !RegExp(r'\b\d{5}\b').hasMatch(line)) {
        continue;
      }

      // 3. Standalone Series line
      final seriesOnlyMatch = RegExp(r'^\s*(?:series|serial|sere|sereis)?\s*[:=-]?\s*\(?(\d{1,4})[a-z]?\)?\s*[:=-]?\s*$', caseSensitive: false).firstMatch(line);
      if (seriesOnlyMatch != null && !RegExp(r'\b\d{5}\b').hasMatch(line)) {
        currentSeries = seriesOnlyMatch.group(1) ?? currentSeries;
        continue;
      }

      // 4. Parse Tickets:
      int previousCount = items.length;

      // Range format e.g. "12- 31112-20", "12- 12345-9", "31112 to 31120", "28311--28315"
      final explicitRangeMatch = RegExp(
        r'^(?:\(?(\d{1,4})[a-z]?\)?\s*[=\-*\/#:\._,~@|\\!\$%\^&+\s]+)?(\d{5})\s*(?:--|\s+to\s+|-)(\d{1,5})(?:\s*[-=x*:\s]\s*(\d+))?\s*$',
        caseSensitive: false,
      ).firstMatch(line);

      bool handledAsRange = false;
      if (explicitRangeMatch != null) {
        final seriesPart = explicitRangeMatch.group(1);
        final startTkt = explicitRangeMatch.group(2)!;
        final endPart = explicitRangeMatch.group(3)!;
        final countPart = explicitRangeMatch.group(4);

        final isExplicit = line.contains('--') || line.toLowerCase().contains('to') || countPart != null;
        final isShortShare = standardShares.contains(endPart.trim());

        final expandedNumbers = _expandTicketRange(startTkt, endPart);
        // If series prefix is given (e.g. "12- 31112-20") or explicit range or expandedNumbers is valid, treat as RANGE!
        if (expandedNumbers != null && expandedNumbers.isNotEmpty && (seriesPart != null || isExplicit || !isShortShare || expandedNumbers.length > 1)) {
          final s = seriesPart != null ? _cleanSeries(seriesPart, fallback: currentSeries) : currentSeries;
          currentSeries = s;
          final price = _getPriceForSeries(s);
          for (final tNo in expandedNumbers) {
            items.add(_ParsedItem(
              series: s,
              ticketNo: tNo,
              quantity: 1,
              pricePerTicket: price,
            ));
          }
          handledAsRange = true;
        }
      }

      if (handledAsRange) continue;

      // Pattern B: Suffix Series format (e.g. 57952 -60, 52725 -40, 27269-12)
      final suffixSeriesMatch = RegExp(
        r'^(\d{5})\s*[=\-*\/#:\._,~@|\\!\$%\^&+\s]+\s*\(?(\d{1,4})[a-z]?\)?(?:\s*[-=x*:\s]\s*(\d+))?\s*$',
        caseSensitive: false,
      ).firstMatch(line);

      if (suffixSeriesMatch != null) {
        final s = _cleanSeries(suffixSeriesMatch.group(2)!, fallback: currentSeries);
        currentSeries = s;
        final tNo = suffixSeriesMatch.group(1)!;
        final qty = int.tryParse(suffixSeriesMatch.group(3) ?? '1') ?? 1;
        final price = _getPriceForSeries(s);
        items.add(_ParsedItem(
          series: s,
          ticketNo: tNo,
          quantity: qty > 0 ? qty : 1,
          pricePerTicket: price,
        ));
        continue;
      }

      // Pattern C: Prefix Series format (e.g. 12=14371, 6=09379, 12-46751)
      final prefixTktMatch = RegExp(
        r'^\(?(\d{1,4})[a-z]?\)?\s*[=\-*\/#:\._,~@|\\!\$%\^&+\s]*\s*(\d{5})(?:\s*[-=x*:\s]\s*(\d+))?\s*$',
        caseSensitive: false,
      ).firstMatch(line);

      if (prefixTktMatch != null) {
        final s = _cleanSeries(prefixTktMatch.group(1)!, fallback: currentSeries);
        currentSeries = s;
        final tNo = prefixTktMatch.group(2)!;
        final qty = int.tryParse(prefixTktMatch.group(3) ?? '1') ?? 1;
        final price = _getPriceForSeries(s);
        items.add(_ParsedItem(
          series: s,
          ticketNo: tNo,
          quantity: qty > 0 ? qty : 1,
          pricePerTicket: price,
        ));
        continue;
      }

      // Pattern D: Plain 5-digit tickets (single or multiple on same line)
      final all5Digits = RegExp(r'\b\d{5}\b').allMatches(line);
      if (all5Digits.isNotEmpty) {
        final leadSeriesMatch = RegExp(r'^\s*\(?(\d{1,4})[a-z]?\)?\s*[-=:\s]').firstMatch(line);
        if (leadSeriesMatch != null) {
          currentSeries = _cleanSeries(leadSeriesMatch.group(1)!, fallback: currentSeries);
        }
        final price = _getPriceForSeries(currentSeries);
        for (final m in all5Digits) {
          final tNo = m.group(0)!;
          items.add(_ParsedItem(
            series: currentSeries,
            ticketNo: tNo,
            quantity: 1,
            pricePerTicket: price,
          ));
        }
        continue;
      }

      if (items.length == previousCount) {
        unparsed.add(line);
      }
    }

    setState(() {
      _parsedItems = items;
      _unparsedLines = unparsed;
      if (_autoDetectShift) {
        _selectedShift = detectedShift;
      }
      if (_autoDetectDate) {
        _selectedDate = detectedDate;
      }
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      _rawTextCtrl.text = data.text!;
      _parseRawText(data.text!);
    }
  }

  void _applySeriesToAll(String newSeries) {
    final clean = _cleanSeries(newSeries);
    setState(() {
      _fallbackSeries = clean;
      final price = _getPriceForSeries(clean);
      for (final it in _parsedItems) {
        it.series = clean;
        it.pricePerTicket = price;
      }
    });
  }

  Future<void> _confirmAndBookAll() async {
    if (_parsedItems.isEmpty) return;

    final customer = _customerCtrl.text.trim().isNotEmpty ? _customerCtrl.text.trim() : 'Walk-in Customer';
    final drawCode = _selectedShift.replaceAll(RegExp(r'\s+'), '-').toUpperCase();

    setState(() => _isSaving = true);

    try {
      final List<TicketSaleModel> salesToSave = [];
      int index = 0;

      for (final item in _parsedItems) {
        index++;
        final uniqueSalt = math.Random().toString().substring(2, 8);
        final saleId = 'tkt_parse_${DateTime.now().millisecondsSinceEpoch}_${uniqueSalt}_${item.series}_${item.ticketNo}_$index';
        final recNo = 'REC-${item.series}-${item.ticketNo}';

        salesToSave.add(TicketSaleModel(
          id: saleId,
          receiptNumber: recNo,
          buyerName: customer,
          buyerPhone: '',
          agentCode: 'AG-POS',
          agentName: customer,
          drawCode: drawCode,
          drawName: _selectedShift,
          ticketSeries: item.series,
          ticketNumber: '${item.series} ${item.ticketNo}',
          quantity: item.quantity,
          pricePerTicket: item.pricePerTicket,
          totalAmount: item.totalAmount,
          commissionAmount: item.totalAmount * 0.05,
          status: TicketStatus.sold,
          paymentMode: PaymentMode.cash,
          saleDate: DateTime.now(),
          drawDate: _selectedDate,
        ));
      }

      await ref.read(ticketSalesViewModelProvider.notifier).addTicketSalesBulk(salesToSave);

      try {
        final existingCustomers = ref.read(sellerCustomerViewModelProvider).sellers;
        final match = existingCustomers.any((c) => c.name.trim().toLowerCase() == customer.toLowerCase());
        if (!match && customer.toLowerCase() != 'walk-in customer') {
          final newCust = SellerCustomerModel(
            id: 'cust_${DateTime.now().millisecondsSinceEpoch}',
            name: customer,
            accessKey: customer.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''),
            password: '123',
            phone: '',
            createdAt: DateTime.now(),
          );
          await DatabaseService.instance.insertSellerCustomer(newCust);
          ref.read(sellerCustomerViewModelProvider.notifier).loadSellers();
        }
      } catch (_) {}

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
                const SizedBox(width: 10),
                Text(
                  '✅ Successfully Booked ${salesToSave.length} Number(s) for "$customer" ($_selectedShift)!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error saving numbers: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableSeries = ref.watch(seriesPriceViewModelProvider).seriesList;
    final registeredCustomers = ref.watch(sellerCustomerViewModelProvider).sellers;

    int totalTickets = 0;
    double totalAmount = 0.0;
    final Map<String, int> seriesBreakdown = {};

    for (final it in _parsedItems) {
      totalTickets += it.quantity;
      totalAmount += it.totalAmount;
      seriesBreakdown[it.series] = (seriesBreakdown[it.series] ?? 0) + it.quantity;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Container(
        width: 1120,
        height: 720,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary.withAlpha(120),
            width: 1.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(200),
              blurRadius: 32,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          children: [
            // TOP HEADER BAR
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(19),
                  topRight: Radius.circular(19),
                ),
                border: Border(bottom: BorderSide(color: Color(0xFF334155))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(40),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.paste_rounded, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NUMBER BOOKING TEXT PARSER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                        Text(
                          'Paste raw WhatsApp / Parcha text to automatically extract party, shift, date & numbers',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste_go_rounded, size: 16),
                    label: const Text('PASTE CLIPBOARD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // MAIN TWO-COLUMN WORKSPACE
            Expanded(
              child: Row(
                children: [
                  // LEFT PANEL: TEXT INPUT & SESSION CONTROLS
                  Container(
                    width: 440,
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF131D31),
                      border: Border(right: BorderSide(color: Color(0xFF334155))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Party / Customer Name', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Autocomplete<String>(
                                    initialValue: TextEditingValue(text: _customerCtrl.text),
                                    optionsBuilder: (textEditingValue) {
                                      if (textEditingValue.text.isEmpty) {
                                        return registeredCustomers.map((c) => c.name);
                                      }
                                      return registeredCustomers
                                          .where((c) => c.name.toLowerCase().contains(textEditingValue.text.toLowerCase()))
                                          .map((c) => c.name);
                                    },
                                    onSelected: (val) {
                                      _customerCtrl.text = val;
                                      setState(() {});
                                    },
                                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                                      return TextField(
                                        controller: controller..text = _customerCtrl.text,
                                        focusNode: focusNode,
                                        onChanged: (v) => _customerCtrl.text = v,
                                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          prefixIcon: const Icon(Icons.person_rounded, size: 16, color: AppColors.primary),
                                          hintText: 'Customer name',
                                          hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                                          filled: true,
                                          fillColor: const Color(0xFF1E293B),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Draw Date', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                InkWell(
                                  onTap: () async {
                                    final p = await showDatePicker(
                                      context: context,
                                      initialDate: _selectedDate,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2030),
                                      builder: (ctx, child) => Theme(
                                        data: ThemeData.dark().copyWith(
                                          colorScheme: const ColorScheme.dark(
                                            primary: AppColors.primary,
                                            onPrimary: Colors.black,
                                            surface: Color(0xFF1E293B),
                                          ),
                                        ),
                                        child: child!,
                                      ),
                                    );
                                    if (p != null) {
                                      setState(() {
                                        _selectedDate = p;
                                        _autoDetectDate = false;
                                      });
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF334155)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.calendar_month_rounded, size: 15, color: AppColors.primary),
                                        const SizedBox(width: 6),
                                        Text(
                                          DateFormat('dd/MM/yy').format(_selectedDate),
                                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        const Text('Draw Shift Timing', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Row(
                          children: ['Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'].map((shift) {
                            final isSel = _selectedShift.toLowerCase().contains(shift.substring(5, 6));
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(shift, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  selected: isSel,
                                  selectedColor: AppColors.primary,
                                  labelStyle: TextStyle(color: isSel ? Colors.white : Colors.grey.shade400),
                                  onSelected: (sel) {
                                    if (sel) {
                                      setState(() {
                                        _selectedShift = shift;
                                        _autoDetectShift = false;
                                      });
                                    }
                                  },
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            const Text('Default Series: ', style: TextStyle(color: Colors.grey, fontSize: 11.5, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF334155)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: availableSeries.any((s) => s.seriesName.replaceAll(RegExp(r'\D'), '') == _fallbackSeries)
                                      ? _fallbackSeries
                                      : (availableSeries.isNotEmpty ? availableSeries.first.seriesName : '12'),
                                  isDense: true,
                                  dropdownColor: const Color(0xFF1E293B),
                                  style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12),
                                  items: availableSeries.map((s) {
                                    final clean = s.seriesName.replaceAll(RegExp(r'\D'), '');
                                    return DropdownMenuItem(
                                      value: clean.isNotEmpty ? clean : s.seriesName,
                                      child: Text('Series ${s.seriesName} (₹${s.ticketPrice.toStringAsFixed(0)})'),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) _applySeriesToAll(val);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Row(
                            children: [
                              const Text('Live Color Code: ', style: TextStyle(color: Colors.grey, fontSize: 10.5, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 4),
                              _buildLegendTag('🟢 Valid 5-Digit', const Color(0xFF4ADE80), const Color(0xFF14532D)),
                              const SizedBox(width: 6),
                              _buildLegendTag('🔴 Invalid / >5 Digit', const Color(0xFFF87171), const Color(0xFF7F1D1D)),
                              const SizedBox(width: 6),
                              _buildLegendTag('🔵 Shift', const Color(0xFF38BDF8), const Color(0xFF0369A1)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // LEFT TEXT EDITOR SEARCH & JUMP BAR
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B1120),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.find_in_page_rounded, size: 16, color: Colors.cyanAccent),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _leftSearchCtrl,
                                  onChanged: (v) => _performLeftSearch(v, jumpNext: true),
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    hintText: 'Search text in left box...',
                                    hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                                  ),
                                ),
                              ),
                              if (_leftSearchMatchCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.cyan.withAlpha(40),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.cyanAccent.withAlpha(100)),
                                  ),
                                  child: Text(
                                    '${_currentLeftSearchIndex + 1}/$_leftSearchMatchCount',
                                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              IconButton(
                                icon: const Icon(Icons.arrow_upward_rounded, size: 15, color: Colors.grey),
                                tooltip: 'Previous Match',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                onPressed: _leftSearchMatchCount > 0
                                    ? () => _performLeftSearch(_leftSearchCtrl.text, jumpNext: false)
                                    : null,
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_downward_rounded, size: 15, color: Colors.grey),
                                tooltip: 'Next Match',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                onPressed: _leftSearchMatchCount > 0
                                    ? () => _performLeftSearch(_leftSearchCtrl.text, jumpNext: true)
                                    : null,
                              ),
                              if (_leftSearchCtrl.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 14, color: Colors.grey),
                                  tooltip: 'Clear search',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                  onPressed: () {
                                    _leftSearchCtrl.clear();
                                    _performLeftSearch('', jumpNext: false);
                                  },
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),

                        // FAST 2-BOX RANGE & NUMBER ENTRY BAR (Series + From 5-Digits + To Max 3-Digits)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF2563EB).withAlpha(150)),
                          ),
                          child: Row(
                            children: [
                              // Series Input
                              SizedBox(
                                width: 80,
                                height: 32,
                                child: TextField(
                                  controller: _quickSeriesCtrl,
                                  focusNode: _quickSeriesFocusNode,
                                  textCapitalization: TextCapitalization.characters,
                                  textInputAction: TextInputAction.next,
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyanAccent, fontSize: 12),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'Ser ($_fallbackSeries)',
                                    hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 10.5),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                    filled: true,
                                    fillColor: const Color(0xFF1E293B),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.5)),
                                  ),
                                  onSubmitted: (val) {
                                    final s = val.trim().isNotEmpty ? val.trim().toUpperCase() : _fallbackSeries;
                                    _fallbackSeries = s;
                                    _quickSeriesCtrl.text = s;
                                    _quickFromTicketFocusNode.requestFocus();
                                  },
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Box 1: From (Strictly 5-Digits Only)
                              Expanded(
                                flex: 3,
                                child: SizedBox(
                                  height: 32,
                                  child: TextField(
                                    controller: _quickFromTicketCtrl,
                                    focusNode: _quickFromTicketFocusNode,
                                    maxLength: 5,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.next,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(5),
                                    ],
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Color(0xFF4ADE80), fontSize: 13),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      counterText: '',
                                      hintText: 'From (5-Digits) *',
                                      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      filled: true,
                                      fillColor: const Color(0xFF1E293B),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF4ADE80), width: 1.5)),
                                    ),
                                    onSubmitted: (_) {
                                      if (_quickToRangeCtrl.text.isNotEmpty) {
                                        _addQuickRangeToParser();
                                      } else {
                                        _quickToRangeFocusNode.requestFocus();
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Box 2: To Range End (Strictly Max 3-Digits Only)
                              Expanded(
                                flex: 2,
                                child: SizedBox(
                                  height: 32,
                                  child: TextField(
                                    controller: _quickToRangeCtrl,
                                    focusNode: _quickToRangeFocusNode,
                                    maxLength: 3,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.done,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(3),
                                    ],
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.amberAccent, fontSize: 13),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      counterText: '',
                                      hintText: 'To (Max 3-Dig)',
                                      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      filled: true,
                                      fillColor: const Color(0xFF1E293B),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.amberAccent, width: 1.5)),
                                    ),
                                    onSubmitted: (_) => _addQuickRangeToParser(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // + Add Button
                              SizedBox(
                                height: 32,
                                child: ElevatedButton.icon(
                                  onPressed: _addQuickRangeToParser,
                                  icon: const Icon(Icons.add, size: 14),
                                  label: const Text('ADD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),

                        Expanded(
                          child: Stack(
                            children: [
                              Scrollbar(
                                controller: _rawTextScrollCtrl,
                                thumbVisibility: true,
                                radius: const Radius.circular(6),
                                child: TextField(
                                  controller: _rawTextCtrl,
                                  focusNode: _rawTextFocusNode,
                                  scrollController: _rawTextScrollCtrl,
                                  maxLines: null,
                                  maxLength: null,
                                  keyboardType: TextInputType.multiline,
                                  expands: true,
                                  textAlignVertical: TextAlignVertical.top,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    fontSize: 12.5,
                                    height: 1.45,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Paste message text here...\n\nExample formats:\nSk\nDear 1 PM\n12- 15204\n24 57655\n36**88060\n36 65491-95-5\n12- 18255 = 10\n12- 15204, 15205, 15206',
                                    hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.4),
                                    filled: true,
                                    fillColor: const Color(0xFF0B1120),
                                    contentPadding: const EdgeInsets.fromLTRB(14, 14, 36, 28),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(color: Color(0xFF334155)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(color: Color(0xFF334155)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                                    ),
                                  ),
                                ),
                              ),
                              if (_rawTextCtrl.text.isNotEmpty)
                                Positioned(
                                  top: 6,
                                  right: 12,
                                  child: IconButton(
                                    icon: const Icon(Icons.clear_rounded, color: Colors.grey, size: 18),
                                    tooltip: 'Clear input',
                                    onPressed: () {
                                      _rawTextCtrl.clear();
                                      setState(() => _parsedItems = []);
                                    },
                                  ),
                                ),
                              if (_rawTextCtrl.text.isNotEmpty)
                                Positioned(
                                  bottom: 6,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B).withAlpha(220),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(color: const Color(0xFF334155)),
                                    ),
                                    child: Text(
                                      '${_rawTextCtrl.text.split('\n').where((l) => l.trim().isNotEmpty).length} lines | ${_rawTextCtrl.text.length} chars',
                                      style: const TextStyle(
                                        color: Colors.cyanAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
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

                  // RIGHT PANEL: LIVE PARSED PREVIEW TABLE
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          decoration: const BoxDecoration(
                            color: Color(0xFF1E293B),
                            border: Border(bottom: BorderSide(color: Color(0xFF334155))),
                          ),
                          child: Row(
                            children: [
                              _buildMetricCard(
                                title: 'TOTAL TICKETS',
                                value: '$totalTickets',
                                color: Colors.cyanAccent,
                                icon: Icons.confirmation_number_rounded,
                              ),
                              const SizedBox(width: 14),
                              _buildMetricCard(
                                title: 'TOTAL AMOUNT',
                                value: '₹${totalAmount.toStringAsFixed(2)}',
                                color: Colors.greenAccent,
                                icon: Icons.currency_rupee_rounded,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF334155)),
                                  ),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          setState(() => _selectedSeriesFilter = 'All');
                                        },
                                        borderRadius: BorderRadius.circular(5),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: _selectedSeriesFilter == 'All' ? const Color(0xFF7C3AED) : const Color(0xFF7C3AED).withAlpha(30),
                                            borderRadius: BorderRadius.circular(5),
                                            border: Border.all(
                                              color: _selectedSeriesFilter == 'All' ? Colors.purpleAccent : const Color(0xFF7C3AED).withAlpha(100),
                                              width: _selectedSeriesFilter == 'All' ? 1.4 : 1.0,
                                            ),
                                          ),
                                          child: Text(
                                            'ALL: $totalTickets',
                                            style: TextStyle(
                                              color: _selectedSeriesFilter == 'All' ? Colors.white : Colors.purple.shade200,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                      ...seriesBreakdown.entries.map((e) {
                                        final isSel = _selectedSeriesFilter == e.key;
                                        return InkWell(
                                          onTap: () {
                                            setState(() {
                                              _selectedSeriesFilter = isSel ? 'All' : e.key;
                                            });
                                          },
                                          borderRadius: BorderRadius.circular(5),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isSel ? const Color(0xFF7C3AED) : const Color(0xFF7C3AED).withAlpha(30),
                                              borderRadius: BorderRadius.circular(5),
                                              border: Border.all(
                                                color: isSel ? Colors.purpleAccent : const Color(0xFF7C3AED).withAlpha(100),
                                                width: isSel ? 1.4 : 1.0,
                                              ),
                                            ),
                                            child: Text(
                                              'S-${e.key}: ${e.value}',
                                              style: TextStyle(
                                                color: isSel ? Colors.white : Colors.purpleAccent,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Unrecognized / Invalid Lines Warning Banner
                        if (_unparsedLines.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            decoration: BoxDecoration(
                              color: const Color(0xFF450A0A).withAlpha(180),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.redAccent.shade200, width: 1.4),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.redAccent.withAlpha(40),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      '⚠️ ${_unparsedLines.length} Invalid / >5 Digit Line(s) (Click to Jump & Edit):',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withAlpha(50),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'INVALID',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Ye number 5-digit se bada hai ya ticket format me match nahi hua. Click karke seedha theek karein:',
                                  style: TextStyle(color: Colors.grey.shade300, fontSize: 11.5),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 7,
                                  runSpacing: 6,
                                  children: _unparsedLines.map((unp) {
                                    return Tooltip(
                                      message: 'Click karke left box me is line par jayein aur edit karein',
                                      child: InkWell(
                                        onTap: () => _jumpToUnparsedLine(unp),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E293B),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.redAccent.shade200.withAlpha(160), width: 1.2),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.edit_note_rounded, size: 14, color: Colors.redAccent),
                                              const SizedBox(width: 5),
                                              ConstrainedBox(
                                                constraints: const BoxConstraints(maxWidth: 220),
                                                child: Text(
                                                  unp,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Color(0xFFFCA5A5),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'monospace',
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Icon(Icons.arrow_back_rounded, size: 12, color: Colors.amberAccent),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),

                        if (_parsedItems.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (v) => setState(() => _searchQuery = v.trim()),
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'Search parsed ticket no, series…',
                                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.purpleAccent),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.grey),
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: const Color(0xFF0F172A),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFF334155)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFF334155)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Colors.purpleAccent, width: 1.4),
                                ),
                              ),
                            ),
                          ),

                        Expanded(
                          child: _parsedItems.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.format_list_bulleted_rounded, size: 48, color: Colors.grey.shade700),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No tickets parsed yet',
                                        style: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Paste or type ticket text in the left panel to see live preview',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                )
                              : Builder(
                                  builder: (context) {
                                    final displayedItems = _parsedItems.where((it) {
                                      final matchesSeries = _selectedSeriesFilter == 'All' || it.series == _selectedSeriesFilter;
                                      final q = _searchQuery.toLowerCase();
                                      final matchesSearch = q.isEmpty ||
                                          it.ticketNo.contains(q) ||
                                          it.series.toLowerCase().contains(q);
                                      return matchesSeries && matchesSearch;
                                    }).toList();
                                    if (displayedItems.isEmpty) {
                                      return Center(
                                        child: Text(
                                          'No tickets found for Series $_selectedSeriesFilter',
                                          style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                        ),
                                      );
                                    }
                                    return ListView.separated(
                                      padding: const EdgeInsets.all(12),
                                      itemCount: displayedItems.length,
                                      separatorBuilder: (ctx, i) => const Divider(color: Color(0xFF1E293B), height: 1),
                                      itemBuilder: (context, idx) {
                                        final item = displayedItems[idx];
                                        return InkWell(
                                          onTap: () => _editParsedItem(item),
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                            decoration: BoxDecoration(
                                              color: idx % 2 == 0 ? const Color(0xFF111C33) : const Color(0xFF0F172A),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  width: 32,
                                                  child: Text(
                                                    '#${idx + 1}',
                                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary.withAlpha(40),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    'Series ${item.series}',
                                                    style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11.5),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF14532D).withAlpha(160),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: const Color(0xFF4ADE80).withAlpha(130)),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF4ADE80)),
                                                      SizedBox(width: 3),
                                                      Text(
                                                        '5-DIGIT',
                                                        style: TextStyle(color: Color(0xFF4ADE80), fontSize: 9.5, fontWeight: FontWeight.w900),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    '${item.series} ${item.ticketNo}',
                                                    style: const TextStyle(
                                                      color: Color(0xFF4ADE80),
                                                      fontWeight: FontWeight.w900,
                                                      fontSize: 14,
                                                      fontFamily: 'monospace',
                                                      letterSpacing: 1.1,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  'Qty: ${item.quantity}',
                                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                                ),
                                                const SizedBox(width: 16),
                                                Text(
                                                  '₹${item.pricePerTicket.toStringAsFixed(0)}',
                                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                                ),
                                                const SizedBox(width: 16),
                                                Text(
                                                  '₹${item.totalAmount.toStringAsFixed(2)}',
                                                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                                ),
                                                const SizedBox(width: 8),
                                                IconButton(
                                                  icon: const Icon(Icons.edit_note_rounded, color: Colors.cyanAccent, size: 20),
                                                  tooltip: 'Edit Entry',
                                                  onPressed: () => _editParsedItem(item),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                                  tooltip: 'Remove',
                                                  onPressed: () {
                                                    setState(() => _parsedItems.remove(item));
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // BOTTOM ACTION FOOTER BAR
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(19),
                  bottomRight: Radius.circular(19),
                ),
                border: Border(top: BorderSide(color: Color(0xFF334155))),
              ),
              child: Row(
                children: [
                  Text(
                    'Target: ${_customerCtrl.text.isNotEmpty ? _customerCtrl.text : 'Walk-in'} | Shift: $_selectedShift | Date: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                      side: const BorderSide(color: Color(0xFF475569)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('CANCEL'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_rounded, size: 18),
                    label: Text(
                      _isSaving ? 'BOOKING...' : '⚡ CONFIRM & BOOK ALL ($totalTickets NUMBERS)',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.8),
                    ),
                    onPressed: (_parsedItems.isEmpty || _isSaving) ? null : _confirmAndBookAll,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: Colors.grey.shade400, fontSize: 10, fontWeight: FontWeight.bold)),
              Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendTag(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor.withAlpha(120),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: textColor.withAlpha(100)),
      ),
      child: Text(
        label,
        style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}