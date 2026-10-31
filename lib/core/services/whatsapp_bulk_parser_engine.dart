import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../features/shared/models/ticket_sale_model.dart';

/// Single parsed ticket item from bulk engine
class BulkParsedTicket {
  final String series;
  final String ticketNo;
  final int quantity;
  final double pricePerTicket;
  final String buyerName;
  final String shiftName;
  final DateTime ticketDate;
  final String rawOriginalLine;
  final int lineNumber;
  final bool isAutoCorrected;
  final String? autoCorrectReason;

  const BulkParsedTicket({
    required this.series,
    required this.ticketNo,
    this.quantity = 1,
    required this.pricePerTicket,
    required this.buyerName,
    required this.shiftName,
    required this.ticketDate,
    required this.rawOriginalLine,
    this.lineNumber = 0,
    this.isAutoCorrected = false,
    this.autoCorrectReason,
  });

  double get totalAmount => pricePerTicket * quantity;

  TicketSaleModel toTicketSaleModel({
    required String receiptPrefix,
    required int index,
    String? partyOverride,
  }) {
    final now = DateTime.now();
    final drawCode = shiftName.toLowerCase().contains('1')
        ? 'D-1PM'
        : shiftName.toLowerCase().contains('6')
            ? 'D-6PM'
            : 'D-8PM';

    final effectiveBuyer = (partyOverride != null && partyOverride.trim().isNotEmpty)
        ? partyOverride.trim()
        : (buyerName.isNotEmpty ? buyerName : 'Walk-in Customer');

    final fullTicketNumber = '$series $ticketNo';
    final uniqueId = 'tkt_wa_${ticketDate.millisecondsSinceEpoch}_${now.microsecondsSinceEpoch}_$index';
    final receiptNumber = '$receiptPrefix-${now.year}-${(index + 1).toString().padLeft(6, '0')}';

    return TicketSaleModel(
      id: uniqueId,
      receiptNumber: receiptNumber,
      buyerName: effectiveBuyer,
      buyerPhone: '0000000000',
      agentCode: 'AG-WA',
      agentName: effectiveBuyer,
      drawCode: drawCode,
      drawName: shiftName,
      ticketSeries: series,
      ticketNumber: fullTicketNumber,
      quantity: quantity,
      pricePerTicket: pricePerTicket,
      totalAmount: totalAmount,
      commissionAmount: 0.0,
      status: TicketStatus.sold,
      paymentMode: PaymentMode.cash,
      saleDate: ticketDate,
      drawDate: ticketDate,
    );
  }

  BulkParsedTicket copyWith({
    String? series,
    String? ticketNo,
    int? quantity,
    double? pricePerTicket,
    String? buyerName,
    String? shiftName,
    DateTime? ticketDate,
    String? rawOriginalLine,
    int? lineNumber,
    bool? isAutoCorrected,
    String? autoCorrectReason,
  }) {
    return BulkParsedTicket(
      series: series ?? this.series,
      ticketNo: ticketNo ?? this.ticketNo,
      quantity: quantity ?? this.quantity,
      pricePerTicket: pricePerTicket ?? this.pricePerTicket,
      buyerName: buyerName ?? this.buyerName,
      shiftName: shiftName ?? this.shiftName,
      ticketDate: ticketDate ?? this.ticketDate,
      rawOriginalLine: rawOriginalLine ?? this.rawOriginalLine,
      lineNumber: lineNumber ?? this.lineNumber,
      isAutoCorrected: isAutoCorrected ?? this.isAutoCorrected,
      autoCorrectReason: autoCorrectReason ?? this.autoCorrectReason,
    );
  }
}

/// Parameters sent to the isolate
class BulkParserParams {
  final String rawText;
  final String defaultShift;
  final String defaultSeller;
  final String fallbackSeries;
  final Map<String, double> seriesPriceMap;
  final DateTime targetDate;
  final bool enableAiAutoCorrect;
  final bool autoDetectShift;
  final bool autoDetectSeller;
  final bool autoDetectDate;

  BulkParserParams({
    required this.rawText,
    required this.defaultShift,
    required this.defaultSeller,
    required this.fallbackSeries,
    required this.seriesPriceMap,
    required this.targetDate,
    this.enableAiAutoCorrect = true,
    this.autoDetectShift = true,
    this.autoDetectSeller = true,
    this.autoDetectDate = true,
  });
}

/// Result returned from the isolate
class BulkParserResult {
  final List<BulkParsedTicket> tickets;
  final List<String> unparsedLines;
  final Map<String, int> sellerTicketCounts;
  final Map<String, double> sellerAmountTotals;
  final Map<String, int> shiftTicketCounts;
  final Map<String, int> dateTicketCounts;
  final int totalLinesRead;
  final int autoCorrectedCount;
  final int duplicatesFilteredCount;
  final Duration executionDuration;

  const BulkParserResult({
    required this.tickets,
    required this.unparsedLines,
    required this.sellerTicketCounts,
    required this.sellerAmountTotals,
    required this.shiftTicketCounts,
    required this.dateTicketCounts,
    required this.totalLinesRead,
    required this.autoCorrectedCount,
    required this.duplicatesFilteredCount,
    required this.executionDuration,
  });

  int get totalTickets => tickets.fold(0, (sum, t) => sum + t.quantity);
  double get totalAmount => tickets.fold(0.0, (sum, t) => sum + t.totalAmount);
}

DateTime? _parseFlexibleDate(String dateStr) {
  final clean = dateStr.trim().replaceAll(RegExp(r'[^\d/\.-]'), '');
  final parts = clean.split(RegExp(r'[/.-]'));
  if (parts.length >= 2) {
    int? day = int.tryParse(parts[0]);
    int? month = int.tryParse(parts[1]);
    int year = DateTime.now().year;

    if (parts.length >= 3) {
      int? rawY = int.tryParse(parts[2]);
      if (rawY != null) {
        year = rawY < 100 ? (2000 + rawY) : rawY;
        final currentYear = DateTime.now().year;
        if (year > currentYear) {
          year = currentYear;
        }
      }
    }

    if (day != null && month != null) {
      if (day > 12 && month <= 12) {
        // day/month format
      } else if (month > 12 && day <= 12) {
        final tmp = day;
        day = month;
        month = tmp;
      }
      try {
        return DateTime(year, month, day);
      } catch (_) {}
    }
  }
  return null;
}

String _formatDateKey(DateTime d) {
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ==========================================
// PRE-COMPILED TOP-LEVEL REGULAR EXPRESSIONS
// (Zero runtime compilation overhead in tight loops)
// ==========================================
final _regNonDigits = RegExp(r'\D');
final _regMetaNoise1 = RegExp(r'^(?:Messages and calls are end-to-end encrypted|This message was deleted|You deleted this message|<Media omitted>|You pinned a message|ye hisba hia|\*Learn more\*)', caseSensitive: false);
final _regMetaForwarded = RegExp(r'^(?:forwarded|forwarded message|fwd|forward|\*forwarded\*|\u203A\u203A\s*forwarded)\s*$', caseSensitive: false);
final _regMetaGreetings = RegExp(r'^\s*(?:hi+|hello+|hlo+|hey+|ok+|haan+|ha+|namaste+|thanks|thx|bye|bhai|sir|boss|yes|no|Ok\s*🆗)\b', caseSensitive: false);
final _regMetaEmail = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
final _regMetaDashes = RegExp(r'^[-=_*#.,;]{3,}$');
final _regMetaReligious = RegExp(r'^\s*(?:shiv|radhe|om|jai|.,,)\s*$', caseSensitive: false);

final _regWaHeader = RegExp(
  r'^(?:\[?(\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4}),?\s+[\d:.]+(?:\s*(?:[aApP][mM]|\u202F[aApP][mM]))?\]?\s*(?:-|\s*:)?\s*([^:\n]+?):\s*)(.*)$',
  caseSensitive: false,
);
final _regCleanSender = RegExp(r'[^\w\s\.\-]');

final _regTypoO1 = RegExp(r'\b[Oo](\d{4})(?=\D|\b)');
final _regTypoO2 = RegExp(r'(?<=\d)[Oo](?=\d)');
final _regTypoO3 = RegExp(r'(?<=\d{4})[Oo]\b');
final _regTypoI1 = RegExp(r'\b[lI](\d{4})(?=\D|\b)');
final _regTypoI2 = RegExp(r'(?<=\d)[lI](?=\d)');
final _regTypoI3 = RegExp(r'(?<=\d{4})[lI]\b');

final _regConversationalWords = RegExp(
  r'\b(?:bhai|bhaiya|sir|boss|payment|paisa|paise|rupaye|rupee|rupees|rs|inr|gpay|phonepe|paytm|online|cash|transfer|account|ac|balance|hisab|hesab|bhej|bhejo|bheja|bhejiye|bhejva|send|sent|sending|dekh|dekho|dekhiye|karo|karna|kare|karein|kar|check|screenshot|ss|photo|pic|image|call|baat|bolo|batao|bataiye|kal|aaj|aajka|parso|kitna|hua|nahi|hoga|raha|rahe|gaya|gaye|aaya|aaye|tha|the|thi|hai|hain|ho|hun|please|plz|urgent|theek|thik|namaste|ram|radhe|shyam|jai|mata|shree|hello|hlo|hey|good\s+morning|good\s+night|thanks|thank\s+you|dhanyawad|welcome|bye)\b',
  caseSensitive: false,
);

final _regEndMarker = RegExp(
  r'^(?:end(?:\s+(?:1|6|8)\s*pm)?|booking\s+(?:end|sampat|close|closed|stop|khatam|samapt)|stop|sampat|khatam|samapt|close|closed|---\s*end\s*---)\s*$',
  caseSensitive: false,
);

final _regMajorStartHeader = RegExp(
  r'(?:^start\b|booking\s+(?:ab\s+jayega|start|open)|(?:0?[168])\s*(?::00|\.00|[:.])?\s*(?:pm|qm|am|p)?\s+booking|\bbooking\s+(?:for\s+)?(?:0?[168])\s*(?:pm|qm|am|p)?|\.\.\.\s*pm[168]|\.\.\s*pm[168]|^dear\s+(?:1|6|8)\s*pm\s*$)',
  caseSensitive: false,
);

final _regHas5Digits = RegExp(r'\b\d{5}\b');
final _regAll5Digits = RegExp(r'\b\d{5}\b');

final _regShiftDear1 = RegExp(r'(?:\b(?:time\s*[:=]?\s*|dear\s*)?0?1\s*(?::00|\.00|[:.;])?\s*(?:pm|qm|am|p|pn|baje)\b|\bpm\s*0?1\b)', caseSensitive: false);
final _regShiftDear6 = RegExp(r'(?:\b(?:time\s*[:=]?\s*|dear\s*)?0?6\s*(?::00|\.00|[:.;])?\s*(?:pm|qm|am|p|pn|baje)\b|\bpm\s*0?6\b)', caseSensitive: false);
final _regShiftDear8 = RegExp(r'(?:\b(?:time\s*[:=]?\s*|dear\s*)?0?8\s*(?::00|\.00|[:.;])?\s*(?:pm|qm|am|p|pn|baje)\b|\bpm\s*0?8\b)', caseSensitive: false);

final _regDateShiftCombinedHeader = RegExp(
  r'^(\d{1,2})[=\/\.-](\d{1,2})[=\/\.-](200\d{2}|20\d{2}|\d{2})[=\s\/\.-]+(?:dear\s*)?0?([168])\s*(?::?00)?[\s.]*(?:pm|qm|am|p)?\s*$',
  caseSensitive: false,
);

final _regDatePartyShiftHeader = RegExp(
  r'^(\d{1,2}[\/\.-]\d{1,2}(?:[\/\.-](?:20\d{2}|\d{2}))?)[.\s:=/-]+([A-Za-z][A-Za-z0-9\s_]{0,20}?)[.\s:=/-]+(?:dear\s*)?([168])\s*(?::00|\.00|\.)?\s*(?:pm|qm|am|p)?\s*$',
  caseSensitive: false,
);

final _regBoundaryDate = RegExp(r'\b(\d{1,2}[\/\.-]\d{1,2}(?:[\/\.-]\d{2,4})?)\b');

final _regNamedSellerWithMeta = RegExp(
  r'^([A-Za-z][A-Za-z0-9\s_]{0,22})[.\s:=/-]+(?:(?:booking|bookin|bokg|bok|bkg|date|time|\d{1,2}[=.\/-]+\d{1,2}(?:[=.\/-]+(?:\d{4}|\d{2}))?|(?:1|6|8)\s*(?::00|\.00|\.)?[\s.]*(?:pm|qm|gm|p|baje|pn)?|\(?[168]:?pm\)?|[.\s:=/-]+)\s*)*$',
  caseSensitive: false,
);

final _regSimpleName = RegExp(
  r'^(Laddu|Ajmal|Irfan|Rustam(?:\s+g)?|Sanni\s+kumar|Vijay|Deepak|Shekhar|Anil\s+Ram|Suman|Mukesh|Wakil|Ck|Sk|P|Bipin|Ibran)\b\s*(?:booking|bookin)?\s*$',
  caseSensitive: false,
);

final _regStandaloneSeries = RegExp(
  r'^(?:(?:\(|\[)\s*([0-9]{1,4})\s*(?:\)|\])|[×xX]\s*([0-9]{1,4})|s\s*([0-9]{1,4})|([0-9]{1,4})\s*(?:c|s|sirij|series|\.s|-s)?)$',
  caseSensitive: false,
);

final _regStandaloneShift1 = RegExp(r'^(?:(?:time\s*[:=]?\s*|dear\s*)?0?1\s*(?::00|\.00|[:.])?\s*(?:pm|qm|am|p|pn|baje)|pm\s*0?1)\s*$', caseSensitive: false);
final _regStandaloneShift6 = RegExp(r'^(?:(?:time\s*[:=]?\s*|dear\s*)?0?6\s*(?::00|\.00|[:.])?\s*(?:pm|qm|am|p|pn|baje)|pm\s*0?6)\s*$', caseSensitive: false);
final _regStandaloneShift8 = RegExp(r'^(?:(?:time\s*[:=]?\s*|dear\s*)?0?8\s*(?::00|\.00|[:.])?\s*(?:pm|qm|am|p|pn|baje)|pm\s*0?8)\s*$', caseSensitive: false);

final _regDateOrNoiseLine = RegExp(
  r'^(?:date\s*[:=\/\.-]?\s*\d{1,2}[\/\.-]\d{1,2}|time\s*[:=\/\.-]?\s*[168]|[168]\s*(?:pm|am|qm|gm|p|baje)|(?:1|6|8)\s*:\s*00\s*(?:pm|am)?|\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4}|Updated\s*|\d{1,2}\/\d{1,2}\\\d{2})$',
  caseSensitive: false,
);

final _regExplicitSuffixSeries = RegExp(
  r'^(\d{5})\s*(?:[=:\/.\-~*#@+"]+|--+|\.\.+|\s*-\s*|\s+)?\s*(\d{1,3})\s*(?:c|s|sirij|series)\s*$',
  caseSensitive: false,
);

final _regComplexRange = RegExp(
  r'^(?:(?:(?:\(|\[)\s*(?:series\s*|sirij\s*|s\s*|c\s*)?(\d{1,4})\s*(?:\)|\])|(?:series\s*|sirij\s*|s\s*|c\s*)?(\d{1,4})\s*(?:[:=/.\-~*#@+=]+|\s+))\s*)?'
  r'(\d{5})\s*'
  r'(?:--+|\s+to\s+|-+|se|\/|_+|,+\s*|\.\.+)\s*'
  r'(\d{1,5})'
  r'(?:'
    r'(?:\s*(?:--|-|\/|=|,+|go|\s+|[*xXpP])\s*(\d{1,3}))?'
    r'(?:\s*(?:pcs?|go|g0|p|pis))?'
    r'(?:\s*[,:=/.\-~*#@+=\s]*\s*(?:(?:\(|\[)\s*(?:series\s*|sirij\s*|s\s*|c\s*)?(\d{1,4})\s*(?:\)|\])|(?:series\s*|sirij\s*|s\s*|c\s*)?(\d{1,4})\s*(?:[.\s]*(?:c|s|sirij|series)|go)?))?'
  r')?'
  r'\s*[,;. ]*$',
  caseSensitive: false,
);

final _regSpaceRange = RegExp(
  r'^(?:(?:(?:\(|\[)\s*(?:series\s*|sirij\s*|s\s*|c\s*)?(\d{1,4})\s*(?:\)|\])|(?:series\s*|sirij\s*|s\s*|c\s*)?(\d{1,4})\s*[:=/.\-~*#@+=]*)\s+)?'
  r'(\d{5})\s+(\d{1,3})'
  r'(?:\s+(?:(?:\(|\[)\s*(?:series\s*|sirij\s*|s\s*|c\s*)?(\d{1,4})\s*(?:\)|\])|(?:series\s*|sirij\s*|s\s*|c\s*)?(\d{1,4})\s*(?:c|s|sirij|series)?))?$',
  caseSensitive: false,
);

final _regSingleTicketEqualsQty = RegExp(
  r'^(?:(?:\(|\[)\s*(\d{1,4})\s*(?:\)|\])\.?|(\d{1,4})\s*[:\/-]?\s+)?(\d{5})\s*=\s*(\d{1,4})\s*$',
  caseSensitive: false,
);

final _regSuffixSeries = RegExp(
  r'^(\d{5})\s*(?:(?:\(|\[)\s*(?:series\s*|sirij\s*|s\s*|c\s*)?(\d{1,4})\s*(?:\)|\])|(?:[:=/.\-~*#@+xX÷"]+|--+|\.\.+|\s*-\s*|\s+)\s*(?:series\s*|sirij\s*|s\s*|c\s*)?(\d{1,3})\s*(?:[.\s]*(?:c|s|sirij|series))?)$',
  caseSensitive: false,
);

final _regPrefixSeries = RegExp(
  r'^(?:(?:1|6|8)\s*PM\s*)?(?:(?:\(|\[)\s*(\d{1,4})\s*(?:\)|\])\.?|(\d{1,4})\s*(?:c|s)?\s*[:=/.\-~*#@+"]+)\s*(\d{5})(?:\s*[*xX]\s*(\d+))?$',
  caseSensitive: false,
);

final _regInlinePrefix = RegExp(
  r'^(?:(?:\(|\[)\s*(\d{1,4})\s*(?:\)|\])|(\d{1,4})\s*(?:[:=/.\-~*#@+]|\s*|$))',
  caseSensitive: false,
);
final _regInlineSuffixClean = RegExp(
  r'^(?:(?:\(|\[)\s*(?:series\s*|sirij\s*|s\s*|c\s*)?(\d{1,4})\s*(?:\)|\])|(?:[:\/.\-~#@+,]+\s*|\s+)?(?:s\s*|c\s*)?(\d{1,3})\s*(?:c|s|sirij|series)?)$',
  caseSensitive: false,
);
final _regQtyMatch = RegExp(
  r'(?:[*xX]\s*(\d{1,4})|\bqty\s*[:=]?\s*(\d{1,4})|[=-]\s*(\d{1,4}))',
  caseSensitive: false,
);

class _PendingTicketItem {
  final String ticketNo;
  final int qty;
  final String seller;
  final String shift;
  final DateTime date;
  final String originalLine;
  final int lineIndex;
  final bool isCorrected;
  final String? reason;

  _PendingTicketItem({
    required this.ticketNo,
    required this.qty,
    required this.seller,
    required this.shift,
    required this.date,
    required this.originalLine,
    required this.lineIndex,
    this.isCorrected = false,
    this.reason,
  });
}

/// Standalone Background Worker function suitable for compute()
BulkParserResult parseWhatsAppTextIsolate(BulkParserParams params) {
  final stopwatch = Stopwatch()..start();
  final List<BulkParsedTicket> parsedTickets = [];
  final List<String> unparsedLines = [];
  final Map<String, int> sellerCounts = {};
  final Map<String, double> sellerAmounts = {};
  final Map<String, int> shiftCounts = {};
  final Map<String, int> dateCounts = {};
  final Set<String> seenTicketKeys = {};

  int autoCorrectedCount = 0;
  int dupesCount = 0;

  DateTime currentDate = params.targetDate;
  String currentShift = params.defaultShift.isNotEmpty ? params.defaultShift : 'Dear 1 PM';
  String currentSeller = params.defaultSeller.isNotEmpty ? params.defaultSeller : 'Mama2';
  String currentSeries = params.fallbackSeries.isNotEmpty ? params.fallbackSeries : '12';
  String? currentMessageSeries;
  final List<_PendingTicketItem> pendingMessageTickets = [];

  double getPrice(String series) {
    if (params.seriesPriceMap.containsKey(series)) {
      return params.seriesPriceMap[series]!;
    }
    double perUnit = 3.75;
    if (params.seriesPriceMap.containsKey('100') && (params.seriesPriceMap['100'] ?? 0) > 0) {
      perUnit = params.seriesPriceMap['100']! / 100.0;
    }
    final numVal = double.tryParse(series.replaceAll(_regNonDigits, '')) ?? 12.0;
    return numVal * perUnit;
  }

  String cleanSeries(String raw) {
    final digits = raw.replaceAll(_regNonDigits, '');
    if (digits.isEmpty) return currentSeries;
    final intVal = int.tryParse(digits);
    if (intVal != null) {
      return intVal.toString();
    }
    return digits.length <= 4 ? digits : digits.substring(0, math.min(digits.length, 4));
  }

  int currentLineIndex = 0;

  void addTicket({
    required String series,
    required String ticketNo,
    required int qty,
    required String seller,
    required String shift,
    required DateTime date,
    required String originalLine,
    bool isCorrected = false,
    String? reason,
  }) {
    final cleanTkt = ticketNo.padLeft(5, '0');
    var sClean = cleanSeries(series);
    if (sClean == '1') {
      final msgSeries = currentMessageSeries;
      sClean = (msgSeries != null && msgSeries.isNotEmpty && msgSeries != '1')
          ? msgSeries
          : (currentSeries != '1' ? currentSeries : params.fallbackSeries);
    }
    final price = getPrice(sClean);
    final dateKey = _formatDateKey(date);
    final key = '$dateKey-$shift-$sClean-$cleanTkt-$seller';

    if (seenTicketKeys.contains(key)) {
      dupesCount++;
      // Allow duplicates: accept multiple bookings of same series & same ticket
    } else {
      seenTicketKeys.add(key);
    }

    parsedTickets.add(BulkParsedTicket(
      series: sClean,
      ticketNo: cleanTkt,
      quantity: qty > 0 ? qty : 1,
      pricePerTicket: price,
      buyerName: seller,
      shiftName: shift,
      ticketDate: date,
      rawOriginalLine: originalLine,
      lineNumber: currentLineIndex + 1,
      isAutoCorrected: isCorrected,
      autoCorrectReason: reason,
    ));

    sellerCounts[seller] = (sellerCounts[seller] ?? 0) + (qty > 0 ? qty : 1);
    sellerAmounts[seller] = (sellerAmounts[seller] ?? 0.0) + (price * (qty > 0 ? qty : 1));
    shiftCounts[shift] = (shiftCounts[shift] ?? 0) + (qty > 0 ? qty : 1);
    dateCounts[dateKey] = (dateCounts[dateKey] ?? 0) + (qty > 0 ? qty : 1);
    if (isCorrected) autoCorrectedCount++;
  }

  void flushPendingTickets({String? overrideSeries}) {
    if (pendingMessageTickets.isEmpty) return;
    final s = overrideSeries ?? currentMessageSeries ?? params.fallbackSeries;
    for (final p in pendingMessageTickets) {
      final oldLineIdx = currentLineIndex;
      currentLineIndex = p.lineIndex;
      addTicket(
        series: s,
        ticketNo: p.ticketNo,
        qty: p.qty,
        seller: p.seller,
        shift: p.shift,
        date: p.date,
        originalLine: p.originalLine,
        isCorrected: p.isCorrected,
        reason: p.reason,
      );
      currentLineIndex = oldLineIdx;
    }
    pendingMessageTickets.clear();
  }

  List<String>? expandRange(String startTkt, String endPart) {
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
    } else if (endPart.length == 4) {
      final prefix = startTkt.substring(0, 1);
      final last4 = int.tryParse(endPart);
      if (last4 == null) return null;
      final candidate = int.tryParse('$prefix$endPart');
      if (candidate != null && candidate >= startFull && (candidate - startFull) <= 300) {
        endFull = candidate;
      } else {
        endFull = int.tryParse(endPart.padLeft(5, '0'));
      }
    } else if (endPart.length == 5) {
      endFull = int.tryParse(endPart);
    }

    if (endFull == null || endFull < startFull || (endFull - startFull) > 300) {
      return null;
    }

    final List<String> result = [];
    for (int i = startFull; i <= endFull; i++) {
      result.add(i.toString().padLeft(5, '0'));
    }
    return result;
  }

  bool isSectionLocked = false;

  // Pre-process and split into clean lines (1:1 matching UI editor lines)
  final cleanText = params.rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = cleanText.split('\n');
  final totalLines = lines.length;

  // Pre-scan primary date and shift from text if auto-detection is enabled
  if (params.autoDetectDate) {
    for (final rawLine in lines) {
      final t = rawLine.trim();
      if (t.isEmpty) continue;
      String content = t;
      final wMatch = _regWaHeader.firstMatch(t);
      if (wMatch != null) {
        content = (wMatch.group(3) ?? '').trim();
      }

      // 1. Check if message content has an explicit draw date marker with shift/boundary
      final bMatch = _regBoundaryDate.firstMatch(content);
      if (bMatch != null && (_regMajorStartHeader.hasMatch(content) || RegExp(r'(?:pm|qm|am|baje|dear)', caseSensitive: false).hasMatch(content))) {
        final parsed = _parseFlexibleDate(bMatch.group(1)!);
        if (parsed != null) {
          currentDate = parsed;
          break;
        }
      }
      final dsMatch = _regDateShiftCombinedHeader.firstMatch(content);
      if (dsMatch != null) {
        final dStr = '${dsMatch.group(1)}/${dsMatch.group(2)}/${dsMatch.group(3)}';
        final parsed = _parseFlexibleDate(dStr);
        if (parsed != null) {
          currentDate = parsed;
          break;
        }
      }
      final dpsMatch = _regDatePartyShiftHeader.firstMatch(content);
      if (dpsMatch != null) {
        final parsed = _parseFlexibleDate(dpsMatch.group(1)!);
        if (parsed != null) {
          currentDate = parsed;
          break;
        }
      }

      // 2. Fallback to WhatsApp timestamp date if no explicit draw date was found in content
      if (wMatch != null && wMatch.group(1) != null) {
        final parsed = _parseFlexibleDate(wMatch.group(1)!);
        if (parsed != null) {
          currentDate = parsed;
          break;
        }
      }
    }
  }

  if (params.autoDetectShift) {
    for (final rawLine in lines) {
      final t = rawLine.trim();
      if (t.isEmpty) continue;
      if (_regHas5Digits.hasMatch(t)) break; // Stop at first ticket line
      if (_regShiftDear8.hasMatch(t) || _regStandaloneShift8.hasMatch(t)) {
        currentShift = 'Dear 8 PM';
        break;
      } else if (_regShiftDear6.hasMatch(t) || _regStandaloneShift6.hasMatch(t)) {
        currentShift = 'Dear 6 PM';
        break;
      } else if (_regShiftDear1.hasMatch(t) || _regStandaloneShift1.hasMatch(t)) {
        currentShift = 'Dear 1 PM';
        break;
      }
    }
  }

  for (int lineIdx = 0; lineIdx < totalLines; lineIdx++) {
    currentLineIndex = lineIdx;
    final originalLine = lines[lineIdx];
    var trimmed = originalLine.trim();
    if (trimmed.isEmpty) continue;

    // 0. Ignore WhatsApp metadata & noise
    if (_regMetaNoise1.hasMatch(trimmed)) continue;
    if (_regMetaForwarded.hasMatch(trimmed)) continue;
    if (_regMetaGreetings.hasMatch(trimmed)) {
      unparsedLines.add(originalLine);
      continue;
    }
    if (_regMetaEmail.hasMatch(trimmed)) continue;
    if (_regMetaDashes.hasMatch(trimmed)) continue;
    if (_regMetaReligious.hasMatch(trimmed)) continue;

    // 1. WhatsApp chat timestamp and sender header parsing
    String contentLine = trimmed;
    final waHeaderMatch = _regWaHeader.firstMatch(contentLine);

    if (waHeaderMatch != null) {
      flushPendingTickets();
      currentMessageSeries = null;
      final headerDateStr = waHeaderMatch.group(1);
      final sender = (waHeaderMatch.group(2) ?? '').trim();

      // Only adopt header date if section is not locked
      if (!isSectionLocked && params.autoDetectDate && headerDateStr != null && parsedTickets.isEmpty) {
        final parsedDate = _parseFlexibleDate(headerDateStr);
        if (parsedDate != null) {
          currentDate = parsedDate;
        }
      }

      if (params.autoDetectSeller && sender.isNotEmpty) {
        final cleanSender = sender.replaceAll(_regCleanSender, '').trim();
        if (cleanSender.isNotEmpty && cleanSender.length <= 30 && !cleanSender.contains('deleted')) {
          currentSeller = cleanSender;
        }
      }
      contentLine = (waHeaderMatch.group(3) ?? '').trim();
    }

    if (contentLine.isEmpty) continue;

    if (contentLine.endsWith('<This message was edited>')) {
      contentLine = contentLine.replaceAll('<This message was edited>', '').trim();
    }
    if (contentLine.isEmpty) continue;

    // AI Typo & Normalization (Run early so 5-digit detection is accurate!)
    String lineForParsing = contentLine.replaceAll(RegExp(r'^[\s,;]+'), '');
    if (lineForParsing.isEmpty) continue;
    bool lineWasCorrected = false;
    String? correctionReason;

    if (params.enableAiAutoCorrect) {
      lineForParsing = lineForParsing
          .replaceAllMapped(_regTypoO1, (m) => '0${m.group(1)}')
          .replaceAllMapped(_regTypoO2, (_) => '0')
          .replaceAllMapped(_regTypoO3, (_) => '0')
          .replaceAllMapped(_regTypoI1, (m) => '1${m.group(1)}')
          .replaceAllMapped(_regTypoI2, (_) => '1')
          .replaceAllMapped(_regTypoI3, (_) => '1');
      if (lineForParsing != contentLine) {
        lineWasCorrected = true;
        correctionReason = 'Auto-corrected typo';
      }
    }

    // 2. SECTION END MARKER (Unlocks the section)
    final isEndMarker = _regEndMarker.hasMatch(lineForParsing);

    if (isEndMarker) {
      isSectionLocked = false;
      continue;
    }

    // 2.1 COMBINED DATE & SHIFT (e.g. 12=6=2026=1pm, 8=6=26=1pm, 12/06/26 1pm, 8/6/26.1.pm)
    final dateShiftMatch = _regDateShiftCombinedHeader.firstMatch(lineForParsing);
    if (dateShiftMatch != null) {
      if (!isSectionLocked) {
        if (params.autoDetectDate) {
          final d = int.tryParse(dateShiftMatch.group(1)!);
          final m = int.tryParse(dateShiftMatch.group(2)!);
          var y = int.tryParse(dateShiftMatch.group(3)!);
          if (y != null && y < 100) y = 2000 + y;
          if (d != null && m != null && y != null) {
            try {
              currentDate = DateTime(y, m, d);
            } catch (_) {}
          }
        }
        if (params.autoDetectShift) {
          final sDigit = dateShiftMatch.group(4);
          if (sDigit == '1') {
            currentShift = 'Dear 1 PM';
          } else if (sDigit == '6') {
            currentShift = 'Dear 6 PM';
          } else if (sDigit == '8') {
            currentShift = 'Dear 8 PM';
          }
        }
      }
      continue; // Skip boundary line from ticket generation
    }

    // 2.2 DATE + PARTY + SHIFT HEADER (e.g. 12/6/26. Sk. 1:00 pm, 8/6/26 Sk 6pm)
    // When section is locked (Start...End), date, shift, and party are strictly locked.
    final datePartyShiftMatch = _regDatePartyShiftHeader.firstMatch(lineForParsing);
    if (datePartyShiftMatch != null && !_regHas5Digits.hasMatch(lineForParsing)) {
      if (!isSectionLocked) {
        if (params.autoDetectDate) {
          final parsed = _parseFlexibleDate(datePartyShiftMatch.group(1)!);
          if (parsed != null) {
            currentDate = parsed;
          }
        }
        if (params.autoDetectShift) {
          final sDigit = datePartyShiftMatch.group(3);
          if (sDigit == '1') {
            currentShift = 'Dear 1 PM';
          } else if (sDigit == '6') {
            currentShift = 'Dear 6 PM';
          } else if (sDigit == '8') {
            currentShift = 'Dear 8 PM';
          }
        }
        isSectionLocked = true;
      }
      continue; // Silently skip line: not a ticket, not an issue!
    }

    // 3. MAJOR SECTION START / BOUNDARY MARKER (Locks Shift & Date for entire block!)
    final isMajorStartHeader = _regMajorStartHeader.hasMatch(lineForParsing);

    if (isMajorStartHeader && !_regHas5Digits.hasMatch(lineForParsing)) {
      if (params.autoDetectShift) {
        if (_regShiftDear1.hasMatch(lineForParsing)) {
          currentShift = 'Dear 1 PM';
        } else if (_regShiftDear6.hasMatch(lineForParsing)) {
          currentShift = 'Dear 6 PM';
        } else if (_regShiftDear8.hasMatch(lineForParsing)) {
          currentShift = 'Dear 8 PM';
        }
      }
      if (params.autoDetectDate) {
        final dateInBoundary = _regBoundaryDate.firstMatch(lineForParsing);
        if (dateInBoundary != null) {
          final parsed = _parseFlexibleDate(dateInBoundary.group(1)!);
          if (parsed != null) {
            currentDate = parsed;
          }
        }
      }
      isSectionLocked = true; // Lock section shift and date!
      continue; // Skip boundary line from ticket generation
    }

    // Conversational sentence / text words check:
    // If line contains regular human conversational words or sentences, mark it invalid & add to unparsedLines
    if (_regConversationalWords.hasMatch(lineForParsing)) {
      unparsedLines.add(originalLine);
      continue;
    }

    // Ticket line words check:
    // User Rule: "12 series sirf usi ticket ko assign hoga jis message me 5 digit ke alawa kuch nahi hoga,
    // ticket number ke aage koi extra text ya words hoga agar wo parsed nahi ho raha hai to usko under review me dalega aur purana wala ko disturb nahi karna"
    if (_regHas5Digits.hasMatch(lineForParsing)) {
      final validTicketWords = RegExp(
        r'^(?:pm|am|qm|gm|pcs|pis|go|to|se|sirij|series|sem|c|s|qty|dear|time|date|start|end|booking|'
        r'laddu|ajmal|irfan|rustam|sanni|kumar|vijay|deepak|shekhar|anil|ram|suman|mukesh|wakil|ck|sk|p|bipin|ibran)$',
        caseSensitive: false,
      );
      final unparsedWords = lineForParsing.split(RegExp(r'[^a-zA-Z]+')).where((w) {
        if (w.length < 2) return false;
        final lw = w.toLowerCase();
        if (validTicketWords.hasMatch(lw)) return false;
        if (currentSeller.toLowerCase().contains(lw)) return false;
        return true;
      }).toList();

      if (unparsedWords.isNotEmpty) {
        unparsedLines.add(originalLine);
        continue;
      }
    } else {
      final nonLotteryWords = lineForParsing.split(RegExp(r'[^a-zA-Z]+')).where((w) {
        if (w.length < 2) return false;
        final lw = w.toLowerCase();
        return !RegExp(r'^(?:pm|am|qm|gm|pcs|pis|go|to|se|sirij|series|c|s)$').hasMatch(lw);
      }).toList();
      if (nonLotteryWords.length >= 3) {
        unparsedLines.add(originalLine);
        continue;
      }
    }

    // 4. Non-ticket lines check (Seller announcements, standalone series, date/time notes)
    if (!_regHas5Digits.hasMatch(lineForParsing)) {
      // 4.1 Standalone Series line
      final standaloneSeriesMatch = _regStandaloneSeries.firstMatch(lineForParsing);
      if (standaloneSeriesMatch != null) {
        final sDigits = standaloneSeriesMatch.group(1) ??
            standaloneSeriesMatch.group(2) ??
            standaloneSeriesMatch.group(3) ??
            standaloneSeriesMatch.group(4);
        if (sDigits != null && sDigits.isNotEmpty && sDigits.length <= 4) {
          final sVal = int.tryParse(sDigits);
          if (sVal != null && sVal <= 200) {
            currentMessageSeries = sDigits;
            currentSeries = sDigits;
            flushPendingTickets(overrideSeries: sDigits);
            continue;
          }
        }
      }

      // 4.2 Named Seller Headers (e.g. "Vijay.. 8..6..2026..1pm", "Sanni kumar 8/6/26.1.pm", "Sk 1pm")
      final namedSellerWithMeta = _regNamedSellerWithMeta.firstMatch(lineForParsing);
      if (namedSellerWithMeta != null) {
        continue; // Never unparsed!
      }

      // 4.3 Simple Named Seller (e.g. "Laddu", "Vijay", "Sk", "Mama2")
      final simpleNameMatch = _regSimpleName.firstMatch(lineForParsing);
      if (simpleNameMatch != null) {
        continue; // Never unparsed!
      }

      // 4.4 Standalone shift / date or noise line
      if (!isSectionLocked && params.autoDetectShift) {
        if (_regStandaloneShift8.hasMatch(lineForParsing) || _regShiftDear8.hasMatch(lineForParsing)) {
          currentShift = 'Dear 8 PM';
          continue;
        } else if (_regStandaloneShift6.hasMatch(lineForParsing) || _regShiftDear6.hasMatch(lineForParsing)) {
          currentShift = 'Dear 6 PM';
          continue;
        } else if (_regStandaloneShift1.hasMatch(lineForParsing) || _regShiftDear1.hasMatch(lineForParsing)) {
          currentShift = 'Dear 1 PM';
          continue;
        }
      }

      if (_regStandaloneShift1.hasMatch(lineForParsing) ||
          _regStandaloneShift6.hasMatch(lineForParsing) ||
          _regStandaloneShift8.hasMatch(lineForParsing) ||
          _regDateOrNoiseLine.hasMatch(lineForParsing)) {
        continue;
      }

    }

    // 6. Extraction of Ticket Items

    // Case 0: Explicit Suffix Series Pattern (e.g. 23640..12c, 11395..12c, 57344...12c)
    // Must run BEFORE range check so single tickets ending in 'c'/'s' are never split as ranges!
    final explicitSuffixMatch = _regExplicitSuffixSeries.firstMatch(lineForParsing);
    if (explicitSuffixMatch != null) {
      final tNo = explicitSuffixMatch.group(1)!;
      final sPart = explicitSuffixMatch.group(2)!;
      final sNum = int.tryParse(sPart);
      if (sNum != null && sNum <= 200) {
        if (currentMessageSeries == null) {
          currentMessageSeries = sPart;
          currentSeries = sPart;
          flushPendingTickets(overrideSeries: sPart);
        }
        addTicket(
          series: sPart,
          ticketNo: tNo,
          qty: 1,
          seller: currentSeller,
          shift: currentShift,
          date: currentDate,
          originalLine: originalLine,
          isCorrected: lineWasCorrected,
          reason: correctionReason,
        );
        continue;
      }
    }

    // Case 0.5: Single Ticket with '=' (e.g. 97986 = 6, 21783 = 6, 40778 = 1, (24) 40778 = 1, 24 40778 = 1)
    // User Rule:
    // - If no series is defined in this message (currentMessageSeries == null) and number > 1 (e.g. 97986 = 6):
    //   The number is the SERIES (Series 6), and quantity is 1!
    // - If series was already defined in message header (e.g. (24)), or number is 1 (e.g. 40778 = 1):
    //   The series is the defined series (24), and = 1 is quantity 1!
    final singleEqualsMatch = _regSingleTicketEqualsQty.firstMatch(lineForParsing);
    if (singleEqualsMatch != null) {
      final prefixSeries = singleEqualsMatch.group(1) ?? singleEqualsMatch.group(2);
      final tNo = singleEqualsMatch.group(3)!;
      final qStr = singleEqualsMatch.group(4)!;
      final numVal = int.tryParse(qStr) ?? 1;

      String effectiveSeries;
      int qty = 1;

      if (prefixSeries != null && prefixSeries.trim().isNotEmpty) {
        // Line has explicit prefix series: e.g. 24 40778 = 1 or (24) 40778 = 1
        effectiveSeries = cleanSeries(prefixSeries.trim());
        qty = 1;
        currentMessageSeries = effectiveSeries;
        currentSeries = effectiveSeries;
      } else if (numVal > 1 && numVal <= 200) {
        // "38453=24", "55257=40", "64350=60", "97986=6", "21783=6":
        // '= 24', '= 40', '= 60', '= 6' IS THE SERIES for this ticket!
        // Ticket quantity is ALWAYS 1!
        effectiveSeries = cleanSeries(qStr);
        qty = 1;
        currentMessageSeries = effectiveSeries;
        currentSeries = effectiveSeries;
        flushPendingTickets(overrideSeries: effectiveSeries);
      } else {
        // numVal is 1 (e.g. 40778 = 1 under (24)):
        // Ticket quantity is 1! Series is the message series (e.g. 24) or fallback!
        effectiveSeries = currentMessageSeries ?? currentSeries;
        qty = 1;
      }

      addTicket(
        series: effectiveSeries,
        ticketNo: tNo,
        qty: qty,
        seller: currentSeller,
        shift: currentShift,
        date: currentDate,
        originalLine: originalLine,
        isCorrected: lineWasCorrected,
        reason: correctionReason,
      );
      continue;
    }

    // Case A: Complex Range Line (or space-separated range line)
    String normalizedForRange = lineForParsing
        .replaceAll(RegExp(r',+'), ',')
        .replaceAll(RegExp(r',\s*go', caseSensitive: false), ' go');
    while (normalizedForRange.endsWith(',')) {
      normalizedForRange = normalizedForRange.substring(0, normalizedForRange.length - 1).trim();
    }

    final complexRangeMatch = _regComplexRange.firstMatch(normalizedForRange);
    final spaceRangeMatch = (complexRangeMatch == null) ? _regSpaceRange.firstMatch(lineForParsing) : null;

    if (complexRangeMatch != null || spaceRangeMatch != null) {
      final prefixSeries = complexRangeMatch != null
          ? (complexRangeMatch.group(1) ?? complexRangeMatch.group(2))
          : (spaceRangeMatch?.group(1) ?? spaceRangeMatch?.group(2));
      final startTkt = complexRangeMatch != null
          ? complexRangeMatch.group(3)!
          : spaceRangeMatch!.group(3)!;
      final endPart = complexRangeMatch != null
          ? complexRangeMatch.group(4)!
          : spaceRangeMatch!.group(4)!;
      final rawInter = complexRangeMatch?.group(5);
      final rawSuffix = complexRangeMatch != null
          ? (complexRangeMatch.group(6) ?? complexRangeMatch.group(7))
          : (spaceRangeMatch?.group(5) ?? spaceRangeMatch?.group(6));

      // Dynamic series support: any positive integer up to 500 can be a series ("series kuch bhi aa sakta hai")
      bool isDynamicSeriesNumber(String s) {
        final digits = s.replaceAll(_regNonDigits, '');
        if (digits.isEmpty) return false;
        final val = int.tryParse(digits);
        return val != null && val > 0 && val <= 500;
      }

      String? suffixSeries;

      if (prefixSeries != null && prefixSeries.isNotEmpty) {
        // User Rule: "kisi me pehle series uske baad range aur last me quantity define ho,
        // usko last wale ko jo quantity usko ignore, jo actual [range tickets] hoga wahi lena hai."
        // E.g.: "5 = 83953-56 = 3" -> Series is 5, range is 83953-56 (4 actual tickets: 83953, 83954, 83955, 83956).
        // The trailing "= 3" is completely ignored. Each ticket has qty = 1.
        suffixSeries = null;
      } else if (rawSuffix != null && rawSuffix.isNotEmpty) {
        suffixSeries = rawSuffix;
      } else if (rawInter != null && rawInter.isNotEmpty) {
        final expandedCheck = expandRange(startTkt, endPart);
        final rangeCount = expandedCheck?.length;
        final rawVal = int.tryParse(rawInter);

        // Check if rawVal is redundant ticket count of the range:
        // E.g. 61405-09-5 (5 tickets), 76480-89-10 (10 tickets), 83953-56 = 3 (end - start = 3 or count)
        bool isRangeCount = false;
        if (rawVal != null && rangeCount != null) {
          if (rawVal == rangeCount) {
            isRangeCount = true;
          } else {
            final sNum = int.tryParse(startTkt.length >= endPart.length ? startTkt.substring(startTkt.length - endPart.length) : startTkt);
            final eNum = int.tryParse(endPart);
            if (sNum != null && eNum != null && rawVal == (eNum - sNum)) {
              isRangeCount = true;
            }
          }
        }

        if (isRangeCount) {
          // Trailing number is redundant count of tickets in the range!
          suffixSeries = null;
        } else if (rawVal != null && rawVal > 0 && rawVal <= 500) {
          // Trailing number on a range with no prefix series (e.g. 76480-89 12, 76480-89 = 18, 74370-79 6, 76480-89 35)
          // is the DYNAMIC suffix series!
          suffixSeries = rawInter;
        } else {
          suffixSeries = null;
        }
      }

      final hasExplicitRangeWord = lineForParsing.contains('..') ||
          lineForParsing.contains('--') ||
          lineForParsing.contains('__') ||
          RegExp(r'\b(?:to|se)\b', caseSensitive: false).hasMatch(lineForParsing);
      final hasPrefixSeries = prefixSeries != null && prefixSeries.isNotEmpty;
      final hasSuffixSeries = suffixSeries != null && suffixSeries.isNotEmpty;
      final isFull5DigitRange = endPart.length == 5;

      final rangeExpands = expandRange(startTkt, endPart) != null;
      final hasTrailingModifier = rawInter != null && rawInter.isNotEmpty;

      // 1. When endPart has >= 3 digits (e.g. 71450-459, 71450-1459, 71450___459),
      //    it is ALWAYS a range (lottery series is never 3 digits like 459).
      // 2. When endPart has 2 digits and can physically expand forward (endFull >= startFull),
      //    it is a range if series is defined, explicit range delimiters exist, or trailing quantity/modifier exists (e.g. 83953-56 = 3).
      // 3. If expandRange fails (e.g. 59375-18 where 18 < 75), it is NEVER a range; it is ticket-suffix series!
      final isMultiDigitNonSeriesEnd = endPart.length >= 3 ||
          (endPart.length == 2 && rangeExpands &&
              (hasPrefixSeries || hasSuffixSeries || hasExplicitRangeWord || currentMessageSeries != null || hasTrailingModifier));

      // User Rule: "range wale har message me pehle series define hoga"
      // A range is ONLY valid if a series is already defined beforehand in this message (currentMessageSeries),
      // or explicitly specified on the line as a prefix (e.g. 12= 10251-60) or suffix (e.g. 10251-60 = 12, 76480-89 12).
      // If no series is defined in this message yet, lines like "10251 -60" CANNOT be ranges; they define the series.
      final hasDefinedSeriesForRange = hasPrefixSeries ||
          hasSuffixSeries ||
          (currentMessageSeries != null && currentMessageSeries.isNotEmpty) ||
          hasExplicitRangeWord ||
          isFull5DigitRange ||
          isMultiDigitNonSeriesEnd;

      final isValidRange = hasDefinedSeriesForRange &&
          (hasPrefixSeries ||
              hasSuffixSeries ||
              hasExplicitRangeWord ||
              isFull5DigitRange ||
              isMultiDigitNonSeriesEnd);

      if (isValidRange) {
        String series = (currentMessageSeries != null && currentMessageSeries.isNotEmpty)
            ? cleanSeries(currentMessageSeries)
            : params.fallbackSeries;
        if (prefixSeries != null && prefixSeries.isNotEmpty && int.tryParse(prefixSeries)! <= 200) {
          series = cleanSeries(prefixSeries);
        } else if (suffixSeries != null && suffixSeries.isNotEmpty && int.tryParse(suffixSeries)! <= 200) {
          series = cleanSeries(suffixSeries);
        }

        // Line-level prefix or suffix series belongs strictly to this range; do not pollute subsequent lines!
        if (!hasPrefixSeries && !hasSuffixSeries) {
          currentMessageSeries ??= series;
          currentSeries = series;
          flushPendingTickets(overrideSeries: series);
        }

        const int rangeQty = 1;

        final expanded = expandRange(startTkt, endPart);
        if (expanded != null && expanded.isNotEmpty) {
          for (final tNo in expanded) {
            addTicket(
              series: series,
              ticketNo: tNo,
              qty: rangeQty,
              seller: currentSeller,
              shift: currentShift,
              date: currentDate,
              originalLine: originalLine,
              isCorrected: lineWasCorrected,
              reason: correctionReason,
            );
          }
          continue;
        }
      }
    }

    // Case B: Suffix Series Pattern
    final suffixSeriesMatch = _regSuffixSeries.firstMatch(lineForParsing);

    if (suffixSeriesMatch != null) {
      final tNo = suffixSeriesMatch.group(1)!;
      final bracketPart = suffixSeriesMatch.group(2);
      final plainPart = suffixSeriesMatch.group(3);
      final sPart = bracketPart ?? plainPart!;
      final sNum = int.tryParse(sPart);
      if (sNum != null && sNum <= 200) {
        String effectiveS;
        int qty = 1;

        final hasExplicitSeriesMarker = bracketPart != null ||
            lineForParsing.contains('*') ||
            lineForParsing.contains('x') ||
            lineForParsing.contains('X') ||
            lineForParsing.contains('=') ||
            lineForParsing.contains('÷') ||
            lineForParsing.toLowerCase().contains('c') ||
            lineForParsing.toLowerCase().contains('s') ||
            lineForParsing.toLowerCase().contains('sirij') ||
            lineForParsing.toLowerCase().contains('series');

        final msgSeries = currentMessageSeries;
        if (sNum == 1) {
          // "41458-1", "41458=1", "41458 1":
          // User Rule: Suffix 1 is ALWAYS quantity 1, NEVER Series 1!
          // Series is the message series (e.g. 12) or active series!
          effectiveS = (msgSeries != null && msgSeries.isNotEmpty)
              ? msgSeries
              : currentSeries;
          qty = 1;
        } else {
          // Dynamic Series: Any suffix number > 1 (e.g. 59375-18, 88454-24, 52373-12, 97986=6, 23693(18), 41451*5, 71987÷12)
          // defines the DYNAMIC SERIES for that ticket! Quantity is ALWAYS 1!
          effectiveS = sPart;
          qty = 1;
          currentSeries = sPart;
          flushPendingTickets(overrideSeries: sPart);
        }

        addTicket(
          series: effectiveS,
          ticketNo: tNo,
          qty: qty,
          seller: currentSeller,
          shift: currentShift,
          date: currentDate,
          originalLine: originalLine,
          isCorrected: lineWasCorrected,
          reason: correctionReason,
        );
        continue;
      }
    }

    // Case C: Prefix Series Pattern
    final prefixSeriesMatch = _regPrefixSeries.firstMatch(lineForParsing);

    if (prefixSeriesMatch != null) {
      final sPart = prefixSeriesMatch.group(1) ?? prefixSeriesMatch.group(2)!;
      final tNo = prefixSeriesMatch.group(3)!;
      final qtyStr = prefixSeriesMatch.group(4);
      final sNum = int.tryParse(sPart);
      if (sNum != null && sNum <= 200) {
        if (currentMessageSeries == null) {
          currentMessageSeries = sPart;
          currentSeries = sPart;
          flushPendingTickets(overrideSeries: sPart);
        }
        const int qty = 1;
        addTicket(
          series: sPart,
          ticketNo: tNo,
          qty: qty,
          seller: currentSeller,
          shift: currentShift,
          date: currentDate,
          originalLine: originalLine,
          isCorrected: lineWasCorrected,
          reason: correctionReason,
        );
        continue;
      }
    }

    // Case D: Multiple 5-digit tickets on same line (or single 5-digit ticket)
    final all5Digits = _regAll5Digits.allMatches(lineForParsing).toList();
    if (all5Digits.isNotEmpty) {
      final List<String> explicitLineSeriesList = [];

      // 1. Prefix series: MUST appear strictly before the first 5-digit ticket on the line
      final firstTktMatch = all5Digits.first;
      final textBeforeFirstTkt = lineForParsing.substring(0, firstTktMatch.start).trim();
      if (textBeforeFirstTkt.isNotEmpty) {
        // Check for series range like 12-14 or 12 to 14
        final rangeMatch = RegExp(r'^(?:s\s*|c\s*)?(\d{1,3})\s*(?:--|-|\s+to\s+)\s*(\d{1,3})\s*(?:c|s|sirij|series)?\b', caseSensitive: false).firstMatch(textBeforeFirstTkt);
        if (rangeMatch != null) {
          final startS = int.tryParse(rangeMatch.group(1)!);
          final endS = int.tryParse(rangeMatch.group(2)!);
          if (startS != null && endS != null && startS > 0 && endS > 0 && startS <= 200 && endS <= 200 && startS <= endS && (endS - startS) <= 50) {
            for (int sVal = startS; sVal <= endS; sVal++) {
              explicitLineSeriesList.add(cleanSeries(sVal.toString()));
            }
          }
        }
        if (explicitLineSeriesList.isEmpty) {
          final sMatches = RegExp(r'(?:(?:\(|\[)\s*(\d{1,4})\s*(?:\)|\])|(?:s\s*|c\s*)?(\d{1,4})\s*(?:c|s|sirij|series)?\b)', caseSensitive: false).allMatches(textBeforeFirstTkt);
          for (final sm in sMatches) {
            final rawS = sm.group(1) ?? sm.group(2);
            if (rawS != null && rawS.isNotEmpty) {
              final val = int.tryParse(rawS);
              if (val != null && val > 0 && val <= 200) {
                final cleaned = cleanSeries(rawS);
                if (!explicitLineSeriesList.contains(cleaned)) {
                  explicitLineSeriesList.add(cleaned);
                }
              }
            }
          }
        }
      }

      // 2. Suffix series: MUST appear strictly after the last 5-digit ticket on the line
      final lastTktMatch = all5Digits.last;
      final textAfterLastTkt = lineForParsing.substring(lastTktMatch.end).trim();
      if (textAfterLastTkt.isNotEmpty && explicitLineSeriesList.isEmpty) {
        final sMatches = RegExp(
          r'(?:(?:\(|\[)\s*(?:series\s*|sirij\s*|s\s*|c\s*)?(\d{1,4})\s*(?:\)|\])|(?:s\s*|c\s*)?(\d{1,4})\s*(?:c|s|sirij|series)?\b)',
          caseSensitive: false,
        ).allMatches(textAfterLastTkt);
        for (final sm in sMatches) {
          final rawS = sm.group(1) ?? sm.group(2);
          if (rawS != null && rawS.isNotEmpty) {
            final val = int.tryParse(rawS);
            if (val != null && val > 0 && val <= 500 && val != 1) {
              final cleaned = cleanSeries(rawS);
              if (!explicitLineSeriesList.contains(cleaned)) {
                explicitLineSeriesList.add(cleaned);
              }
            }
          }
        }
      }

      const int lineQty = 1;

      // Validate that the line doesn't contain unrecognized leftover garbage/noise
      // User rule: "TICKE TNO KE AKE KUCH EXTRA JYDA HOGA USKO REW SEION ME DALO"
      bool hasUnparsedTrailing = false;
      if (textAfterLastTkt.isNotEmpty) {
        String remainingAfter = textAfterLastTkt;
        remainingAfter = remainingAfter.replaceAll(RegExp(r'^(?:[:=/.\-~*#@+,]+|\s+)+'), '');
        remainingAfter = remainingAfter.replaceAll(RegExp(r'[*xXpP=-]\s*\d+\s*(?:pcs|pis|go|p)?', caseSensitive: false), '');
        // Strip bracket series like (18) or [18]
        remainingAfter = remainingAfter.replaceAll(RegExp(r'(?:\(|\[)\s*(?:s\s*|c\s*|series\s*|sirij\s*)?\d{1,4}\s*(?:c|s|sirij|series)?\s*(?:\)|\])', caseSensitive: false), '');
        // Strip normal series
        remainingAfter = remainingAfter.replaceAll(RegExp(r'(?:s\s*|c\s*)?\b\d{1,3}\s*(?:c|s|sirij|series)?\b', caseSensitive: false), '');
        remainingAfter = remainingAfter.replaceAll(RegExp(r'[\s,.:;=/\-~*#@+"()\[\]]+'), '').trim();
        if (remainingAfter.isNotEmpty) {
          hasUnparsedTrailing = true;
        }
      }

      bool hasUnparsedLeading = false;
      if (textBeforeFirstTkt.isNotEmpty) {
        String remainingBefore = textBeforeFirstTkt;
        remainingBefore = remainingBefore.replaceAll(RegExp(r'(?:\(|\[)\s*(?:s\s*|c\s*)?\d{1,4}\s*(?:\)|\])', caseSensitive: false), '');
        remainingBefore = remainingBefore.replaceAll(RegExp(r'(?:s\s*|c\s*)?\b\d{1,4}\s*(?:c|s|sirij|series)?\b', caseSensitive: false), '');
        remainingBefore = remainingBefore.replaceAll(RegExp(r'[\s,.:;=/\-~*#@+"()\[\]]+'), '').trim();
        if (remainingBefore.isNotEmpty) {
          hasUnparsedLeading = true;
        }
      }

      bool hasUnparsedBetween = false;
      for (int i = 0; i < all5Digits.length - 1; i++) {
        final currentEnd = all5Digits[i].end;
        final nextStart = all5Digits[i + 1].start;
        final textBetween = lineForParsing.substring(currentEnd, nextStart).trim();
        final nonSep = textBetween.replaceAll(RegExp(r'[\s,;/\.\-+]+'), '').trim();
        if (nonSep.isNotEmpty) {
          hasUnparsedBetween = true;
          break;
        }
      }

      // If the line has unrecognized extra content around or between the tickets, route it to Under Review Drawer
      if (hasUnparsedTrailing || hasUnparsedLeading || hasUnparsedBetween) {
        unparsedLines.add(originalLine);
        continue;
      }

      final List<String> effectiveSeriesList = explicitLineSeriesList.isNotEmpty
          ? explicitLineSeriesList
          : (currentMessageSeries != null ? [currentMessageSeries!] : []);

      if (effectiveSeriesList.isEmpty) {
        // User Rule: "12 series sirf usi ticket ko assign hoga jis message me 5 digit ke alawa kuch nahi hoga"
        // If no series is defined on line or message (s == null):
        // If there is ANY text before or after that was not an explicit series or valid quantity,
        // route to unparsedLines instead of blindly assigning 12 series!
        if (textBeforeFirstTkt.isNotEmpty) {
          unparsedLines.add(originalLine);
          continue;
        }
        if (textAfterLastTkt.isNotEmpty) {
          final isPureQty = RegExp(r'^(?:[*xXpP=]|qty\b|\s*-\s*)\s*\d+\s*(?:pcs|pis|go|p)?$', caseSensitive: false).hasMatch(textAfterLastTkt);
          if (!isPureQty) {
            unparsedLines.add(originalLine);
            continue;
          }
        }
      }

      if (explicitLineSeriesList.isNotEmpty && currentMessageSeries == null) {
        currentMessageSeries = explicitLineSeriesList.first;
        currentSeries = explicitLineSeriesList.first;
        flushPendingTickets(overrideSeries: explicitLineSeriesList.first);
      }

      if (effectiveSeriesList.isNotEmpty) {
        for (final s in effectiveSeriesList) {
          for (final match in all5Digits) {
            final tNo = match.group(0)!;
            addTicket(
              series: s,
              ticketNo: tNo,
              qty: lineQty,
              seller: currentSeller,
              shift: currentShift,
              date: currentDate,
              originalLine: originalLine,
              isCorrected: lineWasCorrected,
              reason: correctionReason,
            );
          }
        }
      } else {
        for (final match in all5Digits) {
          final tNo = match.group(0)!;
          pendingMessageTickets.add(_PendingTicketItem(
            ticketNo: tNo,
            qty: lineQty,
            seller: currentSeller,
            shift: currentShift,
            date: currentDate,
            originalLine: originalLine,
            lineIndex: currentLineIndex,
            isCorrected: lineWasCorrected,
            reason: correctionReason,
          ));
        }
      }
      continue;
    }

    // Unparsed fallback
    unparsedLines.add(originalLine);
  }

  flushPendingTickets();

  stopwatch.stop();

  return BulkParserResult(
    tickets: parsedTickets,
    unparsedLines: unparsedLines,
    sellerTicketCounts: sellerCounts,
    sellerAmountTotals: sellerAmounts,
    shiftTicketCounts: shiftCounts,
    dateTicketCounts: dateCounts,
    totalLinesRead: totalLines,
    autoCorrectedCount: autoCorrectedCount,
    duplicatesFilteredCount: dupesCount,
    executionDuration: stopwatch.elapsed,
  );
}

/// High-level Async Engine that delegates to compute() isolate
class WhatsAppBulkParserEngine {
  WhatsAppBulkParserEngine._();
  static final WhatsAppBulkParserEngine instance = WhatsAppBulkParserEngine._();

  Future<BulkParserResult> parseBulkChat(BulkParserParams params) async {
    return await compute(parseWhatsAppTextIsolate, params);
  }
}
