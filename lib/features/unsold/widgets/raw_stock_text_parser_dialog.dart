import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/database/database_service.dart';
import '../../bookings/services/gemini_scanner_service.dart';
import '../models/voucher_model.dart';
import '../models/unsold_model.dart';
import '../viewmodels/voucher_viewmodel.dart';
import '../viewmodels/unsold_viewmodel.dart';
import '../../sellers/viewmodels/seller_customer_viewmodel.dart';
import '../../settings/viewmodels/series_price_viewmodel.dart';
import 'ai_stock_scan_review_dialog.dart';
import 'searchable_dealer_picker_dialog.dart';

/// Optimized Voucher Representation for Ultra-Fast Range Matching in Parsing Review
class _FastVoucher {
  final String partyLower;
  final String dealerLower;
  final String dateClean;
  final String shiftLower;
  final String seriesUpper;
  final String seriesNum;
  final int start;
  final int end;
  final String partyName;

  _FastVoucher({
    required this.partyLower,
    required this.dealerLower,
    required this.dateClean,
    required this.shiftLower,
    required this.seriesUpper,
    required this.seriesNum,
    required this.start,
    required this.end,
    required this.partyName,
  });
}

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
    final totalLines = lines.length;
    // ⚡ CHUNKING & FAST RENDER FOR 10K+ LINES:
    // Highlight up to 300 lines to avoid freezing during typing or scrolling
    final int maxHighlightCount = totalLines > 500 ? 300 : totalLines;
    String currentPrefix = '';

    for (int i = 0; i < maxHighlightCount; i++) {
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

      // Dot-Matrix Printer Header / Decorative line
      if (RegExp(r'(?:Purchase\s+Return|Draw\s+No|Total\s*:|Grand\s+Total|\*{2}\s*Return\s*\*{2}|AYUSH|NEW\s+SHIVAM|[=-]{5,}|[\x00-\x1F\x7F-\x9F]+)', caseSensitive: false).hasMatch(contentTrimmed) && !contentTrimmed.contains('* *')) {
        final List<TextSpan> lineSpans = [];
        if (waHeaderPrefix != null) {
          lineSpans.add(TextSpan(text: waHeaderPrefix, style: (style ?? const TextStyle()).copyWith(color: const Color(0xFF94A3B8), fontSize: 11)));
        }
        lineSpans.add(TextSpan(
          text: contentToHighlight + lineEnding,
          style: (style ?? const TextStyle()).copyWith(
            color: const Color(0xFF38BDF8),
            backgroundColor: const Color(0xFF0369A1).withAlpha(80),
            fontWeight: FontWeight.w600,
          ),
        ));
        spans.add(TextSpan(children: lineSpans));
        continue;
      }

      // Dot-Matrix Purchase Return Range Row e.g. * * 90110  90114  =       60
      if (contentTrimmed.contains('* *') && RegExp(r'\*\s*\*\s*\d{5}\s+\d{5}').hasMatch(contentTrimmed)) {
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

    if (maxHighlightCount < totalLines) {
      final remaining = lines.sublist(maxHighlightCount).join('\n');
      spans.add(TextSpan(text: '\n$remaining', style: style));
    }

    return TextSpan(children: spans);
  }
}

class RawStockTextParserDialog extends ConsumerStatefulWidget {
  final StockScanMode mode;
  final String activeShift;
  final DateTime activeDate;
  final String defaultParty;
  final String? initialRawText;

  const RawStockTextParserDialog({
    super.key,
    required this.mode,
    required this.activeShift,
    required this.activeDate,
    required this.defaultParty,
    this.initialRawText,
  });

  /// 🛡️ USER REQUIREMENT: Quantity is strictly the number of tickets in the range:
  /// Quantity = (toTicket - fromTicket + 1) and 1 for single ticket
  static int computeStrictQuantityFromRange({
    required String fromTicket,
    required String toTicket,
    String? series,
  }) {
    String cleanFrom = fromTicket.trim();
    if (cleanFrom.contains('-')) cleanFrom = cleanFrom.split('-').first.trim();
    cleanFrom = cleanFrom.replaceAll(RegExp(r'\D'), '');

    String cleanTo = toTicket.trim();
    if (cleanTo.contains('-')) cleanTo = cleanTo.split('-').first.trim();
    cleanTo = cleanTo.replaceAll(RegExp(r'\D'), '');

    if (cleanFrom.isEmpty) return 1;

    // Expand shorthand toTicket (e.g. 50271 to 74 -> 50274, 50271 to 4 -> 50274, 62150 to 69 -> 62169)
    if (cleanFrom.length > cleanTo.length && cleanTo.isNotEmpty) {
      final prefix = cleanFrom.substring(0, cleanFrom.length - cleanTo.length);
      cleanTo = '$prefix$cleanTo';
    }

    final f = int.tryParse(cleanFrom);
    final t = int.tryParse(cleanTo);

    if (f == null) return 1;
    final toVal = (t != null && t >= f) ? t : f;
    final count = (toVal - f) + 1;
    return count > 0 ? count : 1;
  }

  @override
  ConsumerState<RawStockTextParserDialog> createState() => _RawStockTextParserDialogState();
}

class _RawStockTextParserDialogState extends ConsumerState<RawStockTextParserDialog> {
  final _StockSyntaxHighlightingController _rawTextCtrl = _StockSyntaxHighlightingController();
  final FocusNode _rawTextFocusNode = FocusNode();
  final ScrollController _rawTextScrollCtrl = ScrollController();
  final ScrollController _textInputScrollCtrl = ScrollController();
  final ScrollController _tableScrollCtrl = ScrollController();
  final TextEditingController _partyCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  // ⚡ Strict 30-Line Chunking & Smooth Scrolling Engine State
  static const int kChunkLines = 30;
  List<String> _allRawLines = [];
  int _currentTextChunk = 0;
  int _currentParsedChunk = 0;
  bool _isUpdatingFromChunkSwitch = false;
  bool _isContinuousTableScroll = true;
  DateTime _lastChunkAutoSwitchTime = DateTime.now();

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
  String _selectedStatusFilter = 'ALL';
  String _searchQuery = '';

  // 🔍 Fast Voucher Cross-Checking & Validation State
  List<VoucherModel> _allVouchers = [];
  List<UnsoldModel> _allUnsold = [];
  List<_FastVoucher> _fastVouchers = [];
  final Map<GeminiScannedItem, String?> _validationCache = {};
  int _cachedValidCount = 0;
  int _cachedNotInVoucherCount = 0;
  int _cachedAlreadyIssuedCount = 0;

  // ⚡ 10K+ Lines Chunking & Background Engine State (Zero UI Freeze)
  bool _isChunkProcessing = false;
  String _chunkProgressMessage = '';
  double _chunkProgress = 0.0;
  Timer? _debounceTimer;
  final Map<String, List<_FastVoucher>> _voucherCandidateIndex = {};
  final Map<String, List<UnsoldModel>> _unsoldCandidateIndex = {};

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
    _tableScrollCtrl.addListener(_onTableScroll);
    _textInputScrollCtrl.addListener(() {
      if (_rawTextScrollCtrl.hasClients &&
          _rawTextScrollCtrl.offset != _textInputScrollCtrl.offset) {
        _rawTextScrollCtrl.jumpTo(_textInputScrollCtrl.offset);
      }
    });
    _loadDealersAndSellers();

    // ⚡ Synchronous pre-population from Riverpod ViewModels: eliminates empty vouchers race condition!
    final vmVouchers = ref.read(voucherViewModelProvider).vouchers;
    if (vmVouchers.isNotEmpty) {
      _allVouchers = vmVouchers;
    }
    final vmUnsold = ref.read(unsoldViewModelProvider).unsoldList;
    if (vmUnsold.isNotEmpty) {
      _allUnsold = vmUnsold;
    }
    _buildFastVouchers();

    _loadAllVouchers();
    _loadAllUnsold();

    if (widget.initialRawText != null && widget.initialRawText!.isNotEmpty) {
      _loadFullRawText(widget.initialRawText!);
    }
  }

  Future<void> _loadAllVouchers() async {
    try {
      final rows = await DatabaseService.instance.getVouchers();
      if (mounted) {
        _allVouchers = rows.map((r) => VoucherModel.fromMap(r)).toList();
        _buildFastVouchers();
        _refreshValidationCache();
        setState(() {});
      }
    } catch (_) {
      final vmList = ref.read(voucherViewModelProvider).vouchers;
      if (mounted && vmList.isNotEmpty) {
        _allVouchers = vmList;
        _buildFastVouchers();
        _refreshValidationCache();
        setState(() {});
      }
    }
  }

  Future<void> _loadAllUnsold() async {
    try {
      final rows = await DatabaseService.instance.getUnsoldTickets();
      if (mounted) {
        _allUnsold = rows.map((r) => UnsoldModel.fromMap(r)).toList();
        _refreshValidationCache();
        setState(() {});
      }
    } catch (_) {
      final vmList = ref.read(unsoldViewModelProvider).unsoldList;
      if (mounted && vmList.isNotEmpty) {
        _allUnsold = vmList;
        _refreshValidationCache();
        setState(() {});
      }
    }
  }

  void _buildFastVouchers() {
    final src = _allVouchers.isNotEmpty ? _allVouchers : ref.read(voucherViewModelProvider).vouchers;
    final list = <_FastVoucher>[];
    _voucherCandidateIndex.clear();

    for (final v in src) {
      final s = int.tryParse(v.fromTicket.replaceAll(RegExp(r'\D'), ''));
      final e = int.tryParse(v.toTicket.replaceAll(RegExp(r'\D'), '')) ?? s;
      if (s == null) continue;
      final ser = v.series.trim().toUpperCase();
      final serNum = ser.replaceAll(RegExp(r'\D'), '');
      final fastV = _FastVoucher(
        partyLower: v.partyName.trim().toLowerCase(),
        dealerLower: v.effectiveDealer.trim().toLowerCase(),
        dateClean: v.date.replaceAll('/', '-').replaceAll('.', '-').trim(),
        shiftLower: v.drawShift.trim().toLowerCase(),
        seriesUpper: ser,
        seriesNum: serNum,
        start: s,
        end: e ?? s,
        partyName: v.partyName.trim(),
      );
      list.add(fastV);

      // Fast multi-key indexing for O(1) candidate lookup
      final normD = _normalizeDateToYmd(fastV.dateClean);
      final md = _extractMonthDay(fastV.dateClean);
      final canS = _canonicalShift(fastV.shiftLower);

      void indexV(String dKey, String sKey, String serKey) {
        final k = '${dKey}_${sKey}_$serKey';
        (_voucherCandidateIndex[k] ??= []).add(fastV);
      }

      indexV(normD, canS, ser);
      indexV(normD, 'all', ser);
      indexV(md, canS, ser);
      indexV(md, 'all', ser);

      if (serNum.isNotEmpty && serNum != ser) {
        indexV(normD, canS, serNum);
        indexV(normD, 'all', serNum);
        indexV(md, canS, serNum);
        indexV(md, 'all', serNum);
      }
    }
    _fastVouchers = list;
    _buildFastUnsoldIndex();
  }

  void _buildFastUnsoldIndex() {
    _unsoldCandidateIndex.clear();
    final unsoldSource = _allUnsold.isNotEmpty
        ? _allUnsold
        : ref.read(unsoldViewModelProvider).unsoldList;

    for (final u in unsoldSource) {
      final normD = _normalizeDateToYmd(u.date);
      final md = _extractMonthDay(u.date);
      final canS = _canonicalShift(u.drawShift);
      final ser = u.series.trim().toUpperCase();
      final serNum = ser.replaceAll(RegExp(r'\D'), '');

      void indexU(String dKey, String sKey, String serKey) {
        final k = '${dKey}_${sKey}_$serKey';
        (_unsoldCandidateIndex[k] ??= []).add(u);
      }

      indexU(normD, canS, ser);
      indexU(normD, 'all', ser);
      indexU(md, canS, ser);
      indexU(md, 'all', ser);

      if (serNum.isNotEmpty && serNum != ser) {
        indexU(normD, canS, serNum);
        indexU(normD, 'all', serNum);
        indexU(md, canS, serNum);
        indexU(md, 'all', serNum);
      }
    }
  }

  // 🛡️ Robust Date & Shift Normalization Helpers
  static String _normalizeDateToYmd(String d) {
    final clean = d.replaceAll('/', '-').replaceAll('.', '-').trim();
    final parts = clean.split('-');
    if (parts.length >= 3) {
      if (parts[0].length == 4) {
        final y = parts[0];
        final m = parts[1].padLeft(2, '0');
        final day = parts[2].padLeft(2, '0');
        return '$y-$m-$day';
      } else {
        final day = parts[0].padLeft(2, '0');
        final m = parts[1].padLeft(2, '0');
        var y = parts[2];
        if (y.length == 2) y = '20$y';
        return '$y-$m-$day';
      }
    }
    return clean;
  }

  static String _extractMonthDay(String d) {
    final clean = d.replaceAll('/', '-').replaceAll('.', '-').trim();
    final parts = clean.split('-');
    if (parts.length >= 3) {
      if (parts[0].length == 4) {
        return '${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}';
      } else {
        return '${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
      }
    }
    return clean;
  }

  static String _canonicalShift(String s) {
    final lower = s.toLowerCase().trim();
    if (lower == 'all') return 'all';
    if (lower.contains('mor') || lower.contains('1')) return '1';
    if (lower.contains('day') || lower.contains('6')) return '6';
    if (lower.contains('eve') || lower.contains('nig') || lower.contains('8') || lower.contains('night')) return '8';
    return lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  List<_FastVoucher> _getCandidateVouchers(
    String itemDate,
    String itemMd,
    String itemCanonicalShift,
    String cleanSer,
    String serNumItem,
  ) {
    if (_voucherCandidateIndex.isEmpty) return _fastVouchers;

    final result = <_FastVoucher>[];
    void addKey(String k) {
      final list = _voucherCandidateIndex[k];
      if (list != null) result.addAll(list);
    }

    addKey('${itemDate}_${itemCanonicalShift}_$cleanSer');
    addKey('${itemDate}_all_$cleanSer');
    if (serNumItem.isNotEmpty && serNumItem != cleanSer) {
      addKey('${itemDate}_${itemCanonicalShift}_$serNumItem');
      addKey('${itemDate}_all_$serNumItem');
    }

    addKey('${itemMd}_${itemCanonicalShift}_$cleanSer');
    addKey('${itemMd}_all_$cleanSer');

    if (result.isEmpty) {
      final serFiltered = _fastVouchers.where((v) =>
        v.seriesUpper == cleanSer || (serNumItem.isNotEmpty && v.seriesNum == serNumItem)
      ).toList();
      if (serFiltered.isNotEmpty) return serFiltered;
      return _fastVouchers;
    }
    return result;
  }

  List<UnsoldModel> _getCandidateUnsold(
    String itemDate,
    String itemMd,
    String itemCanonicalShift,
    String cleanSer,
    String serNumItem,
  ) {
    if (_unsoldCandidateIndex.isEmpty) {
      return _allUnsold.isNotEmpty ? _allUnsold : ref.read(unsoldViewModelProvider).unsoldList;
    }

    final result = <UnsoldModel>[];
    void addKey(String k) {
      final list = _unsoldCandidateIndex[k];
      if (list != null) result.addAll(list);
    }

    addKey('${itemDate}_${itemCanonicalShift}_$cleanSer');
    addKey('${itemDate}_all_$cleanSer');
    if (serNumItem.isNotEmpty && serNumItem != cleanSer) {
      addKey('${itemDate}_${itemCanonicalShift}_$serNumItem');
      addKey('${itemDate}_all_$serNumItem');
    }

    addKey('${itemMd}_${itemCanonicalShift}_$cleanSer');
    addKey('${itemMd}_all_$cleanSer');

    if (result.isEmpty) {
      final allU = _allUnsold.isNotEmpty ? _allUnsold : ref.read(unsoldViewModelProvider).unsoldList;
      final serFiltered = allU.where((u) =>
        u.series.trim().toUpperCase() == cleanSer || (serNumItem.isNotEmpty && u.series.replaceAll(RegExp(r'\D'), '') == serNumItem)
      ).toList();
      if (serFiltered.isNotEmpty) return serFiltered;
      return allU;
    }
    return result;
  }

  // ⚡ CHUNKING & ASYNC VALIDATION (60 FPS Non-Freezing Engine)
  Future<void> _refreshValidationCacheAsync() async {
    final total = _parsedItems.length;
    final bool showProgress = total > 300;

    if (showProgress && mounted) {
      setState(() {
        _isChunkProcessing = true;
        _chunkProgress = 0.0;
        _chunkProgressMessage = '⚡ Cross-Checking $total entries with vouchers...';
      });
      await Future<void>.delayed(Duration.zero);
    }

    _validationCache.clear();
    int valid = 0;
    int notInVouch = 0;
    int already = 0;

    // Fast O(1) map for duplicate detection within current batch
    final seenRanges = <String, List<GeminiScannedItem>>{};

    for (int i = 0; i < total; i++) {
      if (showProgress && i > 0 && i % 400 == 0) {
        if (mounted) {
          setState(() {
            _chunkProgress = i / total;
            final chunkNum = (i ~/ 400) + 1;
            final totalChunks = (total / 400).ceil();
            _chunkProgressMessage = '⚡ Validating Chunk $chunkNum/$totalChunks ($i / $total items) [${(_chunkProgress * 100).toInt()}%]';
          });
        }
        await Future<void>.delayed(Duration.zero);
      }

      final item = _parsedItems[i];
      final from = item.fromTicket.trim();
      final to = item.toTicket.trim();
      final startI = int.tryParse(from);
      final endI = int.tryParse(to);
      final cleanSer = item.series.trim().toUpperCase();
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final rawItemDate = (item.targetDate != null && item.targetDate!.isNotEmpty) ? item.targetDate! : dateStr;
      final normItemDate = _normalizeDateToYmd(rawItemDate);
      final rawItemShift = (item.drawShift != null && item.drawShift!.isNotEmpty) ? item.drawShift! : _selectedShift;
      final itemCanonicalShift = _canonicalShift(rawItemShift);

      // Fast check if duplicate within current batch using indexed candidates
      bool isBatchDuplicate = false;
      final batchKey = '${normItemDate}_${itemCanonicalShift}_$cleanSer';
      final existingCandidates = seenRanges[batchKey];
      if (existingCandidates != null && startI != null && endI != null) {
        for (final prev in existingCandidates) {
          final prevFrom = int.tryParse(prev.fromTicket) ?? 0;
          final prevTo = int.tryParse(prev.toTicket) ?? prevFrom;
          if (startI <= prevTo && endI >= prevFrom) {
            isBatchDuplicate = true;
            break;
          }
        }
      }

      String? status;
      if (isBatchDuplicate) {
        status = 'Duplicate in Text';
      } else {
        status = _computeItemValidationStatus(item);
      }

      _validationCache[item] = status;

      if (startI != null && endI != null && !isBatchDuplicate) {
        (seenRanges[batchKey] ??= []).add(item);
      }

      if (status == null) {
        valid++;
      } else {
        if (status.contains('Not in Voucher') || status.contains('Issued to')) {
          notInVouch++;
        } else if (status.contains('Already') || status.contains('Duplicate')) {
          already++;
        }
      }
    }

    if (mounted) {
      setState(() {
        _cachedValidCount = valid;
        _cachedNotInVoucherCount = notInVouch;
        _cachedAlreadyIssuedCount = already;
        _isChunkProcessing = false;
        _chunkProgress = 1.0;
        _chunkProgressMessage = '';
      });
    }
  }

  void _refreshValidationCache() {
    _refreshValidationCacheAsync();
  }

  String? _computeItemValidationStatus(GeminiScannedItem item) {
    final from = item.fromTicket.trim();
    final to = item.toTicket.trim();
    if (from.length != 5 || to.length != 5) return 'Invalid Number';
    final cleanSer = item.series.trim().toUpperCase();
    if (cleanSer == '?' || cleanSer.isEmpty) return 'Missing Series';
    final serNumItem = cleanSer.replaceAll(RegExp(r'\D'), '');

    final startI = int.tryParse(from);
    final endI = int.tryParse(to);
    if (startI == null || endI == null || endI < startI) return 'Invalid Range';

    final partyName = (item.sellerName.isNotEmpty && item.sellerName != 'Walk-in Party')
        ? item.sellerName.trim()
        : _partyCtrl.text.trim();
    final partyLower = partyName.toLowerCase();
    final cleanP2 = partyLower.replaceAll(RegExp(r'[^a-z0-9]'), '');

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final rawItemDate = (item.targetDate != null && item.targetDate!.isNotEmpty) ? item.targetDate! : dateStr;
    final itemDate = _normalizeDateToYmd(rawItemDate);
    final itemMd = _extractMonthDay(rawItemDate);

    final rawItemShift = (item.drawShift != null && item.drawShift!.isNotEmpty) ? item.drawShift! : _selectedShift;
    final itemCanonicalShift = _canonicalShift(rawItemShift);

    if (widget.mode == StockScanMode.voucher) {
      final candidates = _getCandidateVouchers(itemDate, itemMd, itemCanonicalShift, cleanSer, serNumItem);
      for (final v in candidates) {
        final normVDate = _normalizeDateToYmd(v.dateClean);
        final vMd = _extractMonthDay(v.dateClean);
        final matchesDate = normVDate == itemDate || vMd == itemMd || v.dateClean == rawItemDate;
        if (matchesDate && (v.seriesUpper == cleanSer || (serNumItem.isNotEmpty && v.seriesNum == serNumItem))) {
          final vCanonicalShift = _canonicalShift(v.shiftLower);
          final matchesShift = itemCanonicalShift == 'all' ||
              vCanonicalShift == 'all' ||
              vCanonicalShift == itemCanonicalShift;
          final cleanP1 = v.partyLower.replaceAll(RegExp(r'[^a-z0-9]'), '');
          final isSameParty = partyName.isNotEmpty &&
              partyName != 'Walk-in Party' &&
              (cleanP1 == cleanP2 ||
               v.partyLower == partyLower ||
               v.partyLower.contains(partyLower) ||
               partyLower.contains(v.partyLower));
          if (matchesShift && isSameParty && startI <= v.end && endI >= v.start) {
            return 'Already in Voucher (${v.partyName})';
          }
        }
      }
    } else {
      // Unsold Mode: strictly verify that ticket was actually issued in a voucher!
      bool wasIssuedToThisParty = false;
      String? issuedToOtherParty;
      bool foundInAnyVoucher = false;

      final vCandidates = _getCandidateVouchers(itemDate, itemMd, itemCanonicalShift, cleanSer, serNumItem);
      for (final v in vCandidates) {
        // 1. Date matching: exact date or MM-DD match
        final normVDate = _normalizeDateToYmd(v.dateClean);
        final vMd = _extractMonthDay(v.dateClean);
        final matchesDate = normVDate == itemDate || vMd == itemMd || v.dateClean == rawItemDate;
        if (!matchesDate) continue;

        // 2. Shift matching: canonical 1, 6, 8 or 'all'
        final vCanonicalShift = _canonicalShift(v.shiftLower);
        final matchesShift = itemCanonicalShift == 'all' ||
            vCanonicalShift == 'all' ||
            vCanonicalShift == itemCanonicalShift;
        if (!matchesShift) continue;

        // 3. Series matching:
        final matchesSeries = v.seriesUpper == cleanSer || (serNumItem.isNotEmpty && v.seriesNum == serNumItem);
        if (!matchesSeries) continue;

        // 4. Ticket Range matching:
        if (startI >= v.start && endI <= v.end) {
          foundInAnyVoucher = true;
          final cleanP1 = v.partyLower.replaceAll(RegExp(r'[^a-z0-9]'), '');
          final cleanD1 = v.dealerLower.replaceAll(RegExp(r'[^a-z0-9]'), '');
          final isThisParty = partyName.isNotEmpty &&
              partyName != 'Walk-in Party' &&
              (cleanP1 == cleanP2 ||
               cleanP1.contains(cleanP2) ||
               cleanP2.contains(cleanP1) ||
               v.partyLower == partyLower ||
               v.partyLower.contains(partyLower) ||
               partyLower.contains(v.partyLower) ||
               cleanD1 == cleanP2 ||
               cleanD1.contains(cleanP2) ||
               cleanP2.contains(cleanD1) ||
               v.dealerLower == partyLower);

          if (isThisParty) {
            wasIssuedToThisParty = true;
            break;
          } else {
            issuedToOtherParty = v.partyName;
          }
        }
      }

      if (partyName.isNotEmpty && partyName != 'Walk-in Party') {
        if (!wasIssuedToThisParty) {
          if (issuedToOtherParty != null && issuedToOtherParty.isNotEmpty) {
            return 'Issued to $issuedToOtherParty';
          }
          return 'Not in Voucher ($partyName)';
        }
      } else {
        if (!foundInAnyVoucher) {
          return 'Not in Voucher';
        }
      }

      // 5. 🚫 BLOCK ALL DUPLICATE UNSOLD RETURNS (Regardless of party name variations)
      final uCandidates = _getCandidateUnsold(itemDate, itemMd, itemCanonicalShift, cleanSer, serNumItem);
      for (final u in uCandidates) {
        final normUDate = _normalizeDateToYmd(u.date);
        final uMd = _extractMonthDay(u.date);
        final matchesDate = normUDate == itemDate || uMd == itemMd || u.date == rawItemDate;
        if (!matchesDate) continue;

        final uCanonicalShift = _canonicalShift(u.drawShift);
        final matchesShift = itemCanonicalShift == 'all' ||
            uCanonicalShift == 'all' ||
            uCanonicalShift == itemCanonicalShift;
        if (!matchesShift) continue;

        final uSer = u.series.trim().toUpperCase();
        final uSerNum = uSer.replaceAll(RegExp(r'\D'), '');
        final matchesSeries = uSer == cleanSer || (serNumItem.isNotEmpty && uSerNum == serNumItem);
        if (!matchesSeries) continue;

        final startU = int.tryParse(u.fromTicket);
        final endU = int.tryParse(u.toTicket);
        if (startU != null && endU != null) {
          if (startI <= endU && endI >= startU) {
            return 'Already Returned (${u.partyName})';
          }
        }
      }
    }

    return null;
  }

  void _removeAlreadyIssuedItems() {
    final count = _cachedAlreadyIssuedCount;
    setState(() {
      _parsedItems.removeWhere((it) {
        final s = _validationCache[it] ?? _computeItemValidationStatus(it);
        return s != null && (s.contains('Already in Voucher') || s.contains('Already Returned') || s.contains('Duplicate'));
      });
      _refreshValidationCache();
      _recalculateAllPrices();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🗑️ Removed $count duplicate / already returned tickets!'),
        backgroundColor: const Color(0xFF166534),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _removeNotInVoucherItems() {
    final count = _cachedNotInVoucherCount;
    setState(() {
      _parsedItems.removeWhere((it) {
        final s = _validationCache[it] ?? _computeItemValidationStatus(it);
        return s != null && (s.contains('Not in Voucher') || s.contains('Issued to'));
      });
      _refreshValidationCache();
      _recalculateAllPrices();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🗑️ Removed $count tickets that were not found in any voucher!'),
        backgroundColor: const Color(0xFF166534),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _autoDetectAndSyncMetadata(String text) {
    if (text.trim().isEmpty) return;

    DateTime? detectedDate;
    String? detectedShift;
    String? detectedParty;

    // 1. Date Detection
    final dateHeaderMatch = RegExp(
      r'(?:Purchase\s+Return\s+List\s+of|Date\s*[:=-]?|\bDate\b)\s*[:=-]?\s*(\d{1,2})[\/\.-](\d{1,2})[\/\.-](\d{2,4})',
      caseSensitive: false,
    ).firstMatch(text);

    if (dateHeaderMatch != null) {
      final d = int.tryParse(dateHeaderMatch.group(1)!);
      final m = int.tryParse(dateHeaderMatch.group(2)!);
      var y = int.tryParse(dateHeaderMatch.group(3)!);
      if (d != null && m != null && y != null) {
        if (y < 100) y += 2000;
        if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
          detectedDate = DateTime(y, m, d);
        }
      }
    } else {
      final standaloneDateMatch = RegExp(r'\b(\d{1,2})[\/\.-](\d{1,2})[\/\.-](20\d{2})\b').firstMatch(text);
      if (standaloneDateMatch != null) {
        final d = int.tryParse(standaloneDateMatch.group(1)!);
        final m = int.tryParse(standaloneDateMatch.group(2)!);
        final y = int.tryParse(standaloneDateMatch.group(3)!);
        if (d != null && m != null && y != null && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
          detectedDate = DateTime(y, m, d);
        }
      }
    }

    // 2. Shift Detection
    if (RegExp(r'(?:dear\s*morning|dear\s*1(?::00|\.00|\.)?\s*pm|\bmor\s+\d+|\bmorning\b|\b1\s*pm\b|\b1:00\s*pm\b)', caseSensitive: false).hasMatch(text)) {
      detectedShift = 'Dear 1 PM';
    } else if (RegExp(r'(?:dear\s*day|dear\s*6(?::00|\.00|\.)?\s*pm|\bday\s+\d+|\bday\b|\b6\s*pm\b|\b6:00\s*pm\b)', caseSensitive: false).hasMatch(text)) {
      detectedShift = 'Dear 6 PM';
    } else if (RegExp(r'(?:dear\s*evening|dear\s*night|dear\s*8(?::00|\.00|\.)?\s*pm|\beve\s+\d+|\bnig\s+\d+|\bevening\b|\bnight\b|\b8\s*pm\b|\b8:00\s*pm\b)', caseSensitive: false).hasMatch(text)) {
      detectedShift = 'Dear 8 PM';
    }

    // 3. Party Detection
    final lines = text.split(RegExp(r'\r?\n'));
    for (int i = 0; i < lines.length && i < 15; i++) {
      final cleanL = lines[i].replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]+'), '').trim();
      if (cleanL.toLowerCase().contains('draw no') || cleanL.contains('* *')) break;
      final partyPrefixMatch = RegExp(r'^(?:party|seller|customer|name|client)\s*[:=-]\s*(.+)$', caseSensitive: false).firstMatch(cleanL);
      if (partyPrefixMatch != null) {
        final p = partyPrefixMatch.group(1)!.trim();
        if (p.isNotEmpty) {
          detectedParty = p;
          break;
        }
      }
      if (cleanL.isNotEmpty &&
          !cleanL.toLowerCase().contains('purchase return') &&
          !cleanL.toLowerCase().contains('page :') &&
          !cleanL.toLowerCase().contains('ayush ag') &&
          cleanL.length >= 3 &&
          cleanL.length <= 40 &&
          !RegExp(r'^\d+$').hasMatch(cleanL)) {
        if (cleanL.toUpperCase() == cleanL || cleanL.contains('SHIVAM') || cleanL.contains('AGENCY') || cleanL.contains('ENTERPRISE')) {
          detectedParty = cleanL;
          break;
        }
      }
    }

    bool stateChanged = false;
    if (detectedDate != null && detectedDate != _selectedDate) {
      _selectedDate = detectedDate;
      stateChanged = true;
    }
    if (detectedShift != null && detectedShift != _selectedShift) {
      _selectedShift = detectedShift;
      stateChanged = true;
    }
    if (detectedParty != null && detectedParty.isNotEmpty && detectedParty != _partyCtrl.text) {
      _partyCtrl.text = detectedParty;
      stateChanged = true;
      if (_availableDealers.contains(detectedParty)) {
        _selectedDealer = detectedParty;
        _selectedSubSeller = null;
      } else {
        for (final d in _availableDealers) {
          if (_dealerToSellersMap[d]?.contains(detectedParty) ?? false) {
            _selectedDealer = d;
            _selectedSubSeller = detectedParty;
            break;
          }
        }
      }
    }

    if (stateChanged && mounted) {
      setState(() {});
    }
  }

  void _loadDealersAndSellers() {
    final list = ref.read(sellerCustomerViewModelProvider).sellers;
    if (list.isEmpty) {
      ref.read(sellerCustomerViewModelProvider.notifier).loadSellers();
      return;
    }
    final dealers = <String>[];
    final map = <String, List<String>>{};

    for (final s in list) {
      final name = s.name.trim();
      if (name.isEmpty) continue;
      if (s.isDealer) {
        dealers.add(name);
        map[name] = [];
        map[name.toLowerCase()] = [];
      }
    }
    dealers.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    for (final s in list) {
      final name = s.name.trim();
      if (name.isEmpty || s.isDealer) continue;
      final parent = (s.parentDealer ?? '').trim();
      if (parent.isNotEmpty) {
        if (map.containsKey(parent)) {
          map[parent]!.add(name);
        }
        final pLower = parent.toLowerCase();
        if (map.containsKey(pLower) && pLower != parent) {
          map[pLower]!.add(name);
        }
      }
    }
    for (final l in map.values) {
      l.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
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
    _debounceTimer?.cancel();
    _rawTextCtrl.removeListener(_onTextChanged);
    _rawTextCtrl.dispose();
    _rawTextFocusNode.dispose();
    _rawTextScrollCtrl.dispose();
    _textInputScrollCtrl.dispose();
    _tableScrollCtrl.removeListener(_onTableScroll);
    _tableScrollCtrl.dispose();
    _partyCtrl.dispose();
    _searchCtrl.dispose();
    _quickSeriesCtrl.dispose();
    _quickFromCtrl.dispose();
    _quickToCtrl.dispose();
    super.dispose();
  }

  void _loadFullRawText(String fullText) {
    if (fullText.trim().isEmpty) {
      _allRawLines = [];
      _currentTextChunk = 0;
      _currentParsedChunk = 0;
      _rawTextCtrl.text = '';
      _reparseTextAsync();
      return;
    }
    _allRawLines = fullText.split(RegExp(r'\r?\n'));
    _currentTextChunk = 0;
    _currentParsedChunk = 0;
    _loadActiveChunkIntoEditor();
    _reparseTextAsync();
  }

  void _loadActiveChunkIntoEditor() {
    _isUpdatingFromChunkSwitch = true;
    if (_allRawLines.isEmpty) {
      _rawTextCtrl.text = '';
    } else {
      final start = _currentTextChunk * kChunkLines;
      final chunkLines = _allRawLines.skip(start).take(kChunkLines).toList();
      _rawTextCtrl.text = chunkLines.join('\n');
    }
    _isUpdatingFromChunkSwitch = false;
  }

  void _syncEditorChunkToAllRawLines() {
    if (_allRawLines.isEmpty) {
      _allRawLines = _rawTextCtrl.text.split(RegExp(r'\r?\n'));
      return;
    }
    final chunkLines = _rawTextCtrl.text.split(RegExp(r'\r?\n'));
    final start = _currentTextChunk * kChunkLines;
    final currentChunkSize = math.min(kChunkLines, _allRawLines.length - start);
    final end = start + currentChunkSize;
    if (start <= _allRawLines.length) {
      _allRawLines.replaceRange(start, math.min(end, _allRawLines.length), chunkLines);
    } else {
      _allRawLines.addAll(chunkLines);
    }
  }

  void _switchToTextChunk(int newChunk) {
    if (newChunk < 0 || newChunk >= _totalTextChunks) return;
    _syncEditorChunkToAllRawLines();
    setState(() {
      _currentTextChunk = newChunk;
      _loadActiveChunkIntoEditor();
    });
  }

  void _onTableScroll() {
    if (_isContinuousTableScroll || !_tableScrollCtrl.hasClients) return;
    final now = DateTime.now();
    if (now.difference(_lastChunkAutoSwitchTime).inMilliseconds < 400) return;

    final pos = _tableScrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent + 28) {
      if (_currentParsedChunk < _totalParsedChunks - 1) {
        _lastChunkAutoSwitchTime = now;
        _switchToParsedChunk(_currentParsedChunk + 1, scrollToTop: true);
      }
    } else if (pos.pixels <= pos.minScrollExtent - 28) {
      if (_currentParsedChunk > 0) {
        _lastChunkAutoSwitchTime = now;
        _switchToParsedChunk(_currentParsedChunk - 1, scrollToBottom: true);
      }
    }
  }

  void _switchToParsedChunk(int newChunk, {bool scrollToTop = true, bool scrollToBottom = false}) {
    if (newChunk < 0 || newChunk >= _totalParsedChunks) return;
    setState(() {
      _currentParsedChunk = newChunk;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tableScrollCtrl.hasClients) {
        if (scrollToBottom) {
          _tableScrollCtrl.jumpTo(_tableScrollCtrl.position.maxScrollExtent);
        } else if (scrollToTop) {
          _tableScrollCtrl.jumpTo(0.0);
        }
      }
    });
  }

  int get _totalTextChunks {
    if (_allRawLines.isEmpty) return 1;
    return ((_allRawLines.length + kChunkLines - 1) ~/ kChunkLines).clamp(1, 9999);
  }

  int get _totalParsedChunks {
    final total = _displayedItems.length;
    if (total == 0) return 1;
    return ((total + kChunkLines - 1) ~/ kChunkLines).clamp(1, 9999);
  }

  List<GeminiScannedItem> get _visibleParsedChunkItems {
    final all = _displayedItems;
    if (all.isEmpty) return [];
    final start = _currentParsedChunk * kChunkLines;
    if (start >= all.length) {
      return all.take(kChunkLines).toList();
    }
    return all.skip(start).take(kChunkLines).toList();
  }

  void _onTextChanged() {
    if (_isUpdatingFromChunkSwitch) return;

    // ⚡ Detect if large text (> 30 lines) was pasted directly into the text box:
    final currentLines = _rawTextCtrl.text.split(RegExp(r'\r?\n'));
    if (currentLines.length > kChunkLines) {
      _loadFullRawText(_rawTextCtrl.text);
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) {
        _syncEditorChunkToAllRawLines();
        _reparseTextAsync();
      }
    });
  }

  void _onRowItemChanged(GeminiScannedItem item) {
    item.quantity = RawStockTextParserDialog.computeStrictQuantityFromRange(
      fromTicket: item.fromTicket,
      toTicket: item.toTicket,
      series: item.series,
    );
    _recalculateAllPrices();
    _validationCache[item] = _computeItemValidationStatus(item);
    _refreshValidationCache();
    setState(() {});
  }

  Future<void> _reparseTextAsync() async {
    final text = _allRawLines.isNotEmpty ? _allRawLines.join('\n') : _rawTextCtrl.text;
    if (text.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _parsedItems = [];
          _unparsedLines = [];
          _selectedItems.clear();
          _lastSelectedIdx = null;
          _validationCache.clear();
          _cachedValidCount = 0;
          _cachedNotInVoucherCount = 0;
          _cachedAlreadyIssuedCount = 0;
          _isChunkProcessing = false;
          _chunkProgressMessage = '';
        });
      }
      return;
    }

    final totalLines = _allRawLines.isNotEmpty ? _allRawLines.length : text.split('\n').length;
    final bool isLarge = totalLines > 100;

    if (isLarge && mounted) {
      setState(() {
        _isChunkProcessing = true;
        _chunkProgress = 0.1;
        _chunkProgressMessage = '⚡ Parsing $totalLines lines in chunks of 30...';
      });
      await Future<void>.delayed(Duration.zero);
    }

    _autoDetectAndSyncMetadata(text);

    final party = _partyCtrl.text.trim().isNotEmpty ? _partyCtrl.text.trim() : widget.defaultParty;
    final parseResult = _parseRawStockText(
      text: text,
      defaultSeller: party,
      fallbackDate: DateFormat('yyyy-MM-dd').format(_selectedDate),
      mode: widget.mode,
    );

    if (isLarge && mounted) {
      setState(() {
        _chunkProgress = 0.4;
        _chunkProgressMessage = '⚡ Condensing ${parseResult.items.length} ticket ranges...';
      });
      await Future<void>.delayed(Duration.zero);
    }

    final condensed = GeminiScannerService.instance.condenseIntoRanges(parseResult.items);

    if (mounted) {
      setState(() {
        _parsedItems = condensed;
        _unparsedLines = parseResult.unparsedLines;
        _recalculateAllPrices();
        if (_currentParsedChunk >= _totalParsedChunks) {
          _currentParsedChunk = 0;
        }
      });
    }

    await _refreshValidationCacheAsync();
  }

  void _reparseText() {
    _reparseTextAsync();
  }

  ({List<GeminiScannedItem> items, List<String> unparsedLines}) _parseRawStockText({
    required String text,
    required String defaultSeller,
    required String fallbackDate,
    required StockScanMode mode,
  }) {
    final List<GeminiScannedItem> items = [];
    final List<String> unparsedLines = [];

    // ⚡ Direct Large Model JSON Support: If user or Large AI model provided JSON format
    final trimmedText = text.trim();
    if ((trimmedText.startsWith('[') && trimmedText.endsWith(']')) ||
        (trimmedText.startsWith('{') && trimmedText.endsWith('}')) ||
        trimmedText.contains('"series"') ||
        trimmedText.contains('"from"')) {
      try {
        String cleanJson = trimmedText;
        if (cleanJson.contains('```')) {
          cleanJson = cleanJson
              .replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '')
              .replaceAll('```', '')
              .trim();
        }

        final dynamic decoded = jsonDecode(cleanJson);
        List<dynamic> jsonList = [];
        if (decoded is List) {
          jsonList = decoded;
        } else if (decoded is Map) {
          // ⚡ Smart Engine: Auto-sync shift, date, and party from JSON summary!
          if (decoded['summary'] is Map) {
            final sMap = decoded['summary'] as Map;
            if (sMap['detected_party'] != null && sMap['detected_party'].toString().isNotEmpty) {
              final pName = sMap['detected_party'].toString();
              if (pName != 'Walk-in Customer' && _partyCtrl.text.isEmpty) {
                _partyCtrl.text = pName;
              }
            }
            if (sMap['detected_shift'] != null) {
              final sStr = sMap['detected_shift'].toString();
              final matchedShift = GeminiScannerService.instance.detectShiftFromText(sStr);
              if (matchedShift != null) {
                _selectedShift = matchedShift;
              }
            }
            if (sMap['detected_date'] != null) {
              final d = DateTime.tryParse(sMap['detected_date'].toString());
              if (d != null) {
                _selectedDate = d;
              }
            }
          }

          if (decoded['items'] is List) {
            jsonList = decoded['items'];
          } else if (decoded['vouchers'] is List) {
            jsonList = decoded['vouchers'];
          } else if (decoded['unsold'] is List) {
            jsonList = decoded['unsold'];
          } else if (decoded['data'] is List) {
            jsonList = decoded['data'];
          } else {
            jsonList = [decoded];
          }
        }

        for (final entry in jsonList) {
          if (entry is! Map) continue;
          final ser = entry['series']?.toString() ?? entry['ser']?.toString() ?? '12';
          final from = entry['from_ticket']?.toString() ??
              entry['from']?.toString() ??
              entry['start']?.toString() ??
              entry['ticket_no']?.toString() ??
              '';
          final to = entry['to_ticket']?.toString() ??
              entry['to']?.toString() ??
              entry['end']?.toString() ??
              from;

          if (from.isEmpty) continue;
          // 🛡️ USER REQUIREMENT: Quantity printed/written can have errors!
          // Quantity MUST strictly be decided by ticket range count * series multiplier:
          final int qty = RawStockTextParserDialog.computeStrictQuantityFromRange(
            fromTicket: from,
            toTicket: to,
            series: ser,
          );

          final rateVal = (entry['rate'] is num)
              ? (entry['rate'] as num).toDouble()
              : (entry['price'] is num)
                  ? (entry['price'] as num).toDouble()
                  : _getPriceForSeries(ser);

          final amountVal = (entry['amount'] is num)
              ? (entry['amount'] as num).toDouble()
              : (qty * rateVal);

          final partyVal = entry['party_name']?.toString() ??
              entry['dealer']?.toString() ??
              entry['party']?.toString() ??
              defaultSeller;
          final shiftVal = entry['draw_shift']?.toString() ??
              entry['shift']?.toString() ??
              _selectedShift;
          final doubtVal = entry['doubt']?.toString() ??
              entry['ai_doubt']?.toString() ??
              entry['confusion']?.toString();

          items.add(GeminiScannedItem(
            series: ser,
            ticketNo: from == to ? from : '$from-$to',
            fromTicket: from,
            toTicket: to,
            amount: amountVal,
            quantity: qty,
            sellerName: partyVal,
            drawShift: shiftVal,
            targetDate: fallbackDate,
            aiDoubt: doubtVal,
          ));
        }

        // Also capture any unparsed / blurry notes from JSON, while silencing intentional non-ticket noise
        if (decoded is Map && decoded['unparsed'] is List) {
          for (final u in decoded['unparsed']) {
            if (u != null) {
              if (u is Map) {
                final raw = u['raw_text']?.toString() ?? '';
                final reason = u['reason']?.toString() ?? '';
                // 🔇 SILENCE NOISE: If this is intentional ledger/matrix notes, settlement, date column, or non-ticket notes, do not treat as error issue!
                final isKnownNoise = RegExp(
                  r'(?:ledger|settlement|matrix|not (?:individual )?lottery|tracking|payment|total|hisab|date column|gpay|upi|balance)',
                  caseSensitive: false,
                ).hasMatch('$raw $reason');
                if (!isKnownNoise) {
                  unparsedLines.add(reason.isNotEmpty ? '$raw ($reason)' : raw);
                }
              } else if (u.toString().trim().isNotEmpty) {
                final str = u.toString().trim();
                final isKnownNoise = RegExp(
                  r'(?:ledger|settlement|matrix|not (?:individual )?lottery|tracking|payment|total|hisab|date column|gpay|upi|balance)',
                  caseSensitive: false,
                ).hasMatch(str);
                if (!isKnownNoise) {
                  unparsedLines.add(str);
                }
              }
            }
          }
        }

        if (items.isNotEmpty || unparsedLines.isNotEmpty) {
          return (items: items, unparsedLines: unparsedLines);
        }
      } catch (e) {
        // Fall back to line-by-line regex parser if JSON parsing fails
      }
    }

    // ⚡ Direct Dot-Matrix Printer / Purchase Return List Support:
    // e.g. "Purchase Return List of 28.09.2026", "MOR 12 Draw No : 305", "* * 90110 90114 = 60"
    if (trimmedText.contains('* *') && RegExp(r'\*\s*\*\s*\d{5}\s+\d{5}').hasMatch(trimmedText)) {
      final dotMatrixLines = trimmedText.split(RegExp(r'\r?\n'));
      String curDotSeries = '12';
      String detectedParty = defaultSeller;
      String detectedDate = fallbackDate;
      String detectedShift = _selectedShift;

      // Detect Date from "Purchase Return List of 28.09.2026"
      final dateHeaderMatch = RegExp(r'Purchase\s+Return\s+List\s+of\s+(\d{1,2})[\.-](\d{1,2})[\.-](\d{2,4})', caseSensitive: false).firstMatch(trimmedText);
      if (dateHeaderMatch != null) {
        final d = dateHeaderMatch.group(1)!.padLeft(2, '0');
        final m = dateHeaderMatch.group(2)!.padLeft(2, '0');
        var y = dateHeaderMatch.group(3)!;
        if (y.length == 2) y = '20$y';
        detectedDate = '$y-$m-$d';
      }

      // Detect Party from lines before the first "Draw No"
      for (final dl in dotMatrixLines) {
        final cleanL = dl.replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]+'), '').trim();
        if (cleanL.toLowerCase().contains('draw no') || cleanL.contains('* *')) break;
        if (cleanL.isNotEmpty &&
            !cleanL.toLowerCase().contains('purchase return') &&
            !cleanL.toLowerCase().contains('page :') &&
            cleanL.length >= 3 &&
            cleanL.length <= 40) {
          // If contains known party or agency e.g. "NEW SHIVAM"
          if (!cleanL.toUpperCase().contains('AYUSH AG') || detectedParty == defaultSeller) {
            detectedParty = cleanL;
          }
        }
      }

      // Auto-sync UI Party, Date, Shift synchronously
      if (detectedParty != defaultSeller && _partyCtrl.text != detectedParty) {
        _partyCtrl.text = detectedParty;
      }
      final parsedDate = DateTime.tryParse(detectedDate);
      if (parsedDate != null && _selectedDate != parsedDate) {
        _selectedDate = parsedDate;
      }

      final entryPattern = RegExp(r'\*\s*\*\s*(\d{5})\s+(\d{5})\s*=\s*(\d+)');
      final headerPattern = RegExp(r'(MOR|DAY|EVE|NIG)\s+(\d+)(?:\s+Draw)?', caseSensitive: false);

      for (final rawL in dotMatrixLines) {
        final cleanL = rawL.replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]+'), ' ').trim();
        if (cleanL.isEmpty) continue;

        // 1. Shift & Series Header (e.g. "DAY 12 Draw No : 305", "MOR 20", "EVE 24 Draw")
        final hMatch = headerPattern.firstMatch(cleanL);
        if (hMatch != null) {
          final shiftCode = hMatch.group(1)!.toUpperCase();
          curDotSeries = hMatch.group(2)!;
          if (shiftCode == 'MOR') {
            detectedShift = 'Dear 1 PM';
          } else if (shiftCode == 'DAY') {
            detectedShift = 'Dear 6 PM';
          } else if (shiftCode == 'EVE' || shiftCode == 'NIG') {
            detectedShift = 'Dear 8 PM';
          }
          continue;
        }

        // 2. Standalone Series Header or Series Tag (e.g. "20", "(20)", "[20]", "SERIES 20", "SER 20", "20.", "20 (6 PM)", "20 6PM")
        if (!cleanL.contains('* *') && !RegExp(r'\b\d{5}\b').hasMatch(cleanL)) {
          final serOnlyMatch = RegExp(
            r'^(?:ser(?:ies)?\s*[:=-]?\s*)?[\(\[\{]?\s*([0-9]{1,3})\s*[\)\]\}]?(?:[\s.:=-]+(?:(?:dear\s*)?[168](?::00|\.00|\.)?\s*(?:pm|am|day|mor|eve|nig)?|morning|day|evening|night)?)?\s*$',
            caseSensitive: false,
          ).firstMatch(cleanL);
          if (serOnlyMatch != null) {
            final sDigits = serOnlyMatch.group(1)!;
            final val = int.tryParse(sDigits);
            if (val != null && val <= 500 && val > 0) {
              curDotSeries = sDigits;
              if (RegExp(r'\b(?:1|mor|morning)\b', caseSensitive: false).hasMatch(cleanL)) {
                detectedShift = 'Dear 1 PM';
              } else if (RegExp(r'\b(?:6|day)\b', caseSensitive: false).hasMatch(cleanL)) {
                detectedShift = 'Dear 6 PM';
              } else if (RegExp(r'\b(?:8|eve|nig|night|evening)\b', caseSensitive: false).hasMatch(cleanL)) {
                detectedShift = 'Dear 8 PM';
              }
              continue;
            }
          }
        }

        // 3. Dot-matrix range entries: * * 62150 62169 = 400
        final matches = entryPattern.allMatches(cleanL);
        if (matches.isNotEmpty) {
          for (final m in matches) {
            final from = m.group(1)!;
            final to = m.group(2)!;
            final fromNum = int.tryParse(from) ?? 0;
            final toNum = int.tryParse(to) ?? fromNum;
            final books = (toNum >= fromNum) ? (toNum - fromNum + 1) : 1;
            final printedQty = int.tryParse(m.group(3)!);

            // ⚡ Auto-Detect / Sync Series from row's printed quantity:
            // e.g. 62150 62169 (20 books) = 400 => 400 / 20 = 20!
            String rowSeries = curDotSeries;
            if (printedQty != null && books > 0 && printedQty % books == 0) {
              final derivedSeries = printedQty ~/ books;
              const validSeriesList = [1, 5, 10, 12, 20, 24, 25, 36, 40, 50, 60, 100, 200];
              if (validSeriesList.contains(derivedSeries)) {
                rowSeries = derivedSeries.toString();
                curDotSeries = rowSeries; // Update current series for all subsequent lines!
              }
            }

            final qty = books;
            final rateVal = _getPriceForSeries(rowSeries);
            final amountVal = qty * rateVal;

            items.add(GeminiScannedItem(
              series: rowSeries,
              ticketNo: from == to ? from : '$from-$to',
              fromTicket: from,
              toTicket: to,
              quantity: qty,
              amount: amountVal,
              sellerName: detectedParty,
              drawShift: detectedShift,
              targetDate: detectedDate,
            ));
          }
        }
      }

      if (items.isNotEmpty) {
        return (items: items, unparsedLines: <String>[]);
      }
    }

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

      // 1. Check for Series Header or Series+Shift Combo (e.g. 24. 1pm, 24., (12), [36], SER 12, SERIES 20)
      if (!RegExp(r'\b\d{5}\b').hasMatch(l)) {
        String sClean = l;
        // Strip shift / timing noise if present (e.g. "1pm", "6pm", "dear 1pm")
        sClean = sClean.replaceAll(RegExp(r'\b(?:(?:dear\s*)?[168](?::00|\.00|\.)?\s*(?:pm|baje|am|qm|gm|p)?|morning|day|night|evening)\b', caseSensitive: false), ' ');
        // Strip dates if present
        sClean = sClean.replaceAll(RegExp(r'\b\d{1,2}[\/\.=-]\d{1,2}[\/\.=-]\d{2,4}\b'), ' ');

        final serMatch = RegExp(r'(?:^|[\s,;])[\(\[\{]?\s*(?:ser(?:ies)?)?\s*([0-9]{1,4}[A-Za-z]{0,4})\s*[\)\]\}]?(?:[\s:=.]|$)', caseSensitive: false).firstMatch(sClean);
        if (serMatch != null) {
          final sDigits = serMatch.group(1)!.replaceAll(RegExp(r'\D'), '');
          if (sDigits.isNotEmpty && int.tryParse(sDigits) != null && int.parse(sDigits) <= 5000) {
            currentSeries = sDigits;
            currentPrefix = ''; // Reset prefix on new series
            currentPrefix3 = '';
            continue;
          }
        }
      }

      // 2. In-Message Shift IGNORED: Active shift remains strictly locked to _selectedShift!
      final detectedShift = GeminiScannerService.instance.detectShiftFromText(l);
      if (detectedShift != null) {
        continue; // Skip noise line
      }

      // 3. In-Message Date IGNORED: Active date remains strictly locked to selected date!
      final dateMatch = RegExp(r'\b(\d{1,2})[\/\-](\d{1,2})(?:[\/\-](\d{2,4}))?\b').firstMatch(l);
      final singleDateMatch = RegExp(r'^\s*(\d{1,2})[\/\-]\s*[:]?\s*$').firstMatch(l);
      if ((dateMatch != null && !l.contains('to') && !l.contains('-') && l.length <= 12) || singleDateMatch != null) {
        continue; // Skip noise line
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
          final books = (end3 - start3) + 1;
          final qty = books;

          items.add(GeminiScannedItem(
            series: s,
            ticketNo: books > 1 ? '$fromStr - $toStr' : fromStr,
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
          final books = (end2 - start2) + 1;
          final qty = books;

          items.add(GeminiScannedItem(
            series: currentSeries,
            ticketNo: books > 1 ? '$fromStr - $toStr' : fromStr,
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
          final books = (end3 - start3) + 1;
          final qty = books;

          items.add(GeminiScannedItem(
            series: currentSeries,
            ticketNo: books > 1 ? '$fromStr - $toStr' : fromStr,
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
          final books = (tNum >= fNum) ? (tNum - fNum) + 1 : 1;
          final qty = books;

          currentPrefix = fTkt.substring(0, 2);

          items.add(GeminiScannedItem(
            series: s,
            ticketNo: books > 1 ? '$fTkt - $tTkt' : fTkt,
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
    final targetTrimmed = targetLine.trim();
    if (targetTrimmed.isEmpty) return;

    if (_allRawLines.isNotEmpty) {
      final globalIdx = _allRawLines.indexWhere((l) => l.trim() == targetTrimmed);
      if (globalIdx >= 0) {
        final targetChunk = globalIdx ~/ kChunkLines;
        if (targetChunk != _currentTextChunk) {
          _switchToTextChunk(targetChunk);
        }
      }
    }

    final fullText = _rawTextCtrl.text;
    if (fullText.isEmpty) return;

    final lines = fullText.split('\n');
    final List<int> matchOffsets = [];
    final List<int> matchLengths = [];

    int currentOffset = 0;
    for (final line in lines) {
      if (line.trim() == targetTrimmed) {
        matchOffsets.add(currentOffset);
        matchLengths.add(line.length);
      }
      currentOffset += line.length + 1;
    }

    if (matchOffsets.isEmpty) return;

    int idx = 0;
    if (_lastJumpedText == targetTrimmed) {
      idx = (_lastJumpedOccurrence + 1) % matchOffsets.length;
    }
    _lastJumpedText = targetTrimmed;
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

  /// Multi-Line Batch Tool: Prepend Series/Prefix to selected lines or active chunk lines
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
      final modified = text.split('\n').map((l) {
        if (l.trim().isEmpty) return l;
        return '$prefix$l';
      }).join('\n');
      _rawTextCtrl.text = modified;
    }
    _syncEditorChunkToAllRawLines();
    _reparseTextAsync();
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
    _syncEditorChunkToAllRawLines();
    _reparseTextAsync();
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

    _syncEditorChunkToAllRawLines();
    _allRawLines.add(lineToInsert);
    _quickFromCtrl.clear();
    _quickToCtrl.clear();
    final lastChunk = (_allRawLines.length - 1) ~/ kChunkLines;
    _currentTextChunk = lastChunk;
    _loadActiveChunkIntoEditor();
    _reparseTextAsync();
  }

  void _recalculateAllPrices() {
    for (final item in _parsedItems) {
      item.quantity = RawStockTextParserDialog.computeStrictQuantityFromRange(
        fromTicket: item.fromTicket,
        toTicket: item.toTicket,
        series: item.series,
      );
      final rate = _getPriceForSeries(item.series);
      item.amount = rate * (item.quantity > 0 ? item.quantity : 1);
    }
  }

  double _getPriceForSeries(String series) {
    try {
      final seriesState = ref.read(seriesPriceViewModelProvider);
      final price = seriesState.getPriceForSeries(series);
      if (price > 0) return price;
    } catch (_) {}

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
    if (_selectedStatusFilter == 'NOT_IN_VOUCHER') {
      filtered = filtered.where((it) {
        final s = _validationCache[it] ?? _computeItemValidationStatus(it);
        return s != null && (s.contains('Not in Voucher') || s.contains('Issued to'));
      }).toList();
    } else if (_selectedStatusFilter == 'VALID') {
      filtered = filtered.where((it) {
        final s = _validationCache[it] ?? _computeItemValidationStatus(it);
        return s == null;
      }).toList();
    } else if (_selectedStatusFilter == 'ALREADY_RETURNED') {
      filtered = filtered.where((it) {
        final s = _validationCache[it] ?? _computeItemValidationStatus(it);
        return s != null && s.contains('Already');
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
      _refreshValidationCache();
    });
  }

  Future<void> _applyDateToSelected() async {
    if (_selectedItems.isEmpty) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1970),
      lastDate: DateTime(2999),
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
        _refreshValidationCache();
      });
    }
  }

  void _deleteSelectedItems() {
    if (_selectedItems.isEmpty) return;
    setState(() {
      _parsedItems.removeWhere((it) => _selectedItems.contains(it));
      _selectedItems.clear();
      _lastSelectedIdx = null;
      _refreshValidationCache();
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      _loadFullRawText(data.text!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📋 Pasted ${_allRawLines.length} lines (${_totalTextChunks} chunks of 30 lines each)!'),
            backgroundColor: const Color(0xFF166534),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _pickAndLoadTextFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: widget.mode == StockScanMode.voucher
            ? 'Select Voucher Text File (.txt, .prn, .log, .json)'
            : 'Select Unsold / Purchase Return Text File (.txt, .prn, .log, .json)',
        type: FileType.custom,
        allowedExtensions: ['txt', 'prn', 'log', 'json', 'csv', 'dat'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.first;
      String fileContent = '';

      if (pickedFile.bytes != null) {
        fileContent = utf8.decode(pickedFile.bytes!, allowMalformed: true);
      } else if (pickedFile.path != null) {
        final f = File(pickedFile.path!);
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          fileContent = utf8.decode(bytes, allowMalformed: true);
        }
      }

      if (fileContent.trim().isNotEmpty) {
        _loadFullRawText(fileContent);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.file_open_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '📄 Loaded "${pickedFile.name}" (${_allRawLines.length} lines, ${_totalTextChunks} chunks of 30 lines!)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF065F46),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Selected file is empty!'),
              backgroundColor: Colors.amber,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Error opening file: $e'),
            backgroundColor: Colors.redAccent,
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

    final partyName = _partyCtrl.text.trim().isNotEmpty ? _partyCtrl.text.trim() : widget.defaultParty;
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // 🛡️ User Match & Verification Step: Confirm before committing to database
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.verified_outlined, color: Color(0xFF38BDF8), size: 22),
            const SizedBox(width: 8),
            Text(
              widget.mode == StockScanMode.voucher ? 'Verify & Save Stock Vouchers?' : 'Verify & Save Unsold Returns?',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please verify that all ticket ranges and quantities are correct before saving:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_rounded, size: 14, color: Color(0xFF38BDF8)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Party / Dealer: $partyName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFFFBBF24)),
                      const SizedBox(width: 6),
                      Text('Shift: $_selectedShift  |  Date: $dateStr', style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
                    ],
                  ),
                  const Divider(color: Color(0xFF334155), height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('📊 Total Ranges: ${_parsedItems.length}', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                      Text('🎟️ Total Tickets: $_totalTickets', style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('💰 Total Value:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text('₹${_totalAmount.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (widget.mode == StockScanMode.unsold) ...[
                    const Divider(color: Color(0xFF334155), height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF34D399)),
                            const SizedBox(width: 4),
                            Text('✓ In Voucher: $_cachedValidCount', style: const TextStyle(color: Color(0xFF34D399), fontSize: 11.5, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        if (_cachedNotInVoucherCount > 0)
                          Row(
                            children: [
                              const Icon(Icons.cancel_rounded, size: 13, color: Color(0xFFF87171)),
                              const SizedBox(width: 4),
                              Text('❌ Not In Voucher: $_cachedNotInVoucherCount', style: const TextStyle(color: Color(0xFFF87171), fontSize: 11.5, fontWeight: FontWeight.bold)),
                            ],
                          ),
                      ],
                    ),
                    if (_cachedNotInVoucherCount > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF450A0A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFEF4444)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFF87171)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Warning: $_cachedNotInVoucherCount ticket(s) were not found in any voucher issued to "$partyName"! Do you still want to proceed?',
                                style: const TextStyle(color: Color(0xFFFECACA), fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel / Review First', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_circle_rounded, size: 16),
            label: const Text('Confirm & Save Entries', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    final now = DateTime.now();

    try {
      int duplicateSkippedCount = 0;
      if (widget.mode == StockScanMode.voucher) {
        final List<VoucherModel> vouchersToSave = [];
        final seenRanges = <String>{};

        for (int i = 0; i < _parsedItems.length; i++) {
          final it = _parsedItems[i];
          final status = _validationCache[it] ?? _computeItemValidationStatus(it);
          if (status != null && (status.contains('Already in Voucher') || status.contains('Duplicate in Text'))) {
            duplicateSkippedCount++;
            continue;
          }
          final fTkt = it.fromTicket.isNotEmpty ? it.fromTicket : (it.ticketNo.contains('-') ? it.ticketNo.split('-').first.trim() : it.ticketNo);
          final tTkt = it.toTicket.isNotEmpty ? it.toTicket : (it.ticketNo.contains('-') ? it.ticketNo.split('-').last.trim() : it.ticketNo);
          final entryDate = _sanitizeTargetDate(it.targetDate, dateStr);
          final itemShift = (it.drawShift != null && it.drawShift!.isNotEmpty) ? it.drawShift! : _selectedShift;
          final normDate = _normalizeDateToYmd(entryDate);
          final canShift = _canonicalShift(itemShift);
          final serUpper = (it.series.isNotEmpty ? it.series : '12').toUpperCase();

          final key = '${normDate}_${canShift}_${serUpper}_$fTkt-$tTkt';
          if (seenRanges.contains(key)) {
            duplicateSkippedCount++;
            continue;
          }
          seenRanges.add(key);

          final voucherNo = 'VOUCH-${DateFormat('HHmmss').format(now)}-$i';
          final rate = it.amount / (it.quantity > 0 ? it.quantity : 1);
          final itemParty = (it.sellerName.isNotEmpty && it.sellerName != 'Walk-in Party')
              ? it.sellerName.trim()
              : partyName;

          vouchersToSave.add(
            VoucherModel(
              id: 'vouch_${now.microsecondsSinceEpoch}_$i',
              voucherNo: voucherNo,
              date: entryDate,
              drawShift: itemShift,
              partyName: itemParty,
              dealerName: partyName,
              series: serUpper,
              fromTicket: fTkt,
              toTicket: tTkt,
              totalQty: it.quantity > 0 ? it.quantity : 1,
              pricePerTicket: rate,
              totalAmount: it.amount,
              createdAt: now,
            ),
          );
        }

        if (vouchersToSave.isEmpty) {
          setState(() => _isSaving = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ All vouchers were duplicates or already exist! Nothing to save.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        final totalToSave = vouchersToSave.length;
        const chunkSize = 500;
        final totalChunks = (totalToSave / chunkSize).ceil();
        for (int c = 0; c < totalChunks; c++) {
          final startIdx = c * chunkSize;
          final endIdx = (startIdx + chunkSize < totalToSave) ? startIdx + chunkSize : totalToSave;
          final chunk = vouchersToSave.sublist(startIdx, endIdx);

          if (mounted) {
            setState(() {
              _chunkProgress = endIdx / totalToSave;
              _chunkProgressMessage = '💾 Saving Chunk ${c + 1}/$totalChunks ($endIdx / $totalToSave vouchers)...';
            });
          }

          await ref.read(voucherViewModelProvider.notifier).addVouchersBatch(chunk);
          await Future<void>.delayed(Duration.zero);
        }
        _allVouchers = [...vouchersToSave, ..._allVouchers];
        _buildFastVouchers();
      } else {
        final List<UnsoldModel> unsoldToSave = [];
        final seenRanges = <String>{};

        for (int i = 0; i < _parsedItems.length; i++) {
          final it = _parsedItems[i];
          final status = _validationCache[it] ?? _computeItemValidationStatus(it);

          // 🚫 STRICT DUPLICATE PREVENTION: Never insert if already returned or duplicate in text
          if (status != null && (status.contains('Already Returned') || status.contains('Duplicate in Text') || status.contains('Already in Voucher'))) {
            duplicateSkippedCount++;
            continue;
          }

          final fTkt = it.fromTicket.isNotEmpty ? it.fromTicket : (it.ticketNo.contains('-') ? it.ticketNo.split('-').first.trim() : it.ticketNo);
          final tTkt = it.toTicket.isNotEmpty ? it.toTicket : (it.ticketNo.contains('-') ? it.ticketNo.split('-').last.trim() : it.ticketNo);
          final entryDate = _sanitizeTargetDate(it.targetDate, dateStr);
          final itemShift = (it.drawShift != null && it.drawShift!.isNotEmpty) ? it.drawShift! : _selectedShift;
          final normDate = _normalizeDateToYmd(entryDate);
          final canShift = _canonicalShift(itemShift);
          final serUpper = (it.series.isNotEmpty ? it.series : '12').toUpperCase();

          final key = '${normDate}_${canShift}_${serUpper}_$fTkt-$tTkt';
          if (seenRanges.contains(key)) {
            duplicateSkippedCount++;
            continue;
          }
          seenRanges.add(key);

          final returnNo = 'RET-${DateFormat('HHmmss').format(now)}-$i';
          final rate = it.amount / (it.quantity > 0 ? it.quantity : 1);
          final itemParty = (it.sellerName.isNotEmpty && it.sellerName != 'Walk-in Party')
              ? it.sellerName.trim()
              : partyName;

          unsoldToSave.add(
            UnsoldModel(
              id: 'unsold_${now.microsecondsSinceEpoch}_$i',
              returnNo: returnNo,
              date: entryDate,
              drawShift: itemShift,
              partyName: itemParty,
              dealerName: partyName,
              series: serUpper,
              fromTicket: fTkt,
              toTicket: tTkt,
              totalQty: it.quantity > 0 ? it.quantity : 1,
              pricePerTicket: rate,
              totalAmount: it.amount,
              createdAt: now,
            ),
          );
        }

        if (unsoldToSave.isEmpty) {
          setState(() => _isSaving = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ All tickets were duplicates or already returned! Nothing was saved.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        final totalToSave = unsoldToSave.length;
        const chunkSize = 500;
        final totalChunks = (totalToSave / chunkSize).ceil();
        for (int c = 0; c < totalChunks; c++) {
          final startIdx = c * chunkSize;
          final endIdx = (startIdx + chunkSize < totalToSave) ? startIdx + chunkSize : totalToSave;
          final chunk = unsoldToSave.sublist(startIdx, endIdx);

          if (mounted) {
            setState(() {
              _chunkProgress = endIdx / totalToSave;
              _chunkProgressMessage = '💾 Saving Chunk ${c + 1}/$totalChunks ($endIdx / $totalToSave unsold)...';
            });
          }

          await ref.read(unsoldViewModelProvider.notifier).addUnsoldBatch(chunk);
          await Future<void>.delayed(Duration.zero);
        }
        _allUnsold = [...unsoldToSave, ..._allUnsold];
      }

      if (mounted) {
        if (duplicateSkippedCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ℹ️ $duplicateSkippedCount duplicate/already returned tickets were skipped!'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        setState(() {
          _isSaving = false;
          _isChunkProcessing = false;
        });
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isChunkProcessing = false;
        });
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
            it.quantity = RawStockTextParserDialog.computeStrictQuantityFromRange(
              fromTicket: it.fromTicket,
              toTicket: it.toTicket,
              series: it.series,
            );
            fixedCount++;

            if (int.tryParse(prefix2) != null) {
              final start3 = fStr.substring(2);
              final newFrom2 = '$prefix2$start3';
              final newTo2 = '$prefix2$last3';
              final cloneQty = RawStockTextParserDialog.computeStrictQuantityFromRange(
                fromTicket: newFrom2,
                toTicket: newTo2,
                series: it.series,
              );
              final clone = GeminiScannedItem(
                series: it.series,
                ticketNo: '$newFrom2 - $newTo2',
                fromTicket: newFrom2,
                toTicket: newTo2,
                quantity: cloneQty,
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
            it.quantity = RawStockTextParserDialog.computeStrictQuantityFromRange(
              fromTicket: it.fromTicket,
              toTicket: it.toTicket,
              series: it.series,
            );
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

  Widget _buildTextChunkNavBar() {
    final totalChunks = _totalTextChunks;
    final totalLines = _allRawLines.length;
    final startLine = totalLines == 0 ? 0 : (_currentTextChunk * kChunkLines) + 1;
    final endLine = totalLines == 0 ? 0 : math.min((_currentTextChunk + 1) * kChunkLines, totalLines);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF070E1E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.layers_rounded, size: 14, color: Color(0xFF38BDF8)),
          const SizedBox(width: 5),
          Text(
            'TEXT CHUNK ${_currentTextChunk + 1}/$totalChunks',
            style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 10.5),
          ),
          const SizedBox(width: 4),
          Text(
            '($startLine-$endLine of $totalLines lines • 30/chunk)',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 9.5),
          ),
          const Spacer(),
          // Prev Chunk
          InkWell(
            onTap: _currentTextChunk > 0 ? () => _switchToTextChunk(_currentTextChunk - 1) : null,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _currentTextChunk > 0 ? const Color(0xFF1E293B) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _currentTextChunk > 0 ? const Color(0xFF475569) : Colors.transparent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left_rounded, size: 14, color: _currentTextChunk > 0 ? Colors.white : Colors.grey.shade700),
                  Text('Prev', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: _currentTextChunk > 0 ? Colors.white : Colors.grey.shade700)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Next Chunk
          InkWell(
            onTap: _currentTextChunk < totalChunks - 1 ? () => _switchToTextChunk(_currentTextChunk + 1) : null,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _currentTextChunk < totalChunks - 1 ? const Color(0xFF1E293B) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _currentTextChunk < totalChunks - 1 ? const Color(0xFF475569) : Colors.transparent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Next', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: _currentTextChunk < totalChunks - 1 ? Colors.white : Colors.grey.shade700)),
                  Icon(Icons.chevron_right_rounded, size: 14, color: _currentTextChunk < totalChunks - 1 ? Colors.white : Colors.grey.shade700),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextChunkPills() {
    if (_totalTextChunks <= 1) return const SizedBox.shrink();
    return Container(
      height: 24,
      margin: const EdgeInsets.only(bottom: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _totalTextChunks,
        itemBuilder: (ctx, i) {
          final isCur = i == _currentTextChunk;
          final sL = (i * kChunkLines) + 1;
          final eL = math.min((i + 1) * kChunkLines, _allRawLines.length);
          return Padding(
            padding: const EdgeInsets.only(right: 3),
            child: InkWell(
              onTap: () => _switchToTextChunk(i),
              borderRadius: BorderRadius.circular(3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isCur ? const Color(0xFF0284C7) : const Color(0xFF0B1220),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: isCur ? const Color(0xFF38BDF8) : const Color(0xFF1E293B)),
                ),
                child: Text(
                  'C${i + 1}: $sL-$eL',
                  style: TextStyle(
                    color: isCur ? Colors.white : Colors.grey.shade400,
                    fontSize: 9,
                    fontWeight: isCur ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTableChunkNavBar() {
    final totalChunks = _totalParsedChunks;
    final totalItems = _displayedItems.length;
    final startItem = totalItems == 0 ? 0 : (_currentParsedChunk * kChunkLines) + 1;
    final endItem = totalItems == 0 ? 0 : math.min((_currentParsedChunk + 1) * kChunkLines, totalItems);

    return Container(
      margin: const EdgeInsets.fromLTRB(6, 0, 6, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF070E1E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        children: [
          Icon(
            _isContinuousTableScroll ? Icons.unfold_more_rounded : Icons.table_rows_rounded,
            size: 14,
            color: const Color(0xFF4ADE80),
          ),
          const SizedBox(width: 5),
          Text(
            _isContinuousTableScroll
                ? 'ALL ROWS ($totalItems total)'
                : 'TABLE CHUNK ${_currentParsedChunk + 1}/$totalChunks',
            style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 10.5),
          ),
          const SizedBox(width: 4),
          Text(
            _isContinuousTableScroll
                ? '• 60FPS Virtualized Smooth Scroll'
                : '($startItem-$endItem of $totalItems rows • 30/chunk)',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 9.5),
          ),
          const Spacer(),
          // Mode Toggle: 30/Chunk vs Continuous All
          InkWell(
            onTap: () {
              setState(() {
                _isContinuousTableScroll = !_isContinuousTableScroll;
              });
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _isContinuousTableScroll ? const Color(0xFF1E3A8A) : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _isContinuousTableScroll ? const Color(0xFF60A5FA) : const Color(0xFF334155)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isContinuousTableScroll ? Icons.flash_on_rounded : Icons.view_stream_rounded,
                    size: 11,
                    color: _isContinuousTableScroll ? const Color(0xFF93C5FD) : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _isContinuousTableScroll ? 'Scroll: Continuous' : 'Scroll: 30/Page',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: _isContinuousTableScroll ? Colors.white : Colors.grey.shade300,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_isContinuousTableScroll) ...[
            const SizedBox(width: 6),
            // Prev Chunk
            InkWell(
              onTap: _currentParsedChunk > 0 ? () => _switchToParsedChunk(_currentParsedChunk - 1) : null,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _currentParsedChunk > 0 ? const Color(0xFF1E293B) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _currentParsedChunk > 0 ? const Color(0xFF475569) : Colors.transparent),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left_rounded, size: 14, color: _currentParsedChunk > 0 ? Colors.white : Colors.grey.shade700),
                    Text('Prev', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: _currentParsedChunk > 0 ? Colors.white : Colors.grey.shade700)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Next Chunk
            InkWell(
              onTap: _currentParsedChunk < totalChunks - 1 ? () => _switchToParsedChunk(_currentParsedChunk + 1) : null,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _currentParsedChunk < totalChunks - 1 ? const Color(0xFF1E293B) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _currentParsedChunk < totalChunks - 1 ? const Color(0xFF475569) : Colors.transparent),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Next', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: _currentParsedChunk < totalChunks - 1 ? Colors.white : Colors.grey.shade700)),
                    Icon(Icons.chevron_right_rounded, size: 14, color: _currentParsedChunk < totalChunks - 1 ? Colors.white : Colors.grey.shade700),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTableChunkPills() {
    if (_isContinuousTableScroll || _totalParsedChunks <= 1) return const SizedBox.shrink();
    return Container(
      height: 24,
      margin: const EdgeInsets.fromLTRB(6, 0, 6, 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _totalParsedChunks,
        itemBuilder: (ctx, i) {
          final isCur = i == _currentParsedChunk;
          final sR = (i * kChunkLines) + 1;
          final eR = math.min((i + 1) * kChunkLines, _displayedItems.length);
          return Padding(
            padding: const EdgeInsets.only(right: 3),
            child: InkWell(
              onTap: () => _switchToParsedChunk(i),
              borderRadius: BorderRadius.circular(3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isCur ? const Color(0xFF166534) : const Color(0xFF0B1220),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: isCur ? const Color(0xFF4ADE80) : const Color(0xFF1E293B)),
                ),
                child: Text(
                  'R${i + 1}: $sR-$eR',
                  style: TextStyle(
                    color: isCur ? Colors.white : Colors.grey.shade400,
                    fontSize: 9,
                    fontWeight: isCur ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
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
                _refreshValidationCache();
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
    ref.watch(sellerCustomerViewModelProvider);
    ref.listen<SellerCustomerState>(sellerCustomerViewModelProvider, (prev, next) {
      _loadDealersAndSellers();
    });

    final isVoucher = widget.mode == StockScanMode.voucher;
    final primaryColor = isVoucher ? const Color(0xFF3B82F6) : const Color(0xFFEF4444);
    final primaryGlow = isVoucher ? const Color(0xFF1D4ED8) : const Color(0xFFDC2626);
    final modeTitle = isVoucher ? 'PASTE JSON / VOUCHER PARCHA' : 'PASTE JSON / UNSOLD RETURN';

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
        child: Stack(
          children: [
            Column(
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
                                  if (val != null) {
                                    final oldShift = _selectedShift;
                                    setState(() {
                                      _selectedShift = val;
                                      for (final it in _parsedItems) {
                                        if (it.drawShift == null || it.drawShift == oldShift) {
                                          it.drawShift = val;
                                        }
                                      }
                                    });
                                    _refreshValidationCache();
                                  }
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
                                firstDate: DateTime(1970),
                                lastDate: DateTime(2999),
                              );
                              if (picked != null) {
                                final oldDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
                                final newDateStr = DateFormat('yyyy-MM-dd').format(picked);
                                setState(() {
                                  _selectedDate = picked;
                                  for (final it in _parsedItems) {
                                    if (it.targetDate == null || it.targetDate == oldDateStr) {
                                      it.targetDate = newDateStr;
                                    }
                                  }
                                });
                                _refreshValidationCache();
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

                  // 🔍 Real-Time Voucher Verification Badges
                  if (_parsedItems.isNotEmpty && widget.mode == StockScanMode.unsold) ...[
                    _statPill('$_cachedValidCount', 'In Voucher', const Color(0xFF064E3B), const Color(0xFF34D399)),
                    const SizedBox(width: 6),
                    if (_cachedNotInVoucherCount > 0) ...[
                      _statPill('$_cachedNotInVoucherCount', 'Not In Voucher', const Color(0xFF450A0A), const Color(0xFFF87171)),
                      const SizedBox(width: 6),
                    ],
                    if (_cachedAlreadyIssuedCount > 0) ...[
                      _statPill('$_cachedAlreadyIssuedCount', 'Duplicate', const Color(0xFF451A03), const Color(0xFFFBBF24)),
                      const SizedBox(width: 6),
                    ],
                  ],

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

                  // 🏢 1. Dealer Selector (Instant Searchable Modal)
                  InkWell(
                    onTap: () async {
                      final chosen = await SearchableDealerPickerDialog.show(
                        context: context,
                        dealers: _availableDealers,
                        dealerToSellersMap: _dealerToSellersMap,
                        selectedDealer: _selectedDealer,
                        title: 'Select Dealer (${_availableDealers.length})',
                        allowAllOption: true,
                        allOptionLabel: '🏢 All Dealers / Direct',
                        allOptionValue: 'All Dealers',
                      );
                      if (chosen != null) {
                        setState(() {
                          _selectedDealer = (chosen == 'All Dealers') ? null : chosen;
                          _selectedSubSeller = null;
                          if (_selectedDealer != null) {
                            _partyCtrl.text = _selectedDealer!;
                          }
                          _reparseText();
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFF59E0B).withAlpha(140)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.workspace_premium_rounded, size: 14, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 6),
                          Text(
                            _selectedDealer ?? 'Select Dealer (${_availableDealers.length})',
                            style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.search_rounded, size: 14, color: Color(0xFFF59E0B)),
                        ],
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
                      onChanged: (val) {
                        final cleanParty = val.trim();
                        for (final item in _parsedItems) {
                          item.sellerName = cleanParty;
                        }
                        _refreshValidationCache();
                        setState(() {});
                      },
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
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _pickAndLoadTextFile,
                                  icon: const Icon(Icons.file_open_rounded, size: 13),
                                  label: const Text('📁 UPLOAD .TXT / .PRN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF059669),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                ),
                                const SizedBox(width: 6),
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
                                ElevatedButton.icon(
                                  onPressed: () {
                                    final currentParty = _partyCtrl.text.isNotEmpty ? _partyCtrl.text : widget.defaultParty;
                                    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                                    _rawTextCtrl.text = '''{
  "summary": {
    "detected_party": "$currentParty",
    "detected_shift": "Dear 8 PM",
    "detected_date": "$todayStr",
    "total_ranges": 5,
    "total_tickets": 500,
    "has_doubts": false
  },
  "items": [
    {
      "raw_text": "08:P.M-(12) 85100-300-399",
      "series": "12",
      "from": "85100",
      "to": "85399",
      "qty": 300,
      "rate": 4.50,
      "party": "$currentParty",
      "shift": "Dear 8 PM",
      "doubt": null
    },
    {
      "raw_text": "08:P.M-(20) 52150-750-799 (Booklet 1)",
      "series": "20",
      "from": "52150",
      "to": "52199",
      "qty": 50,
      "rate": 7.50,
      "party": "$currentParty",
      "shift": "Dear 8 PM",
      "doubt": null
    },
    {
      "raw_text": "08:P.M-(20) 52150-750-799 (Booklet 2)",
      "series": "20",
      "from": "52750",
      "to": "52799",
      "qty": 50,
      "rate": 7.50,
      "party": "$currentParty",
      "shift": "Dear 8 PM",
      "doubt": null
    },
    {
      "raw_text": "08:P.M-(24) 34150-750-799 (Booklet 1)",
      "series": "24",
      "from": "34150",
      "to": "34199",
      "qty": 50,
      "rate": 9.00,
      "party": "$currentParty",
      "shift": "Dear 8 PM",
      "doubt": null
    },
    {
      "raw_text": "08:P.M-(24) 34150-750-799 (Booklet 2)",
      "series": "24",
      "from": "34750",
      "to": "34799",
      "qty": 50,
      "rate": 9.00,
      "party": "$currentParty",
      "shift": "Dear 8 PM",
      "doubt": null
    }
  ],
  "unparsed": [
    {
      "raw_text": "Date column: 28/09/26 with daily ledger count (80, 76)",
      "reason": "Stock voucher settlement ledger note"
    }
  ]
}''';
                                    _reparseText();
                                  },
                                  icon: const Icon(Icons.data_object_rounded, size: 13),
                                  label: const Text('{ } SAMPLE JSON', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6366F1),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _allRawLines.clear();
                                      _currentTextChunk = 0;
                                      _currentParsedChunk = 0;
                                      _rawTextCtrl.clear();
                                      _parsedItems.clear();
                                      _unparsedLines.clear();
                                      _selectedItems.clear();
                                      _lastSelectedIdx = null;
                                      _validationCache.clear();
                                      _cachedValidCount = 0;
                                      _cachedNotInVoucherCount = 0;
                                      _cachedAlreadyIssuedCount = 0;
                                    });
                                  },
                                  icon: const Icon(Icons.delete_sweep_rounded, size: 13, color: Colors.grey),
                                  label: const Text('CLEAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: Colors.grey)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFF334155)),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                ),
                                if (_unparsedLines.isNotEmpty) ...[
                                  const SizedBox(width: 6),
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
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B1220),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF1E293B)),
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
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
                                  const SizedBox(width: 8),
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

                          // ⚡ Text Chunk Navigation Bar & Quick Jump Pills (30 Lines / Chunk)
                          _buildTextChunkNavBar(),
                          _buildTextChunkPills(),

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
                                    width: 38,
                                    padding: const EdgeInsets.only(top: 12, bottom: 12),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF070B16),
                                      borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
                                      border: Border(right: BorderSide(color: Color(0xFF1E293B))),
                                    ),
                                    child: ListView.builder(
                                      controller: _rawTextScrollCtrl,
                                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                                      itemCount: textLines.isEmpty ? 1 : textLines.length,
                                      itemBuilder: (ctx, i) {
                                        final realLineNum = (_currentTextChunk * kChunkLines) + (i + 1);
                                        return InkWell(
                                          onTap: () => _handleLineGutterClick(i),
                                          child: Container(
                                            height: 18.1,
                                            alignment: Alignment.centerRight,
                                            padding: const EdgeInsets.only(right: 6),
                                            child: Text(
                                              '$realLineNum',
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

                                  // Actual Text Field with Synchronized Smooth Scrolling & Scrollbar
                                  Expanded(
                                    child: Scrollbar(
                                      controller: _textInputScrollCtrl,
                                      thumbVisibility: true,
                                      trackVisibility: true,
                                      thickness: 5,
                                      radius: const Radius.circular(3),
                                      child: TextField(
                                        controller: _rawTextCtrl,
                                        scrollController: _textInputScrollCtrl,
                                        scrollPhysics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
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
                                              ? 'Paste JSON array OR Voucher parcha text here...\n\nExample JSON:\n[\n  {"series": "12", "from": "50271", "to": "50274", "qty": 4, "rate": 37.50, "party": "Raju"}\n]\n\nOr Regular Text:\n(12) 50271-274\n(24) 11200-299...'
                                              : 'Paste JSON array OR Unsold parcha text here...\n\nExample JSON:\n[\n  {"series": "12", "from": "50271", "to": "50274", "qty": 4, "party": "Raju"}\n]\n\nOr Regular Text:\n(12) 50271-274...',
                                          hintStyle: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                                          border: InputBorder.none,
                                          contentPadding: const EdgeInsets.all(12),
                                        ),
                                        onChanged: (_) => _onTextChanged(),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          color: const Color(0xFF0B1120),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
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
                                    width: 150,
                                    height: 26,
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
                              if (_parsedItems.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    const Text('Status Filter:', style: TextStyle(color: Colors.grey, fontSize: 9.5, fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 6),
                                    _buildStatusFilterPill('ALL', 'ALL (${_parsedItems.length})', const Color(0xFF1E293B), Colors.grey.shade300),
                                    const SizedBox(width: 4),
                                    _buildStatusFilterPill('VALID', '✓ In Voucher ($_cachedValidCount)', const Color(0xFF064E3B), const Color(0xFF34D399)),
                                    if (_cachedNotInVoucherCount > 0) ...[
                                      const SizedBox(width: 4),
                                      _buildStatusFilterPill('NOT_IN_VOUCHER', '❌ Not in Voucher ($_cachedNotInVoucherCount)', const Color(0xFF450A0A), const Color(0xFFF87171)),
                                    ],
                                    if (_cachedAlreadyIssuedCount > 0) ...[
                                      const SizedBox(width: 4),
                                      _buildStatusFilterPill('ALREADY_RETURNED', '⚠️ Duplicate ($_cachedAlreadyIssuedCount)', const Color(0xFF451A03), const Color(0xFFFBBF24)),
                                    ],
                                    const Spacer(),
                                    if (widget.mode == StockScanMode.unsold && _cachedNotInVoucherCount > 0)
                                      InkWell(
                                        onTap: _removeNotInVoucherItems,
                                        borderRadius: BorderRadius.circular(4),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF7F1D1D),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFFEF4444)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.delete_sweep_rounded, size: 12, color: Colors.white),
                                              const SizedBox(width: 4),
                                              Text('Discard $_cachedNotInVoucherCount Not in Voucher', style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (_cachedAlreadyIssuedCount > 0) ...[
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: _removeAlreadyIssuedItems,
                                        borderRadius: BorderRadius.circular(4),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF78350F),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFFF59E0B)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.delete_sweep_rounded, size: 12, color: Colors.white),
                                              const SizedBox(width: 4),
                                              Text('Discard $_cachedAlreadyIssuedCount Duplicates', style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Bulk Action Bar (when selected)
                        _buildReviewBulkActionBar(),

                        // ⚡ Table Chunk Navigation Bar & Quick Jump Pills (30 Rows / Chunk)
                        _buildTableChunkNavBar(),
                        _buildTableChunkPills(),

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
                              const SizedBox(width: 4),
                              SizedBox(
                                width: 120,
                                child: Center(
                                  child: Text(
                                    widget.mode == StockScanMode.voucher ? 'VOUCHER STATUS' : 'IN VOUCHER?',
                                    style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 36, child: Center(child: Text('DEL', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 10)))),
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
                              : Scrollbar(
                                  controller: _tableScrollCtrl,
                                  thumbVisibility: true,
                                  trackVisibility: true,
                                  thickness: 6,
                                  radius: const Radius.circular(3),
                                  child: ListView.builder(
                                    controller: _tableScrollCtrl,
                                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                                    itemExtent: 31.0,
                                    itemCount: _isContinuousTableScroll
                                        ? _displayedItems.length
                                        : _visibleParsedChunkItems.length,
                                    itemBuilder: (ctx, idx) {
                                      final items = _isContinuousTableScroll
                                          ? _displayedItems
                                          : _visibleParsedChunkItems;
                                      final item = items[idx];
                                      final realIdx = _isContinuousTableScroll
                                          ? idx
                                          : ((_currentParsedChunk * kChunkLines) + idx);
                                      final isSelected = _selectedItems.contains(item);

                                      return _StockItemRowWidget(
                                        key: ValueKey('item_${item.hashCode}_${item.fromTicket}_${item.toTicket}'),
                                        item: item,
                                        index: realIdx,
                                        isSelected: isSelected,
                                        selectedDate: _selectedDate,
                                        selectedShift: _selectedShift,
                                        mode: widget.mode,
                                        statusBadge: _buildItemStatusBadge(item),
                                        onTap: () => _handleRowTap(realIdx, item),
                                        onDelete: () => setState(() {
                                          _parsedItems.remove(item);
                                          _selectedItems.remove(item);
                                          _refreshValidationCache();
                                        }),
                                        onItemChanged: () => _onRowItemChanged(item),
                                        onPickDate: () async {
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate: _selectedDate,
                                            firstDate: DateTime(1970),
                                            lastDate: DateTime(2999),
                                          );
                                          if (picked != null) {
                                            item.targetDate = DateFormat('yyyy-MM-dd').format(picked);
                                            _onRowItemChanged(item);
                                          }
                                        },
                                        onToggleShift: () {
                                          final cur = (item.drawShift != null && item.drawShift!.isNotEmpty) ? item.drawShift! : _selectedShift;
                                          final next = cur.contains('1') ? 'Dear 6 PM' : (cur.contains('6') ? 'Dear 8 PM' : 'Dear 1 PM');
                                          item.drawShift = next;
                                          _onRowItemChanged(item);
                                        },
                                      );
                                    },
                                  ),
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

                  // Quick Discard Not in Voucher Button (Unsold Mode)
                  if (widget.mode == StockScanMode.unsold && _cachedNotInVoucherCount > 0) ...[
                    ElevatedButton.icon(
                      onPressed: _removeNotInVoucherItems,
                      icon: const Icon(Icons.delete_sweep_rounded, size: 14),
                      label: Text(
                        'DISCARD NOT IN VOUCHER ($_cachedNotInVoucherCount)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB91C1C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (_cachedAlreadyIssuedCount > 0) ...[
                    ElevatedButton.icon(
                      onPressed: _removeAlreadyIssuedItems,
                      icon: const Icon(Icons.delete_sweep_rounded, size: 14),
                      label: Text(
                        'DISCARD DUPLICATES ($_cachedAlreadyIssuedCount)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB45309),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

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
        if (_isChunkProcessing || _isSaving)
          Positioned(
            top: 58,
            right: 18,
            child: _buildChunkProgressBubble(),
          ),
      ],
    ),
  ),
);
}

  Widget _buildChunkProgressBubble() {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 390),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0284C7).withAlpha(140),
              blurRadius: 18,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.black.withAlpha(200),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '⚡ FAST CHUNK ENGINE',
                  style: TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF065F46),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '60 FPS • NO FREEZE',
                    style: TextStyle(
                      color: Color(0xFF6EE7B7),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _chunkProgressMessage.isNotEmpty ? _chunkProgressMessage : 'Processing chunks in background...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _chunkProgress > 0 ? _chunkProgress.clamp(0.0, 1.0) : null,
                minHeight: 5,
                backgroundColor: const Color(0xFF334155),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF06B6D4)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusFilterPill(String key, String label, Color bg, Color textCol) {
    final isSel = _selectedStatusFilter == key;
    return InkWell(
      onTap: () => setState(() => _selectedStatusFilter = key),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSel ? bg.withAlpha(240) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSel ? textCol : textCol.withAlpha(60)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSel ? Colors.white : textCol,
            fontSize: 9.5,
            fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildItemStatusBadge(GeminiScannedItem item) {
    final status = _validationCache[item] ?? _computeItemValidationStatus(item);

    if (status == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF064E3B),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF10B981).withAlpha(150)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 10.5, color: Color(0xFF34D399)),
            SizedBox(width: 3),
            Text('In Voucher', style: TextStyle(color: Color(0xFF34D399), fontSize: 9, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    if (status.contains('Not in Voucher')) {
      return Tooltip(
        message: status,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF450A0A),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFEF4444)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cancel_rounded, size: 10.5, color: Color(0xFFF87171)),
              SizedBox(width: 3),
              Text('Not In Voucher', style: TextStyle(color: Color(0xFFF87171), fontSize: 9, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    if (status.contains('Issued to')) {
      return Tooltip(
        message: status,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF431407),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFF97316)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_horiz_rounded, size: 10.5, color: Color(0xFFFB923C)),
              const SizedBox(width: 3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 82),
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFFB923C), fontSize: 8.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Already returned / duplicate
    return Tooltip(
      message: status,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF451A03),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFF59E0B)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 10.5, color: Color(0xFFFBBF24)),
            const SizedBox(width: 3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 82),
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 8.5, fontWeight: FontWeight.bold),
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

/// Dedicated State-Preserving Table Row Widget
/// Ensures typing into Series and Ticket Range text boxes never causes cursor resets,
/// loss of focus, or lagging, while immediately recalculating amounts and auto-updating vouchers.
class _StockItemRowWidget extends StatefulWidget {
  final GeminiScannedItem item;
  final int index;
  final bool isSelected;
  final DateTime selectedDate;
  final String selectedShift;
  final StockScanMode mode;
  final Widget statusBadge;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onItemChanged;
  final Future<void> Function() onPickDate;
  final VoidCallback onToggleShift;

  const _StockItemRowWidget({
    super.key,
    required this.item,
    required this.index,
    required this.isSelected,
    required this.selectedDate,
    required this.selectedShift,
    required this.mode,
    required this.statusBadge,
    required this.onTap,
    required this.onDelete,
    required this.onItemChanged,
    required this.onPickDate,
    required this.onToggleShift,
  });

  @override
  State<_StockItemRowWidget> createState() => _StockItemRowWidgetState();
}

class _StockItemRowWidgetState extends State<_StockItemRowWidget> {
  late TextEditingController _seriesCtrl;
  late TextEditingController _ticketCtrl;

  @override
  void initState() {
    super.initState();
    _seriesCtrl = TextEditingController(text: widget.item.series);
    _ticketCtrl = TextEditingController(text: widget.item.ticketNo);
  }

  @override
  void didUpdateWidget(_StockItemRowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep controllers in sync when items are updated externally (e.g. bulk series apply)
    if (widget.item.series != _seriesCtrl.text) {
      final oldSel = _seriesCtrl.selection;
      _seriesCtrl.value = _seriesCtrl.value.copyWith(
        text: widget.item.series,
        selection: oldSel.isValid && oldSel.end <= widget.item.series.length
            ? oldSel
            : TextSelection.collapsed(offset: widget.item.series.length),
      );
    }
    if (widget.item.ticketNo != _ticketCtrl.text) {
      final oldSel = _ticketCtrl.selection;
      _ticketCtrl.value = _ticketCtrl.value.copyWith(
        text: widget.item.ticketNo,
        selection: oldSel.isValid && oldSel.end <= widget.item.ticketNo.length
            ? oldSel
            : TextSelection.collapsed(offset: widget.item.ticketNo.length),
      );
    }
  }

  @override
  void dispose() {
    _seriesCtrl.dispose();
    _ticketCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final idx = widget.index;
    final isSelected = widget.isSelected;

    return InkWell(
      onTap: widget.onTap,
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
            // Checkbox & Row #
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
                onTap: widget.onPickDate,
                child: Text(
                  item.targetDate != null
                      ? item.targetDate!.split('-').skip(1).join('/')
                      : DateFormat('dd/MM').format(widget.selectedDate),
                  style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 9.5, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Shift Pill
            SizedBox(
              width: 58,
              child: GestureDetector(
                onTap: widget.onToggleShift,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: ((item.drawShift ?? widget.selectedShift).contains('1'))
                        ? const Color(0xFF0F2942)
                        : ((item.drawShift ?? widget.selectedShift).contains('6') ? const Color(0xFF2E1065) : const Color(0xFF3F1D38)),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: ((item.drawShift ?? widget.selectedShift).contains('1'))
                          ? const Color(0xFF38BDF8).withAlpha(150)
                          : ((item.drawShift ?? widget.selectedShift).contains('6') ? const Color(0xFFA78BFA).withAlpha(150) : const Color(0xFFF472B6).withAlpha(150)),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      (item.drawShift != null && item.drawShift!.isNotEmpty ? item.drawShift! : widget.selectedShift).replaceAll('Dear ', ''),
                      style: TextStyle(
                        color: ((item.drawShift ?? widget.selectedShift).contains('1'))
                            ? const Color(0xFF38BDF8)
                            : ((item.drawShift ?? widget.selectedShift).contains('6') ? const Color(0xFFA78BFA) : const Color(0xFFF472B6)),
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Series (Editable Text Box)
            SizedBox(
              width: 50,
              height: 24,
              child: TextField(
                controller: _seriesCtrl,
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
                  item.quantity = RawStockTextParserDialog.computeStrictQuantityFromRange(
                    fromTicket: item.fromTicket,
                    toTicket: item.toTicket,
                    series: item.series,
                  );
                  widget.onItemChanged();
                },
              ),
            ),
            const SizedBox(width: 6),

            // Ticket Range (Editable Text Box)
            Expanded(
              child: SizedBox(
                height: 24,
                child: TextField(
                  controller: _ticketCtrl,
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
                    } else {
                      item.fromTicket = val.trim();
                      item.toTicket = val.trim();
                    }
                    item.quantity = RawStockTextParserDialog.computeStrictQuantityFromRange(
                      fromTicket: item.fromTicket,
                      toTicket: item.toTicket,
                      series: item.series,
                    );
                    widget.onItemChanged();
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
            const SizedBox(width: 4),

            // 🔍 Voucher Status Badge
            SizedBox(
              width: 120,
              child: Center(child: widget.statusBadge),
            ),
            const SizedBox(width: 4),

            // Delete Action
            SizedBox(
              width: 36,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFF87171)),
                onPressed: widget.onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
