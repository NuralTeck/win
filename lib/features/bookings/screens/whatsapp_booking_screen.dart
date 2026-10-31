// ignore_for_file: unused_field, unused_element
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_colors.dart';
import '../../../core/database/database_service.dart';
import '../../../core/services/whatsapp_bulk_parser_engine.dart';
import '../../../core/services/whatsapp_zip_service.dart';
import '../../../core/services/series_color_registry.dart';
import '../../settings/viewmodels/series_price_viewmodel.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../services/gemini_scanner_service.dart';
import '../widgets/ai_photo_review_dialog.dart';

class DesktopSmoothScrollBehavior extends MaterialScrollBehavior {
  const DesktopSmoothScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class BulkShiftGroup {
  String shiftName;
  DateTime drawDate;
  String buyerName;
  List<BulkParsedTicket> tickets;
  List<String> unparsedLines;

  int? _cachedTotalTickets;
  double? _cachedTotalAmount;
  Map<String, List<BulkParsedTicket>>? _cachedTicketsBySeries;
  List<String>? _cachedUniqueSeries;

  BulkShiftGroup({
    required this.shiftName,
    required this.drawDate,
    required this.buyerName,
    required this.tickets,
    List<String>? unparsedLines,
  }) : unparsedLines = unparsedLines ?? [];

  void invalidateCache() {
    _cachedTotalTickets = null;
    _cachedTotalAmount = null;
    _cachedTicketsBySeries = null;
    _cachedUniqueSeries = null;
  }

  int get totalTickets {
    _cachedTotalTickets ??= tickets.fold<int>(0, (int sum, t) => sum + t.quantity);
    return _cachedTotalTickets!;
  }

  double get totalAmount {
    _cachedTotalAmount ??= tickets.fold<double>(0.0, (double sum, t) => sum + t.totalAmount);
    return _cachedTotalAmount!;
  }

  Map<String, List<BulkParsedTicket>> get ticketsBySeries {
    if (_cachedTicketsBySeries != null) return _cachedTicketsBySeries!;
    final map = <String, List<BulkParsedTicket>>{};
    for (final t in tickets) {
      final s = t.series.trim().isEmpty ? '12' : t.series.trim();
      map.putIfAbsent(s, () => []).add(t);
    }
    _cachedTicketsBySeries = map;
    return map;
  }

  List<String> get uniqueSeries {
    if (_cachedUniqueSeries != null) return _cachedUniqueSeries!;
    final list = ticketsBySeries.keys.toList();
    list.sort((a, b) {
      if (a == 'Undefined' || a == 'Invalid') return 1;
      if (b == 'Undefined' || b == 'Invalid') return -1;
      final na = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final nb = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
      return na.compareTo(nb);
    });
    _cachedUniqueSeries = list;
    return list;
  }
}

class _IndexedSearchMatch {
  final BulkParsedTicket ticket;
  final BulkShiftGroup group;
  final int groupIndex;
  final int ticketIndex;

  _IndexedSearchMatch({
    required this.ticket,
    required this.group,
    required this.groupIndex,
    required this.ticketIndex,
  });
}

Color _getSeriesColor(String series) {
  return SeriesColorRegistry.getColor(series);
}

class FastSyntaxTextEditingController extends TextEditingController {
  String? _highlightedTarget;
  bool _syntaxHighlightingEnabled = true;

  // Cached Compiled Span to prevent UI thread freeze on cursor blinks/scroll
  String? _cachedText;
  String? _cachedTarget;
  double? _cachedSz;
  bool? _cachedSyntaxEnabled;
  TextSpan? _cachedSpan;

  String? get highlightedTarget => _highlightedTarget;
  set highlightedTarget(String? val) {
    _highlightedTarget = val;
    _cachedSpan = null;
    notifyListeners();
  }

  bool get syntaxHighlightingEnabled => _syntaxHighlightingEnabled;
  set syntaxHighlightingEnabled(bool val) {
    if (_syntaxHighlightingEnabled != val) {
      _syntaxHighlightingEnabled = val;
      _cachedSpan = null;
      notifyListeners();
    }
  }

  void invalidateSpanCache() {
    _cachedSpan = null;
  }

  FastSyntaxTextEditingController({super.text});

  static TextStyle _defaultStyle(double sz) => TextStyle(
        fontFamily: 'monospace',
        fontSize: sz,
        color: Colors.white,
      );

  static TextStyle _targetStyle(double sz) => TextStyle(
        fontFamily: 'monospace',
        fontSize: sz,
        color: Colors.black,
        fontWeight: FontWeight.w900,
        backgroundColor: const Color(0xFFFFD700),
      );

  static TextStyle _ticketStyle(double sz) => TextStyle(
        fontFamily: 'monospace',
        fontSize: sz,
        color: const Color(0xFFFDE047), // High-contrast Amber-Gold for 5-digit/4-digit tickets
        fontWeight: FontWeight.bold,
      );

  static TextStyle _seriesStyle(double sz, String series) {
    final c = _getSeriesColor(series);
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: sz,
      color: c,
      fontWeight: FontWeight.bold,
    );
  }

  static TextStyle _headerStyle(double sz) => TextStyle(
        fontFamily: 'monospace',
        fontSize: sz,
        color: const Color(0xFF34D399), // Emerald Green for Shift/Date boundaries
        fontWeight: FontWeight.bold,
      );

  static TextStyle _metaSenderStyle(double sz) => TextStyle(
        fontFamily: 'monospace',
        fontSize: sz * 0.95,
        color: const Color(0xFFA78BFA), // Lavender/Purple for WhatsApp Senders & Timestamps
        fontWeight: FontWeight.w600,
      );

  static TextStyle _delimiterStyle(double sz) => TextStyle(
        fontFamily: 'monospace',
        fontSize: sz,
        color: const Color(0xFF64748B), // Slate gray for delimiters (- = / x)
      );

  static const Set<String> _validSeriesSet = {
    '1', '2', '3', '4', '5', '6', '8', '10', '12', '14', '16', '18', '20', '24', '25', '30', '36', '40', '48', '50', '60', '100'
  };

  static final RegExp _regWaPrefix = RegExp(
    r'^(?:\[?(\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4}),?\s+[\d:.]+(?:\s*(?:[aApP][mM]|\u202F[aApP][mM]))?\]?\s*(?:-|\s*:)?\s*([^:\n]+?):\s*)',
    caseSensitive: false,
  );

  static final RegExp _regSectionHeader = RegExp(
    r'^(?:(?:start|booking|dear|stop|end|sampat|khatam)\b|\d{1,2}[\/\.-]\d{1,2}(?:[\/\.-]\d{2,4})?[\s.=:,-]*(?:1|6|8)\s*(?:pm|am)?|\b(?:1|6|8)\s*(?:pm|am)\b)',
    caseSensitive: false,
  );

  static final RegExp _regTokens = RegExp(
    r'(\b\d{5}\b|\b\d{4}\b)|(\b[sS]?\d{1,3}[cs]?\b|\(\d{1,3}\))|([=:\/\-~*#+]+|\bto\b|\bse\b)',
  );

  static List<InlineSpan> _applyTargetHighlight(
    String text,
    TextStyle style,
    String? target,
    double sz,
  ) {
    if (target == null || target.length < 2 || !text.toLowerCase().contains(target.toLowerCase())) {
      return [TextSpan(text: text, style: style)];
    }

    final spans = <InlineSpan>[];
    int startIdx = 0;
    final textLower = text.toLowerCase();
    final targetLower = target.toLowerCase();
    int matchIdx = textLower.indexOf(targetLower, startIdx);

    while (matchIdx != -1) {
      if (matchIdx > startIdx) {
        spans.add(TextSpan(text: text.substring(startIdx, matchIdx), style: style));
      }
      spans.add(TextSpan(text: text.substring(matchIdx, matchIdx + target.length), style: _targetStyle(sz)));
      startIdx = matchIdx + target.length;
      matchIdx = textLower.indexOf(targetLower, startIdx);
    }

    if (startIdx < text.length) {
      spans.add(TextSpan(text: text.substring(startIdx), style: style));
    }
    return spans;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final String fullText = text;
    if (fullText.isEmpty) {
      return TextSpan(text: '', style: style);
    }

    final baseStyle = style ?? _defaultStyle(12.5);
    final double sz = baseStyle.fontSize ?? 12.5;
    final target = _highlightedTarget?.trim();

    // 1. Instant Cache Hit Check (Zero CPU usage on cursor blinks, scrolling, clicks)
    if (_cachedSpan != null &&
        _cachedText == fullText &&
        _cachedTarget == target &&
        _cachedSz == sz &&
        _cachedSyntaxEnabled == _syntaxHighlightingEnabled) {
      return _cachedSpan!;
    }

    // 2. Fallback if syntax highlighting is explicitly disabled
    if (!_syntaxHighlightingEnabled) {
      final span = TextSpan(
        style: baseStyle,
        children: _applyTargetHighlight(fullText, baseStyle, target, sz),
      );
      _cachedText = fullText;
      _cachedTarget = target;
      _cachedSz = sz;
      _cachedSyntaxEnabled = _syntaxHighlightingEnabled;
      _cachedSpan = span;
      return span;
    }

    // 3. Ultra-Fast Span Building with Direct Array Appends
    final lines = fullText.split('\n');
    final allSpans = <InlineSpan>[];
    final hasTarget = target != null && target.length >= 2 && fullText.toLowerCase().contains(target.toLowerCase());

    void addSpan(String str, TextStyle st) {
      if (str.isEmpty) return;
      if (hasTarget && str.toLowerCase().contains(target.toLowerCase())) {
        allSpans.addAll(_applyTargetHighlight(str, st, target, sz));
      } else {
        allSpans.add(TextSpan(text: str, style: st));
      }
    }

    final headerStyle = _headerStyle(sz);
    final senderStyle = _metaSenderStyle(sz);
    final tktStyle = _ticketStyle(sz);
    final delimStyle = _delimiterStyle(sz);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i > 0) {
        allSpans.add(const TextSpan(text: '\n'));
      }
      if (line.isEmpty) continue;

      // Header line
      if (_regSectionHeader.hasMatch(line)) {
        addSpan(line, headerStyle);
        continue;
      }

      int contentStart = 0;
      final waMatch = _regWaPrefix.firstMatch(line);
      if (waMatch != null) {
        final prefixText = waMatch.group(0)!;
        addSpan(prefixText, senderStyle);
        contentStart = prefixText.length;
      }

      if (contentStart >= line.length) continue;

      final content = line.substring(contentStart);
      final tokenMatches = _regTokens.allMatches(content);
      int lastIdx = 0;

      for (final tm in tokenMatches) {
        if (tm.start > lastIdx) {
          addSpan(content.substring(lastIdx, tm.start), baseStyle);
        }

        final tokenText = tm.group(0)!;
        if (tm.group(1) != null) {
          addSpan(tokenText, tktStyle);
        } else if (tm.group(2) != null) {
          final clean = tokenText.replaceAll(RegExp(r'\D'), '');
          if (_validSeriesSet.contains(clean)) {
            addSpan(tokenText, _seriesStyle(sz, clean));
          } else {
            addSpan(tokenText, baseStyle);
          }
        } else if (tm.group(3) != null) {
          addSpan(tokenText, delimStyle);
        } else {
          addSpan(tokenText, baseStyle);
        }
        lastIdx = tm.end;
      }

      if (lastIdx < content.length) {
        addSpan(content.substring(lastIdx), baseStyle);
      }
    }

    final resultSpan = TextSpan(style: baseStyle, children: allSpans);
    _cachedText = fullText;
    _cachedTarget = target;
    _cachedSz = sz;
    _cachedSyntaxEnabled = _syntaxHighlightingEnabled;
    _cachedSpan = resultSpan;
    return resultSpan;
  }
}

class WhatsAppBookingScreen extends ConsumerStatefulWidget {
  const WhatsAppBookingScreen({super.key});

  @override
  ConsumerState<WhatsAppBookingScreen> createState() => _WhatsAppBookingScreenState();
}

class _WhatsAppBookingScreenState extends ConsumerState<WhatsAppBookingScreen> {
  String _operationMode = 'auto'; // 'auto' | 'fixed'
  bool _enforceStrictTargetDate = false;

  static String _getInitialDefaultShift() {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    final totalMinutes = hour * 60 + minute;
    if (totalMinutes > 1095 || totalMinutes < 480) { // After 6:15 PM (18:15) or early morning
      return 'Dear 8 PM';
    } else if (totalMinutes > 795) { // 1:15 PM (13:15) to 6:15 PM
      return 'Dear 6 PM';
    } else { // Morning up to 1:15 PM
      return 'Dear 1 PM';
    }
  }

  late String _targetShift;
  DateTime _targetDate = DateTime.now();
  String _fallbackSeries = '12';
  final TextEditingController _buyerCtrl = TextEditingController(text: 'Party');
  final FastSyntaxTextEditingController _chatInputCtrl = FastSyntaxTextEditingController();
  final ScrollController _inputScrollCtrl = ScrollController();
  final FocusNode _chatInputFocusNode = FocusNode();
  double _chatFontSize = 12.5;
  // Per-Card Series Filters: key = groupIndex, value = selected series string or null (All)
  final Map<int, String?> _cardSeriesFilter = {};
  bool _isFilterBarCollapsed = false;
  bool _groupBySeriesAccordion = false;
  final Set<String> _collapsedSeriesKeys = {};

  List<BulkParsedTicket> _getEffectiveTicketsForGroup(int groupIndex) {
    if (groupIndex < 0 || groupIndex >= _parsedGroups.length) return [];
    final group = _parsedGroups[groupIndex];
    final activeSeries = _cardSeriesFilter[groupIndex];
    if (activeSeries == null) return group.tickets;
    return group.tickets.where((t) => t.series == activeSeries).toList();
  }

  // Web-App Style Fixed-Window Virtual Pagination per Shift Card
  final Map<int, int> _groupPageIndices = {};
  static const int _ticketsPageSize = 25;

  int _getGroupPageIndex(int groupIndex, int totalTickets) {
    if (totalTickets <= 0) return 0;
    final maxPage = (totalTickets - 1) ~/ _ticketsPageSize;
    final current = _groupPageIndices[groupIndex] ?? 0;
    return current.clamp(0, math.max(0, maxPage));
  }

  void _nextPageForGroup(int groupIndex, int totalTickets) {
    final maxPage = (totalTickets - 1) ~/ _ticketsPageSize;
    final current = _getGroupPageIndex(groupIndex, totalTickets);
    if (current < maxPage) {
      setState(() {
        _groupPageIndices[groupIndex] = current + 1;
      });
      final ctrl = _cardRowsScrollControllers[groupIndex];
      if (ctrl != null && ctrl.hasClients) {
        ctrl.jumpTo(0.0);
      }
    }
  }

  void _prevPageForGroup(int groupIndex, int totalTickets) {
    final current = _getGroupPageIndex(groupIndex, totalTickets);
    if (current > 0) {
      setState(() {
        _groupPageIndices[groupIndex] = current - 1;
      });
      final ctrl = _cardRowsScrollControllers[groupIndex];
      if (ctrl != null && ctrl.hasClients) {
        ctrl.jumpTo(0.0);
      }
    }
  }

  // Chat Panel Sliding Window Chunking (Prevents Flutter Desktop UI Freezing / Not Responding)
  String? _fullChatText;
  bool _isLargeMode = false;
  static const int _chatChunkSize = 30; // Ultra-light 30-line chunk renders in ~0.2ms with instant butter-smooth sliding
  int _chatWindowStartLine = 0;
  int _chunkLineCount = 0;

  void _loadChatWindow({
    int? centerAroundLine,
    int? chunkIndex,
    bool resetScroll = true,
  }) {
    if (_fullChatText == null) return;
    final lines = _fullChatText!.split('\n');
    final totalLines = lines.length;
    if (totalLines == 0) return;

    int start = 0;
    if (centerAroundLine != null) {
      final centerIdx = centerAroundLine - 1;
      start = math.max(0, centerIdx - (_chatChunkSize ~/ 2));
      if (start + _chatChunkSize > totalLines) {
        start = math.max(0, totalLines - _chatChunkSize);
      }
    } else if (chunkIndex != null) {
      start = chunkIndex * _chatChunkSize;
      if (start >= totalLines) {
        start = math.max(0, ((totalLines - 1) ~/ _chatChunkSize) * _chatChunkSize);
      }
    } else {
      start = _chatWindowStartLine;
    }

    start = start.clamp(0, math.max(0, totalLines - 1));
    final end = math.min(start + _chatChunkSize, totalLines);
    _chatWindowStartLine = start;
    _chunkLineCount = end - start;

    final chunkText = lines.sublist(start, end).join('\n');
    if (_chatInputCtrl.text != chunkText) {
      setState(() {
        _chatInputCtrl.value = TextEditingValue(
          text: chunkText,
          selection: const TextSelection.collapsed(offset: 0),
        );
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_inputScrollCtrl.hasClients) {
        if (centerAroundLine != null) {
          final targetLineInChunk = (centerAroundLine - 1) - start;
          final targetY = 12.0 + targetLineInChunk * _measuredChatLineHeight;
          final vHeight = _inputScrollCtrl.position.viewportDimension;
          final targetScroll = (targetY - (vHeight / 2.0)).clamp(0.0, _inputScrollCtrl.position.maxScrollExtent);
          _inputScrollCtrl.jumpTo(targetScroll);
        } else if (resetScroll) {
          _inputScrollCtrl.jumpTo(0.0);
        } else {
          final maxS = _inputScrollCtrl.position.maxScrollExtent;
          if (_inputScrollCtrl.offset > maxS) {
            _inputScrollCtrl.jumpTo(maxS);
          }
        }
      }
    });
  }

  void _syncCurrentChatChunkToFullText() {
    if (_fullChatText == null || !_isLargeMode) return;
    final allLines = _fullChatText!.split('\n');
    final start = _chatWindowStartLine;
    final end = math.min(start + _chunkLineCount, allLines.length);

    final currentChunkLines = _chatInputCtrl.text.split('\n');
    allLines.replaceRange(start, end, currentChunkLines);
    _chunkLineCount = currentChunkLines.length;
    _fullChatText = allLines.join('\n');
  }

  void _nextChatChunk() {
    if (_fullChatText == null) return;
    _syncCurrentChatChunkToFullText();
    final allLines = _fullChatText!.split('\n');
    final totalLines = allLines.length;
    final newStart = math.min(_chatWindowStartLine + 20, math.max(0, totalLines - _chatChunkSize));
    if (newStart != _chatWindowStartLine) {
      _chatWindowStartLine = newStart;
      _loadChatWindow(resetScroll: false);
    }
  }

  void _prevChatChunk() {
    if (_fullChatText == null) return;
    _syncCurrentChatChunkToFullText();
    final newStart = math.max(0, _chatWindowStartLine - 20);
    if (newStart != _chatWindowStartLine) {
      _chatWindowStartLine = newStart;
      _loadChatWindow(resetScroll: false);
    }
  }

  void _enterLargeMode(String fullText, {int targetLine = 1}) {
    final cleanFullText = fullText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    _fullChatText = cleanFullText;
    _isLargeMode = true;
    _chatWindowStartLine = 0;
    _chunkLineCount = 0;

    _loadChatWindow(centerAroundLine: targetLine, resetScroll: true);
    _parseBulkChat(fullTextOverride: cleanFullText);
  }

  final TextEditingController _quickSeriesCtrl = TextEditingController(text: '12');
  final TextEditingController _quickTicketCtrl = TextEditingController();
  final TextEditingController _quickQtyCtrl = TextEditingController(text: '1');
  final FocusNode _quickTicketFocusNode = FocusNode();
  final List<String> _manualAddedSignatures = [];

  bool _reparseRequested = false;

  int? _activeGroupIndex;
  int? _activeTicketIndex;
  final Map<int, ScrollController> _cardRowsScrollControllers = {};

  ScrollController _getCardRowsScrollController(int groupIndex) {
    return _cardRowsScrollControllers.putIfAbsent(groupIndex, () => ScrollController());
  }

  // Hot Reload VM compatibility stubs
  int _getGroupDisplayLimit(int groupIndex, int totalCount) => _ticketsPageSize;
  void _loadMoreTicketsForGroup(int groupIndex, int totalCount) => _nextPageForGroup(groupIndex, totalCount);
  void _showAllTicketsForGroup(int groupIndex, int totalCount) {}

  final TextEditingController _chatSearchCtrl = TextEditingController();
  List<int> _chatSearchMatchIndices = [];
  int _currentSearchMatchIndex = -1;
  Timer? _chatSearchDebounceTimer;

  List<BulkShiftGroup> _parsedGroups = [];
  final Set<int> _selectedGroupIndices = {};
  List<String> _unparsedLines = [];
  bool _showDockedReviewPanel = false;
  int _currentUnparsedIndex = 0;

  bool _isParsing = false;
  bool _isSaving = false;
  Timer? _parseDebounceTimer;
  Timer? _searchDebounceTimer;

  final TextEditingController _universalSearchCtrl = TextEditingController();
  String _universalSearchQuery = '';
  List<_IndexedSearchMatch> _cachedUniversalMatches = [];
  final Map<int, int> _cachedGroupMatchCounts = {};
  final ScrollController _cardsOuterScrollCtrl = ScrollController();

  void _onChatInputScroll() {
    // Keep scroll stable without resetting user's cursor or text
  }

  @override
  void initState() {
    super.initState();
    _targetShift = _getInitialDefaultShift();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _inputScrollCtrl.addListener(_onChatInputScroll);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _inputScrollCtrl.removeListener(_onChatInputScroll);
    _cardsOuterScrollCtrl.dispose();
    _parseDebounceTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _chatSearchDebounceTimer?.cancel();
    for (final c in _cardRowsScrollControllers.values) {
      c.dispose();
    }
    _cardRowsScrollControllers.clear();
    _buyerCtrl.dispose();
    _quickSeriesCtrl.dispose();
    _quickTicketCtrl.dispose();
    _quickQtyCtrl.dispose();
    _quickTicketFocusNode.dispose();
    _chatInputFocusNode.dispose();
    _chatInputCtrl.dispose();
    _chatSearchCtrl.dispose();
    _universalSearchCtrl.dispose();
    _inputScrollCtrl.dispose();
    super.dispose();
  }

  Widget _buildTopShiftBtn(String shiftValue, String label, Color accentColor) {
    final isSelected = _targetShift == shiftValue;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        if (_targetShift != shiftValue) {
          setState(() {
            _targetShift = shiftValue;
          });
          _parseBulkChat();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? accentColor : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: isSelected ? accentColor : Colors.white24,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? accentColor : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorLegendChip(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _onChatTextChanged(String val) {
    _parseDebounceTimer?.cancel();

    // If user deleted all text or it's empty, immediately clear cards
    if (val.trim().isEmpty) {
      if (_isLargeMode) {
        _fullChatText = null;
        _isLargeMode = false;
        _chunkLineCount = 0;
      }
      setState(() {
        _parsedGroups = [];
        _selectedGroupIndices.clear();
        _cardSeriesFilter.clear();
        _cachedUniversalMatches = [];
        _unparsedLines = [];
      });
      return;
    }

    if (_isLargeMode && _fullChatText != null) {
      _syncCurrentChatChunkToFullText();
      _parseDebounceTimer = Timer(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        _parseBulkChat(fullTextOverride: _fullChatText);
      });
      return;
    }

    final lineCount = val.split('\n').length;
    if (!_isLargeMode && lineCount > _chatChunkSize) {
      final textToStore = val;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enterLargeMode(textToStore);
      });
      return;
    }

    _parseDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _parseBulkChat(fullTextOverride: _chatInputCtrl.text);
    });
  }

  void _addQuickTicketEntry() {
    final rawTkt = _quickTicketCtrl.text.trim();
    if (rawTkt.isEmpty) return;

    final s = _quickSeriesCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    final series = s.isNotEmpty ? s : (_fallbackSeries.isNotEmpty ? _fallbackSeries : '12');
    final tktNo = rawTkt.padLeft(5, '0');
    final qty = int.tryParse(_quickQtyCtrl.text.trim()) ?? 1;

    final tktSig = '$series-$tktNo-$qty';
    _manualAddedSignatures.remove(tktSig);
    _manualAddedSignatures.add(tktSig); // Keep newest manual entry signature

    final newLine = '$series $tktNo${qty > 1 ? ' * $qty' : ''}';

    _parseDebounceTimer?.cancel();

    if (_isLargeMode && _fullChatText != null) {
      _syncCurrentChatChunkToFullText();
      final curFull = _fullChatText!.trim();
      _fullChatText = curFull.isEmpty ? newLine : '$curFull\n$newLine';
      final totalLines = _fullChatText!.split('\n').length;
      _loadChatWindow(centerAroundLine: totalLines, resetScroll: false);
      _parseBulkChat(fullTextOverride: _fullChatText, isFromManualAdd: true);
    } else {
      final curText = _chatInputCtrl.text.trim();
      final updated = curText.isEmpty ? newLine : '$curText\n$newLine';
      _chatInputCtrl.text = updated;
      _parseBulkChat(fullTextOverride: updated, isFromManualAdd: true);
    }

    _quickTicketCtrl.clear();
    _quickTicketFocusNode.requestFocus();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('➕ New Entry Added (Bottom Live): S$series #$tktNo ($qty tkt)'),
        duration: const Duration(milliseconds: 1400),
        backgroundColor: Colors.teal[800],
      ),
    );
  }

  Future<void> _forceReparseCurrentText() async {
    _parseDebounceTimer?.cancel();
    if (_isLargeMode) {
      _syncCurrentChatChunkToFullText();
    }
    final textToParse = (_isLargeMode && _fullChatText != null) ? _fullChatText! : _chatInputCtrl.text;
    await _parseBulkChat(fullTextOverride: textToParse);
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      final total = _parsedGroups.fold(0, (s, g) => s + g.totalTickets);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            total > 0
                ? '⚡ Updated! Total $total tickets successfully parsed across ${_parsedGroups.length} shifts.'
                : '⚡ Re-parsed: 0 tickets found in text.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: total > 0 ? const Color(0xFF0D5F52) : Colors.orange.shade800,
        ),
      );
    }
  }

  void _onChatSearchChanged(String val) {
    _chatSearchDebounceTimer?.cancel();
    _chatSearchDebounceTimer = Timer(const Duration(milliseconds: 80), () {
      if (mounted) _executeChatSearch(val);
    });
  }

  void _executeChatSearch(String query) {
    final clean = query.trim();
    if (clean.isEmpty) {
      setState(() {
        _chatSearchMatchIndices = [];
        _currentSearchMatchIndex = -1;
        _chatInputCtrl.highlightedTarget = null;
      });
      return;
    }

    final cleanLower = clean.toLowerCase();

    if (_isLargeMode && _fullChatText != null) {
      _syncCurrentChatChunkToFullText();
      final allLines = _fullChatText!.split('\n');
      final List<int> matchingLines = [];
      for (int i = 0; i < allLines.length; i++) {
        if (allLines[i].toLowerCase().contains(cleanLower)) {
          matchingLines.add(i + 1); // 1-based line number across full chat
        }
      }

      setState(() {
        _chatSearchMatchIndices = matchingLines;
        _currentSearchMatchIndex = matchingLines.isNotEmpty ? 0 : -1;
        _chatInputCtrl.highlightedTarget = clean;
      });

      if (matchingLines.isNotEmpty) {
        _jumpToSearchMatch(matchingLines[0], clean.length, requestFocus: false);
      }
      return;
    }

    final fullText = _chatInputCtrl.text;
    final fullTextLower = fullText.toLowerCase();

    final List<int> matches = [];
    int start = 0;
    while (matches.length < 500) {
      final idx = fullTextLower.indexOf(cleanLower, start);
      if (idx == -1) break;
      matches.add(idx);
      start = idx + clean.length;
      if (start >= fullText.length) break;
    }

    setState(() {
      _chatSearchMatchIndices = matches;
      _currentSearchMatchIndex = matches.isNotEmpty ? 0 : -1;
      _chatInputCtrl.highlightedTarget = clean;
    });

    if (matches.isNotEmpty) {
      _jumpToSearchMatch(matches[0], clean.length, requestFocus: false);
    }
  }

  void _nextSearchMatch() {
    if (_chatSearchMatchIndices.isEmpty) return;
    setState(() {
      _currentSearchMatchIndex = (_currentSearchMatchIndex + 1) % _chatSearchMatchIndices.length;
    });
    final idx = _chatSearchMatchIndices[_currentSearchMatchIndex];
    _jumpToSearchMatch(idx, _chatSearchCtrl.text.trim().length, requestFocus: false);
  }

  void _prevSearchMatch() {
    if (_chatSearchMatchIndices.isEmpty) return;
    setState(() {
      _currentSearchMatchIndex = (_currentSearchMatchIndex - 1 + _chatSearchMatchIndices.length) % _chatSearchMatchIndices.length;
    });
    final idx = _chatSearchMatchIndices[_currentSearchMatchIndex];
    _jumpToSearchMatch(idx, _chatSearchCtrl.text.trim().length, requestFocus: false);
  }

  void _jumpToSearchMatch(int idx, int length, {bool requestFocus = false}) {
    final queryText = _chatSearchCtrl.text.trim();

    if (_isLargeMode && _fullChatText != null) {
      _indicateTicketInChatText(
        queryText,
        targetLineNumber: idx, // In large mode, idx is the 1-based line number!
        focusChat: requestFocus,
        allowWindowSlide: true,
      );
      return;
    }

    final fullText = _chatInputCtrl.text;
    if (idx < 0 || idx >= fullText.length) return;

    if (requestFocus) {
      _chatInputFocusNode.requestFocus();
      final safeBase = idx.clamp(0, fullText.length);
      final safeExtent = (safeBase + length).clamp(safeBase, fullText.length);
      _chatInputCtrl.selection = TextSelection(
        baseOffset: safeBase,
        extentOffset: safeExtent,
      );
    }

    if (_inputScrollCtrl.hasClients) {
      final precedingText = fullText.substring(0, idx);
      final lineNumber = precedingText.split('\n').length - 1;
      final estimatedLineHeight = _chatFontSize * 1.4;
      final lineCenterY = 10.0 + lineNumber * estimatedLineHeight + (estimatedLineHeight / 2.0);
      final viewportHeight = _inputScrollCtrl.position.viewportDimension;
      final targetScroll = (lineCenterY - (viewportHeight / 2.0)).clamp(
        0.0,
        _inputScrollCtrl.position.maxScrollExtent,
      );
      _inputScrollCtrl.animateTo(
        targetScroll,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _clearChatSearch() {
    _chatSearchCtrl.clear();
    setState(() {
      _chatSearchMatchIndices = [];
      _currentSearchMatchIndex = -1;
      _chatInputCtrl.highlightedTarget = null;
    });
  }

  double get _measuredChatLineHeight {
    final tp = TextPainter(
      text: TextSpan(
        text: '12 58359',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: _chatFontSize,
          height: 1.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.preferredLineHeight;
  }

  void _indicateTicketInChatText(
    String target, {
    String? originalLine,
    int? targetLineNumber,
    bool focusChat = false,
    bool allowWindowSlide = false,
  }) {
    final cleanTarget = target.trim();
    if (cleanTarget.isEmpty) return;

    final fullText = _chatInputCtrl.text;
    final estimatedLineHeight = _measuredChatLineHeight;
    const topPadding = 12.0;

    int resolvedTargetLine0 = (targetLineNumber != null && targetLineNumber > 0) ? (targetLineNumber - 1) : -1;

    // In Large Mode, if target line number is null, find the exact line across _fullChatText!
    if (resolvedTargetLine0 < 0 && _isLargeMode && _fullChatText != null) {
      _syncCurrentChatChunkToFullText();
      final allLines = _fullChatText!.split('\n');
      final searchTarget = (originalLine != null && originalLine.trim().isNotEmpty)
          ? originalLine.trim().toLowerCase()
          : cleanTarget.toLowerCase();

      int found = -1;
      // 1. Exact trimmed match
      for (int i = 0; i < allLines.length; i++) {
        if (allLines[i].trim().toLowerCase() == searchTarget) {
          found = i;
          break;
        }
      }
      // 2. Line contains searchTarget
      if (found == -1) {
        for (int i = 0; i < allLines.length; i++) {
          if (allLines[i].toLowerCase().contains(searchTarget)) {
            found = i;
            break;
          }
        }
      }
      // 3. Fallback: line contains cleanTarget
      if (found == -1 && cleanTarget.toLowerCase() != searchTarget) {
        final ct = cleanTarget.toLowerCase();
        for (int i = 0; i < allLines.length; i++) {
          if (allLines[i].toLowerCase().contains(ct)) {
            found = i;
            break;
          }
        }
      }
      if (found != -1) {
        resolvedTargetLine0 = found;
      }
    }

    // Dynamic center-anchored window positioning in Large Mode
    if (resolvedTargetLine0 >= 0 && _isLargeMode && _fullChatText != null) {
      final lineInWindow = resolvedTargetLine0 - _chatWindowStartLine;
      final isComfortablyInside = lineInWindow >= 0 && lineInWindow < _chunkLineCount;

      // Only slide the chat window if explicitly requested (e.g. from Locate button)
      if (!isComfortablyInside) {
        if (!allowWindowSlide) {
          // Do not jump screen away while user is working on their chunk!
          return;
        }
        _syncCurrentChatChunkToFullText();
        _loadChatWindow(centerAroundLine: resolvedTargetLine0 + 1, resetScroll: false);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentLineInWindow = resolvedTargetLine0 - _chatWindowStartLine;
        final chunkText = _chatInputCtrl.text;
        final chunkLines = chunkText.split('\n');
        int charOffset = 0;
        for (int i = 0; i < math.min(currentLineInWindow, chunkLines.length); i++) {
          charOffset += chunkLines[i].length + 1;
        }

        final lineStr = (currentLineInWindow >= 0 && currentLineInWindow < chunkLines.length) ? chunkLines[currentLineInWindow] : '';
        final lineStrLower = lineStr.toLowerCase();
        final ctLower = cleanTarget.toLowerCase();
        int matchWithinLine = lineStrLower.indexOf(ctLower);
        String targetToHighlight = cleanTarget;
        if (matchWithinLine != -1) {
          targetToHighlight = lineStr.substring(matchWithinLine, matchWithinLine + cleanTarget.length);
        } else if (originalLine != null && originalLine.trim().isNotEmpty) {
          final origTrim = originalLine.trim();
          final origLower = origTrim.toLowerCase();
          final origMatch = lineStrLower.indexOf(origLower);
          if (origMatch != -1) {
            targetToHighlight = lineStr.substring(origMatch, origMatch + origTrim.length);
            matchWithinLine = origMatch;
          } else if (lineStr.trim().isNotEmpty) {
            targetToHighlight = lineStr.trim();
            matchWithinLine = lineStr.indexOf(targetToHighlight);
          }
        } else if (lineStr.trim().isNotEmpty) {
          targetToHighlight = lineStr.trim();
          matchWithinLine = lineStr.indexOf(targetToHighlight);
        }
        // Fallback: if not found on currentLine, search anywhere in chunk
        if (matchWithinLine == -1) {
          for (int li = 0; li < chunkLines.length; li++) {
            final lLower = chunkLines[li].toLowerCase();
            final mIdx = lLower.indexOf(ctLower);
            if (mIdx != -1) {
              matchWithinLine = mIdx;
              targetToHighlight = chunkLines[li].substring(mIdx, mIdx + cleanTarget.length);
              charOffset = 0;
              for (int k = 0; k < li; k++) {
                charOffset += chunkLines[k].length + 1;
              }
              break;
            }
          }
        }

        int finalIdx = matchWithinLine != -1 ? (charOffset + matchWithinLine) : charOffset;

        _chatInputCtrl.highlightedTarget = targetToHighlight;
        final safeBase = finalIdx.clamp(0, chunkText.length);
        final safeExtent = (safeBase + targetToHighlight.length).clamp(safeBase, chunkText.length);
        _chatInputCtrl.selection = TextSelection(
          baseOffset: safeBase,
          extentOffset: safeExtent,
        );
        if (focusChat) {
          _chatInputFocusNode.requestFocus();
        }

        if (_inputScrollCtrl.hasClients) {
          final lineTop = topPadding + currentLineInWindow * estimatedLineHeight;
          final vHeight = _inputScrollCtrl.position.viewportDimension;
          final targetScroll = (lineTop - (vHeight / 2.0)).clamp(0.0, _inputScrollCtrl.position.maxScrollExtent);
          _inputScrollCtrl.animateTo(targetScroll, duration: const Duration(milliseconds: 70), curve: Curves.easeOut);
        }
      });
      return;
    }

    int idx = -1;
    String highlightText = cleanTarget;
    int? resolvedLineNumber;

    if (targetLineNumber != null && targetLineNumber > 0) {
      final lines = fullText.split('\n');
      final line0 = targetLineNumber - 1;
      if (line0 < lines.length) {
        resolvedLineNumber = line0;
        int charOffset = 0;
        for (int i = 0; i < line0; i++) {
          charOffset += lines[i].length + 1;
        }
        final lineStr = lines[line0];
        final matchInLine = lineStr.toLowerCase().indexOf(cleanTarget.toLowerCase());
        if (matchInLine != -1) {
          idx = charOffset + matchInLine;
          highlightText = lineStr.substring(matchInLine, matchInLine + cleanTarget.length);
        } else if (originalLine != null && originalLine.trim().isNotEmpty) {
          final oTrim = originalLine.trim();
          final oMatch = lineStr.toLowerCase().indexOf(oTrim.toLowerCase());
          if (oMatch != -1) {
            idx = charOffset + oMatch;
            highlightText = lineStr.substring(oMatch, oMatch + oTrim.length);
          } else {
            idx = charOffset;
            highlightText = lineStr.trim().isNotEmpty ? lineStr.trim() : cleanTarget;
          }
        } else {
          idx = charOffset;
          highlightText = lineStr.trim().isNotEmpty ? lineStr.trim() : cleanTarget;
        }
      }
    }

    if (idx == -1) {
      final fullLower = fullText.toLowerCase();
      if (originalLine != null && originalLine.trim().isNotEmpty) {
        final snip = originalLine.trim().toLowerCase();
        idx = fullLower.indexOf(snip);
        if (idx != -1) {
          highlightText = fullText.substring(idx, idx + originalLine.trim().length);
        }
      }
      if (idx == -1) {
        final ctLower = cleanTarget.toLowerCase();
        idx = fullLower.indexOf(ctLower);
        if (idx != -1) {
          highlightText = fullText.substring(idx, idx + cleanTarget.length);
        }
      }
    }

    _chatInputCtrl.highlightedTarget = highlightText;

    if (idx != -1) {
      final safeBase = idx.clamp(0, fullText.length);
      final safeExtent = (safeBase + highlightText.length).clamp(safeBase, fullText.length);
      _chatInputCtrl.selection = TextSelection(
        baseOffset: safeBase,
        extentOffset: safeExtent,
      );
      if (focusChat) {
        _chatInputFocusNode.requestFocus();
      }

      if (_inputScrollCtrl.hasClients) {
        final lineNumber = resolvedLineNumber ?? (fullText.substring(0, idx).split('\n').length - 1);
        final vHeight = _inputScrollCtrl.position.viewportDimension;
        final lineTop = topPadding + lineNumber * estimatedLineHeight;
        final targetScroll = (lineTop - (vHeight / 2.0)).clamp(0.0, _inputScrollCtrl.position.maxScrollExtent);
        _inputScrollCtrl.animateTo(targetScroll, duration: const Duration(milliseconds: 70), curve: Curves.easeOut);
      }
    }
  }

  void _onUniversalSearchChanged(String val) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      final q = val.trim().toLowerCase();
      _cachedGroupMatchCounts.clear();

      if (q.isEmpty) {
        setState(() {
          _universalSearchQuery = '';
          _cachedUniversalMatches = [];
        });
        return;
      }

      final List<_IndexedSearchMatch> matches = [];
      for (int gIdx = 0; gIdx < _parsedGroups.length; gIdx++) {
        final g = _parsedGroups[gIdx];
        final effTickets = _getEffectiveTicketsForGroup(gIdx);
        for (int tIdx = 0; tIdx < effTickets.length; tIdx++) {
          final t = effTickets[tIdx];
          if (t.ticketNo.toLowerCase().contains(q) || t.series.toLowerCase().contains(q)) {
            matches.add(_IndexedSearchMatch(
              ticket: t,
              group: g,
              groupIndex: gIdx,
              ticketIndex: tIdx,
            ));
            _cachedGroupMatchCounts[gIdx] = (_cachedGroupMatchCounts[gIdx] ?? 0) + 1;
          }
        }
      }

      setState(() {
        _universalSearchQuery = q;
        _cachedUniversalMatches = matches;
      });
    });
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final focused = FocusManager.instance.primaryFocus;
    final isEditingMultilineChat = focused != null && focused == _chatInputFocusNode;
    final isEditingSingleLine = focused != null &&
        focused.context?.widget is EditableText &&
        (focused.context?.widget as EditableText).maxLines == 1;

    // If user is actively typing in the multiline chat box, let arrow keys move the caret normally
    if (isEditingMultilineChat) {
      return false;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_parsedGroups.isNotEmpty) {
        _selectNextTicket();
        return true;
      } else if (_chatSearchMatchIndices.isNotEmpty) {
        _nextSearchMatch();
        return true;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_parsedGroups.isNotEmpty) {
        _selectPrevTicket();
        return true;
      } else if (_chatSearchMatchIndices.isNotEmpty) {
        _prevSearchMatch();
        return true;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      if (_parsedGroups.isNotEmpty) {
        _selectStepTickets(10);
        return true;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      if (_parsedGroups.isNotEmpty) {
        _selectStepTickets(-10);
        return true;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight && !isEditingSingleLine) {
      if (_parsedGroups.isNotEmpty) {
        _selectNextPage();
        return true;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft && !isEditingSingleLine) {
      if (_parsedGroups.isNotEmpty) {
        _selectPrevPage();
        return true;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.f3) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _prevSearchMatch();
      } else {
        _nextSearchMatch();
      }
      return true;
    }
    return false;
  }

  void _selectStepTickets(int step) {
    if (_parsedGroups.isEmpty) return;
    int gIdx = _activeGroupIndex ?? 0;
    int tIdx = _activeTicketIndex ?? 0;
    if (gIdx >= _parsedGroups.length) gIdx = 0;
    final currentTickets = _getEffectiveTicketsForGroup(gIdx);
    if (currentTickets.isEmpty) return;

    final newTIdx = (tIdx + step).clamp(0, currentTickets.length - 1);
    _setActiveTicket(gIdx, newTIdx);
  }

  void _selectNextPage() {
    _selectStepTickets(20);
  }

  void _selectPrevPage() {
    _selectStepTickets(-20);
  }

  void _selectNextTicket() {
    if (_parsedGroups.isEmpty) {
      if (_chatSearchMatchIndices.isNotEmpty) {
        _nextSearchMatch();
      }
      return;
    }

    int gIdx = _activeGroupIndex ?? 0;
    if (gIdx >= _parsedGroups.length) gIdx = 0;
    final currentTickets = _getEffectiveTicketsForGroup(gIdx);
    if (currentTickets.isEmpty) return;

    if (_universalSearchQuery.isNotEmpty && _cachedUniversalMatches.isNotEmpty) {
      final groupMatches = _cachedUniversalMatches.where((m) => m.groupIndex == gIdx).toList();
      if (groupMatches.isNotEmpty) {
        int matchIdx = -1;
        for (int i = 0; i < groupMatches.length; i++) {
          if (groupMatches[i].ticketIndex == _activeTicketIndex) {
            matchIdx = i;
            break;
          }
        }
        final nextIdx = (matchIdx + 1) % groupMatches.length;
        final m = groupMatches[nextIdx];
        _setActiveTicket(m.groupIndex, m.ticketIndex);
        return;
      }
    }

    int tIdx = _activeTicketIndex ?? -1;
    // Stay strictly within the current card / set without jumping to another card!
    final nextTIdx = (tIdx + 1) % currentTickets.length;
    _setActiveTicket(gIdx, nextTIdx);
  }

  void _selectPrevTicket() {
    if (_parsedGroups.isEmpty) {
      if (_chatSearchMatchIndices.isNotEmpty) {
        _prevSearchMatch();
      }
      return;
    }

    int gIdx = _activeGroupIndex ?? 0;
    if (gIdx >= _parsedGroups.length) gIdx = _parsedGroups.length - 1;
    final currentTickets = _getEffectiveTicketsForGroup(gIdx);
    if (currentTickets.isEmpty) return;

    if (_universalSearchQuery.isNotEmpty && _cachedUniversalMatches.isNotEmpty) {
      final groupMatches = _cachedUniversalMatches.where((m) => m.groupIndex == gIdx).toList();
      if (groupMatches.isNotEmpty) {
        int matchIdx = 0;
        for (int i = 0; i < groupMatches.length; i++) {
          if (groupMatches[i].ticketIndex == _activeTicketIndex) {
            matchIdx = i;
            break;
          }
        }
        final prevIdx = (matchIdx - 1 + groupMatches.length) % groupMatches.length;
        final m = groupMatches[prevIdx];
        _setActiveTicket(m.groupIndex, m.ticketIndex);
        return;
      }
    }

    int tIdx = _activeTicketIndex ?? 0;
    // Stay strictly within the current card / set without jumping to another card!
    final prevTIdx = (tIdx - 1 + currentTickets.length) % currentTickets.length;
    _setActiveTicket(gIdx, prevTIdx);
  }

  void _setActiveTicket(int gIdx, int tIdx, {bool fromUserTap = false}) {
    if (gIdx < 0 || gIdx >= _parsedGroups.length) return;
    final effTickets = _getEffectiveTicketsForGroup(gIdx);
    if (effTickets.isEmpty) return;
    final safeTIdx = tIdx.clamp(0, effTickets.length - 1);

    setState(() {
      _activeGroupIndex = gIdx;
      _activeTicketIndex = safeTIdx;
    });

    final t = effTickets[safeTIdx];

    // 1. LEFT SIDE: Smoothly highlight and ensure visible in chat editor
    _indicateTicketInChatText(
      t.ticketNo,
      originalLine: t.rawOriginalLine,
      targetLineNumber: t.lineNumber,
      focusChat: false,
      allowWindowSlide: true,
    );

    // 2. RIGHT SIDE: Ensure active card row is comfortably visible in the card's scroll view
    void ensureCardRowVisible() {
      final ctrl = _getCardRowsScrollController(gIdx);
      if (!ctrl.hasClients) return;

      final rowTop = 4.0 + safeTIdx * 38.0;
      final rowBottom = rowTop + 38.0;
      final curScroll = ctrl.offset;
      final viewportHeight = ctrl.position.viewportDimension;

      // Keep 3-row buffer (114px) so upcoming tickets below are always visible ahead
      final minVis = curScroll + 114.0;
      final maxVis = curScroll + viewportHeight - 114.0;

      if (rowTop < minVis) {
        final target = (rowTop - 114.0).clamp(0.0, ctrl.position.maxScrollExtent);
        ctrl.animateTo(target, duration: const Duration(milliseconds: 70), curve: Curves.easeOut);
      } else if (rowBottom > maxVis) {
        final target = (rowBottom + 114.0 - viewportHeight).clamp(0.0, ctrl.position.maxScrollExtent);
        ctrl.animateTo(target, duration: const Duration(milliseconds: 70), curve: Curves.easeOut);
      }
    }

    ensureCardRowVisible();
  }

  void _reCenterActiveTicketInParallel() {
    if (_activeGroupIndex != null && _activeTicketIndex != null) {
      final eff = _getEffectiveTicketsForGroup(_activeGroupIndex!);
      if (_activeTicketIndex! < eff.length) {
        final t = eff[_activeTicketIndex!];
        _indicateTicketInChatText(
          t.ticketNo,
          originalLine: t.rawOriginalLine,
          targetLineNumber: t.lineNumber,
          allowWindowSlide: true,
        );
        final ctrl = _getCardRowsScrollController(_activeGroupIndex!);
        if (ctrl.hasClients) {
          final rowCenterY = 4.0 + _activeTicketIndex! * 38.0 + 19.0;
          final vHeight = ctrl.position.viewportDimension;
          ctrl.animateTo(
            (rowCenterY - (vHeight / 2.0)).clamp(0.0, ctrl.position.maxScrollExtent),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }
  }

  void _changeChatFontSize(double delta) {
    setState(() {
      _chatFontSize = (_chatFontSize + delta).clamp(9.0, 26.0);
      _chatInputCtrl.invalidateSpanCache();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reCenterActiveTicketInParallel();
    });
  }



  Future<void> _parseBulkChat({String? fullTextOverride, bool isFromManualAdd = false}) async {
    if (_isParsing) {
      _reparseRequested = true;
      return;
    }
    setState(() => _isParsing = true);
    await Future.delayed(const Duration(milliseconds: 5)); // Allow frame render for loading indicator

    final rawText = fullTextOverride ?? _chatInputCtrl.text;
    if (rawText.trim().isEmpty) {
      setState(() {
        _parsedGroups = [];
        _selectedGroupIndices.clear();
        _chatSearchMatchIndices = [];
        _currentSearchMatchIndex = -1;
        _cachedUniversalMatches = [];
        _isParsing = false;
      });
      return;
    }

    try {
      final priceState = ref.read(seriesPriceViewModelProvider);
      final Map<String, double> priceMap = {};
      for (final p in priceState.seriesList) {
        priceMap[p.seriesName] = p.ticketPrice;
      }

      final customParty = _buyerCtrl.text.trim();
      final hasCustomParty = customParty.isNotEmpty && customParty.toLowerCase() != 'party';
      final defaultParty = hasCustomParty ? customParty : 'Party';

      final params = BulkParserParams(
        rawText: rawText,
        defaultShift: _targetShift,
        defaultSeller: defaultParty,
        fallbackSeries: _fallbackSeries,
        seriesPriceMap: priceMap,
        targetDate: _targetDate,
        enableAiAutoCorrect: true,
        autoDetectShift: _operationMode == 'auto',
        autoDetectSeller: !hasCustomParty,
        autoDetectDate: !_enforceStrictTargetDate,
      );

      final result = await WhatsAppBulkParserEngine.instance.parseBulkChat(params);

      // Group tickets into Shift Groups strictly by Date + Shift (so ALL tickets for that shift appear in ONE card)
      final Map<String, BulkShiftGroup> groupMap = {};
      for (final t in result.tickets) {
        if (_enforceStrictTargetDate) {
          final isSameDate = t.ticketDate.year == _targetDate.year &&
              t.ticketDate.month == _targetDate.month &&
              t.ticketDate.day == _targetDate.day;
          if (!isSameDate) continue;
        }

        final groupKey = '${t.ticketDate.year}_${t.ticketDate.month}_${t.ticketDate.day}_${t.shiftName}';
        final effectiveParty = hasCustomParty ? customParty : (defaultParty.isNotEmpty && defaultParty != 'Party' ? defaultParty : (t.buyerName.isNotEmpty ? t.buyerName : 'Party'));
        final group = groupMap.putIfAbsent(groupKey, () => BulkShiftGroup(
          shiftName: t.shiftName,
          drawDate: t.ticketDate,
          buyerName: effectiveParty,
          tickets: [],
        ));
        group.tickets.add(t);
      }

      final groupList = groupMap.values.toList()
        ..sort((a, b) {
          final dateCmp = a.drawDate.compareTo(b.drawDate);
          if (dateCmp != 0) return dateCmp;
          return a.shiftName.compareTo(b.shiftName);
        });

      if (mounted) {
        setState(() {
          _parsedGroups = groupList;
          if (groupList.isNotEmpty && !_enforceStrictTargetDate) {
            _targetDate = groupList.first.drawDate;
          }
          _unparsedLines = result.unparsedLines.where((l) {
            final trim = l.trim();
            if (trim.isEmpty) return false;
            if (trim.contains('end-to-end encrypted')) return false;
            if (trim.contains('<Media omitted>')) return false;
            return true;
          }).toList();
          _selectedGroupIndices.clear();
          for (int i = 0; i < groupList.length; i++) {
            _selectedGroupIndices.add(i);
          }
          _isParsing = false;
        });

        if (isFromManualAdd && groupList.isNotEmpty) {
          // Identify which group received the latest manual ticket
          int targetGroupIdx = (_activeGroupIndex ?? 0).clamp(0, groupList.length - 1);
          if (_manualAddedSignatures.isNotEmpty) {
            final latestSig = _manualAddedSignatures.last;
            for (int i = 0; i < groupList.length; i++) {
              if (groupList[i].tickets.any((t) => '${t.series}-${t.ticketNo}-${t.quantity}' == latestSig)) {
                targetGroupIdx = i;
                break;
              }
            }
          }

          final effTickets = _getEffectiveTicketsForGroup(targetGroupIdx);
          final lastTktIndex = effTickets.isNotEmpty ? effTickets.length - 1 : 0;

          if (_manualAddedSignatures.isNotEmpty) {
            final lastSig = _manualAddedSignatures.last;
            final series = lastSig.split('-').first;
            _collapsedSeriesKeys.remove('${targetGroupIdx}_$series');
          }

          _setActiveTicket(targetGroupIdx, lastTktIndex);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Scroll right card rows to very bottom so the new ticket is immediately visible live
            final ctrl = _cardRowsScrollControllers[targetGroupIdx];
            if (ctrl != null && ctrl.hasClients) {
              ctrl.jumpTo(ctrl.position.maxScrollExtent);
            }
            // Scroll left chat text to very bottom so the newly added line is visible above quick add
            if (_inputScrollCtrl.hasClients) {
              _inputScrollCtrl.jumpTo(_inputScrollCtrl.position.maxScrollExtent);
            }
          });
        }

        if (_universalSearchQuery.isNotEmpty) {
          _onUniversalSearchChanged(_universalSearchQuery);
        }
      }
    } catch (e, stack) {
      debugPrint('Error parsing bulk chat: $e\n$stack');
      if (mounted) setState(() => _isParsing = false);
    } finally {
      if (_reparseRequested && mounted) {
        _reparseRequested = false;
        Future.microtask(() {
          if (mounted) _parseBulkChat();
        });
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
      if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else if (file.bytes != null) {
        content = utf8.decode(file.bytes!);
      }

      final lineCount = content.split('\n').length;
      if (lineCount > _chatChunkSize) {
        _enterLargeMode(content);
      } else {
        _isLargeMode = false;
        _fullChatText = null;
        _chatInputCtrl.text = content;
        await _parseBulkChat(fullTextOverride: content);
      }
    }
  }

  Future<void> _pickAndProcessZipFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      Uint8List? zipBytes = file.bytes;
      if (zipBytes == null && file.path != null) {
        zipBytes = await File(file.path!).readAsBytes();
      }

      if (zipBytes == null || zipBytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Could not read ZIP file data.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      // Show unpacking dialog
      BuildContext? unpackDialogCtx;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          unpackDialogCtx = ctx;
          return Dialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.amberAccent),
                  SizedBox(width: 16),
                  Text('Unpacking WhatsApp ZIP archive...', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13.5)),
                ],
              ),
            ),
          );
        },
      );

      final zipResult = await WhatsAppZipService.instance.extractZip(zipBytes);

      if (unpackDialogCtx != null && unpackDialogCtx!.mounted) {
        Navigator.of(unpackDialogCtx!).pop();
      }

      if (!zipResult.hasChatText && !zipResult.hasMediaImages) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ ZIP archive me koi chat text ya photos nahi mile!'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
        return;
      }

      // 1. Process Text Chat Messages
      if (zipResult.hasChatText) {
        final content = zipResult.chatText!;
        final lineCount = content.split('\n').length;
        if (lineCount > _chatChunkSize) {
          _enterLargeMode(content);
        } else {
          _isLargeMode = false;
          _fullChatText = null;
          _chatInputCtrl.text = content;
          await _parseBulkChat(fullTextOverride: content);
        }
      }

      // 2. Process Media Images with Gemini AI if any photos exist in the ZIP
      if (zipResult.hasMediaImages && mounted) {
        final photosCount = zipResult.mediaImages.length;
        final shouldScan = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Colors.amberAccent, width: 1.2),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Colors.amberAccent, size: 22),
                ),
                const SizedBox(width: 10),
                Text('$photosCount Attached Photos Found', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
            content: Text(
              'WhatsApp ZIP me $photosCount photos (tickets/parchi) mili hain.\n\nKya aap Gemini Vision AI ke zariye in photos ko scan karke tickets nikaalna chahte hain?',
              style: const TextStyle(fontSize: 12.5, color: Colors.white70, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Skip Photos', style: TextStyle(color: Colors.white60)),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.black),
                label: const Text('Scan with Gemini AI', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        );

        if (shouldScan == true && mounted) {
          await _scanAndReviewZipMedia(zipResult.mediaImages);
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 WhatsApp ZIP text successfully loaded (${zipResult.chatFileName ?? 'chat.txt'})!'),
            backgroundColor: Colors.teal.shade700,
          ),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error processing ZIP: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading ZIP file: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _scanAndReviewZipMedia(List<WhatsAppZipMediaItem> mediaItems) async {
    final allFilesBytes = mediaItems.map((m) => m.bytes).toList();
    if (allFilesBytes.isEmpty) return;

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
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.amberAccent),
                const SizedBox(width: 20),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<String>(
                      valueListenable: scanProgressNotifier,
                      builder: (_, msg, _) => Text(
                        msg,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Gemini AI extracting tickets and series...',
                      style: TextStyle(color: Colors.white60, fontSize: 11.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    final List<GeminiScannedItem> scannedTickets = [];
    try {
      for (int i = 0; i < mediaItems.length; i++) {
        final item = mediaItems[i];
        if (mediaItems.length > 1) {
          scanProgressNotifier.value = 'Scanning Photo ${i + 1} of ${mediaItems.length} (${item.filename})...';
        }
        final seller = item.sender ?? (_buyerCtrl.text.isNotEmpty ? _buyerCtrl.text : 'Party');
        final items = await GeminiScannerService.instance.scanImage(
          imageBytes: item.bytes,
          defaultSeller: seller,
        );
        for (final t in items) {
          t.photoIndex = i;
          if (item.date != null) {
            t.targetDate = DateFormat('yyyy-MM-dd').format(item.date!);
          }
          if (item.shift != null && item.shift!.isNotEmpty) {
            t.drawShift = item.shift;
          }
          if (t.sellerName == 'Walk-in Customer' && seller.isNotEmpty) {
            t.sellerName = seller;
          }
        }
        scannedTickets.addAll(items);
      }
    } catch (scanErr) {
      debugPrint('⚠️ [ZIP SCAN ERROR] $scanErr');
    } finally {
      if (progressDialogCtx != null && progressDialogCtx!.mounted) {
        Navigator.of(progressDialogCtx!, rootNavigator: true).pop();
      }
    }

    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;

    final firstItem = mediaItems.first;
    final activeShift = firstItem.shift ?? _targetShift;
    final activeDate = firstItem.date ?? _targetDate;
    final defaultSeller = firstItem.sender ?? (_buyerCtrl.text.isNotEmpty ? _buyerCtrl.text : 'Party');

    // Open Confirmation & Review Modal with Image Preview & Editing
    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AiPhotoReviewDialog(
        imageBytes: allFilesBytes.first,
        allImageBytes: allFilesBytes,
        initialItems: scannedTickets,
        activeShift: activeShift,
        activeDate: activeDate,
        defaultSeller: defaultSeller,
      ),
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 ${scannedTickets.length} photo tickets verified and saved successfully!'),
          backgroundColor: Colors.teal.shade700,
        ),
      );
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      final text = data.text!;
      final lineCount = text.split('\n').length;
      if (lineCount > _chatChunkSize) {
        _enterLargeMode(text);
      } else {
        _isLargeMode = false;
        _fullChatText = null;
        _chatInputCtrl.text = text;
        await _parseBulkChat(fullTextOverride: text);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📋 WhatsApp chat pasted and parsed successfully!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _clearAll() {
    _chatInputCtrl.clear();
    _chatSearchCtrl.clear();
    _universalSearchCtrl.clear();
    _quickTicketCtrl.clear();
    _fullChatText = null;
    _isLargeMode = false;
    _chunkLineCount = 0;
    _cardSeriesFilter.clear();
    _groupPageIndices.clear();
    _manualAddedSignatures.clear();
    setState(() {
      _parsedGroups = [];
      _selectedGroupIndices.clear();
      _chatSearchMatchIndices = [];
      _currentSearchMatchIndex = -1;
      _cachedUniversalMatches = [];
      _universalSearchQuery = '';
    });
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
                final origIdx = group.tickets.indexOf(ticket);
                if (origIdx != -1) {
                  group.tickets.removeAt(origIdx);
                  group.invalidateCache();
                } else if (ticketIndex < group.tickets.length) {
                  group.tickets.removeAt(ticketIndex);
                  group.invalidateCache();
                }
                if (group.tickets.isEmpty) {
                  final idx = _parsedGroups.indexOf(group);
                  _parsedGroups.remove(group);
                  _selectedGroupIndices.remove(idx);
                  _cardSeriesFilter.remove(idx);
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final newSeries = seriesCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
              final newTkt = ticketCtrl.text.trim();
              if (newTkt.isNotEmpty) {
                final s = newSeries.isNotEmpty ? newSeries : '12';
                final t = newTkt.padLeft(5, '0');

                final priceState = ref.read(seriesPriceViewModelProvider);
                double newPrice = 45.0;
                for (final p in priceState.seriesList) {
                  if (p.seriesName == s) {
                    newPrice = p.ticketPrice;
                    break;
                  }
                }

                setState(() {
                  final updatedTicket = BulkParsedTicket(
                    series: s,
                    ticketNo: t,
                    quantity: ticket.quantity,
                    pricePerTicket: newPrice,
                    buyerName: ticket.buyerName,
                    shiftName: ticket.shiftName,
                    ticketDate: ticket.ticketDate,
                    rawOriginalLine: '$s $t',
                    lineNumber: ticket.lineNumber,
                    isAutoCorrected: true,
                    autoCorrectReason: 'Manually updated',
                  );
                  final origIdx = group.tickets.indexOf(ticket);
                  if (origIdx != -1) {
                    group.tickets[origIdx] = updatedTicket;
                  } else if (ticketIndex < group.tickets.length) {
                    group.tickets[ticketIndex] = updatedTicket;
                  }
                  group.invalidateCache();
                });

                // Update line in _fullChatText and _chatInputCtrl if original line was found
                final oldLine = ticket.rawOriginalLine.trim();
                if (oldLine.isNotEmpty) {
                  if (_fullChatText != null && _fullChatText!.contains(oldLine)) {
                    _fullChatText = _fullChatText!.replaceFirst(oldLine, '$s $t');
                  }
                  final full = _chatInputCtrl.text;
                  if (full.contains(oldLine)) {
                    _chatInputCtrl.text = full.replaceFirst(oldLine, '$s $t');
                  }
                }

                if (_universalSearchQuery.isNotEmpty) {
                  _onUniversalSearchChanged(_universalSearchQuery);
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ Updated Ticket #$s-$t successfully!'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('Update Ticket', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditPartyDialog(BulkShiftGroup group) async {
    final ctrl = TextEditingController(text: group.buyerName == 'Party' ? '' : group.buyerName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.tealAccent, width: 1.2),
        ),
        title: Row(
          children: const [
            Icon(Icons.person_rounded, color: Colors.tealAccent, size: 22),
            SizedBox(width: 8),
            Text('Change Party / Buyer Name', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the Party or Customer name for this booking:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Party / Buyer Name',
                labelStyle: const TextStyle(color: Colors.tealAccent),
                hintText: 'e.g. SK, Raju, Kolkata...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: AppColors.surfaceContainerLowest,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.tealAccent)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.tealAccent.withValues(alpha: 0.6))),
              ),
              onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Save Party Name', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && mounted) {
      setState(() {
        _buyerCtrl.text = newName;
      });
      _parseBulkChat();
    }
  }

  void _jumpToUnparsedIssue(int index) {
    if (_unparsedLines.isEmpty) return;
    final safeIdx = index.clamp(0, _unparsedLines.length - 1);
    setState(() {
      _currentUnparsedIndex = safeIdx;
    });
    final line = _unparsedLines[safeIdx].trim();
    _indicateTicketInChatText(
      line,
      originalLine: line,
      focusChat: true,
      allowWindowSlide: true,
    );
  }

  void _nextUnparsedIssue() {
    if (_unparsedLines.isEmpty) return;
    final nextIdx = (_currentUnparsedIndex + 1) % _unparsedLines.length;
    _jumpToUnparsedIssue(nextIdx);
  }

  void _prevUnparsedIssue() {
    if (_unparsedLines.isEmpty) return;
    final prevIdx = (_currentUnparsedIndex - 1 + _unparsedLines.length) % _unparsedLines.length;
    _jumpToUnparsedIssue(prevIdx);
  }

  void _deleteUnparsedLine(String lineToDelete) {
    final target = lineToDelete.trim();
    if (target.isEmpty) return;

    if (_isLargeMode && _fullChatText != null) {
      _syncCurrentChatChunkToFullText();
      final allLines = _fullChatText!.split('\n');
      final updated = allLines.where((l) => l.trim() != target).join('\n');
      _fullChatText = updated;
      _loadChatWindow(centerAroundLine: _chatWindowStartLine + 1, resetScroll: false);
    } else {
      final allLines = _chatInputCtrl.text.split('\n');
      final updated = allLines.where((l) => l.trim() != target).join('\n');
      _chatInputCtrl.text = updated;
    }
    _parseBulkChat();
  }

  void _deleteUnparsedLineAt(int index) {
    if (_unparsedLines.isEmpty) return;
    final safeIdx = index.clamp(0, _unparsedLines.length - 1);
    final lineToDelete = _unparsedLines[safeIdx];
    _deleteUnparsedLine(lineToDelete);
    if (_currentUnparsedIndex >= _unparsedLines.length - 1) {
      _currentUnparsedIndex = math.max(0, _unparsedLines.length - 2);
    }
  }

  void _replaceUnparsedLine(String oldLine, String newLine) {
    final oldTrim = oldLine.trim();
    if (oldTrim.isEmpty) return;

    if (_isLargeMode && _fullChatText != null) {
      _syncCurrentChatChunkToFullText();
      final allLines = _fullChatText!.split('\n');
      final updatedList = allLines.map((l) => l.trim() == oldTrim ? newLine : l).toList();
      final updated = updatedList.join('\n');
      _fullChatText = updated;
      _loadChatWindow(centerAroundLine: _chatWindowStartLine + 1, resetScroll: false);
    } else {
      final allLines = _chatInputCtrl.text.split('\n');
      final updated = allLines.map((l) => l.trim() == oldTrim ? newLine : l).join('\n');
      _chatInputCtrl.text = updated;
    }
    _parseBulkChat();
  }

  void _promptQuickFixLine(String oldLine) {
    final editCtrl = TextEditingController(text: oldLine.trim());
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white24),
          ),
          title: const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: Colors.amberAccent, size: 20),
              SizedBox(width: 8),
              Text('Edit / Fix Line', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Original Line in Chat:', style: TextStyle(fontSize: 11, color: Colors.white54)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
                child: Text(oldLine, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Colors.amberAccent)),
              ),
              const SizedBox(height: 12),
              const Text('Replace with:', style: TextStyle(fontSize: 11, color: Colors.white54)),
              const SizedBox(height: 4),
              TextField(
                controller: editCtrl,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.tealAccent)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
              onPressed: () {
                final newText = editCtrl.text.trim();
                Navigator.pop(ctx);
                if (newText.isNotEmpty && newText != oldLine.trim()) {
                  _replaceUnparsedLine(oldLine, newText);
                }
              },
              child: const Text('Save & Reparse', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUnderReviewStrip() {
    if (_unparsedLines.isEmpty) return const SizedBox.shrink();
    final safeIdx = _currentUnparsedIndex.clamp(0, _unparsedLines.length - 1);
    final currentSnippet = _unparsedLines[safeIdx].trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF261805),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.8), width: 1.1),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 15, color: Colors.amberAccent),
          const SizedBox(width: 6),
          Text(
            '${_unparsedLines.length} Issues:',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amberAccent),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: _prevUnparsedIssue,
            borderRadius: BorderRadius.circular(3),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(3)),
              child: const Icon(Icons.keyboard_arrow_left_rounded, size: 16, color: Colors.amberAccent),
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '${safeIdx + 1}/${_unparsedLines.length}',
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(width: 3),
          InkWell(
            onTap: _nextUnparsedIssue,
            borderRadius: BorderRadius.circular(3),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(3)),
              child: const Icon(Icons.keyboard_arrow_right_rounded, size: 16, color: Colors.amberAccent),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              currentSnippet,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 6),
          // Locate Button (Zero popup!)
          InkWell(
            onTap: () => _jumpToUnparsedIssue(safeIdx),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.tealAccent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.near_me_rounded, size: 11, color: Colors.black),
                  SizedBox(width: 3),
                  Text('Locate', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Quick Fix Button
          InkWell(
            onTap: () => _promptQuickFixLine(currentSnippet),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Edit', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70)),
            ),
          ),
          const SizedBox(width: 4),
          // Remove Line Button
          InkWell(
            onTap: () => _deleteUnparsedLineAt(safeIdx),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.redAccent, width: 0.8),
              ),
              child: const Text('Del', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.redAccent)),
            ),
          ),
          const SizedBox(width: 6),
          // Toggle All List in right panel
          InkWell(
            onTap: () {
              setState(() {
                _showDockedReviewPanel = !_showDockedReviewPanel;
              });
            },
            child: Text(
              _showDockedReviewPanel ? 'Hide All ▲' : 'All (${_unparsedLines.length}) ▼',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amberAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDockedReviewPanel() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.8), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                const Icon(Icons.rate_review_rounded, color: Colors.amberAccent, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Lines Under Review (${_unparsedLines.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amberAccent),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '• Click Locate to view line in chat without closing panel • Edit or Delete line',
                    style: TextStyle(fontSize: 9.5, color: Colors.white54),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() => _showDockedReviewPanel = false);
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _unparsedLines.length,
              separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 1),
              itemBuilder: (ctx, idx) {
                final line = _unparsedLines[idx];
                final isCurrent = idx == _currentUnparsedIndex;
                return Container(
                  color: isCurrent ? Colors.amber.withValues(alpha: 0.09) : Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        alignment: Alignment.center,
                        child: Text(
                          '${idx + 1}',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: isCurrent ? Colors.amberAccent : Colors.white38,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          line,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: isCurrent ? Colors.amberAccent : Colors.white,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Locate Button
                      InkWell(
                        onTap: () {
                          setState(() => _currentUnparsedIndex = idx);
                          _indicateTicketInChatText(
                            line.trim(),
                            originalLine: line.trim(),
                            focusChat: true,
                            allowWindowSlide: true,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.tealAccent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_rounded, size: 11, color: Colors.black),
                              SizedBox(width: 3),
                              Text('Locate', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Edit Button
                      InkWell(
                        onTap: () => _promptQuickFixLine(line),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Edit', style: TextStyle(fontSize: 10, color: Colors.white70)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Delete Button
                      InkWell(
                        onTap: () => _deleteUnparsedLine(line),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6), width: 0.8),
                          ),
                          child: const Text('Del', style: TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold)),
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
    );
  }

  Future<void> _saveAndBookAll() async {
    final selectedIndices = _selectedGroupIndices.toList()..sort();
    if (selectedIndices.isEmpty) return;

    int totalTicketsCount = 0;
    double totalSalesValue = 0.0;
    final List<MapEntry<BulkShiftGroup, List<BulkParsedTicket>>> groupsToSave = [];

    for (final gIdx in selectedIndices) {
      if (gIdx < 0 || gIdx >= _parsedGroups.length) continue;
      final group = _parsedGroups[gIdx];
      final effTickets = _getEffectiveTicketsForGroup(gIdx);
      if (effTickets.isEmpty) continue;

      totalTicketsCount += effTickets.fold<int>(0, (sum, t) => sum + t.quantity);
      totalSalesValue += effTickets.fold<double>(0.0, (sum, t) => sum + t.totalAmount);
      groupsToSave.add(MapEntry(group, effTickets));
    }

    if (totalTicketsCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Selected cards/series filters me koi ticket save karne ke liye nahi hai!'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final hasCustomParty = _buyerCtrl.text.trim().isNotEmpty && _buyerCtrl.text.trim().toLowerCase() != 'party';
    final customParty = _buyerCtrl.text.trim();
    final defaultGroupParty = groupsToSave.isNotEmpty && groupsToSave.first.key.buyerName.isNotEmpty && groupsToSave.first.key.buyerName.toLowerCase() != 'party'
        ? groupsToSave.first.key.buyerName
        : 'Party';
    final partyName = hasCustomParty ? customParty : defaultGroupParty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.tealAccent, width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.tealAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check_circle_outline_rounded, color: Colors.tealAccent, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Confirm Booking & Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 2),
                  Text('Kya aap selected tickets ko save karna chahte hain?', style: TextStyle(color: Colors.white60, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF141E33),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Party Name:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(partyName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent)),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Selected Cards / Shifts:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text('${groupsToSave.length} Cards', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Tickets to Book:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text('$totalTicketsCount Tkts', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.greenAccent)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Gross Amount:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text('₹${totalSalesValue.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.amberAccent)),
                      ],
                    ),
                  ],
                ),
              ),
              if (_unparsedLines.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Colors.amberAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Note: Review Section me ${_unparsedLines.length} unparsed lines hain jo book nahi hongi.',
                          style: const TextStyle(fontSize: 11, color: Colors.amberAccent),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            icon: const Icon(Icons.save_rounded, size: 16),
            label: Text('Confirm & Save ($totalTicketsCount Tkts)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _isSaving = true);

    try {
      final List<TicketSaleModel> allSales = [];
      int counter = 0;

      for (final entry in groupsToSave) {
        final group = entry.key;
        final effTickets = entry.value;
        final effectiveCardParty = hasCustomParty
            ? customParty
            : (group.buyerName.isNotEmpty && group.buyerName.toLowerCase() != 'party'
                ? group.buyerName
                : (partyName.isNotEmpty && partyName.toLowerCase() != 'party' ? partyName : 'Walk-in Customer'));
        for (final t in effTickets) {
          counter++;
          allSales.add(t.toTicketSaleModel(
            receiptPrefix: 'WA',
            index: counter,
            partyOverride: effectiveCardParty,
          ));
        }
      }

      await DatabaseService.instance.insertTicketSalesBulk(allSales);

      if (mounted) {
        setState(() => _isSaving = false);

        // Show Post-Save Success Confirmation Modal
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (successCtx) => AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.greenAccent, width: 1.5),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 28),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Booking Saved Successfully! 🎉', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      SizedBox(height: 2),
                      Text('Database me ticket bookings successfully save ho gayi hain.', style: TextStyle(color: Colors.white60, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF141E33),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Party Name:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(partyName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent)),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Tickets Booked:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text('$totalTicketsCount Tkts', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.greenAccent)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Gross Amount:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text('₹${totalSalesValue.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.amberAccent)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Cards / Shifts:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text('${groupsToSave.length} Cards Saved', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(successCtx);
                },
                child: const Text('Keep View', style: TextStyle(color: Colors.white60)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                icon: const Icon(Icons.add_task_rounded, size: 16),
                label: const Text('Start New Booking (Clear)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () {
                  Navigator.pop(successCtx);
                  _clearAll();
                },
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final priceState = ref.watch(seriesPriceViewModelProvider);
    SeriesColorRegistry.updateFromList(priceState.seriesList);

    int selectedTicketsCount = 0;
    double selectedTotalAmount = 0.0;
    for (final groupIndex in _selectedGroupIndices) {
      if (groupIndex >= 0 && groupIndex < _parsedGroups.length) {
        final effTickets = _getEffectiveTicketsForGroup(groupIndex);
        selectedTicketsCount += effTickets.fold<int>(0, (sum, t) => sum + t.quantity);
        selectedTotalAmount += effTickets.fold<double>(0.0, (sum, t) => sum + t.totalAmount);
      }
    }

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: ScrollConfiguration(
        behavior: const DesktopSmoothScrollBehavior(),
        child: Column(
          children: [
            // 1. Top Enterprise Control Bar
            _buildTopControlBar(),

            // 2. Main Workspace Split View
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Panel: WhatsApp Chat Monospace Editor / Inspector
                    Expanded(
                      flex: 4,
                      child: _buildLeftChatPanel(),
                    ),

                    const SizedBox(width: 14),

                    // Right Panel: Parsed Cards & Universal Verification
                    Expanded(
                      flex: 6,
                      child: _buildRightCardsPanel(selectedTicketsCount, selectedTotalAmount),
                    ),
                  ],
                ),
              ),
            ),

            // 3. Saving Progress Bar (if active)
            if (_isSaving)
              const LinearProgressIndicator(
                backgroundColor: AppColors.surfaceContainerHigh,
                color: AppColors.primary,
              ),

            // 4. Bottom Master Action Footer Bar
            _buildBottomFooterBar(selectedTicketsCount, selectedTotalAmount),
          ],
        ),
      ),
    );
  }

  Widget _buildTopControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            // Title & Icon
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.tealAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.tealAccent, width: 1.2),
              ),
              child: const Icon(Icons.mark_chat_read_rounded, color: Colors.tealAccent, size: 20),
            ),
            const SizedBox(width: 8),
            const Text(
              'WhatsApp Booking',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),

            const SizedBox(width: 14),

            // Party / Buyer Text Field (PROMINENT, FRONT POSITION)
            SizedBox(
              width: 165,
              height: 34,
              child: TextField(
                controller: _buyerCtrl,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.person_rounded, size: 16, color: Colors.tealAccent),
                  labelText: 'Party / Buyer',
                  labelStyle: const TextStyle(fontSize: 10.5, color: Colors.tealAccent, fontWeight: FontWeight.bold),
                  hintText: 'Enter Party Name...',
                  hintStyle: const TextStyle(fontSize: 10, color: Colors.white38),
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.tealAccent, width: 1.2)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.tealAccent.withValues(alpha: 0.6), width: 1.2)),
                ),
                onChanged: (val) {
                  _parseDebounceTimer?.cancel();
                  _parseDebounceTimer = Timer(const Duration(milliseconds: 250), () {
                    if (mounted) _parseBulkChat();
                  });
                },
                onSubmitted: (_) => _parseBulkChat(),
              ),
            ),

            const SizedBox(width: 12),

            // Date Picker Button
            InkWell(
              onTap: () async {
                final first = _targetDate.isBefore(DateTime(2020)) ? _targetDate : DateTime(2020);
                final last = _targetDate.isAfter(DateTime(2035)) ? _targetDate : DateTime(2035);
                final d = await showDatePicker(
                  context: context,
                  initialDate: _targetDate,
                  firstDate: first,
                  lastDate: last,
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
                  border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.7)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.amberAccent),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('dd/MM/yyyy').format(_targetDate),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Colors.amberAccent),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 10),

            // Strict Date Lock Switch
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Date Lock:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                const SizedBox(width: 4),
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

            const SizedBox(width: 10),

            // Shift Quick Buttons: Dear 1 PM | Dear 6 PM | Dear 8 PM (Always visible & 1-click selectable!)
            Container(
              height: 32,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTopShiftBtn('Dear 1 PM', '1:00 PM', const Color(0xFF2DD4BF)),
                  const SizedBox(width: 4),
                  _buildTopShiftBtn('Dear 6 PM', '6:00 PM', const Color(0xFFF59E0B)),
                  const SizedBox(width: 4),
                  _buildTopShiftBtn('Dear 8 PM', '8:00 PM', const Color(0xFFA855F7)),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // Mode Choice Chips
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

            const SizedBox(width: 8),

            // Fallback Series Dropdown
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _fallbackSeries,
                  dropdownColor: AppColors.surfaceContainerHigh,
                  items: const ['6', '10', '12', '14', '16', '18', '20', '24', '30', '36', '40', '48', '50', '60', '100'].map((item) {
                    return DropdownMenuItem<String>(
                      value: item,
                      child: Text('Default: $item', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _fallbackSeries = val);
                      _parseBulkChat();
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftChatPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Paste WhatsApp Chat:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 8),
                      // Text Font Size Controls (Badhane / Ghatane ka)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: 'Text size chhota karein (A-)',
                              child: InkWell(
                                onTap: () => _changeChatFontSize(-1.0),
                                borderRadius: BorderRadius.circular(4),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  child: Text('A-', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                _chatFontSize.toStringAsFixed(1),
                                style: const TextStyle(fontSize: 11, color: Colors.tealAccent, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Tooltip(
                              message: 'Text size bada karein (A+)',
                              child: InkWell(
                                onTap: () => _changeChatFontSize(1.0),
                                borderRadius: BorderRadius.circular(4),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  child: Text('A+', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    icon: _isParsing
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.sync_rounded, size: 15),
                    label: Text(
                      _isParsing ? 'Updating...' : 'Update',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.tealAccent,
                      foregroundColor: Colors.black,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      minimumSize: const Size(0, 28),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: _isParsing ? null : _forceReparseCurrentText,
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.paste_rounded, size: 18, color: AppColors.primary),
                    tooltip: 'Paste from clipboard',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    onPressed: _pasteFromClipboard,
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_open_rounded, size: 18, color: Colors.purpleAccent),
                    tooltip: 'Import .txt file',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    onPressed: _pickChatFile,
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_zip_rounded, size: 19, color: Colors.amberAccent),
                    tooltip: 'Import WhatsApp .zip (Chat + Photos)',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    onPressed: _pickAndProcessZipFile,
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear_all_rounded, size: 18, color: Colors.redAccent),
                    tooltip: 'Clear input',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    onPressed: _clearAll,
                  ),
                ],
              ),
            ],
          ),

          // Live Syntax Colors Legend Bar
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.palette_outlined, size: 12, color: Colors.tealAccent),
                const SizedBox(width: 5),
                const Text('Live Colors:', style: TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                _buildColorLegendChip('Series', const Color(0xFF22D3EE)),
                const SizedBox(width: 6),
                _buildColorLegendChip('Ticket #', const Color(0xFFFDE047)),
                const SizedBox(width: 6),
                _buildColorLegendChip('Sender', const Color(0xFFA78BFA)),
                const SizedBox(width: 6),
                _buildColorLegendChip('Header', const Color(0xFF34D399)),
                const Spacer(),
                InkWell(
                  onTap: () {
                    setState(() {
                      _chatInputCtrl.syntaxHighlightingEnabled = !_chatInputCtrl.syntaxHighlightingEnabled;
                    });
                  },
                  child: Text(
                    _chatInputCtrl.syntaxHighlightingEnabled ? 'Color: ON' : 'Color: OFF',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _chatInputCtrl.syntaxHighlightingEnabled ? Colors.tealAccent : Colors.white38,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // In-Chat Search Bar with Yellow Highlight
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _chatSearchMatchIndices.isNotEmpty
                    ? const Color(0xFFFFD700)
                    : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                const Icon(Icons.search_rounded, size: 16, color: Color(0xFFFFD700)),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _chatSearchCtrl,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Search number ya text (e.g. 41151)...',
                      hintStyle: TextStyle(fontSize: 11, color: Colors.white38),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: _onChatSearchChanged,
                    onSubmitted: (_) => _nextSearchMatch(),
                  ),
                ),
                if (_chatSearchCtrl.text.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: _chatSearchMatchIndices.isNotEmpty ? const Color(0xFFFFD700) : Colors.white10,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      _chatSearchMatchIndices.isNotEmpty
                          ? '${_currentSearchMatchIndex + 1}/${_chatSearchMatchIndices.length}'
                          : '0/0',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _chatSearchMatchIndices.isNotEmpty ? Colors.black : Colors.white60,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    onPressed: _chatSearchMatchIndices.isNotEmpty ? _nextSearchMatch : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    onPressed: _chatSearchMatchIndices.isNotEmpty ? _prevSearchMatch : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 14),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    color: Colors.white54,
                    onPressed: _clearChatSearch,
                  ),
                ],
              ],
            ),
          ),

          // Large Mode Indicator Banner with Sliding Window Chunk Navigation
          if (_isLargeMode)
            Builder(
              builder: (ctx) {
                final totalLines = _fullChatText?.split('\n').length ?? 0;
                final startLine = _chatWindowStartLine + 1;
                final endLine = math.min(_chatWindowStartLine + _chunkLineCount, totalLines);

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade900.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.tealAccent),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.swap_vert_rounded, size: 15, color: Colors.tealAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '⚡ Lines $startLine–$endLine of $totalLines (Auto-slide)',
                          style: const TextStyle(fontSize: 10.5, color: Colors.tealAccent, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 16, color: Colors.tealAccent),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        tooltip: 'Previous lines',
                        onPressed: _chatWindowStartLine > 0 ? _prevChatChunk : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.tealAccent),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        tooltip: 'Next lines',
                        onPressed: (_chatWindowStartLine + _chunkLineCount < totalLines) ? _nextChatChunk : null,
                      ),
                    ],
                  ),
                );
              },
            ),

          // Persistent Under Review Issue Navigation Strip
          _buildUnderReviewStrip(),

          // Main Chat Multiline Active TextField
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: RawScrollbar(
                controller: _inputScrollCtrl,
                thumbVisibility: true,
                trackVisibility: false,
                interactive: true,
                thickness: 6.0,
                radius: const Radius.circular(3),
                thumbColor: Colors.tealAccent.withValues(alpha: 0.4),
                child: TextField(
                  focusNode: _chatInputFocusNode,
                  controller: _chatInputCtrl,
                  scrollController: _inputScrollCtrl,
                  maxLines: null,
                  expands: true,
                  cursorColor: Colors.tealAccent,
                  cursorWidth: 2.0,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: _chatFontSize,
                    color: Colors.white,
                    height: 1.4,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'WhatsApp chat yahan paste ya type karein...',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                  onChanged: _onChatTextChanged,
                ),
              ),
            ),
          ),

          const SizedBox(height: 6),

          // Quick Ticket Entry Bar (Live Instant Add)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                // Series input
                SizedBox(
                  width: 52,
                  height: 30,
                  child: TextField(
                    controller: _quickSeriesCtrl,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Series',
                      labelStyle: const TextStyle(fontSize: 9.5, color: Colors.tealAccent),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      filled: true,
                      fillColor: AppColors.surfaceContainerLowest,
                      contentPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Ticket Number input
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _quickTicketCtrl,
                      focusNode: _quickTicketFocusNode,
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Colors.white),
                      keyboardType: TextInputType.number,
                      maxLength: 5,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                      decoration: InputDecoration(
                        hintText: 'New Ticket (e.g. 58359)...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                        filled: true,
                        fillColor: AppColors.surfaceContainerLowest,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _addQuickTicketEntry(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Qty input
                SizedBox(
                  width: 44,
                  height: 30,
                  child: TextField(
                    controller: _quickQtyCtrl,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Qty',
                      labelStyle: const TextStyle(fontSize: 9.5, color: Colors.amberAccent),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      filled: true,
                      fillColor: AppColors.surfaceContainerLowest,
                      contentPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _addQuickTicketEntry(),
                  ),
                ),
                const SizedBox(width: 6),
                // Add Entry Button
                ElevatedButton.icon(
                  onPressed: _addQuickTicketEntry,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 30),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightCardsPanel(int selectedTicketsCount, double selectedTotalAmount) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar with Select/Deselect All
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Parsed Cards (${_parsedGroups.length}):',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if (_isParsing && _parsedGroups.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent),
                    ),
                    const SizedBox(width: 4),
                    const Text('Updating...', style: TextStyle(fontSize: 11, color: Colors.tealAccent)),
                  ],
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
                  if (_unparsedLines.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _showDockedReviewPanel = !_showDockedReviewPanel;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _showDockedReviewPanel ? Colors.amberAccent : Colors.amber.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.8)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _showDockedReviewPanel ? Icons.visibility_off_rounded : Icons.rate_review_outlined,
                              size: 12,
                              color: _showDockedReviewPanel ? Colors.black : Colors.amberAccent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _showDockedReviewPanel ? 'Close Review' : 'Review Lines (${_unparsedLines.length})',
                              style: TextStyle(
                                fontSize: 10,
                                color: _showDockedReviewPanel ? Colors.black : Colors.amberAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (_selectedGroupIndices.isNotEmpty)
                Text(
                  'Selected: $selectedTicketsCount Tkts • ₹${selectedTotalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.amberAccent),
                ),
            ],
          ),

          const SizedBox(height: 6),

          // Universal Ticket Verification Search Bar
          if (_parsedGroups.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _universalSearchQuery.isNotEmpty
                      ? (_cachedUniversalMatches.isNotEmpty ? Colors.amberAccent : Colors.redAccent.withValues(alpha: 0.6))
                      : AppColors.border,
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  const Icon(Icons.manage_search_rounded, size: 17, color: Colors.white60),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _universalSearchCtrl,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Universal Ticket Verification (e.g. 41151)...',
                        hintStyle: TextStyle(fontSize: 11, color: Colors.white38),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: _onUniversalSearchChanged,
                      onSubmitted: (_) => _selectNextTicket(),
                    ),
                  ),
                  if (_universalSearchQuery.isNotEmpty) ...[
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      color: Colors.white70,
                      onPressed: () {
                        _universalSearchCtrl.clear();
                        _onUniversalSearchChanged('');
                      },
                    ),
                  ],
                ],
              ),
            ),

          // Docked Under Review List Panel (Zero-popup interactive panel)
          if (_showDockedReviewPanel && _unparsedLines.isNotEmpty)
            _buildDockedReviewPanel(),

          // Shift Group Cards List
          Expanded(
            child: _isParsing && _parsedGroups.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 44,
                          height: 44,
                          child: CircularProgressIndicator(
                            strokeWidth: 3.5,
                            color: Colors.tealAccent,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'WhatsApp Tickets Parsing...',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.tealAccent),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Background isolate processing • Zero system freeze',
                          style: TextStyle(fontSize: 11.5, color: Colors.white60),
                        ),
                      ],
                    ),
                  )
                : _parsedGroups.isEmpty
                    ? Center(
                        child: Text(
                          _enforceStrictTargetDate
                              ? 'Date ${DateFormat('dd/MM/yyyy').format(_targetDate)} ke liye koi ticket nahi mila.'
                              : 'No tickets parsed yet. Paste WhatsApp chat on the left.',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      )
                    : _universalSearchQuery.isNotEmpty
                        ? _buildUnifiedSearchResultsView()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_parsedGroups.length > 1) ...[
                                _buildSetsTabBar(),
                                const SizedBox(height: 6),
                              ],
                              Expanded(
                                child: _buildActiveGroupCardView(),
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeriesFilterChip({
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
    VoidCallback? onEditColor,
    VoidCallback? onLongPress,
  }) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(15),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.22) : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 4, spreadRadius: 1)] : null,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? color : Colors.white70,
              ),
            ),
            if (onEditColor != null) ...[
              const SizedBox(width: 5),
              InkWell(
                onTap: onEditColor,
                borderRadius: BorderRadius.circular(10),
                child: Tooltip(
                  message: 'Customize Series Color & Price',
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Icon(Icons.palette_outlined, size: 12, color: color.withValues(alpha: 0.85)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildViewModeToggle() {
    return InkWell(
      onTap: () {
        setState(() {
          _groupBySeriesAccordion = !_groupBySeriesAccordion;
        });
      },
      borderRadius: BorderRadius.circular(5),
      child: Tooltip(
        message: _groupBySeriesAccordion ? 'Switch to Flat List View' : 'Switch to Grouped by Color & Collapsible View',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: _groupBySeriesAccordion ? Colors.purpleAccent.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: _groupBySeriesAccordion ? Colors.purpleAccent : Colors.transparent,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _groupBySeriesAccordion ? Icons.folder_copy_outlined : Icons.list_alt_rounded,
                size: 13,
                color: _groupBySeriesAccordion ? Colors.purpleAccent : Colors.white70,
              ),
              const SizedBox(width: 4),
              Text(
                _groupBySeriesAccordion ? 'Color Groups' : 'Flat List',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: _groupBySeriesAccordion ? FontWeight.bold : FontWeight.w500,
                  color: _groupBySeriesAccordion ? Colors.purpleAccent : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardSeriesFilterBar(BulkShiftGroup group, int groupIndex) {
    final seriesMap = group.ticketsBySeries;
    if (seriesMap.isEmpty) return const SizedBox.shrink();

    final activeSeries = _cardSeriesFilter[groupIndex];
    final sortedSeries = group.uniqueSeries;
    final totalRows = group.tickets.length;
    final totalQty = group.totalTickets;
    final allChipLabel = (totalRows == totalQty)
        ? 'All ($totalRows)'
        : 'All ($totalRows lines • $totalQty tkts)';

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: activeSeries != null ? Colors.amberAccent.withValues(alpha: 0.6) : Colors.white12,
          width: activeSeries != null ? 1.2 : 1.0,
        ),
      ),
      child: _isFilterBarCollapsed
          ? Row(
              children: [
                Icon(
                  Icons.filter_alt_rounded,
                  size: 14,
                  color: activeSeries != null ? Colors.amberAccent : Colors.tealAccent,
                ),
                const SizedBox(width: 5),
                Text(
                  'Color Filter:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: activeSeries != null ? Colors.amberAccent : Colors.white70,
                  ),
                ),
                const SizedBox(width: 8),
                _buildSeriesFilterChip(
                  label: activeSeries == null ? allChipLabel : 'S$activeSeries (${seriesMap[activeSeries]?.length ?? 0})',
                  isSelected: true,
                  color: activeSeries == null ? Colors.tealAccent : _getSeriesColor(activeSeries),
                  onTap: () {
                    setState(() {
                      _cardSeriesFilter[groupIndex] = null;
                      _groupPageIndices[groupIndex] = 0;
                    });
                  },
                ),
                const Spacer(),
                _buildViewModeToggle(),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _isFilterBarCollapsed = false),
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.tealAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.5), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.palette_outlined, size: 12, color: Colors.tealAccent),
                        const SizedBox(width: 4),
                        Text(
                          'Colors (${sortedSeries.length}) ▼',
                          style: const TextStyle(fontSize: 10.5, color: Colors.tealAccent, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Icon(
                  Icons.filter_alt_rounded,
                  size: 14,
                  color: activeSeries != null ? Colors.amberAccent : Colors.tealAccent,
                ),
                const SizedBox(width: 5),
                Text(
                  'Filter Series:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: activeSeries != null ? Colors.amberAccent : Colors.white70,
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _showManageAllSeriesDialog(group),
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.5), width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.palette_outlined, size: 12, color: Colors.tealAccent),
                        SizedBox(width: 3),
                        Text(
                          'Color & Price',
                          style: TextStyle(fontSize: 10, color: Colors.tealAccent, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildSeriesFilterChip(
                          label: allChipLabel,
                          isSelected: activeSeries == null,
                          color: Colors.tealAccent,
                          onTap: () {
                            setState(() {
                              _cardSeriesFilter[groupIndex] = null;
                              _groupPageIndices[groupIndex] = 0;
                            });
                          },
                        ),
                        const SizedBox(width: 6),
                        for (final s in sortedSeries) ...[
                          Builder(
                            builder: (context) {
                              final sList = seriesMap[s] ?? [];
                              final sRows = sList.length;
                              final sQty = sList.fold<int>(0, (sum, t) => sum + t.quantity);
                              final sChipLabel = (sRows == sQty) ? 'S$s ($sRows)' : 'S$s ($sRows • $sQty tkts)';
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildSeriesFilterChip(
                                    label: sChipLabel,
                                    isSelected: activeSeries == s,
                                    color: _getSeriesColor(s),
                                    onTap: () {
                                      setState(() {
                                        _cardSeriesFilter[groupIndex] = (activeSeries == s) ? null : s;
                                        _groupPageIndices[groupIndex] = 0;
                                      });
                                    },
                                    onEditColor: () => _showSeriesColorAndPriceDialog(s),
                                    onLongPress: () => _showSeriesColorAndPriceDialog(s),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _buildViewModeToggle(),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => setState(() => _isFilterBarCollapsed = true),
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.keyboard_arrow_up_rounded, size: 14, color: Colors.white70),
                        SizedBox(width: 2),
                        Text('Collapse', style: TextStyle(fontSize: 10, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _showSeriesColorAndPriceDialog(String series) {
    final clean = series.replaceAll(RegExp(r'\D'), '');
    final priceState = ref.read(seriesPriceViewModelProvider);
    final currentPrice = priceState.getPriceForSeries(series);
    final initialPrice = currentPrice > 0 ? currentPrice : 45.0;
    final priceCtrl = TextEditingController(text: initialPrice.toStringAsFixed(1));
    Color selectedColor = SeriesColorRegistry.getColor(series);
    final defaultColor = getDefaultSeriesColor(series);

    int colorTab = 0; // 0 = Presets, 1 = Custom Mixer
    var hsv = HSVColor.fromColor(selectedColor);
    double currentHue = hsv.hue;
    double currentSat = hsv.saturation;
    double currentVal = hsv.value.clamp(0.15, 1.0);
    final hexCtrl = TextEditingController(
      text: selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2),
    );

    const extendedPalette = [
      Color(0xFFEF4444), // Crimson Red
      Color(0xFFF43F5E), // Rose Pink
      Color(0xFFE11D48), // Deep Rose
      Color(0xFFEC4899), // Hot Pink
      Color(0xFFD946EF), // Fuchsia
      Color(0xFFA855F7), // Purple
      Color(0xFF9333EA), // Royal Violet
      Color(0xFF7C3AED), // Deep Violet
      Color(0xFF6366F1), // Indigo
      Color(0xFF3B82F6), // Blue
      Color(0xFF2563EB), // Royal Blue
      Color(0xFF0284C7), // Sky Blue
      Color(0xFF06B6D4), // Cyan
      Color(0xFF0D9488), // Deep Teal
      Color(0xFF14B8A6), // Teal
      Color(0xFF2DD4BF), // Mint Teal
      Color(0xFF10B981), // Emerald
      Color(0xFF22C55E), // Vivid Green
      Color(0xFF16A34A), // Forest Green
      Color(0xFF4ADE80), // Light Green
      Color(0xFF84CC16), // Lime
      Color(0xFFEAB308), // Yellow Gold
      Color(0xFFFBBF24), // Amber
      Color(0xFFF59E0B), // Deep Amber
      Color(0xFFF97316), // Orange
      Color(0xFFEA580C), // Deep Orange
      Color(0xFFFF5722), // Flame Orange
      Color(0xFFB91C1C), // Deep Red
      Color(0xFF78716C), // Stone
      Color(0xFF64748B), // Slate Blue
      Color(0xFF38BDF8), // Light Cyan
      Color(0xFFFF007F), // Neon Magenta
    ];

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void updateFromHsv() {
              selectedColor = HSVColor.fromAHSV(1.0, currentHue, currentSat, currentVal).toColor();
              hexCtrl.text = selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2);
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: selectedColor.withValues(alpha: 0.6), width: 1.5),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: selectedColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: selectedColor),
                    ),
                    child: Text('S$series', style: TextStyle(color: selectedColor, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Customize Series Color & Price',
                      style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ticket Price (₹):', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 16),
                        decoration: InputDecoration(
                          prefixText: '₹ ',
                          prefixStyle: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white24)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: selectedColor)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [22.5, 45.0, 90.0, 112.5, 225.0, 375.0].map((p) {
                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                priceCtrl.text = p.toStringAsFixed(1);
                              });
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Text('₹${p.toStringAsFixed(1)}', style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Live Preview Bar & Reset Button
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141E33),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: selectedColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: selectedColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                                boxShadow: [BoxShadow(color: selectedColor.withValues(alpha: 0.6), blurRadius: 6)],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: selectedColor.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: selectedColor),
                              ),
                              child: Text('S$series #71450', style: TextStyle(color: selectedColor, fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '#${selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}',
                              style: TextStyle(fontSize: 11, color: selectedColor, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                minimumSize: const Size(0, 26),
                              ),
                              icon: const Icon(Icons.refresh_rounded, size: 12, color: Colors.white60),
                              label: const Text('Reset Default', style: TextStyle(fontSize: 10, color: Colors.white60)),
                              onPressed: () {
                                setDialogState(() {
                                  selectedColor = defaultColor;
                                  final newHsv = HSVColor.fromColor(selectedColor);
                                  currentHue = newHsv.hue;
                                  currentSat = newHsv.saturation;
                                  currentVal = newHsv.value.clamp(0.15, 1.0);
                                  hexCtrl.text = selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Tabs for Presets vs Custom Color Mixer
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setDialogState(() => colorTab = 0),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                decoration: BoxDecoration(
                                  color: colorTab == 0 ? const Color(0xFF1E293B) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: colorTab == 0 ? selectedColor : Colors.white12),
                                ),
                                child: Center(
                                  child: Text(
                                    'Preset Palette (${extendedPalette.length})',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: colorTab == 0 ? Colors.white : Colors.white60,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: () => setDialogState(() => colorTab = 1),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                decoration: BoxDecoration(
                                  color: colorTab == 1 ? const Color(0xFF1E293B) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: colorTab == 1 ? selectedColor : Colors.white12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.tune_rounded, size: 13, color: Colors.tealAccent),
                                    const SizedBox(width: 5),
                                    Text(
                                      '🎨 Custom Color Mixer',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: colorTab == 1 ? Colors.white : Colors.white60,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (colorTab == 0) ...[
                        // Preset Colors Grid
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141E33),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: extendedPalette.map((c) {
                              final isThis = c.toARGB32() == selectedColor.toARGB32();
                              return InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    selectedColor = c;
                                    final newHsv = HSVColor.fromColor(selectedColor);
                                    currentHue = newHsv.hue;
                                    currentSat = newHsv.saturation;
                                    currentVal = newHsv.value.clamp(0.15, 1.0);
                                    hexCtrl.text = selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2);
                                  });
                                },
                                borderRadius: BorderRadius.circular(20),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isThis ? Colors.white : Colors.black38,
                                      width: isThis ? 2.5 : 1.0,
                                    ),
                                    boxShadow: isThis
                                        ? [BoxShadow(color: c.withValues(alpha: 0.8), blurRadius: 8, spreadRadius: 2)]
                                        : null,
                                  ),
                                  child: isThis
                                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                                      : null,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ] else ...[
                        // Custom Color Mixer
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141E33),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Hue Rainbow Slider
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Hue (Spectrum):', style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
                                  Text('${currentHue.round()}°', style: const TextStyle(fontSize: 11, color: Colors.tealAccent)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    height: 12,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFF0000),
                                          Color(0xFFFFFF00),
                                          Color(0xFF00FF00),
                                          Color(0xFF00FFFF),
                                          Color(0xFF0000FF),
                                          Color(0xFFFF00FF),
                                          Color(0xFFFF0000),
                                        ],
                                      ),
                                    ),
                                  ),
                                  SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 12,
                                      activeTrackColor: Colors.transparent,
                                      inactiveTrackColor: Colors.transparent,
                                      thumbColor: Colors.white,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9, elevation: 3),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                    ),
                                    child: Slider(
                                      value: currentHue,
                                      min: 0.0,
                                      max: 360.0,
                                      onChanged: (val) {
                                        setDialogState(() {
                                          currentHue = val;
                                          updateFromHsv();
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Saturation Slider
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Saturation (Color Depth):', style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
                                  Text('${(currentSat * 100).round()}%', style: const TextStyle(fontSize: 11, color: Colors.tealAccent)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    height: 10,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(5),
                                      gradient: LinearGradient(
                                        colors: [
                                          HSVColor.fromAHSV(1.0, currentHue, 0.0, currentVal).toColor(),
                                          HSVColor.fromAHSV(1.0, currentHue, 1.0, currentVal).toColor(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 10,
                                      activeTrackColor: Colors.transparent,
                                      inactiveTrackColor: Colors.transparent,
                                      thumbColor: Colors.white,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                    ),
                                    child: Slider(
                                      value: currentSat,
                                      min: 0.0,
                                      max: 1.0,
                                      onChanged: (val) {
                                        setDialogState(() {
                                          currentSat = val;
                                          updateFromHsv();
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Brightness Slider
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Brightness:', style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
                                  Text('${(currentVal * 100).round()}%', style: const TextStyle(fontSize: 11, color: Colors.tealAccent)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    height: 10,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(5),
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.black,
                                          HSVColor.fromAHSV(1.0, currentHue, currentSat, 1.0).toColor(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 10,
                                      activeTrackColor: Colors.transparent,
                                      inactiveTrackColor: Colors.transparent,
                                      thumbColor: Colors.white,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                    ),
                                    child: Slider(
                                      value: currentVal,
                                      min: 0.15,
                                      max: 1.0,
                                      onChanged: (val) {
                                        setDialogState(() {
                                          currentVal = val;
                                          updateFromHsv();
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Hex Code Input
                              Row(
                                children: [
                                  const Text('Hex Code:', style: TextStyle(fontSize: 11.5, color: Colors.white70, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Container(
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E293B),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white24),
                                      ),
                                      child: TextField(
                                        controller: hexCtrl,
                                        maxLength: 6,
                                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                                        style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace'),
                                        decoration: const InputDecoration(
                                          prefixText: ' #',
                                          prefixStyle: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                          border: InputBorder.none,
                                        ),
                                        onChanged: (val) {
                                          final cleanHex = val.replaceAll('#', '').trim();
                                          if (cleanHex.length == 6) {
                                            final parsedInt = int.tryParse('FF$cleanHex', radix: 16);
                                            if (parsedInt != null) {
                                              setDialogState(() {
                                                selectedColor = Color(parsedInt);
                                                final newHsv = HSVColor.fromColor(selectedColor);
                                                currentHue = newHsv.hue;
                                                currentSat = newHsv.saturation;
                                                currentVal = newHsv.value.clamp(0.15, 1.0);
                                              });
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedColor,
                    foregroundColor: ThemeData.estimateBrightnessForColor(selectedColor) == Brightness.dark ? Colors.white : Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Save & Apply', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(dialogCtx);
                    final newP = double.tryParse(priceCtrl.text) ?? initialPrice;
                    await ref.read(seriesPriceViewModelProvider.notifier).updateSeriesColor(series, selectedColor, newPrice: newP);
                    SeriesColorRegistry.setCustomColor(series, selectedColor);

                    if (!mounted) return;
                    setState(() {
                      for (final g in _parsedGroups) {
                        g.tickets = g.tickets.map<BulkParsedTicket>((t) {
                          if (t.series == series || t.series.replaceAll(RegExp(r'\D'), '') == clean) {
                            return t.copyWith(pricePerTicket: newP);
                          }
                          return t;
                        }).toList();
                      }
                    });
                    navigator.pop();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Series S$series color & price (₹$newP) updated!'),
                        backgroundColor: selectedColor,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showManageAllSeriesDialog(BulkShiftGroup group) {
    final sortedSeries = group.uniqueSeries;
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.tealAccent.withValues(alpha: 0.5), width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.palette_rounded, color: Colors.tealAccent, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Manage Series Colors & Prices',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.white70),
                onPressed: () => Navigator.pop(dialogCtx),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: sortedSeries.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(
                      child: Text('No series parsed yet.', style: TextStyle(color: Colors.white60)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: sortedSeries.length,
                    separatorBuilder: (_, _) => const Divider(color: Colors.white12, height: 1),
                    itemBuilder: (ctx, idx) {
                      final s = sortedSeries[idx];
                      final sColor = _getSeriesColor(s);
                      final priceState = ref.read(seriesPriceViewModelProvider);
                      final price = priceState.getPriceForSeries(s);
                      final sList = group.ticketsBySeries[s] ?? [];
                      final tCount = sList.length;

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: sColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: sColor, width: 1.2),
                          ),
                          child: Text('S$s', style: TextStyle(color: sColor, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        title: Text(
                          '$tCount lines in chat',
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Text(
                                '₹${price.toStringAsFixed(1)} / tkt',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: sColor,
                                foregroundColor: ThemeData.estimateBrightnessForColor(sColor) == Brightness.dark ? Colors.white : Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: const Size(60, 28),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              icon: const Icon(Icons.edit, size: 12),
                              label: const Text('Edit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                Navigator.pop(dialogCtx);
                                _showSeriesColorAndPriceDialog(s);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Close', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Color _getShiftColor(String shift) {
    final s = shift.toLowerCase();
    if (s.contains('1')) return const Color(0xFF2DD4BF);
    if (s.contains('6')) return const Color(0xFFFBBF24);
    if (s.contains('8')) return const Color(0xFFA78BFA);
    return Colors.tealAccent;
  }

  Widget _buildSetsTabBar() {
    final safeActiveIdx = (_activeGroupIndex ?? 0).clamp(0, math.max(0, _parsedGroups.length - 1));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(_parsedGroups.length, (idx) {
            final group = _parsedGroups[idx];
            final isActive = idx == safeActiveIdx;
            final isSelected = _selectedGroupIndices.contains(idx);
            final shiftColor = _getShiftColor(group.shiftName);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _activeGroupIndex = idx;
                    _activeTicketIndex = null;
                  });
                },
                borderRadius: BorderRadius.circular(7),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: isActive
                        ? shiftColor.withValues(alpha: 0.22)
                        : (isSelected ? const Color(0xFF1E293B) : const Color(0xFF141E33)),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: isActive
                          ? shiftColor
                          : (isSelected ? Colors.white24 : Colors.transparent),
                      width: isActive ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: isSelected,
                          activeColor: shiftColor,
                          checkColor: Colors.black,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedGroupIndices.add(idx);
                              } else {
                                _selectedGroupIndices.remove(idx);
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: shiftColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: shiftColor.withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          group.shiftName,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: shiftColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${group.totalTickets} Tkts',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                          color: isActive ? Colors.white : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildActiveGroupCardView() {
    if (_parsedGroups.isEmpty) return const SizedBox.shrink();
    final groupIndex = (_activeGroupIndex ?? 0).clamp(0, _parsedGroups.length - 1);
    final group = _parsedGroups[groupIndex];
    final isSelected = _selectedGroupIndices.contains(groupIndex);
    final effectiveTickets = _getEffectiveTicketsForGroup(groupIndex);
    final cardTicketsCount = effectiveTickets.fold<int>(0, (sum, t) => sum + t.quantity);
    final cardTotalAmount = effectiveTickets.fold<double>(0.0, (sum, t) => sum + t.totalAmount);
    final activeSeries = _cardSeriesFilter[groupIndex];
    final shiftColor = _getShiftColor(group.shiftName);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? Colors.tealAccent.withValues(alpha: 0.8) : AppColors.border,
          width: isSelected ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pinned Header Bar of the active card (Never slides off-screen)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1527),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: isSelected,
                  activeColor: shiftColor,
                  checkColor: Colors.black,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: shiftColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: shiftColor),
                  ),
                  child: Text(
                    group.shiftName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                      color: shiftColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        '${DateFormat('dd/MM/yyyy').format(group.drawDate)}  •  ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                      InkWell(
                        onTap: () => _showEditPartyDialog(group),
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: Colors.tealAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.5), width: 0.9),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_rounded, size: 12, color: Colors.tealAccent),
                              const SizedBox(width: 4),
                              Text(
                                group.buyerName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Colors.tealAccent),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.edit, size: 10, color: Colors.tealAccent),
                            ],
                          ),
                        ),
                      ),
                      if (activeSeries != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getSeriesColor(activeSeries).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: _getSeriesColor(activeSeries)),
                          ),
                          child: Text(
                            'S$activeSeries Only',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _getSeriesColor(activeSeries),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$cardTicketsCount Tkts • ₹${cardTotalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amberAccent),
                    ),
                    if (activeSeries != null)
                      Text(
                        'Filtered (${group.totalTickets} Total)',
                        style: const TextStyle(fontSize: 9.5, color: Colors.white38),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Pinned Series Filter Chips
          _buildCardSeriesFilterBar(group, groupIndex),

          // Pinned Body: Full height Tickets List
          Expanded(
            child: Builder(
              builder: (ctx) {
                final totalCount = effectiveTickets.length;
                if (totalCount == 0) {
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Is card me Series S$activeSeries ka koi ticket nahi mila.',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.tealAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            minimumSize: const Size(100, 28),
                          ),
                          onPressed: () {
                            setState(() {
                              _cardSeriesFilter[groupIndex] = null;
                              _groupPageIndices[groupIndex] = 0;
                            });
                          },
                          child: const Text('Show All Series', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                }

                if (_groupBySeriesAccordion) {
                  return _buildGroupedAccordionTicketsView(group, groupIndex, effectiveTickets);
                }

                return Column(
                  children: [
                    Expanded(
                      child: RawScrollbar(
                        controller: _getCardRowsScrollController(groupIndex),
                        thumbVisibility: true,
                        trackVisibility: true,
                        interactive: true,
                        thickness: 6.0,
                        radius: const Radius.circular(3),
                        thumbColor: Colors.tealAccent.withValues(alpha: 0.6),
                        trackColor: Colors.white10,
                        trackRadius: const Radius.circular(3),
                        child: ListView.builder(
                          controller: _getCardRowsScrollController(groupIndex),
                          itemCount: totalCount,
                          itemExtent: 38.0,
                          physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                          itemBuilder: (ctx, ticketIndex) {
                            final t = effectiveTickets[ticketIndex];
                            final sColor = _getSeriesColor(t.series);
                            final isActiveRow = _activeGroupIndex == groupIndex && _activeTicketIndex == ticketIndex;

                            return ExcludeFocus(
                              excluding: true,
                              child: InkWell(
                                canRequestFocus: false,
                                onTap: () {
                                  _setActiveTicket(groupIndex, ticketIndex, fromUserTap: true);
                                },
                                child: Container(
                                  height: 34,
                                  margin: const EdgeInsets.symmetric(vertical: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: isActiveRow ? Colors.tealAccent.withValues(alpha: 0.35) : const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isActiveRow ? const Color(0xFFFFD700) : Colors.white10,
                                      width: isActiveRow ? 2.0 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Text('#${ticketIndex + 1}', style: const TextStyle(fontSize: 11, color: Colors.white38)),
                                      const SizedBox(width: 10),
                                      if (_manualAddedSignatures.contains('${t.series}-${t.ticketNo}-${t.quantity}')) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: Colors.tealAccent.withValues(alpha: 0.25),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.tealAccent, width: 1),
                                          ),
                                          child: const Text(
                                            'NEW',
                                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: sColor.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text('S${t.series}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: sColor)),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '#${t.ticketNo}',
                                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                      const Spacer(),
                                      if (t.quantity > 1) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.amberAccent, width: 1),
                                          ),
                                          child: Text(
                                            'x${t.quantity} QTY',
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Text('${t.quantity} tkt • ₹${t.totalAmount.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
                                        icon: const Icon(Icons.edit_outlined, size: 14, color: Colors.white70),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => _showEditTicketDialog(group, t, ticketIndex),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    // Pinned bottom status bar inside the card
                    Container(
                      height: 28,
                      margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1120),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Lines 1–$totalCount ($cardTicketsCount Tkts • ₹${cardTotalAmount.toStringAsFixed(1)})',
                            style: const TextStyle(fontSize: 10.5, color: Colors.white70, fontWeight: FontWeight.w600),
                          ),
                          Row(
                            children: [
                              InkWell(
                                onTap: () {
                                  final ctrl = _getCardRowsScrollController(groupIndex);
                                  if (ctrl.hasClients) {
                                    ctrl.animateTo(0.0, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
                                  }
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Text('Top ⬆', style: TextStyle(fontSize: 10, color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () {
                                  final ctrl = _getCardRowsScrollController(groupIndex);
                                  if (ctrl.hasClients) {
                                    ctrl.animateTo(ctrl.position.maxScrollExtent, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
                                  }
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Text('Bottom ⬇', style: TextStyle(fontSize: 10, color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedAccordionTicketsView(BulkShiftGroup group, int groupIndex, List<BulkParsedTicket> effectiveTickets) {
    if (effectiveTickets.isEmpty) {
      return const Center(
        child: Text(
          'No tickets for current filter',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }

    final Map<String, List<BulkParsedTicket>> seriesMap = {};
    for (final t in effectiveTickets) {
      seriesMap.putIfAbsent(t.series, () => []).add(t);
    }

    final seriesKeys = seriesMap.keys.toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              const Icon(Icons.palette_outlined, size: 14, color: Colors.tealAccent),
              const SizedBox(width: 6),
              Text(
                'Series Groups (${seriesKeys.length})',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  setState(() {
                    for (final s in seriesKeys) {
                      _collapsedSeriesKeys.remove('${groupIndex}_$s');
                    }
                  });
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text('Expand All', style: TextStyle(fontSize: 10.5, color: Colors.tealAccent, fontWeight: FontWeight.w600)),
                ),
              ),
              const Text(' • ', style: TextStyle(color: Colors.white24, fontSize: 10)),
              InkWell(
                onTap: () {
                  setState(() {
                    for (final s in seriesKeys) {
                      _collapsedSeriesKeys.add('${groupIndex}_$s');
                    }
                  });
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text('Collapse All', style: TextStyle(fontSize: 10.5, color: Colors.amberAccent, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            itemCount: seriesKeys.length,
            padding: const EdgeInsets.only(bottom: 12),
            itemBuilder: (ctx, sIdx) {
              final series = seriesKeys[sIdx];
              final sTickets = seriesMap[series]!;
              final sColor = _getSeriesColor(series);
              final collapseKey = '${groupIndex}_$series';
              final isCollapsed = _collapsedSeriesKeys.contains(collapseKey);
              final sTotalAmount = sTickets.fold<double>(0.0, (sum, t) => sum + t.totalAmount);
              final sTotalTkts = sTickets.fold<int>(0, (sum, t) => sum + t.quantity);

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1527),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: sColor.withValues(alpha: 0.35), width: 1.2),
                ),
                child: Column(
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          if (isCollapsed) {
                            _collapsedSeriesKeys.remove(collapseKey);
                          } else {
                            _collapsedSeriesKeys.add(collapseKey);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: sColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.vertical(
                            top: const Radius.circular(6),
                            bottom: Radius.circular(isCollapsed ? 6 : 0),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: sColor.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: sColor, width: 1),
                              ),
                              child: Text(
                                'Series $series',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: sColor),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '$sTotalTkts tkts',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '• ₹${sTotalAmount.toStringAsFixed(1)}',
                              style: const TextStyle(fontSize: 11, color: Colors.white70),
                            ),
                            const Spacer(),
                            Icon(
                              isCollapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                              color: sColor,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isCollapsed)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Column(
                          children: [
                            for (int i = 0; i < sTickets.length; i++) ...[
                              Builder(builder: (ctx) {
                                final t = sTickets[i];
                                final globalIdx = group.tickets.indexOf(t);
                                final isActiveRow = _activeGroupIndex == groupIndex && _activeTicketIndex == globalIdx;

                                return ExcludeFocus(
                                  excluding: true,
                                  child: InkWell(
                                    canRequestFocus: false,
                                    onTap: () {
                                      if (globalIdx >= 0) {
                                        _setActiveTicket(groupIndex, globalIdx, fromUserTap: true);
                                      }
                                    },
                                    child: Container(
                                      height: 34,
                                      margin: const EdgeInsets.symmetric(vertical: 2),
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      decoration: BoxDecoration(
                                        color: isActiveRow ? Colors.tealAccent.withValues(alpha: 0.35) : const Color(0xFF0F172A),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isActiveRow ? const Color(0xFFFFD700) : Colors.white10,
                                          width: isActiveRow ? 2.0 : 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Text('#${i + 1}', style: const TextStyle(fontSize: 11, color: Colors.white38)),
                                          const SizedBox(width: 10),
                                          if (_manualAddedSignatures.contains('${t.series}-${t.ticketNo}-${t.quantity}')) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: Colors.tealAccent.withValues(alpha: 0.25),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.tealAccent, width: 1),
                                              ),
                                              child: const Text(
                                                'NEW',
                                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: sColor.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text('S${t.series}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: sColor)),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            '#${t.ticketNo}',
                                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white),
                                          ),
                                          const Spacer(),
                                          if (t.quantity > 1) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.amberAccent, width: 1),
                                              ),
                                              child: Text(
                                                'x${t.quantity} QTY',
                                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          Text('${t.quantity} tkt • ₹${t.totalAmount.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
                                            icon: const Icon(Icons.edit_outlined, size: 14, color: Colors.white70),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () => _showEditTicketDialog(group, t, globalIdx >= 0 ? globalIdx : 0),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
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
    );
  }

  Widget _buildUnifiedSearchResultsView() {
    if (_cachedUniversalMatches.isEmpty) {
      return Center(
        child: Text(
          'Ticket ya Series "$_universalSearchQuery" kisi bhi card me nahi mila.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }

    return ListView.separated(
      itemCount: _cachedUniversalMatches.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
      itemBuilder: (ctx, i) {
        final m = _cachedUniversalMatches[i];
        final sColor = _getSeriesColor(m.ticket.series);

        return InkWell(
          onTap: () {
            _setActiveTicket(m.groupIndex, m.ticketIndex);
          },
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: sColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('S${m.ticket.series}', style: TextStyle(color: sColor, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('#${m.ticket.ticketNo}', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text('${DateFormat('dd/MM/yyyy').format(m.group.drawDate)} • ${m.group.shiftName} • ${m.group.buyerName}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                    ],
                  ),
                ),
                Text('₹${m.ticket.totalAmount.toStringAsFixed(1)}', style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomFooterBar(int selectedTicketsCount, double selectedTotalAmount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.analytics_rounded, color: Colors.tealAccent, size: 20),
          const SizedBox(width: 10),
          Text(
            'Selected Cards: ${_selectedGroupIndices.length} / ${_parsedGroups.length} | Tickets: $selectedTicketsCount | Gross: ₹${selectedTotalAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
          ),
          const Spacer(),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedGroupIndices.isEmpty ? Colors.grey : Colors.tealAccent.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(_isSaving ? 'Booking...' : '🚀 Book Selected ($selectedTicketsCount Tkts)'),
            onPressed: (_isSaving || _selectedGroupIndices.isEmpty) ? null : _saveAndBookAll,
          ),
        ],
      ),
    );
  }
}
