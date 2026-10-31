import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/pattern_matcher_service.dart';

/// Visual Syntax Highlighting Controller for Pattern Resolver & Review Queue
class _PatternSyntaxHighlightingController extends TextEditingController {
  _PatternSyntaxHighlightingController();

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

    const purpleStyle = TextStyle(
      color: Color(0xFFC084FC),
      backgroundColor: Color(0x706B21A8),
      fontWeight: FontWeight.bold,
    );
    const greenStyle = TextStyle(
      color: Color(0xFF4ADE80),
      backgroundColor: Color(0x7014532D),
      fontWeight: FontWeight.bold,
    );
    const cyanStyle = TextStyle(
      color: Color(0xFF38BDF8),
      backgroundColor: Color(0x600369A1),
      fontWeight: FontWeight.bold,
    );
    const dateStyle = TextStyle(
      color: Color(0xFF818CF8),
      backgroundColor: Color(0x603730A3),
      fontWeight: FontWeight.bold,
    );
    const greyStyle = TextStyle(
      color: Color(0xFF94A3B8),
      fontStyle: FontStyle.italic,
    );

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isLastLine = i == lines.length - 1;
      final lineEnding = isLastLine ? '' : '\n';

      if (line.trim().isEmpty) {
        spans.add(TextSpan(text: line + lineEnding, style: style));
        continue;
      }

      final trimmed = line.trim();

      // 1. Shift Tag e.g. "1pm", "6pm", "8pm", "morning"
      if (RegExp(r'(?:=|\b)(?:dear\s*)?[168](?::00|\.00|\.)?\s*(?:pm|am|qm|gm|baje)\b|^\s*(?:morning|day|night|evening)\b', caseSensitive: false).hasMatch(trimmed) &&
          !RegExp(r'\b\d{5}\b').hasMatch(trimmed)) {
        spans.add(TextSpan(
          text: line + lineEnding,
          style: (style ?? const TextStyle()).merge(cyanStyle),
        ));
        continue;
      }

      // 2. Date Tag e.g. "8/6/2026", "08/06/26"
      if (RegExp(r'\b\d{1,2}[\/\.-]\d{1,2}(?:[\/\.-]\d{2,4})?\b').hasMatch(trimmed) &&
          !RegExp(r'\b\d{5}\b').hasMatch(trimmed)) {
        spans.add(TextSpan(
          text: line + lineEnding,
          style: (style ?? const TextStyle()).merge(dateStyle),
        ));
        continue;
      }

      // 3. Standalone Series line e.g. "5", "6", "12", "24", "12c", "(24)"
      if (RegExp(r'^(?:(?:\(|\[)\s*([0-9]{1,3}[A-Za-z]?)\s*(?:\)|\])|(?:series\s*[:=-]?\s*)?([0-9]{1,3}[A-Za-z]?)\s*(?:c|s|sirij|series)?)$', caseSensitive: false).hasMatch(trimmed) &&
          !RegExp(r'\b\d{5}\b').hasMatch(trimmed)) {
        spans.add(TextSpan(
          text: line + lineEnding,
          style: (style ?? const TextStyle()).merge(purpleStyle),
        ));
        continue;
      }

      // 4. Check for 5-digit tickets on line
      final fiveDigitMatches = RegExp(r'\b\d{5}\b').allMatches(line).toList();
      if (fiveDigitMatches.isNotEmpty) {
        final List<TextSpan> lineSpans = [];
        int lastIndex = 0;

        for (final m in fiveDigitMatches) {
          if (m.start > lastIndex) {
            final before = line.substring(lastIndex, m.start);
            if (RegExp(r'[0-9]{1,3}[A-Za-z]?\s*[:=/.\-~*#@+]+|[\(\[][0-9]{1,3}[A-Za-z]?[\)\]]').hasMatch(before)) {
              lineSpans.add(TextSpan(text: before, style: (style ?? const TextStyle()).merge(purpleStyle)));
            } else {
              lineSpans.add(TextSpan(text: before, style: style));
            }
          }

          lineSpans.add(TextSpan(
            text: line.substring(m.start, m.end),
            style: (style ?? const TextStyle()).merge(greenStyle),
          ));

          lastIndex = m.end;
        }

        if (lastIndex < line.length) {
          final after = line.substring(lastIndex);
          if (RegExp(r'[:=/.\-~*#@+]+\s*[0-9]{1,3}[A-Za-z]?').hasMatch(after)) {
            lineSpans.add(TextSpan(text: after, style: (style ?? const TextStyle()).merge(purpleStyle)));
          } else {
            lineSpans.add(TextSpan(text: after, style: style));
          }
        }

        lineSpans.add(TextSpan(text: lineEnding, style: style));
        spans.add(TextSpan(children: lineSpans));
        continue;
      }

      // 5. Header / Ignored noise lines e.g. "Updated", "S.k.bookin", "Ajmal"
      spans.add(TextSpan(
        text: line + lineEnding,
        style: (style ?? const TextStyle()).merge(greyStyle),
      ));
    }

    return TextSpan(children: spans);
  }
}

class PatternResolverDialog extends StatefulWidget {
  final Function(List<ParsedTicketItem> tickets, String sender, String? senderName)? onTicketsResolved;

  const PatternResolverDialog({
    super.key,
    this.onTicketsResolved,
  });

  @override
  State<PatternResolverDialog> createState() => _PatternResolverDialogState();
}

class _PatternResolverDialogState extends State<PatternResolverDialog> {
  List<UnparsedMessage> _unparsedList = [];
  UnparsedMessage? _selectedMessage;
  bool _isLoading = true;

  // Visual text size controller (default 14px)
  double _rawTextFontSize = 14.0;

  // Pattern Resolver Inputs
  final TextEditingController _patternNameCtrl = TextEditingController(text: 'Custom Learned Pattern');
  final TextEditingController _regexCtrl = TextEditingController();
  final TextEditingController _sampleCtrl = _PatternSyntaxHighlightingController();

  int _seriesGroup = 1;
  int _ticketGroup = 2;
  int _qtyGroup = 3;

  List<ParsedTicketItem> _testPreviewTickets = [];
  String? _testError;

  @override
  void initState() {
    super.initState();
    _loadUnparsedMessages();
  }

  @override
  void dispose() {
    _patternNameCtrl.dispose();
    _regexCtrl.dispose();
    _sampleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUnparsedMessages() async {
    setState(() => _isLoading = true);
    final list = await PatternMatcherService.instance.fetchPendingUnparsedMessages();
    if (mounted) {
      setState(() {
        _unparsedList = list;
        _isLoading = false;
        if (list.isNotEmpty) {
          _selectMessage(list.first);
        } else {
          _selectedMessage = null;
        }
      });
    }
  }

  bool _isDateOrShiftText(String raw) {
    final clean = raw.trim();
    final isPureDate = RegExp(r'^\s*(\d{1,2}[=\/\.-]\d{1,2}[=\/\.-]\d{2,4}|\d{1,2}[=\/\.-]\d{1,2}|today|tomorrow|aaj|kal)\s*$', caseSensitive: false).hasMatch(clean);
    final isPureShift = RegExp(r'^\s*(?:=)?\s*(?:dear\s*)?[168]\s*(?:pm|am|gm|baje)\s*$', caseSensitive: false).hasMatch(clean);
    final isPureName = RegExp(r'^(?:name:?\s*)?[A-Za-z]{3,20}\s*(?:boakg|booking|bokg|bok|bkg)$', caseSensitive: false).hasMatch(clean);
    return isPureDate || isPureShift || isPureName;
  }

  String? _detectSeriesFromText(String text) {
    final lines = text.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    // 1. Standalone series line at top or bottom (e.g. "5", "6", "18", "24", "40", "12c", "(24)")
    for (final l in lines) {
      if (RegExp(r'\d{5}').hasMatch(l)) continue;
      if (RegExp(r'\d{1,2}[\/\.-]\d{1,2}').hasMatch(l)) continue;
      if (RegExp(r'\b(?:dear\s*)?[168](?::00|\.00|\.)?\s*(?:pm|am|qm|gm|baje)\b', caseSensitive: false).hasMatch(l)) continue;

      final m = RegExp(r'^(?:(?:\(|\[)\s*([0-9]{1,4}[A-Za-z]?)\s*(?:\)|\])|(?:series\s*[:=-]?\s*)?([0-9]{1,4}[A-Za-z]?)\s*(?:c|s|sirij|series)?)$', caseSensitive: false).firstMatch(l);
      if (m != null) {
        final raw = m.group(1) ?? m.group(2);
        if (raw != null && raw.isNotEmpty) {
          final clean = PatternMatcherService.instance.cleanSeriesNumber(raw);
          final numVal = int.tryParse(clean);
          if (numVal != null && numVal > 0 && numVal <= 5000) {
            return clean;
          }
        }
      }
    }

    // 2. Inline series in ticket lines (e.g. "5=36460", "24/81192", "(24)79159", "12454....40")
    for (final l in lines) {
      if (!RegExp(r'\d{5}').hasMatch(l)) continue;
      final preMatch = RegExp(r'^(?:[\(\[]\s*([0-9]{1,4}[cs]?)\s*[\)\]]|([0-9]{1,4}[cs]?)\s*[:=/.\-~*#@+]+)\s*\d{5}', caseSensitive: false).firstMatch(l);
      if (preMatch != null) {
        final raw = preMatch.group(1) ?? preMatch.group(2);
        if (raw != null && raw.isNotEmpty) return PatternMatcherService.instance.cleanSeriesNumber(raw);
      }
      final sufMatch = RegExp(r'^\d{5}\s*[:=/.\-~*#@+]+\s*([0-9]{1,4}[cs]?)', caseSensitive: false).firstMatch(l);
      if (sufMatch != null) {
        final raw = sufMatch.group(1);
        if (raw != null && raw.isNotEmpty) return PatternMatcherService.instance.cleanSeriesNumber(raw);
      }
    }
    return null;
  }

  void _selectMessage(UnparsedMessage msg) {
    setState(() {
      _selectedMessage = msg;
      _sampleCtrl.text = msg.rawText;
      final detected = _detectSeriesFromText(msg.rawText);
      if (detected != null && detected.isNotEmpty) {
        _selectedSeriesOverride = detected;
      }
      _autoGenerateSuggestedRegex(msg.rawText);
      _runTestParse();
    });
  }

  /// Auto-detects structure and suggests an initial regex
  void _autoGenerateSuggestedRegex(String sample) {
    final lines = sample.split(RegExp(r'[\r\n]+'));
    final firstLine = lines.firstWhere(
      (l) => l.trim().isNotEmpty && RegExp(r'\d{5}').hasMatch(l),
      orElse: () => sample.trim(),
    );

    // Case 1: Combined Shift Tag + Series + 5-Digit Ticket e.g. "8gm12c62393", "8pm12c62393", "8gm 12c 62393"
    if (RegExp(r'(?:[168]\s*(?:gm|pm|am|g|p))?[\s-_=]*([0-9]{1,3}[A-Za-z]?)\s*[-:,\/=\s]*(\d{5})', caseSensitive: false).hasMatch(firstLine)) {
      _regexCtrl.text = r'(?:[168]\s*(?:gm|pm|am|g|p))?[\s-_=]*([0-9]{1,3}[A-Za-z]?)\s*[-:,\/=\s]*(\d{5})(?:\s*[*xX]\s*(\d+))?';
      _seriesGroup = 1;
      _ticketGroup = 2;
      _qtyGroup = 3;
      return;
    }

    // Case 2: Bracket series e.g. "(40) 12345"
    if (RegExp(r'[\(\[]\s*([0-9]{1,3}[A-Za-z]?)\s*[\)\]]\s*[-:,\/=\s]*(\d{5})').hasMatch(firstLine)) {
      _regexCtrl.text = r'[\(\[]\s*([0-9]{1,3}[A-Za-z]?)\s*[\)\]]\s*[-:,\/=\s]*(\d{5})(?:\s*[*xX]\s*(\d+))?';
      _seriesGroup = 1;
      _ticketGroup = 2;
      _qtyGroup = 3;
      return;
    }

    // Case 3: Inverted e.g. "12345=12"
    if (RegExp(r'(\d{5})\s*[-:,\/=]\s*([0-9]{1,3}[A-Za-z]?)').hasMatch(firstLine)) {
      _regexCtrl.text = r'(\d{5})\s*[-:,\/=]\s*([0-9]{1,3}[A-Za-z]?)(?:\s*[*xX]\s*(\d+))?';
      _ticketGroup = 1;
      _seriesGroup = 2;
      _qtyGroup = 3;
      return;
    }

    // Default universal fallback template (Strict: Multipliers are ONLY * or x/X, NEVER hyphen -)
    _regexCtrl.text = r'([0-9]{1,3}[A-Za-z]?)\s*[-:,\/=\s]+\s*(\d{5})(?:\s*[*xX]\s*(\d+))?';
    _seriesGroup = 1;
    _ticketGroup = 2;
    _qtyGroup = 3;
  }

  /// Expands ticket ranges like "72170-71" into ["72170", "72171"]
  List<String>? _expandTicketRange(String startTkt, String endPart) {
    return PatternMatcherService.instance.expandTicketRange(startTkt, endPart);
  }

  void _runTestParse() {
    final pattern = _regexCtrl.text.trim();
    final text = _sampleCtrl.text.trim();

    if (text.isEmpty) {
      setState(() {
        _testPreviewTickets = [];
        _testError = null;
      });
      return;
    }

    try {
      final items = <ParsedTicketItem>[];
      final lines = text.split(RegExp(r'[\r\n]+'));

      // 1. Initial Series: Auto-detect from text or fallback to override
      String currentSeries = _selectedSeriesOverride;
      final detected = _detectSeriesFromText(text);
      if (detected != null && detected.isNotEmpty) {
        currentSeries = detected;
        _selectedSeriesOverride = detected;
      }

      RegExp? regex;
      if (pattern.isNotEmpty) {
        try {
          regex = RegExp(pattern, caseSensitive: false, multiLine: true);
        } catch (_) {}
      }

      for (final line in lines) {
        final l = line.trim();
        if (l.isEmpty) continue;

        // Skip non-ticket header lines e.g. "8/6/26.  Sk. 1:00 pm"
        if (!RegExp(r'\d{5}').hasMatch(l)) {
          final isHeaderOrDateOrShift = RegExp(r'\b\d{1,2}[\/\.-]\d{1,2}(?:[\/\.-]\d{2,4})?\b').hasMatch(l) ||
              RegExp(r'\b(?:dear\s*)?[168](?::00|\.00|\.)?\s*(?:pm|am|qm|gm|baje)\b', caseSensitive: false).hasMatch(l) ||
              RegExp(r'^(?:forwarded|fwd|booking|boakg|note|total)\b', caseSensitive: false).hasMatch(l);
          if (isHeaderOrDateOrShift && !RegExp(r'\b\d{1,3}\b').hasMatch(l)) {
            continue;
          }
        }

        // Header / Standalone Series line (e.g. "5", "6", "18", "24", "12c")
        if (!RegExp(r'\d{5}').hasMatch(l) &&
            !RegExp(r'\d{1,2}[\/\.-]\d{1,2}').hasMatch(l) &&
            !RegExp(r'\b(?:dear\s*)?[168](?::00|\.00|\.)?\s*(?:pm|am|qm|gm|baje)\b', caseSensitive: false).hasMatch(l)) {
          final serMatch = RegExp(r'^(?:(?:\(|\[)\s*([0-9]{1,3}[A-Za-z]?)\s*(?:\)|\])|(?:series\s*[:=-]?\s*)?([0-9]{1,3}[A-Za-z]?)\s*(?:c|s|sirij|series)?)$', caseSensitive: false).firstMatch(l);
          if (serMatch != null) {
            final raw = serMatch.group(1) ?? serMatch.group(2);
            if (raw != null && raw.isNotEmpty) {
              currentSeries = PatternMatcherService.instance.cleanSeriesNumber(raw);
              continue;
            }
          }
        }

        // 🌟 PRIORITY 1: TICKET RANGE EXPANSION ("khol karke save karna hai")
        // Case A: Triplet Range e.g. "5 = 62759-83-25" or "40280-289-10" or "43300-309=10 pcs"
        final tripletMatch = RegExp(
          r'^(?:([0-9]{1,3}[A-Za-z]?)\s*[:=/.\-~*#@+]+)?\s*(\d{5})\s*[-~to]+\s*(\d{1,5})\s*[-=x*,\s]+\s*(\d+)(?:\s*(?:pcs?|go|p))?$',
          caseSensitive: false,
        ).firstMatch(l);
        if (tripletMatch != null) {
          final rawS = tripletMatch.group(1);
          final s = rawS != null ? PatternMatcherService.instance.cleanSeriesNumber(rawS) : currentSeries;
          final startNum = int.tryParse(tripletMatch.group(2)!);
          final count = int.tryParse(tripletMatch.group(4)!);
          if (startNum != null && count != null && count > 0 && count <= 200) {
            for (int k = 0; k < count; k++) {
              items.add(ParsedTicketItem(
                series: s,
                ticketNo: (startNum + k).toString().padLeft(5, '0'),
                quantity: 1,
              ));
            }
            continue;
          }
        }

        // Case B: Comma range or double-dot range e.g. "40350,,59" or "5 = 72170..71"
        final commaMatch = RegExp(
          r'^(?:([0-9]{1,3}[A-Za-z]?)\s*[:=/.\-~*#@+]+)?\s*(\d{5})\s*(?:,,+|\.\.+|___+)\s*(\d{1,3})',
          caseSensitive: false,
        ).firstMatch(l);
        if (commaMatch != null) {
          final rawS = commaMatch.group(1);
          final s = rawS != null ? PatternMatcherService.instance.cleanSeriesNumber(rawS) : currentSeries;
          final expanded = _expandTicketRange(commaMatch.group(2)!, commaMatch.group(3)!);
          if (expanded != null && expanded.isNotEmpty) {
            for (final tNo in expanded) {
              items.add(ParsedTicketItem(series: s, ticketNo: tNo, quantity: 1));
            }
            continue;
          }
        }

        // Case C: Hyphen / "to" / "se" range e.g. "5 = 72170-71", "12- 31112-20", "72170 to 72175"
        final hyphenMatch = RegExp(
          r'^(?:([0-9]{1,3}[A-Za-z]?)\s*[:=/.\-~*#@+]+)?\s*(\d{5})\s*[-~/\s]*(?:to|se|-|\/)\s*(\d{1,5})$',
          caseSensitive: false,
        ).firstMatch(l);
        if (hyphenMatch != null) {
          final rawS = hyphenMatch.group(1);
          final s = rawS != null ? PatternMatcherService.instance.cleanSeriesNumber(rawS) : currentSeries;
          final expanded = _expandTicketRange(hyphenMatch.group(2)!, hyphenMatch.group(3)!);
          if (expanded != null && expanded.isNotEmpty) {
            for (final tNo in expanded) {
              items.add(ParsedTicketItem(series: s, ticketNo: tNo, quantity: 1));
            }
            continue;
          }
        }

        // Try regex match
        bool matchedWithRegex = false;
        if (regex != null) {
          final match = regex.firstMatch(l);
          if (match != null) {
            String s = currentSeries;
            if (_seriesGroup > 0 && match.groupCount >= _seriesGroup) {
              final rawS = match.group(_seriesGroup);
              if (rawS != null && rawS.isNotEmpty) {
                final clean = PatternMatcherService.instance.cleanSeriesNumber(rawS);
                if (clean.isNotEmpty && clean != '?') {
                  s = clean;
                }
              }
            }

            String tNo = '';
            if (_ticketGroup > 0 && match.groupCount >= _ticketGroup) {
              tNo = match.group(_ticketGroup) ?? '';
            }

            int qty = 1;
            if (_qtyGroup > 0 && match.groupCount >= _qtyGroup) {
              final rawQty = match.group(_qtyGroup);
              if (rawQty != null) {
                qty = int.tryParse(rawQty) ?? 1;
              }
            }

            if (tNo.length == 5) {
              items.add(ParsedTicketItem(
                series: s,
                ticketNo: tNo,
                quantity: qty > 0 ? qty : 1,
              ));
              matchedWithRegex = true;
            }
          }
        }

        // Fallback for this line if regex didn't extract
        if (!matchedWithRegex) {
          // Inline prefix e.g. 5=36460, 24/81192, (24)79159, 12..44189
          final preMatch = RegExp(r'^(?:[\(\[]\s*([0-9]{1,3}[cs]?)\s*[\)\]]|([0-9]{1,3}[cs]?)\s*[:=/.\-~*#@+]+)\s*(\d{5})', caseSensitive: false).firstMatch(l);
          if (preMatch != null) {
            final rawS = preMatch.group(1) ?? preMatch.group(2);
            final s = rawS != null ? PatternMatcherService.instance.cleanSeriesNumber(rawS) : currentSeries;
            items.add(ParsedTicketItem(series: s, ticketNo: preMatch.group(3)!, quantity: 1));
            continue;
          }

          // Inline suffix e.g. 36460=5, 12454....40
          final sufMatch = RegExp(r'^(\d{5})\s*[:=/.\-~*#@+]+\s*([0-9]{1,3}[cs]?)', caseSensitive: false).firstMatch(l);
          if (sufMatch != null) {
            final rawS = sufMatch.group(2);
            final s = rawS != null ? PatternMatcherService.instance.cleanSeriesNumber(rawS) : currentSeries;
            items.add(ParsedTicketItem(series: s, ticketNo: sufMatch.group(1)!, quantity: 1));
            continue;
          }

          // Pure 5-digit number(s) on line e.g. "36460"
          final all5s = RegExp(r'\b\d{5}\b').allMatches(l);
          for (final m in all5s) {
            items.add(ParsedTicketItem(
              series: currentSeries,
              ticketNo: m.group(0)!,
              quantity: 1,
            ));
          }
        }
      }

      setState(() {
        _testPreviewTickets = items;
        _testError = items.isEmpty ? 'No 5-digit tickets found in this message.' : null;
      });
    } catch (e) {
      setState(() {
        _testPreviewTickets = [];
        _testError = 'Parse Error: $e';
      });
    }
  }

  String _selectedSeriesOverride = '12';

  void _applySeriesToAll(String newSeries) {
    final clean = PatternMatcherService.instance.cleanSeriesNumber(newSeries, fallback: newSeries.isNotEmpty ? newSeries : '12');
    setState(() {
      _selectedSeriesOverride = clean;
      _testPreviewTickets = _testPreviewTickets.map((t) => ParsedTicketItem(
        series: clean,
        ticketNo: t.ticketNo,
        quantity: t.quantity,
      )).toList();
    });
  }

  Future<void> _saveAndTrainBot() async {
    if (_selectedMessage == null || _testPreviewTickets.isEmpty) return;

    final newPattern = LearnedPattern(
      patternName: _patternNameCtrl.text.trim().isEmpty ? 'Custom Learned Pattern' : _patternNameCtrl.text.trim(),
      regexPattern: _regexCtrl.text.trim(),
      seriesGroupIndex: _seriesGroup,
      ticketGroupIndex: _ticketGroup,
      qtyGroupIndex: _qtyGroup,
      sampleText: _selectedMessage!.rawText,
    );

    // 1. Save pattern to database & memory cache
    await PatternMatcherService.instance.saveLearnedPattern(newPattern);

    // 2. Mark unparsed message as resolved
    await PatternMatcherService.instance.updateUnparsedStatus(_selectedMessage!.id, status: 'resolved');

    // 3. Callback to book tickets into Live UI table
    if (widget.onTicketsResolved != null) {
      widget.onTicketsResolved!(
        _testPreviewTickets,
        _selectedMessage!.senderPhone,
        _selectedMessage!.senderName,
      );
    }

    if (mounted) {
      final bookedCount = _testPreviewTickets.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Bot Learned Pattern! $bookedCount ticket(s) pushed to booking table.'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
      // Keep popup open so user can review the next pending message!
      await _loadUnparsedMessages();
    }
  }

  Future<void> _ignoreCurrentMessage() async {
    if (_selectedMessage == null) return;
    await PatternMatcherService.instance.updateUnparsedStatus(_selectedMessage!.id, status: 'ignored');
    await _loadUnparsedMessages();
  }

  Future<void> _clearAllPendingMessages() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text('Dismiss All Pending Messages?'),
          ],
        ),
        content: const Text('Are you sure you want to dismiss all pending date/setup and unparsed messages?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dismiss All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await PatternMatcherService.instance.clearAllPendingUnparsedMessages();
      await _loadUnparsedMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Container(
        width: 950,
        height: 650,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dialog Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.psychology_rounded, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WhatsApp Pattern Resolver & Bot AI Trainer',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      Text(
                        'Map unknown seller messages to train the bot for 100% future auto-booking accuracy.',
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
            const Divider(color: AppColors.border, height: 24),

            // Content Area
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _unparsedList.isEmpty
                      ? _buildEmptyState()
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Queue List
                            Container(
                              width: 280,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.mark_chat_unread_rounded, size: 16, color: AppColors.warning),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Pending Messages (${_unparsedList.length})',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.orangeAccent),
                                          tooltip: 'Dismiss All Pending Messages',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: _clearAllPendingMessages,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Divider(color: AppColors.border, height: 1),
                                  Expanded(
                                    child: ListView.separated(
                                      itemCount: _unparsedList.length,
                                      separatorBuilder: (_, _) => const Divider(color: AppColors.border, height: 1),
                                      itemBuilder: (context, idx) {
                                        final msg = _unparsedList[idx];
                                        final isSelected = _selectedMessage?.id == msg.id;
                                        final isConfig = _isDateOrShiftText(msg.rawText);

                                        return Material(
                                          color: Colors.transparent,
                                          child: ListTile(
                                            dense: true,
                                            selected: isSelected,
                                            selectedTileColor: AppColors.primary.withValues(alpha: 0.15),
                                            title: Row(
                                              children: [
                                                if (isConfig)
                                                  const Padding(
                                                    padding: EdgeInsets.only(right: 6),
                                                    child: Icon(Icons.calendar_month, size: 13, color: Colors.lightBlueAccent),
                                                  ),
                                                Expanded(
                                                  child: Text(
                                                    msg.senderName ?? msg.senderPhone,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            subtitle: Text(
                                              msg.rawText.replaceAll('\n', ' '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isConfig ? Colors.lightBlueAccent.withAlpha(200) : AppColors.textSecondary,
                                              ),
                                            ),
                                            onTap: () => _selectMessage(msg),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),

                            // Right Mapping & Training Editor
                            Expanded(
                              child: _selectedMessage == null
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.task_alt_rounded, size: 54, color: AppColors.success),
                                          const SizedBox(height: 14),
                                          const Text(
                                            'All Pending Messages Resolved!',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                                          ),
                                          const SizedBox(height: 6),
                                          const Text(
                                            'There are no more unrecognized messages in the review queue.',
                                            style: TextStyle(color: Colors.grey, fontSize: 12),
                                          ),
                                          const SizedBox(height: 20),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.surfaceContainerHigh,
                                              foregroundColor: Colors.white,
                                            ),
                                            onPressed: () {
                                              if (Navigator.of(context, rootNavigator: true).canPop()) {
                                                Navigator.of(context, rootNavigator: true).pop();
                                              }
                                            },
                                            child: const Text('Close'),
                                          ),
                                        ],
                                      ),
                                    )
                                  : SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Informational Banner for Date / Shift Messages
                                          if (_isDateOrShiftText(_selectedMessage!.rawText))
                                            Container(
                                              margin: const EdgeInsets.only(bottom: 12),
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.blueAccent.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5)),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.calendar_today_rounded, color: Colors.lightBlueAccent, size: 20),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      '📅 "${_selectedMessage!.rawText}" is a Draw Date / Shift setup message (not a ticket format).\nThe bot stores this in session for all following tickets. Click "Dismiss" to remove from queue.',
                                                      style: const TextStyle(fontSize: 12, color: Colors.white),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  ElevatedButton.icon(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
                                                      foregroundColor: Colors.white,
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                      visualDensity: VisualDensity.compact,
                                                    ),
                                                    icon: const Icon(Icons.delete_outline, size: 14),
                                                    label: const Text('DISMISS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                                    onPressed: _ignoreCurrentMessage,
                                                  ),
                                                ],
                                              ),
                                            ),

                                          // Raw Message Box Header with Zoom / Text Size Controller & Legend
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  const Text(
                                                    'Raw Incoming Text:',
                                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF6B21A8).withAlpha(120),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: const Color(0xFFC084FC).withAlpha(150)),
                                                    ),
                                                    child: const Text('Series (Purple)', style: TextStyle(color: Color(0xFFC084FC), fontSize: 10, fontWeight: FontWeight.bold)),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF14532D).withAlpha(150),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: const Color(0xFF4ADE80).withAlpha(150)),
                                                    ),
                                                    child: const Text('Tickets (Green)', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 10, fontWeight: FontWeight.bold)),
                                                  ),
                                                ],
                                              ),
                                              // Text Size Zoom Controller
                                              Row(
                                                children: [
                                                  const Text('Text Size:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                                  const SizedBox(width: 4),
                                                  IconButton(
                                                    icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.white70),
                                                    tooltip: 'Decrease text size',
                                                    visualDensity: VisualDensity.compact,
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(),
                                                    onPressed: _rawTextFontSize > 11.0
                                                        ? () => setState(() => _rawTextFontSize -= 1.0)
                                                        : null,
                                                  ),
                                                  Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6),
                                                    child: Text(
                                                      '${_rawTextFontSize.toInt()}px',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amberAccent),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.add_circle_outline, size: 18, color: Colors.white70),
                                                    tooltip: 'Increase text size',
                                                    visualDensity: VisualDensity.compact,
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(),
                                                    onPressed: _rawTextFontSize < 24.0
                                                        ? () => setState(() => _rawTextFontSize += 1.0)
                                                        : null,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: _sampleCtrl,
                                            minLines: 4,
                                            maxLines: 10,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: _rawTextFontSize,
                                              height: 1.4,
                                            ),
                                            decoration: InputDecoration(
                                              filled: true,
                                              fillColor: AppColors.surfaceContainerHigh,
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              contentPadding: const EdgeInsets.all(12),
                                            ),
                                            onChanged: (_) => _runTestParse(),
                                          ),
                                          const SizedBox(height: 14),

                                          // Quick Series Fix / Override Bar
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1E293B),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: Colors.amberAccent.withAlpha(100)),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.bolt_rounded, color: Colors.amberAccent, size: 18),
                                                const SizedBox(width: 8),
                                                const Text(
                                                  'Fix Series To All:',
                                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amberAccent),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Wrap(
                                                    spacing: 6,
                                                    runSpacing: 4,
                                                    children: {
                                                      '5', '6', '10', '12', '18', '20', '24', '36', '40', '50', '60', '100',
                                                      if (_selectedSeriesOverride.isNotEmpty) _selectedSeriesOverride,
                                                    }.toList().map((s) {
                                                      final isSel = _selectedSeriesOverride == s;
                                                      return InkWell(
                                                        onTap: () => _applySeriesToAll(s),
                                                        borderRadius: BorderRadius.circular(6),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: isSel ? Colors.amberAccent.withAlpha(50) : AppColors.surfaceContainerHigh,
                                                            borderRadius: BorderRadius.circular(6),
                                                            border: Border.all(color: isSel ? Colors.amberAccent : Colors.white24, width: isSel ? 1.5 : 1),
                                                          ),
                                                          child: Text(
                                                            'Series $s',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
                                                              color: isSel ? Colors.amberAccent : Colors.white70,
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    }).toList(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 16),

                                          // Test Status Output
                                          if (_testError != null)
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: AppColors.error.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: AppColors.error),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Row(
                                                    children: [
                                                      Icon(Icons.error_outline, color: AppColors.error, size: 16),
                                                      SizedBox(width: 6),
                                                      Text('Matching Status: Error', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(_testError!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                                ],
                                              ),
                                            )
                                          else
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: AppColors.success.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: AppColors.success),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 16),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        'Matching Status: SUCCESS (${_testPreviewTickets.length} Tickets Found)',
                                                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 6,
                                                    children: _testPreviewTickets.map((t) {
                                                      return Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: AppColors.surfaceContainerHigh,
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: AppColors.tertiary),
                                                        ),
                                                        child: Text(
                                                          'Series ${t.series} • #${t.ticketNo}${t.quantity > 1 ? ' (x${t.quantity})' : ''}',
                                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                                        ),
                                                      );
                                                    }).toList(),
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
            ),
            const Divider(color: AppColors.border, height: 24),

            // Dialog Footer Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_selectedMessage != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Ignore / Dismiss Message'),
                    onPressed: _ignoreCurrentMessage,
                  )
                else
                  const SizedBox.shrink(),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      icon: const Icon(Icons.smart_toy_rounded, size: 18),
                      label: Text(
                        _testPreviewTickets.isEmpty
                            ? 'Train & Save Pattern'
                            : 'Train Bot & Book ${_testPreviewTickets.length} Ticket(s)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _testPreviewTickets.isEmpty ? null : _saveAndTrainBot,
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 48),
          ),
          const SizedBox(height: 16),
          const Text(
            'All WhatsApp Messages Successfully Parsed!',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'There are currently no unparsed or unrecognized seller messages pending resolution.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
