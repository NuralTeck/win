import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../core/database/database_service.dart';

class GeminiScannedItem {
  String series;
  String ticketNo;
  String fromTicket;
  String toTicket;
  double amount;
  int quantity;
  String sellerName;
  String? targetDate;
  String? drawShift;

  GeminiScannedItem({
    required this.series,
    required this.ticketNo,
    String? fromTicket,
    String? toTicket,
    required this.amount,
    this.quantity = 1,
    this.sellerName = 'Walk-in Customer',
    this.targetDate,
    this.drawShift,
  }) : fromTicket =
           fromTicket ??
           (ticketNo.contains('-')
               ? ticketNo.split('-').first.trim()
               : ticketNo),
       toTicket =
           toTicket ??
           (ticketNo.contains('-')
               ? ticketNo.split('-').last.trim()
               : ticketNo);
}

class LastStockScanSession {
  final Uint8List imageBytes;
  final List<Uint8List>? allFilesBytes;
  final List<GeminiScannedItem> items;
  final bool isVoucher;
  final String activeShift;
  final DateTime activeDate;
  final String defaultParty;

  LastStockScanSession({
    required this.imageBytes,
    this.allFilesBytes,
    required this.items,
    required this.isVoucher,
    required this.activeShift,
    required this.activeDate,
    required this.defaultParty,
  });
}

enum ScanContext { booking, voucher, unsold }

class GeminiScannerService {
  GeminiScannerService._();
  static final GeminiScannerService instance = GeminiScannerService._();

  LastStockScanSession? lastStockScanSession;
  String? lastDetectedShift;
  String? lastDetectedParty;

  String? detectShiftFromText(String text) {
    // 1:00 PM / Day / Morning / 1 PM / 1:00 / 1pm
    if (RegExp(
      r'\b(?:1\s*(?:pm|:00|baje)|day|morning|1pm|1\s*pm)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return 'Dear 1 PM';
    }
    // 6:00 PM / Evening / 6 PM / 6:00 / 6pm
    if (RegExp(
      r'\b(?:6\s*(?:pm|:00|baje)|eve|evening|6pm|6\s*pm)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return 'Dear 6 PM';
    }
    // 8:00 PM / Night / 8 PM / 8:00 / 8pm
    if (RegExp(
      r'\b(?:8\s*(?:pm|:00|baje)|night|8pm|8\s*pm)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return 'Dear 8 PM';
    }
    return null;
  }

  Future<String?> getActiveApiKey() async {
    return await DatabaseService.instance.getGeminiApiKey();
  }

  /// Scan image bytes and extract lottery tickets (Online with Gemini or 100% Offline with Local OCR)
  Future<List<GeminiScannedItem>> scanImage({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
    String defaultSeller = 'Walk-in Customer',
    ScanContext scanContext = ScanContext.booking,
  }) async {
    final apiKey = await getActiveApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      debugPrint(
        'ℹ️ [OFFLINE OCR MODE] No Gemini key found. Using 100% Pure Local Offline OCR Engine...',
      );
      return await _scanOfflineWithLocalEngine(imageBytes, defaultSeller);
    }

    final base64Image = base64Encode(imageBytes);

    final String prompt;
    if (scanContext == ScanContext.voucher) {
      prompt = '''
You are a universal, intelligent OCR parser for Indian lottery Wholesale Stock Issue Vouchers / Parcha sheets.
Extract all stock voucher sections across ALL columns and rows in the image into a JSON list.

UNIVERSAL PARSING RULES:
1. MULTI-SHIFT & MULTI-SERIES COLUMNS (CRITICAL):
   - A single sheet may contain MULTIPLE SHIFTS / DRAW TIMES across columns or sections!
     Examples: "1:00 PM" / "1:Pm" / "1 PM" -> "Dear 1 PM"
               "6:00 PM" / "6:00 Pm" / "6 PM" -> "Dear 6 PM"
               "8:00 PM" / "8:00 Pm" / "8 PM" -> "Dear 8 PM"
   - Look at the header of EACH column or section!
     Example from handwritten voucher sheet:
     Top half: "(12) 1:Pm" | "(12) 6:00 Pm" | "(12) 8:00 Pm"
     Bottom half: "(24) 1:Pm" | "(24) 6:00 Pm" | "(24) 8:Pm"
   - You MUST extract the "drawShift" for EACH section accurately ("Dear 1 PM", "Dear 6 PM", or "Dear 8 PM")!
   - Never combine columns with different times into the same section!

2. HEADER & PARTY NAME:
   - Extract the customer / party name written at top (e.g. "Ram Manoj", "Aniket", "Sunil") as "partyName".

3. DATES:
   - Identify the dates written on the date column or row headers (e.g. 24/8, 25/8, 26/8, 27/8, 28/8, 29/8, 30/8 or 24/08/2026 - 30/08/2026).
   - Convert each date to YYYY-MM-DD or DD/MM format.

4. SERIES:
   - Look for series written above sections or in brackets (e.g. (12), (24), (36), (40), (60), (20), (100), etc.).
   - Associate each column/section with its active series.

5. BASE RANGE & ROW PREFIXES (NEVER MISS ANY PREFIX):
   - In parchas, the top row contains the base formula / range!
     Example A: "55150 to 550-599" (under (12) 1:Pm)
       -> Top row baseRange is "55150 to 550-599"
       -> The 2-digit prefix on top is "55" for date 24/8.
       -> Subsequent rows under that column contain 2-digit prefixes:
          25/8: "12", 26/8: "69", 27/8: "76", 28/8: "83", 29/8: "45", 30/8: "49".
     Example B: "(24) 1:Pm" column: "37450 to 550-599, 38500-49"
        -> First row for 24/8 has prefixes "37" and "38"!
        -> 25/8 row has "43" and "44"!
        -> Include ALL prefixes listed on that date row!
     Example C: "(24) 6:Pm" column: "40350-399, 550 to 750-799"
        -> Always preserve "to" in "550 to 750-799" or write each packet: "550-599, 650-699, 750-799".
        -> Never drop intermediate packets like 650-699!


6. OUTPUT FORMAT:
Output ONLY a valid JSON array of sections inside ```json ``` code fence:
[
  {
    "series": "<series_name_or_number>",
    "drawShift": "<Dear 1 PM / Dear 6 PM / Dear 8 PM>",
    "partyName": "<party_name_or_null>",
    "baseRange": "<top_row_base_range_as_written>",
    "prefixes": [
      {"date": "<date_str>", "prefix": "<prefix_or_ticket_number>"}
    ]
  }
]

No conversational commentary. Output ONLY the JSON array.
''';
    } else if (scanContext == ScanContext.unsold) {
      prompt = '''
You are an expert OCR parser for Indian lottery Unsold Return Parcha sheets.
Extract all unsold tickets and ranges across ALL columns and rows in the image into a JSON structure.

UNSOLD PARCHA STRUCTURE & RULES:
1. HEADER METADATA:
   - "detectedShift": Look for draw timing written at the top (e.g. "6:00 PM", "6 PM", "Evening" -> "Dear 6 PM", "1:00 PM" -> "Dear 1 PM", "8:00 PM" -> "Dear 8 PM").
   - "detectedDate": Look for date written at top (e.g. "28/08" -> "2026-08-28").
   - "partyName": Look for customer / seller / party name at top (e.g. "Madam", "Mason", "Madhav").

2. COLUMNS & 2-DIGIT PREFIX SYSTEM:
   - The page has multiple vertical columns (1, 2, 3, 4...).
   - Each column has a Series header written at the top (e.g. (12), (24), (36), (20)...).
   - The first row in a column gives the base 5-digit number or range (e.g. "49750-753" -> prefix is "49", "50271-274" -> prefix is "50", "51371-" -> prefix is "51", "52770-779" -> prefix is "52").
   - In subsequent rows under that column, 3-digit ranges (e.g. "276-279", "481-483", "182-189") or single 3-digit numbers with trailing dash (e.g. "554-", "553-", "556-") MUST be prefixed with that column's 2-digit prefix to form complete 5-digit tickets/ranges:
     * "276-279" under prefix "50" -> fromTicket: "50276", toTicket: "50279", quantity: 4, ticketNo: "50276 - 50279"
     * "554-" under prefix "50" -> fromTicket: "50554", toTicket: "50554", quantity: 1, ticketNo: "50554"
     * "182-189" under prefix "50" -> fromTicket: "50182", toTicket: "50189", quantity: 8, ticketNo: "50182 - 50189"

3. OUTPUT FORMAT:
Output ONLY a valid JSON object inside ```json ``` code fence:
{
  "detectedShift": "<Dear 1 PM / Dear 6 PM / Dear 8 PM or null>",
  "detectedDate": "<YYYY-MM-DD or DD/MM or null>",
  "partyName": "<party_name_or_null>",
  "items": [
    {
      "series": "<series_number>",
      "fromTicket": "<5_digit_from>",
      "toTicket": "<5_digit_to>",
      "quantity": <number_of_tickets>,
      "ticketNo": "<5_digit_from - 5_digit_to OR single_5_digit>"
    }
  ]
}

Read EVERY column from left to right and top to bottom without skipping any row.
No conversational commentary. Output ONLY the JSON object.
''';
    } else {
      prompt = '''
You are an expert OCR parser for Indian handwritten and printed lottery booking parchas (receipts).
Carefully analyze the lottery booking image and extract all booking items according to these rules:

RULES:
1. If the image is a Weekly / Stock Issue Voucher sheet (having columns with draw times like 1:PM, 6:PM, 8:PM, series like (12), (24), date rows like 31/8, 1, 2, 3... and base ranges like 57200-299):
   IMPORTANT FOR BASE RANGES:
   - In series (24) vouchers, formulas like "550 to 750-799" or "650 to 750-799" mean every 50-ticket packet from start to end (e.g. 550 to 750 includes 550-599, 650-699, 750-799).
   - Write baseRange exactly as written e.g. "40350-399, 550 to 750-799" (preserve the word "to" or list each packet: 550-599, 650-699, 750-799). Never drop intermediate packets like 650-699.
   [
     {
       "series": "<series_number>",
       "drawShift": "<Dear 1 PM / Dear 6 PM / Dear 8 PM>",
       "partyName": "<customer_or_party_name_at_top>",
       "baseRange": "<base_range_as_written>",
       "prefixes": [
         {"date": "<date_as_written>", "prefix": "<prefix_or_ticket_number>"}
       ]
     }
   ]

2. Otherwise, for standard booking parchas:
   - Ticket Numbers: MUST ALWAYS be 5-DIGIT numbers (e.g. 56581, 28311, 04921) or ranges (e.g. 56581-56585).
   - Series: Extract the series (e.g. 12, 24, 36, 100, etc.).
   - Output line-by-line in this exact format:
     <series>=<5_digit_ticket>
     Example:
     12=56581
     12=56582
     24=28311

Output ONLY the data. No explanations.
''';
    }

    final requestBody = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inlineData': {'mimeType': mimeType, 'data': base64Image},
            },
          ],
        },
      ],
      'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 8192},
    });

    final candidateModels = [
      'gemini-3.5-flash-lite',
      'gemini-flash-lite-latest',
      'gemini-3.5-flash',
      'gemini-3.7-flash',
      'gemini-flash-latest',
    ];

    String lastError = '';
    for (final modelName in candidateModels) {
      for (int attempt = 1; attempt <= 2; attempt++) {
        try {
          final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=${apiKey.trim()}',
          );

          final response = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final text =
                data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
            debugPrint('📸 [GEMINI SCAN RESULT RAW ($modelName)]:\n$text');
            final parsedItems = _parseExtractedText(
              text,
              defaultSeller,
              scanContext,
            );
            if (scanContext == ScanContext.voucher ||
                scanContext == ScanContext.unsold) {
              return condenseIntoRanges(parsedItems);
            }
            return parsedItems;
          } else {
            lastError = 'HTTP ${response.statusCode}: ${response.body}';
            if ((response.statusCode == 503 || response.statusCode == 429) &&
                attempt == 1) {
              debugPrint(
                '⚠️ [GEMINI BUSY] $modelName returned ${response.statusCode}. Retrying in 1.5s...',
              );
              await Future.delayed(const Duration(milliseconds: 1500));
              continue;
            }
            debugPrint(
              '⚠️ [GEMINI SCAN NOTE] $modelName returned $lastError. Trying fallback model...',
            );
            break;
          }
        } catch (e) {
          lastError = e.toString();
          debugPrint('⚠️ [GEMINI SCAN EXCEPTION] $modelName: $e');
          break;
        }
      }
    }

    debugPrint(
      'ℹ️ [OFFLINE FALLBACK] Cloud scan unavailable ($lastError). Using 100% Local Offline OCR Engine...',
    );
    return await _scanOfflineWithLocalEngine(imageBytes, defaultSeller);
  }

  /// 100% Pure Offline OCR Engine running locally on Windows
  Future<List<GeminiScannedItem>> _scanOfflineWithLocalEngine(
    Uint8List imageBytes,
    String defaultSeller,
  ) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempImagePath = p.join(
        tempDir.path,
        'temp_ocr_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await File(tempImagePath).writeAsBytes(imageBytes);

      final currentDir = Directory.current.path;
      final nodeExe = File(p.join(currentDir, 'whatsapp_engine', 'node.exe'));
      final scriptPath = File(
        p.join(currentDir, 'whatsapp_engine', 'ocr_offline.js'),
      );

      String execPath = 'node';
      if (nodeExe.existsSync()) {
        execPath = nodeExe.path;
      }

      if (scriptPath.existsSync()) {
        final result = await Process.run(execPath, [
          scriptPath.path,
          tempImagePath,
        ], workingDirectory: p.join(currentDir, 'whatsapp_engine'));

        if (result.exitCode == 0 && result.stdout != null) {
          final String outStr = result.stdout.toString().trim();
          debugPrint('📸 [LOCAL OFFLINE OCR RESULT]: $outStr');
          try {
            final dynamic parsed = jsonDecode(outStr);
            if (parsed is List) {
              final List<GeminiScannedItem> items = [];
              for (final item in parsed) {
                items.add(
                  GeminiScannedItem(
                    series: item['series']?.toString() ?? '12',
                    ticketNo: item['ticketNo']?.toString() ?? '',
                    amount: (item['amount'] as num?)?.toDouble() ?? 0.0,
                    sellerName: defaultSeller,
                  ),
                );
              }
              try {
                await File(tempImagePath).delete();
              } catch (_) {}
              return items;
            }
          } catch (jsonErr) {
            debugPrint('⚠️ [OFFLINE OCR JSON PARSE ERROR] $jsonErr');
          }
        } else {
          debugPrint('⚠️ [OFFLINE OCR PROCESS ERROR]: ${result.stderr}');
        }
      }
      try {
        await File(tempImagePath).delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('⚠️ [OFFLINE OCR EXCEPTION] $e');
    }
    return [];
  }

  String _normalizeScannedDate(String raw, [DateTime? previousDate]) {
    final clean = raw.trim().replaceAll(RegExp(r'[^\d\/\-]'), '');
    final now = DateTime.now();
    if (clean.isEmpty) {
      if (previousDate != null) {
        return '${previousDate.year}-${previousDate.month.toString().padLeft(2, '0')}-${previousDate.day.toString().padLeft(2, '0')}';
      }
      return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }

    // 1. YYYY-MM-DD or YYYY/MM/DD
    final ymdMatch = RegExp(
      r'^(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})[-\/]?$',
    ).firstMatch(clean);
    if (ymdMatch != null) {
      final y = ymdMatch.group(1)!;
      final m = ymdMatch.group(2)!.padLeft(2, '0');
      final d = ymdMatch.group(3)!.padLeft(2, '0');
      return '$y-$m-$d';
    }

    // 2. DD-MM-YYYY or DD/MM/YYYY
    final dmyMatch = RegExp(
      r'^(\d{1,2})[-\/](\d{1,2})[-\/](\d{4})$',
    ).firstMatch(clean);
    if (dmyMatch != null) {
      final d = dmyMatch.group(1)!.padLeft(2, '0');
      final m = dmyMatch.group(2)!.padLeft(2, '0');
      final y = dmyMatch.group(3)!;
      return '$y-$m-$d';
    }

    // 3. DD-MM or DD/MM (with optional trailing slash e.g. 28/08/ or 31/8)
    final dmMatch = RegExp(r'^(\d{1,2})[-\/](\d{1,2})[-\/]?$').firstMatch(clean);
    if (dmMatch != null) {
      final d = int.parse(dmMatch.group(1)!);
      final m = int.parse(dmMatch.group(2)!);
      return '${now.year}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
    }

    // 4. Day only with optional trailing slash e.g. 1/, 2/, 25/, 28/, 28- or just 1, 2
    final dOnlyMatch = RegExp(r'^(\d{1,2})[-\/]?$').firstMatch(clean);
    if (dOnlyMatch != null) {
      final dNum = int.tryParse(dOnlyMatch.group(1)!);
      if (dNum != null && dNum >= 1 && dNum <= 31) {
        if (previousDate != null) {
          int y = previousDate.year;
          int m = previousDate.month;
          // Rollover to next month if day wrapped around (e.g. 31/8 followed by 1/)
          if (dNum < previousDate.day) {
            m++;
            if (m > 12) {
              m = 1;
              y++;
            }
          }
          return '$y-${m.toString().padLeft(2, '0')}-${dNum.toString().padLeft(2, '0')}';
        }
        return '${now.year}-${now.month.toString().padLeft(2, '0')}-${dNum.toString().padLeft(2, '0')}';
      }
    }

    // Fallback
    if (previousDate != null) {
      return '${previousDate.year}-${previousDate.month.toString().padLeft(2, '0')}-${previousDate.day.toString().padLeft(2, '0')}';
    }
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  List<Map<String, int>> _parseBaseRangeSuffixes(String baseRange) {
    final List<Map<String, int>> ranges = [];
    String cleaned = baseRange.trim();

    // Fix OCR glitches where "650 to 750" is transcribed as "650-6750" (repetition of previous hundred digit)
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(\d)50\s*[-~to\s]+\s*(\d)(\d)50', caseSensitive: false),
      (m) => '${m.group(1)}50 to ${m.group(3)}50',
    );

    // 1. If the whole range is 5-digit to 5-digit e.g. 57200-57299, 57200 to 57299, 57200 se 57299
    final full5Match = RegExp(
      r'^(\d{2})(\d{3})\s*(?:[-~]+|\s+(?:to|se|tak|--)\s+)\s*(\d{2})?(\d{3})$',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (full5Match != null) {
      final s = int.parse(full5Match.group(2)!);
      final e = int.parse(full5Match.group(4)!);
      if (e >= s) {
        ranges.add({'start': s, 'end': e});
        return ranges;
      }
    }

    // 2. If starts with 5 digits (e.g. 57200-299 or 40350-399), strip leading 2-digit prefix
    final lead5Match = RegExp(r'^(\d{2})(\d{3})').firstMatch(cleaned);
    if (lead5Match != null) {
      cleaned = cleaned.substring(2);
    }

    // 3. Split by comma, semicolon, slash, plus, ampersand, pipe, or spaces between independent ranges
    final parts = cleaned.split(
      RegExp(r'[,;/+&|]|(?<!to|se|tak)\s+(?=\d{2,3}\s*[-~])', caseSensitive: false),
    );

    for (String part in parts) {
      part = part.trim();
      if (part.isEmpty) continue;

      final sepPattern = r'(?:[-~]+|\s*(?:to|se|tak|--|\/|\+)\s*)';

      // Case 0: Full hundred packet span e.g. "300-399 to 600-699" or "300 to 600-699"
      final hundredSpan = RegExp(
        r'(\d)00(?:-\d{3})?\s*(?:to|se|tak|--|\/|\+)\s*(?:(\d)00\s*[-~]+\s*)?(\d)99',
        caseSensitive: false,
      ).firstMatch(part);
      if (hundredSpan != null) {
        final sH = int.parse(hundredSpan.group(1)!);
        final eH = int.parse(
          hundredSpan.group(3) ?? hundredSpan.group(2) ?? hundredSpan.group(1)!,
        );
        if (eH >= sH) {
          for (int h = sH; h <= eH; h++) {
            ranges.add({'start': h * 100, 'end': h * 100 + 99});
          }
          continue;
        }
      }

      // Case 1: Packet Range e.g. "450 to 550-599", "450 to 650-699", "550 to 750-799", "650 to 750-799"
      final packetRange = RegExp(
        r'(\d)50\s*(?:[-~]+|\s*(?:to|se|tak|--|\/|\+)\s*)\s*(?:(\d)50\s*[-~]+\s*)?(\d)(?:50|99)',
        caseSensitive: false,
      ).firstMatch(part);
      if (packetRange != null) {
        final sH = int.parse(packetRange.group(1)!);
        final eH = int.parse(
          packetRange.group(3) ?? packetRange.group(2) ?? packetRange.group(1)!,
        );
        if (eH >= sH) {
          for (int h = sH; h <= eH; h++) {
            ranges.add({'start': h * 100 + 50, 'end': h * 100 + 99});
          }
          continue;
        }
      }

      // Case 2: Packet Range without -99 e.g. "450 to 550", "550 to 750"
      final packetRangeSimple = RegExp(
        r'(\d)50\s*(?:[-~]+|\s*(?:to|se|tak|--|\/|\+)\s*)\s*(\d)50',
        caseSensitive: false,
      ).firstMatch(part);
      if (packetRangeSimple != null) {
        final sH = int.parse(packetRangeSimple.group(1)!);
        final eH = int.parse(packetRangeSimple.group(2)!);
        if (eH >= sH) {
          for (int h = sH; h <= eH; h++) {
            ranges.add({'start': h * 100 + 50, 'end': h * 100 + 99});
          }
          continue;
        }
      }

      // Case 3: Standard range e.g. "200-299", "350-399", "650-699", "00-99", "50-99"
      final rangeMatch = RegExp(
        '(\\d{2,3})\\s*$sepPattern\\s*(\\d{1,5})',
        caseSensitive: false,
      ).firstMatch(part);
      if (rangeMatch != null) {
        final start = int.parse(rangeMatch.group(1)!);
        final endRaw = rangeMatch.group(2)!;
        int end = int.parse(endRaw);

        if (endRaw.length == 5) {
          end = int.parse(endRaw.substring(2));
        } else if (endRaw.length == 2 && rangeMatch.group(1)!.length == 3) {
          end = (start ~/ 100) * 100 + end;
        } else if (endRaw.length == 1) {
          end = (start ~/ 10) * 10 + end;
        }

        if (end >= start) {
          ranges.add({'start': start, 'end': end});
          continue;
        }
      }

      // Case 4: Standalone 50-packet notation e.g. "450", "550", "650", "750", "350"
      final single50 = RegExp(r'^(\d)50$').firstMatch(part);
      if (single50 != null) {
        final h = int.parse(single50.group(1)!);
        ranges.add({'start': h * 100 + 50, 'end': h * 100 + 99});
        continue;
      }

      // Case 5: Single 2 or 3-digit number e.g. "200", "50"
      final singleNum = RegExp(r'^\d{2,3}$').firstMatch(part);
      if (singleNum != null) {
        final n = int.parse(singleNum.group(0)!);
        ranges.add({'start': n, 'end': n});
        continue;
      }
    }

    return ranges;
  }

  List<GeminiScannedItem> _expandVoucherBlock({
    required String series,
    required String baseRange,
    required List<dynamic> prefixes,
    required String defaultSeller,
    String? drawShift,
  }) {
    final List<GeminiScannedItem> items = [];
    final cleanSer = series.replaceAll(RegExp(r'\D'), '');
    final s = cleanSer.isNotEmpty ? cleanSer : '12';

    final List<dynamic> workingPrefixes = List<dynamic>.from(prefixes);

    // ⚡ Auto-Capture First Prefix from baseRange (e.g. "56150 to 550-599" -> prefix is "56")
    final basePrefixMatch = RegExp(r'^(\d{2})\d{3}').firstMatch(baseRange.trim());
    if (basePrefixMatch != null) {
      final basePref = basePrefixMatch.group(1)!;
      final alreadyPresent = workingPrefixes.any((p) {
        if (p is! Map) return false;
        final pStr = p['prefix']?.toString().replaceAll(RegExp(r'\D'), '').padLeft(2, '0');
        return pStr == basePref;
      });
      if (!alreadyPresent) {
        final firstDate = workingPrefixes.isNotEmpty && workingPrefixes.first is Map
            ? (workingPrefixes.first['date']?.toString() ?? '31/8')
            : '31/8';
        workingPrefixes.insert(0, {'date': firstDate, 'prefix': basePref});

        // If inserting basePref duplicated the date with the next row (e.g. both got 31/8),
        // cleanly increment the subsequent rows so each row gets its rightful consecutive date
        if (workingPrefixes.length > 1 && workingPrefixes[1] is Map) {
          final d0 = workingPrefixes[0]['date']?.toString().trim() ?? '';
          final d1 = workingPrefixes[1]['date']?.toString().trim() ?? '';
          if (d0 == d1 || d0.replaceAll(RegExp(r'\D'), '') == d1.replaceAll(RegExp(r'\D'), '')) {
            for (int i = 1; i < workingPrefixes.length; i++) {
              if (workingPrefixes[i] is! Map) continue;
              final prevD = workingPrefixes[i - 1]['date']?.toString() ?? '';
              final m = RegExp(r'(\d+)').firstMatch(prevD);
              if (m != null) {
                final prevNum = int.tryParse(m.group(1)!) ?? 0;
                if (prevNum >= 31) {
                  workingPrefixes[i]['date'] = '1/';
                } else {
                  workingPrefixes[i]['date'] = '${prevNum + 1}/';
                }
              }
            }
          }
        }
      }
    }

    final suffixRanges = _parseBaseRangeSuffixes(baseRange);

    DateTime? lastDate;
    for (final prefObj in workingPrefixes) {
      if (prefObj is! Map) continue;
      final rawDate = prefObj['date']?.toString() ?? '';
      final targetDate = _normalizeScannedDate(rawDate, lastDate);
      lastDate = DateTime.tryParse(targetDate) ?? lastDate;

      final rawPrefix = prefObj['prefix']?.toString().replaceAll(RegExp(r'\D'), '') ?? '';
      if (rawPrefix.isEmpty) continue;
      final prefix = rawPrefix.padLeft(2, '0');

      if (suffixRanges.isNotEmpty) {
        for (final sr in suffixRanges) {
          final startSuffix = sr['start']!;
          final endSuffix = sr['end']!;
          final fromStr = '$prefix${startSuffix.toString().padLeft(3, '0')}';
          final toStr = '$prefix${endSuffix.toString().padLeft(3, '0')}';
          final qty = (endSuffix - startSuffix) + 1;
          items.add(
            GeminiScannedItem(
              series: s,
              ticketNo: fromStr == toStr ? fromStr : '$fromStr - $toStr',
              fromTicket: fromStr,
              toTicket: toStr,
              quantity: qty,
              amount: 0.0,
              sellerName: defaultSeller,
              targetDate: targetDate,
              drawShift: drawShift,
            ),
          );
        }
      } else {
        // Pattern 2: Continuous 5-Digit Range e.g. 28100-28500
        final contMatch = RegExp(r'(\d{5})\s*[-~to]+\s*(\d{5})').firstMatch(baseRange);
        if (contMatch != null) {
          final startNum = int.parse(contMatch.group(1)!);
          final endNum = int.parse(contMatch.group(2)!);
          final qty = (endNum - startNum) + 1;
          items.add(
            GeminiScannedItem(
              series: s,
              ticketNo: '${contMatch.group(1)} - ${contMatch.group(2)}',
              fromTicket: contMatch.group(1)!,
              toTicket: contMatch.group(2)!,
              quantity: qty,
              amount: 0.0,
              sellerName: defaultSeller,
              targetDate: targetDate,
              drawShift: drawShift,
            ),
          );
        } else if (rawPrefix.length == 5) {
          items.add(
            GeminiScannedItem(
              series: s,
              ticketNo: rawPrefix,
              fromTicket: rawPrefix,
              toTicket: rawPrefix,
              quantity: 1,
              amount: 0.0,
              sellerName: defaultSeller,
              targetDate: targetDate,
              drawShift: drawShift,
            ),
          );
        }
      }
    }

    return items;
  }

  String? _normalizeShift(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final clean = raw.toLowerCase().trim();
    if (clean.contains('1') || clean.contains('one') || clean.contains('morning') || clean.contains('day')) return 'Dear 1 PM';
    if (clean.contains('6') || clean.contains('six') || clean.contains('evening')) return 'Dear 6 PM';
    if (clean.contains('8') || clean.contains('eight') || clean.contains('night')) return 'Dear 8 PM';
    return raw.trim();
  }

  List<GeminiScannedItem> _parseExtractedText(
    String text,
    String defaultSeller, [
    ScanContext scanContext = ScanContext.booking,
  ]) {
    // 1. Try parsing JSON format for wholesale vouchers
    if (scanContext == ScanContext.voucher ||
        text.contains('"baseRange"') ||
        text.contains('"prefixes"')) {
      try {
        String jsonStr = text;
        final jsonMatch = RegExp(
          r'```(?:json)?\s*([\s\S]*?)\s*```',
        ).firstMatch(text);
        if (jsonMatch != null) {
          jsonStr = jsonMatch.group(1)!;
        }
        final startIndex = jsonStr.indexOf('[');
        final endIndex = jsonStr.lastIndexOf(']');
        if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
          final cleanJson = jsonStr.substring(startIndex, endIndex + 1);
          final dynamic decoded = jsonDecode(cleanJson);
          if (decoded is List && decoded.isNotEmpty) {
            final List<GeminiScannedItem> jsonItems = [];
            for (final block in decoded) {
              if (block is Map) {
                final ser = block['series']?.toString() ?? '12';
                final baseRange = block['baseRange']?.toString() ?? '';
                final rawShift = block['drawShift']?.toString() ?? block['shift']?.toString();
                final blockShift = _normalizeShift(rawShift);
                final blockParty = block['partyName']?.toString();
                if (blockParty != null && blockParty.trim().isNotEmpty) {
                  lastDetectedParty = blockParty.trim();
                }
                final prefixes = block['prefixes'];
                if (prefixes is List) {
                  final expanded = _expandVoucherBlock(
                    series: ser,
                    baseRange: baseRange,
                    prefixes: prefixes,
                    defaultSeller: defaultSeller,
                    drawShift: blockShift,
                  );
                  jsonItems.addAll(expanded);
                }
              }
            }
            if (jsonItems.isNotEmpty) {
              debugPrint(
                '✅ [JSON VOUCHER PARSE SUCCESS] Extracted ${jsonItems.length} ranges from ${decoded.length} blocks',
              );
              return jsonItems;
            }
          }
        }
      } catch (e) {
        debugPrint(
          'ℹ️ [JSON VOUCHER PARSE NOTE] $e, falling back to line-by-line parser',
        );
      }
    }

    // 2. Try parsing JSON format for Unsold Return Parcha sheets
    if (scanContext == ScanContext.unsold ||
        text.contains('"detectedShift"') ||
        text.contains('"fromTicket"')) {
      try {
        String jsonStr = text;
        final jsonMatch = RegExp(
          r'```(?:json)?\s*([\s\S]*?)\s*```',
        ).firstMatch(text);
        if (jsonMatch != null) {
          jsonStr = jsonMatch.group(1)!;
        }

        dynamic decoded;
        try {
          decoded = jsonDecode(jsonStr);
        } catch (_) {
          final sObj = jsonStr.indexOf('{');
          final eObj = jsonStr.lastIndexOf('}');
          final sArr = jsonStr.indexOf('[');
          final eArr = jsonStr.lastIndexOf(']');
          if (sObj != -1 && eObj != -1 && (sArr == -1 || sObj < sArr)) {
            decoded = jsonDecode(jsonStr.substring(sObj, eObj + 1));
          } else if (sArr != -1 && eArr != -1) {
            decoded = jsonDecode(jsonStr.substring(sArr, eArr + 1));
          }
        }

        if (decoded != null) {
          List<dynamic> itemsList = [];
          String? detectedParty;
          String? rawDate;

          if (decoded is Map) {
            if (decoded['detectedShift'] != null &&
                decoded['detectedShift'].toString().isNotEmpty) {
              lastDetectedShift = decoded['detectedShift'].toString();
            }
            rawDate = decoded['detectedDate']?.toString();
            detectedParty = decoded['partyName']?.toString().trim();
            final rawItems = decoded['items'];
            if (rawItems is List) {
              itemsList = rawItems;
            }
          } else if (decoded is List) {
            itemsList = decoded;
          }

          final effectiveParty =
              (detectedParty != null && detectedParty.isNotEmpty)
                  ? detectedParty
                  : defaultSeller;

          if (itemsList.isNotEmpty) {
            final List<GeminiScannedItem> jsonItems = [];
            for (final it in itemsList) {
              if (it is Map) {
                final ser = it['series']?.toString() ?? '12';
                final fTkt =
                    it['fromTicket']?.toString().replaceAll(RegExp(r'\D'), '').padLeft(5, '0') ??
                    '';
                final tTkt =
                    it['toTicket']?.toString().replaceAll(RegExp(r'\D'), '').padLeft(5, '0') ??
                    fTkt;
                int q = (it['quantity'] as num?)?.toInt() ?? 0;
                if (q <= 0 && fTkt.isNotEmpty && tTkt.isNotEmpty) {
                  final fNum = int.tryParse(fTkt);
                  final tNum = int.tryParse(tTkt);
                  if (fNum != null && tNum != null && tNum >= fNum) {
                    q = (tNum - fNum) + 1;
                  } else {
                    q = 1;
                  }
                }
                if (q <= 0) q = 1;

                final tNo = it['ticketNo']?.toString() ??
                    (q > 1 ? '$fTkt - $tTkt' : fTkt);

                if (fTkt.isNotEmpty) {
                  jsonItems.add(
                    GeminiScannedItem(
                      series: ser,
                      ticketNo: tNo,
                      fromTicket: fTkt,
                      toTicket: tTkt,
                      quantity: q,
                      amount: 0.0,
                      sellerName: effectiveParty,
                      targetDate: rawDate != null
                          ? _normalizeScannedDate(rawDate)
                          : null,
                    ),
                  );
                }
              }
            }

            if (jsonItems.isNotEmpty) {
              debugPrint(
                '✅ [JSON UNSOLD PARSE SUCCESS] Extracted ${jsonItems.length} unsold ranges',
              );
              return jsonItems;
            }
          }
        }
      } catch (e) {
        debugPrint(
          'ℹ️ [JSON UNSOLD PARSE NOTE] $e, falling back to line-by-line parser',
        );
      }
    }

    final List<GeminiScannedItem> items = [];
    final lines = text.split(RegExp(r'\r?\n'));
    String currentSeries = '';

    for (final line in lines) {
      String l = line.trim();
      if (l.isEmpty) {
        currentSeries = '';
        continue;
      }

      String? lineDate;
      if (l.contains('|')) {
        final parts = l.split('|');
        l = parts.first.trim();
        final rawD = parts.last.trim();
        if (rawD.isNotEmpty) {
          lineDate = _normalizeScannedDate(rawD);
        }
      }

      // Standalone Header
      final headerMatch = RegExp(
        r'^(?:SERIES|SR|SER|SERI)?\s*[\(\[\{]?\s*([0-9]{1,3}\s*[A-Za-z]{0,8}|[A-Za-z]{1,4}\s*[0-9]{1,3})\s*[\)\]\}]?\s*[-:,\/=\s._~|*xX#@+]*$',
        caseSensitive: false,
      ).firstMatch(l);

      if (headerMatch != null &&
          l.length <= 15 &&
          !RegExp(r'\d{5}').hasMatch(l)) {
        final digits = headerMatch.group(1)!.replaceAll(RegExp(r'\D'), '');
        if (digits.isNotEmpty) {
          currentSeries = digits;
          // Retroactive backfill
          for (int i = items.length - 1; i >= 0; i--) {
            if (items[i].series == '?') {
              items[i].series = digits;
            } else {
              break;
            }
          }
          continue;
        }
      }

      // Full 5-Digit Range e.g. 40=39150-39199 or 39150-39199=40 or 39150 to 39199
      final fullRangeMatch = RegExp(
        r'(?:^|[\s,;])(?:([0-9]{1,3}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,3})\s*[-:,\/=\s._~|*xX#@+]+)?(\d{5})\s*[-~to]+\s*(\d{5})(?:\s*[-:,\/=\s._~|*xX#@+]+\s*([0-9]{1,3}[A-Za-z]{0,4}))?',
        caseSensitive: false,
      ).firstMatch(l);

      if (fullRangeMatch != null) {
        final rawS = fullRangeMatch.group(1) ?? fullRangeMatch.group(4);
        final sDigits = rawS != null ? rawS.replaceAll(RegExp(r'\D'), '') : '';
        final s = sDigits.isNotEmpty ? sDigits : currentSeries;
        final start5 = int.tryParse(fullRangeMatch.group(2)!) ?? 0;
        final end5 = int.tryParse(fullRangeMatch.group(3)!) ?? start5;

        if (end5 >= start5 && end5 - start5 <= 1000) {
          final fromStr = start5.toString().padLeft(5, '0');
          final toStr = end5.toString().padLeft(5, '0');
          final qty = (end5 - start5) + 1;

          if (scanContext == ScanContext.voucher ||
              scanContext == ScanContext.unsold ||
              qty > 10) {
            items.add(
              GeminiScannedItem(
                series: s.isNotEmpty ? s : '?',
                ticketNo: qty > 1 ? '$fromStr - $toStr' : fromStr,
                fromTicket: fromStr,
                toTicket: toStr,
                quantity: qty,
                amount: 0.0,
                sellerName: defaultSeller,
                targetDate: lineDate,
              ),
            );
          } else {
            for (int i = start5; i <= end5; i++) {
              items.add(
                GeminiScannedItem(
                  series: s.isNotEmpty ? s : '?',
                  ticketNo: i.toString().padLeft(5, '0'),
                  amount: 0.0,
                  sellerName: defaultSeller,
                  targetDate: lineDate,
                ),
              );
            }
          }
          currentSeries = s.isNotEmpty ? s : currentSeries;
          continue;
        }
      }

      // Range format e.g. 12 12345-49
      final rangeMatch = RegExp(
        r'(?:^|[\s,;])(?:([0-9]{1,3}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,3})\s*[-:,\/=\s._~|*xX#@+]+)?(\d{3})(\d{2})\s*[-~to]+\s*(\d{1,5})',
        caseSensitive: false,
      ).firstMatch(l);

      if (rangeMatch != null) {
        final rawS = rangeMatch.group(1);
        final sDigits = rawS != null ? rawS.replaceAll(RegExp(r'\D'), '') : '';
        final s = sDigits.isNotEmpty ? sDigits : currentSeries;
        final prefix = rangeMatch.group(2)!;
        final start2 = int.tryParse(rangeMatch.group(3)!) ?? 0;
        final endStr = rangeMatch.group(4)!;
        int end2 = int.tryParse(endStr) ?? start2;
        if (endStr.length == 5) {
          end2 = int.tryParse(endStr.substring(3)) ?? start2;
        } else if (endStr.length == 1) {
          final tens = (start2 ~/ 10) * 10;
          end2 = tens + int.parse(endStr);
        }

        if (end2 >= start2 && end2 - start2 <= 500) {
          final fromStr = '$prefix${start2.toString().padLeft(2, '0')}';
          final toStr = '$prefix${end2.toString().padLeft(2, '0')}';
          final qty = (end2 - start2) + 1;

          if (scanContext == ScanContext.voucher ||
              scanContext == ScanContext.unsold ||
              qty > 10) {
            items.add(
              GeminiScannedItem(
                series: s.isNotEmpty ? s : '?',
                ticketNo: qty > 1 ? '$fromStr - $toStr' : fromStr,
                fromTicket: fromStr,
                toTicket: toStr,
                quantity: qty,
                amount: 0.0,
                sellerName: defaultSeller,
              ),
            );
          } else {
            for (int i = start2; i <= end2; i++) {
              items.add(
                GeminiScannedItem(
                  series: s.isNotEmpty ? s : '?',
                  ticketNo: '$prefix${i.toString().padLeft(2, '0')}',
                  amount: 0.0,
                  sellerName: defaultSeller,
                ),
              );
            }
          }
          currentSeries = s.isNotEmpty ? s : currentSeries;
          continue;
        }
      }

      // Trailing Series e.g. 85638*36, 85638=6
      final trailingMatches = RegExp(
        r'(?:^|[\s,;])(\d{5})\s*[-:,\/=\s._~|*xX#@+]+\s*([0-9]{1,3}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,3})(?=[\s,;]|$)',
        caseSensitive: false,
      ).allMatches(l);

      bool matchedTrailing = false;
      for (final m in trailingMatches) {
        final tNo = m.group(1)!;
        final rawS = m.group(2)!.replaceAll(RegExp(r'\D'), '');
        final s = rawS.isNotEmpty ? rawS : currentSeries;
        items.add(
          GeminiScannedItem(
            series: s.isNotEmpty ? s : '?',
            ticketNo: tNo,
            amount: 0.0,
            sellerName: defaultSeller,
          ),
        );
        currentSeries = s.isNotEmpty ? s : currentSeries;
        matchedTrailing = true;
      }
      if (matchedTrailing) continue;

      // Leading Series e.g. 36*49151, 12=69476
      final leadingMatches = RegExp(
        r'(?:^|[\s,;])([0-9]{1,3}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,3})\s*[-:,\/=\s._~|*xX#@+]+\s*(\d{5})(?=[\s,;]|$)',
        caseSensitive: false,
      ).allMatches(l);

      bool matchedLeading = false;
      for (final m in leadingMatches) {
        final rawS = m.group(1)!.replaceAll(RegExp(r'\D'), '');
        final s = rawS.isNotEmpty ? rawS : currentSeries;
        final tNo = m.group(2)!;
        items.add(
          GeminiScannedItem(
            series: s.isNotEmpty ? s : '?',
            ticketNo: tNo,
            amount: 0.0,
            sellerName: defaultSeller,
          ),
        );
        currentSeries = s.isNotEmpty ? s : currentSeries;
        matchedLeading = true;
      }
      if (matchedLeading) continue;

      // Standalone 5-digit tickets
      final all5s = RegExp(r'\b\d{5}\b').allMatches(l);
      if (all5s.isNotEmpty) {
        for (final m in all5s) {
          items.add(
            GeminiScannedItem(
              series: currentSeries.isNotEmpty ? currentSeries : '?',
              ticketNo: m.group(0)!,
              amount: 0.0,
              sellerName: defaultSeller,
            ),
          );
        }
      }
    }

    return items;
  }

  /// Condenses contiguous consecutive tickets of the same series into single range items
  List<GeminiScannedItem> condenseIntoRanges(List<GeminiScannedItem> items) {
    if (items.isEmpty) return [];
    final List<GeminiScannedItem> result = [];

    for (int i = 0; i < items.length;) {
      final current = items[i];
      if (current.quantity > 1 || current.fromTicket != current.toTicket) {
        if (current.toTicket.length == 7 && current.fromTicket.length == 5) {
          final p1 = current.fromTicket.substring(0, 2);
          final p2 = current.toTicket.substring(2, 4);
          final last3 = current.toTicket.substring(4);
          final newTo = '$p1$last3';
          current.toTicket = newTo;
          current.ticketNo = '${current.fromTicket} - $newTo';
          final fNum = int.tryParse(current.fromTicket) ?? 0;
          final tNum = int.tryParse(newTo) ?? fNum;
          current.quantity = (tNum >= fNum) ? (tNum - fNum) + 1 : 50;
          result.add(current);

          if (int.tryParse(p2) != null) {
            final start3 = current.fromTicket.substring(2);
            final sf = '$p2$start3';
            final st = '$p2$last3';
            result.add(
              GeminiScannedItem(
                series: current.series,
                ticketNo: '$sf - $st',
                fromTicket: sf,
                toTicket: st,
                quantity: current.quantity,
                amount: current.amount,
                sellerName: current.sellerName,
                targetDate: current.targetDate,
                drawShift: current.drawShift,
              ),
            );
          }
          i++;
          continue;
        } else if (current.toTicket.length > 5 && current.fromTicket.length == 5) {
          final p1 = current.fromTicket.substring(0, 2);
          final last3 = current.toTicket.substring(current.toTicket.length - 3);
          final newTo = '$p1$last3';
          current.toTicket = newTo;
          current.ticketNo = '${current.fromTicket} - $newTo';
          final fNum = int.tryParse(current.fromTicket) ?? 0;
          final tNum = int.tryParse(newTo) ?? fNum;
          current.quantity = (tNum >= fNum) ? (tNum - fNum) + 1 : 1;
          result.add(current);
          i++;
          continue;
        }
        result.add(current);
        i++;
        continue;
      }

      final int? currentNum = int.tryParse(current.ticketNo);
      if (currentNum == null) {
        result.add(current);
        i++;
        continue;
      }

      int endNum = currentNum;
      int j = i + 1;
      while (j < items.length) {
        final next = items[j];
        if (next.series != current.series ||
            next.targetDate != current.targetDate ||
            next.drawShift != current.drawShift ||
            next.quantity > 1 ||
            next.sellerName != current.sellerName) {
          break;
        }
        final int? nextNum = int.tryParse(next.ticketNo);
        if (nextNum == null || nextNum != endNum + 1) {
          break;
        }
        endNum = nextNum;
        j++;
      }

      final count = (j - i);
      if (count > 1) {
        final fromStr = currentNum.toString().padLeft(5, '0');
        final toStr = endNum.toString().padLeft(5, '0');
        result.add(
          GeminiScannedItem(
            series: current.series,
            ticketNo: '$fromStr - $toStr',
            fromTicket: fromStr,
            toTicket: toStr,
            quantity: count,
            amount: current.amount * count,
            sellerName: current.sellerName,
            targetDate: current.targetDate,
            drawShift: current.drawShift,
          ),
        );
        i = j;
      } else {
        result.add(current);
        i++;
      }
    }

    return result;
  }
}
