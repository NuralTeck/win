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
  String?
  aiDoubt; // ⚠️ AI Confusion / Doubt reason (e.g. "Unclear digit", "Series assumed")
  int photoIndex; // 📸 0-based index of the photo/slip this ticket came from

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
    this.aiDoubt,
    this.photoIndex = 0,
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
  final List<String> aiConfusions; // ⚠️ List of AI doubts and unparsed notes

  LastStockScanSession({
    required this.imageBytes,
    this.allFilesBytes,
    required this.items,
    required this.isVoucher,
    required this.activeShift,
    required this.activeDate,
    required this.defaultParty,
    this.aiConfusions = const [],
  });
}

enum ScanContext { booking, voucher, unsold }

class GeminiScannerService {
  GeminiScannerService._();
  static final GeminiScannerService instance = GeminiScannerService._();

  LastStockScanSession? lastStockScanSession;
  String? lastDetectedShift;
  String? lastDetectedParty;
  List<String> lastAiConfusions =
      []; // ⚠️ Doubts or unparsed notes from latest scan

  // 🔒 Deterministic In-Memory Scan Cache: Eliminates random fluctuations when scanning the same slip multiple times
  final Map<String, List<GeminiScannedItem>> _scanCache = {};

  void clearScanCache() {
    _scanCache.clear();
  }

  String _computeCacheKey(
    Uint8List bytes,
    ScanContext context,
    String defaultSeller,
  ) {
    final len = bytes.length;
    int hash = 0;
    final step = (len / 100).clamp(1, 1000).toInt();
    for (int i = 0; i < len; i += step) {
      hash = (hash * 31 + bytes[i]) & 0x7FFFFFFF;
    }
    return '${len}_${hash}_${context.name}_$defaultSeller';
  }

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

  int _roundRobinKeyIndex = 0;

  Future<List<String>> getActiveApiKeys() async {
    return await DatabaseService.instance.getGeminiApiKeys();
  }

  Future<String?> getActiveApiKey() async {
    final keys = await getActiveApiKeys();
    return keys.isNotEmpty ? keys.first : null;
  }

  /// Scan image bytes and extract lottery tickets (Online with Gemini or 100% Offline with Local OCR)
  Future<List<GeminiScannedItem>> scanImage({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
    String defaultSeller = 'Walk-in Customer',
    ScanContext scanContext = ScanContext.booking,
  }) async {
    // ⚡ Check Deterministic Cache: Returns 100% identical results instantly on repeated scans of the same slip
    final cacheKey = _computeCacheKey(imageBytes, scanContext, defaultSeller);
    if (_scanCache.containsKey(cacheKey)) {
      debugPrint(
        '⚡ [GEMINI SCAN CACHE HIT]: Returning identical deterministic scan results ($cacheKey)',
      );
      final cached = _scanCache[cacheKey]!;
      return cached
          .map(
            (it) => GeminiScannedItem(
              series: it.series,
              ticketNo: it.ticketNo,
              fromTicket: it.fromTicket,
              toTicket: it.toTicket,
              amount: it.amount,
              quantity: it.quantity,
              sellerName: it.sellerName,
              targetDate: it.targetDate,
              drawShift: it.drawShift,
              aiDoubt: it.aiDoubt,
              photoIndex: it.photoIndex,
            ),
          )
          .toList();
    }

    final allKeys = await getActiveApiKeys();
    if (allKeys.isEmpty) {
      debugPrint(
        'ℹ️ [OFFLINE OCR MODE] No Gemini key found. Using 100% Pure Local Offline OCR Engine...',
      );
      return await _scanOfflineWithLocalEngine(imageBytes, defaultSeller);
    }

    // 🔄 Multi-Key Load Balancing Pool: Rotate starting key using Round-Robin across requests
    final int startIdx = _roundRobinKeyIndex % allKeys.length;
    _roundRobinKeyIndex = (_roundRobinKeyIndex + 1) % allKeys.length;

    // Ordered key pool starting with rotated key, followed by remaining keys as instant failovers
    final List<String> keyPool = [];
    for (int i = 0; i < allKeys.length; i++) {
      keyPool.add(allKeys[(startIdx + i) % allKeys.length]);
    }
    debugPrint(
      '🚀 [GEMINI POOL] ${allKeys.length} API Key(s) Active. Starting request with Key index $startIdx.',
    );

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
     Example D: "26100-300-399" (under (12) or (24) Dear 6 PM)
        -> Top row baseRange is "26100-300-399" (prefix 26, ranges 100-199, 200-299, 300-399).
        -> Prefix for date 28 is "26".
        -> Subsequent row prefix (e.g. for date 29) is "18" (applies to the exact same 100-199, 200-299, 300-399 ranges).
        -> Always output compound ranges like "26100-300-399" EXACTLY as written without altering or dropping digits!


6. OUTPUT FORMAT & CONFUSION REPORTING:
If any handwriting is ambiguous, blurry, cut off, or you have doubt on any digit (e.g. '7' vs '1' or '9' vs '2') or series or date:
- Report it in "aiConfusions" array as a clear explanation string so the operator can manually test/verify.
- In that specific prefix, include "aiDoubt": "<concise reason, e.g. 'unclear if 18 or 28'>".
- If you have NO doubt on an item, set "aiDoubt": null.

Output ONLY a valid JSON object:
{
  "detectedShift": "<Dear 1 PM / Dear 6 PM / Dear 8 PM or null>",
  "partyName": "<party_name_or_null>",
  "aiConfusions": [
    "<Any unclear line, blurry digit, ambiguous series, or doubt encountered. If none, empty array []>"
  ],
  "sections": [
    {
      "series": "<series_name_or_number>",
      "drawShift": "<Dear 1 PM / Dear 6 PM / Dear 8 PM>",
      "partyName": "<party_name_or_null>",
      "baseRange": "<top_row_base_range_as_written>",
      "prefixes": [
        {
          "date": "<date_str>",
          "prefix": "<prefix_or_ticket_number>",
          "aiDoubt": "<optional explanation if handwriting was unclear or doubtful, otherwise null>"
        }
      ]
    }
  ]
}

No conversational commentary. Output ONLY the JSON object.
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

2. COLUMNS & 2-DIGIT / 3-DIGIT PREFIX SYSTEM:
   - The page has vertical columns, each under a Series header (e.g. 24, 12, 36...).
   - A full 5-digit number or range establishes the active 3-digit prefix (and 2-digit prefix):
     * "42370-71-2" -> fromTicket: "42370", toTicket: "42371", active prefix becomes "423"
     * "42270-71-2" -> fromTicket: "42270", toTicket: "42271", active prefix becomes "422"
     * "42990-99-10" -> fromTicket: "42990", toTicket: "42999", active prefix becomes "429"
     * "42860-61-2" -> fromTicket: "42860", toTicket: "42861", active prefix becomes "428"
     * "42980-1" -> fromTicket: "42980", toTicket: "42980", active prefix becomes "429"
     * "42170-1" -> fromTicket: "42170", toTicket: "42170", active prefix becomes "421"
   - Subsequent lines under that active prefix use the active prefix to build 5-digit tickets:
     * "74-1" under prefix "423" -> fromTicket: "42374", toTicket: "42374", quantity: 1
     * "76-79-4" under prefix "423" -> fromTicket: "42376", toTicket: "42379", quantity: 4
     * "63-1" under prefix "428" -> fromTicket: "42863", toTicket: "42863", quantity: 1
     * "65-67-3" under prefix "428" -> fromTicket: "42865", toTicket: "42867", quantity: 3
     * "83-1" under prefix "429" -> fromTicket: "42983", toTicket: "42983", quantity: 1
     * "85-88-4" under prefix "429" -> fromTicket: "42985", toTicket: "42988", quantity: 4
     * "73-75-3" under prefix "421" -> fromTicket: "42173", toTicket: "42175", quantity: 3

3. QUANTITY CALCULATION RULE (CRITICAL):
   - ALWAYS calculate quantity strictly as: (toTicket - fromTicket) + 1
   - The trailing number after the last hyphen (e.g. "-1", "-2", "-4", "-10", "-13") is the handwritten quantity — IGNORE IT! It is often written incorrectly on parchas!
   - Examples:
     * "42345-55-10" -> fromTicket: "42345", toTicket: "42355", quantity = (42355 - 42345) + 1 = 11 (IGNORE "10")
     * "42370-71-2" -> fromTicket: "42370", toTicket: "42371", quantity = (42371 - 42370) + 1 = 2 (IGNORE "2")
     * "76-79-4" -> fromTicket: "42376", toTicket: "42379", quantity = (42379 - 42376) + 1 = 4 (IGNORE "4")
     * "74-1" -> fromTicket: "42374", toTicket: "42374", quantity = 1 (IGNORE "1")

4. OUTPUT FORMAT & CONFUSION REPORTING:
If any handwriting is ambiguous, blurry, cut off, or you have doubt on any digit (e.g. '7' vs '1' or '9' vs '2') or series:
- Report it in "aiConfusions" array as a clear explanation string.
- In that specific item, include "aiDoubt": "<concise reason, e.g. 'unclear if 58572 or 58512'>".
- If you have NO doubt on an item, set "aiDoubt": null.

Output ONLY a valid JSON object inside ```json ``` code fence:
{
  "detectedShift": "<Dear 1 PM / Dear 6 PM / Dear 8 PM or null>",
  "detectedDate": "<YYYY-MM-DD or DD/MM or null>",
  "partyName": "<party_name_or_null>",
  "aiConfusions": [
    "<Any unclear line, blurry digit, ambiguous series, or doubt encountered. If none, empty array []>"
  ],
  "items": [
    {
      "series": "<series_number>",
      "fromTicket": "<5_digit_from>",
      "toTicket": "<5_digit_to>",
      "quantity": <(toTicket - fromTicket) + 1>,
      "ticketNo": "<5_digit_from - 5_digit_to OR single_5_digit>",
      "aiDoubt": "<optional explanation if handwriting was unclear or doubtful, otherwise null>"
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
      'generationConfig': {
        'temperature': 0.0,
        'topP': 1.0,
        'topK': 1,
        'responseMimeType': 'application/json',
        'maxOutputTokens': 8192,
      },
    });

    final candidateModels = [
      'gemini-2.5-flash',
      'gemini-1.5-flash',
      'gemini-2.0-flash',
      'gemini-3.5-flash',
      'gemini-flash-latest',
      'gemini-2.5-flash-lite',
      'gemini-1.5-pro',
    ];

    String lastError = '';

    // ⚡ Multi-Key Load Balancing with Instant Auto-Failover:
    // Try the rotated primary key first. If it hits quota (429), busy (503), or network timeout,
    // immediately fail over to the next key in the pool!
    for (int keyIdx = 0; keyIdx < keyPool.length; keyIdx++) {
      final currentApiKey = keyPool[keyIdx].trim();
      final keyShort = currentApiKey.length > 8
          ? '${currentApiKey.substring(0, 8)}...'
          : currentApiKey;

      for (final modelName in candidateModels) {
        for (int attempt = 1; attempt <= 2; attempt++) {
          try {
            final url = Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$currentApiKey',
            );

            final response = await http
                .post(
                  url,
                  headers: {
                    'Content-Type': 'application/json',
                    'x-goog-api-key': currentApiKey,
                  },
                  body: requestBody,
                )
                .timeout(const Duration(seconds: 20));

            if (response.statusCode == 200) {
              final data = jsonDecode(response.body);
              final text =
                  data['candidates']?[0]?['content']?['parts']?[0]?['text'] ??
                  '';
              debugPrint(
                '📸 [GEMINI SCAN RESULT RAW ($modelName with Key $keyShort)]:\n$text',
              );
              final parsedItems = _parseExtractedText(
                text,
                defaultSeller,
                scanContext,
              );
              final finalItems =
                  (scanContext == ScanContext.voucher ||
                      scanContext == ScanContext.unsold)
                  ? condenseIntoRanges(parsedItems)
                  : parsedItems;

              // Save in deterministic cache
              _scanCache[cacheKey] = finalItems;
              return finalItems;
            } else {
              lastError = 'HTTP ${response.statusCode}: ${response.body}';

              // If Rate-Limit (429) or Server Busy (503) and we have other keys in pool,
              // immediately fail over to the next key!
              if ((response.statusCode == 429 || response.statusCode == 503) &&
                  keyIdx < keyPool.length - 1) {
                debugPrint(
                  '⚠️ [LOAD BALANCER FAILOVER] Key $keyShort hit HTTP ${response.statusCode}. Instantly switching to next API key in pool...',
                );
                // Break out of model/attempt loop to jump straight to next API Key in keyPool!
                break;
              }

              if ((response.statusCode == 503 || response.statusCode == 429) &&
                  attempt == 1) {
                debugPrint(
                  '⚠️ [GEMINI BUSY] $modelName returned ${response.statusCode}. Retrying in 1s...',
                );
                await Future.delayed(const Duration(milliseconds: 1000));
                continue;
              }

              debugPrint(
                '⚠️ [GEMINI SCAN NOTE] $modelName on Key $keyShort returned $lastError. Trying next fallback...',
              );
              break;
            }
          } catch (e) {
            lastError = e.toString();
            debugPrint(
              '⚠️ [GEMINI SCAN EXCEPTION] Key $keyShort on $modelName: $e',
            );
            if (keyIdx < keyPool.length - 1) {
              debugPrint(
                '⚠️ [LOAD BALANCER FAILOVER] Network error on $keyShort. Switching to next key in pool...',
              );
              break; // Jump to next key
            }
            break;
          }
        }
        // If quota was exceeded on this key, don't waste time trying other models on the same dead key!
        if (lastError.contains('429') && keyIdx < keyPool.length - 1) {
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
      final yNum = int.tryParse(ymdMatch.group(1)!);
      // 🛡️ If scanned year is old/outdated (e.g. 2021 from handwritten 21), always use current year now.year!
      final y = (yNum != null && (yNum < now.year - 1 || yNum > now.year + 1))
          ? '${now.year}'
          : ymdMatch.group(1)!;
      final m = ymdMatch.group(2)!.padLeft(2, '0');
      final d = ymdMatch.group(3)!.padLeft(2, '0');
      return '$y-$m-$d';
    }

    // 2. DD-MM-YYYY or DD/MM/YYYY or DD-MM-YY or DD/MM/YY (e.g. 31/08/21 or 31/08/2026)
    final dmyMatch = RegExp(
      r'^(\d{1,2})[-\/](\d{1,2})[-\/](\d{2,4})$',
    ).firstMatch(clean);
    if (dmyMatch != null) {
      final d = dmyMatch.group(1)!.padLeft(2, '0');
      final m = dmyMatch.group(2)!.padLeft(2, '0');
      final rawY = dmyMatch.group(3)!;
      final yNum = int.tryParse(rawY);
      final y =
          (rawY.length == 2 ||
              (yNum != null && (yNum < now.year - 1 || yNum > now.year + 1)))
          ? '${now.year}'
          : rawY;
      return '$y-$m-$d';
    }

    // 3. DD-MM or DD/MM (with optional trailing slash e.g. 28/08/ or 31/8)
    final dmMatch = RegExp(
      r'^(\d{1,2})[-\/](\d{1,2})[-\/]?$',
    ).firstMatch(clean);
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

    // 1. If starts with 5 digits (e.g. 26100-300-399 or 57200-299), strip leading 2-digit prefix
    final lead5Match = RegExp(r'^(\d{2})(\d{3})').firstMatch(cleaned);
    if (lead5Match != null) {
      cleaned = cleaned.substring(2);
    }

    // 2. Split by comma, semicolon, slash, plus, ampersand, pipe, or spaces between independent ranges
    final parts = cleaned.split(
      RegExp(
        r'[,;/+&|]|(?<!to|se|tak)\s+(?=\d{2,3}\s*[-~])',
        caseSensitive: false,
      ),
    );

    for (String part in parts) {
      part = part.trim();
      if (part.isEmpty) continue;

      // Pattern A: Compound hundred series shorthand e.g. "100-300-399", "100-200-300-399", "100 to 300-399", "100-399", "100 to 399"
      final hundredSeriesMatch = RegExp(
        r'^(\d)00\s*(?:[-~to\s]+(?:\d00)?)*\s*[-~to\s]+(\d)99$',
        caseSensitive: false,
      ).firstMatch(part);
      if (hundredSeriesMatch != null) {
        final sH = int.parse(hundredSeriesMatch.group(1)!);
        final eH = int.parse(hundredSeriesMatch.group(2)!);
        if (eH >= sH && (eH - sH) <= 9) {
          for (int h = sH; h <= eH; h++) {
            ranges.add({'start': h * 100, 'end': h * 100 + 99});
          }
          continue;
        }
      }

      // Pattern B: Packet range e.g. "450 to 550-599", "550 to 750-799", "650 to 750-799", "150-550-599"
      final packetRangeMatch = RegExp(
        r'(\d)50\s*(?:[-~to\s]+(?:\d50)?)*\s*[-~to\s]+(\d)(?:50|99)',
        caseSensitive: false,
      ).firstMatch(part);
      if (packetRangeMatch != null) {
        final sH = int.parse(packetRangeMatch.group(1)!);
        final eH = int.parse(packetRangeMatch.group(2)!);
        if (eH >= sH && (eH - sH) <= 9) {
          for (int h = sH; h <= eH; h++) {
            ranges.add({'start': h * 100 + 50, 'end': h * 100 + 99});
          }
          continue;
        }
      }

      // Pattern C: Standard range e.g. "200-299", "350-399", "650-699", "00-99", "50-99"
      final rangeMatch = RegExp(
        r'(\d{2,3})\s*[-~to\s]+\s*(\d{1,5})',
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

      // Pattern D: Standalone 50-packet notation e.g. "450", "550", "650", "750", "350"
      final single50 = RegExp(r'^(\d)50$').firstMatch(part);
      if (single50 != null) {
        final h = int.parse(single50.group(1)!);
        ranges.add({'start': h * 100 + 50, 'end': h * 100 + 99});
        continue;
      }

      // Pattern E: Single 2 or 3-digit number e.g. "200", "50"
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
    final basePrefixMatch = RegExp(
      r'^(\d{2})\d{3}',
    ).firstMatch(baseRange.trim());
    if (basePrefixMatch != null) {
      final basePref = basePrefixMatch.group(1)!;
      final alreadyPresent = workingPrefixes.any((p) {
        if (p is! Map) return false;
        final pStr = p['prefix']
            ?.toString()
            .replaceAll(RegExp(r'\D'), '')
            .padLeft(2, '0');
        return pStr == basePref;
      });
      if (!alreadyPresent) {
        final firstDate =
            workingPrefixes.isNotEmpty && workingPrefixes.first is Map
            ? (workingPrefixes.first['date']?.toString() ?? '31/8')
            : '31/8';
        workingPrefixes.insert(0, {'date': firstDate, 'prefix': basePref});

        // If inserting basePref duplicated the date with the next row (e.g. both got 31/8),
        // cleanly increment the subsequent rows so each row gets its rightful consecutive date
        if (workingPrefixes.length > 1 && workingPrefixes[1] is Map) {
          final d0 = workingPrefixes[0]['date']?.toString().trim() ?? '';
          final d1 = workingPrefixes[1]['date']?.toString().trim() ?? '';
          if (d0 == d1 ||
              d0.replaceAll(RegExp(r'\D'), '') ==
                  d1.replaceAll(RegExp(r'\D'), '')) {
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

      final rawPrefix =
          prefObj['prefix']?.toString().replaceAll(RegExp(r'\D'), '') ?? '';
      if (rawPrefix.isEmpty) continue;
      final prefix = rawPrefix.padLeft(2, '0');
      final prefDoubt =
          prefObj['aiDoubt']?.toString() ?? prefObj['doubt']?.toString();

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
              aiDoubt: prefDoubt,
            ),
          );
        }
      } else {
        // Pattern 2: Continuous 5-Digit Range e.g. 28100-28500
        final contMatch = RegExp(
          r'(\d{5})\s*[-~to]+\s*(\d{5})',
        ).firstMatch(baseRange);
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
              aiDoubt: prefDoubt,
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
              aiDoubt: prefDoubt,
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
    if (clean.contains('1') ||
        clean.contains('one') ||
        clean.contains('morning') ||
        clean.contains('day'))
      return 'Dear 1 PM';
    if (clean.contains('6') ||
        clean.contains('six') ||
        clean.contains('evening'))
      return 'Dear 6 PM';
    if (clean.contains('8') ||
        clean.contains('eight') ||
        clean.contains('night'))
      return 'Dear 8 PM';
    return raw.trim();
  }

  @visibleForTesting
  List<GeminiScannedItem> parseExtractedTextForTesting(
    String text,
    String defaultSeller, [
    ScanContext scanContext = ScanContext.booking,
  ]) => _parseExtractedText(text, defaultSeller, scanContext);

  List<GeminiScannedItem> _parseExtractedText(
    String text,
    String defaultSeller, [
    ScanContext scanContext = ScanContext.booking,
  ]) {
    // 1. Try parsing JSON format for wholesale vouchers
    if (scanContext == ScanContext.voucher ||
        text.contains('"baseRange"') ||
        text.contains('"prefixes"') ||
        text.contains('"sections"')) {
      try {
        String jsonStr = text.trim();
        final jsonMatch = RegExp(
          r'```(?:json)?\s*([\s\S]*?)\s*```',
        ).firstMatch(text);
        if (jsonMatch != null) {
          jsonStr = jsonMatch.group(1)!.trim();
        }

        dynamic decoded;
        try {
          decoded = jsonDecode(jsonStr);
        } catch (_) {
          final startIndex = jsonStr.indexOf(RegExp(r'[\[\{]'));
          final lastBracket = jsonStr.lastIndexOf(']');
          final lastBrace = jsonStr.lastIndexOf('}');
          final endIndex = lastBracket > lastBrace ? lastBracket : lastBrace;
          if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
            decoded = jsonDecode(jsonStr.substring(startIndex, endIndex + 1));
          }
        }

        List<dynamic> sections = [];
        if (decoded is Map) {
          final detectedShift = _normalizeShift(
            decoded['detectedShift']?.toString(),
          );
          if (detectedShift != null) {
            lastDetectedShift = detectedShift;
          }
          final party = decoded['partyName']?.toString();
          if (party != null && party.trim().isNotEmpty) {
            lastDetectedParty = party.trim();
          }
          final confusions =
              decoded['aiConfusions'] ??
              decoded['doubts'] ??
              decoded['confusions'];
          if (confusions is List) {
            lastAiConfusions = confusions
                .map((c) => c.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
          final sec =
              decoded['sections'] ?? decoded['items'] ?? decoded['blocks'];
          if (sec is List) {
            sections = sec;
          }
        } else if (decoded is List) {
          sections = decoded;
        }

        if (sections.isNotEmpty) {
          final List<GeminiScannedItem> jsonItems = [];
          for (final block in sections) {
            if (block is Map) {
              final ser = block['series']?.toString() ?? '12';
              final baseRange = block['baseRange']?.toString() ?? '';
              final rawShift =
                  block['drawShift']?.toString() ?? block['shift']?.toString();
              final blockShift = _normalizeShift(rawShift) ?? lastDetectedShift;
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
              '✅ [JSON VOUCHER PARSE SUCCESS] Extracted ${jsonItems.length} ranges from ${sections.length} blocks with ${lastAiConfusions.length} AI confusions flagged',
            );
            return jsonItems;
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
            final rawConfusions = decoded['aiConfusions'];
            if (rawConfusions is List) {
              lastAiConfusions = rawConfusions
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
            } else {
              lastAiConfusions = [];
            }
            final rawItems = decoded['items'];
            if (rawItems is List) {
              itemsList = rawItems;
            }
          } else if (decoded is List) {
            itemsList = decoded;
            lastAiConfusions = [];
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
                    it['fromTicket']
                        ?.toString()
                        .replaceAll(RegExp(r'\D'), '')
                        .padLeft(5, '0') ??
                    '';
                final tTkt =
                    it['toTicket']
                        ?.toString()
                        .replaceAll(RegExp(r'\D'), '')
                        .padLeft(5, '0') ??
                    fTkt;
                // ⚡ ALWAYS recalculate quantity from ticket range (fromTicket to toTicket).
                // NEVER trust handwritten/AI-parsed quantity — it is often wrong on parchas.
                int q = 1;
                if (fTkt.isNotEmpty && tTkt.isNotEmpty) {
                  final fNum = int.tryParse(fTkt);
                  final tNum = int.tryParse(tTkt);
                  if (fNum != null && tNum != null && tNum >= fNum) {
                    q = (tNum - fNum) + 1;
                  }
                }
                if (q <= 0) q = 1;

                final tNo =
                    it['ticketNo']?.toString() ??
                    (q > 1 ? '$fTkt - $tTkt' : fTkt);

                final rawDoubt = it['aiDoubt']?.toString().trim();
                final doubt =
                    (rawDoubt != null &&
                        rawDoubt.isNotEmpty &&
                        rawDoubt.toLowerCase() != 'null')
                    ? rawDoubt
                    : null;

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
                      drawShift: lastDetectedShift,
                      aiDoubt: doubt,
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

    // 3. Try parsing JSON array of booking items or strings
    try {
      final decodedJson = jsonDecode(text.trim());
      if (decodedJson is List) {
        final List<GeminiScannedItem> parsedList = [];
        for (final item in decodedJson) {
          if (item is Map) {
            final s = item['series']?.toString() ?? '12';
            final tNo = item['ticketNo']?.toString() ?? item['ticket']?.toString() ?? '';
            if (tNo.isNotEmpty) {
              parsedList.add(GeminiScannedItem(
                series: s,
                ticketNo: tNo,
                amount: (item['amount'] as num?)?.toDouble() ?? 0.0,
                sellerName: defaultSeller,
              ));
            }
          } else if (item is String) {
            final cleanStr = item.trim().replaceAll(RegExp(r'''^[\["\'`\s]+|[\]",\'`\s]+$'''), '');
            final eqParts = cleanStr.split('=');
            if (eqParts.length == 2) {
              parsedList.add(GeminiScannedItem(
                series: eqParts[0].trim(),
                ticketNo: eqParts[1].trim(),
                amount: 0.0,
                sellerName: defaultSeller,
              ));
            }
          }
        }
        if (parsedList.isNotEmpty) return parsedList;
      }
    } catch (_) {}

    final List<GeminiScannedItem> items = [];
    final lines = text.split(RegExp(r'\r?\n'));
    String currentSeries = '';

    for (final line in lines) {
      String l = line.trim().replaceAll(RegExp(r'''^[\["\'`\s]+|[\]",\'`\s]+$'''), '');
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
        r'^(?:SERIES|SR|SER|SERI)?\s*[\(\[\{]?\s*([0-9]{1,4}\s*[A-Za-z]{0,8}|[A-Za-z]{1,4}\s*[0-9]{1,4})\s*[\)\]\}]?\s*[-:,\/=\s._~|*xX#@+]*$',
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
        r'(?:^|[\s,;])(?:([0-9]{1,4}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,4})\s*[-:,\/=\s._~|*xX#@+]+)?(\d{5})\s*[-~to]+\s*(\d{5})(?:\s*[-:,\/=\s._~|*xX#@+]+\s*([0-9]{1,4}[A-Za-z]{0,4}))?',
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
                aiDoubt: current.aiDoubt,
              ),
            );
          }
          i++;
          continue;
        } else if (current.toTicket.length > 5 &&
            current.fromTicket.length == 5) {
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
            next.sellerName != current.sellerName ||
            next.aiDoubt != current.aiDoubt) {
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
            aiDoubt: current.aiDoubt,
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
