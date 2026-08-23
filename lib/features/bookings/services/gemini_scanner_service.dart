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
  double amount;
  int quantity;
  String sellerName;

  GeminiScannedItem({
    required this.series,
    required this.ticketNo,
    required this.amount,
    this.quantity = 1,
    this.sellerName = 'Walk-in Customer',
  });
}

class GeminiScannerService {
  GeminiScannerService._();
  static final GeminiScannerService instance = GeminiScannerService._();

  Future<String?> getActiveApiKey() async {
    return await DatabaseService.instance.getGeminiApiKey();
  }

  /// Scan image bytes and extract lottery tickets (Online with Gemini or 100% Offline with Local OCR)
  Future<List<GeminiScannedItem>> scanImage({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
    String defaultSeller = 'Walk-in Customer',
  }) async {
    final apiKey = await getActiveApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      debugPrint('ℹ️ [OFFLINE OCR MODE] No Gemini key found. Using 100% Pure Local Offline OCR Engine...');
      return await _scanOfflineWithLocalEngine(imageBytes, defaultSeller);
    }

    final base64Image = base64Encode(imageBytes);
    const prompt = '''
You are an expert OCR parser for Indian lottery slips (parchas).
Carefully analyze the lottery parcha/slip image and extract tickets according to these strict rules:

CRITICAL EXTRACTION RULES:
1. Ticket Numbers: MUST ALWAYS be a 5-DIGIT NUMBER (e.g., 45385, 28311, 65385, 01234). Ignore any number that is not 5 digits.
2. Series: MUST be a 2-DIGIT or 3-DIGIT series (e.g., 12, 24, 36, 100, 84, 84A, 92B, 123).
   - If a series is mentioned at the top or header (e.g., "24 सीरीज", "12"), apply that series to all following 5-digit numbers in that column.
3. IGNORE ALL OTHER NOISE: Ignore random names, signatures, dates, greetings, mobile numbers, total calculations, and decorative text.
4. Reading Order: Read strictly COLUMN-BY-COLUMN from top to bottom (Left column first, then second column, etc.).
5. Output Format: Output each extracted ticket line by line in this exact format:
   <series>=<5-digit-ticket>
   
Example Output:
24=45385
24=55385
12=69476
100=28311

Output ONLY the ticket lines. No markdown formatting, no explanations.
''';

    final requestBody = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inlineData': {
                'mimeType': mimeType,
                'data': base64Image,
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'maxOutputTokens': 4096,
      }
    });

    final candidateModels = [
      'gemini-flash-lite-latest',
      'gemini-3.5-flash-lite',
      'gemini-3.5-flash',
      'gemini-3-flash-preview',
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
            final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
            debugPrint('📸 [GEMINI SCAN RESULT RAW ($modelName)]:\n$text');
            return _parseExtractedText(text, defaultSeller);
          } else {
            lastError = 'HTTP ${response.statusCode}: ${response.body}';
            if ((response.statusCode == 503 || response.statusCode == 429) && attempt == 1) {
              debugPrint('⚠️ [GEMINI BUSY] $modelName returned ${response.statusCode}. Retrying in 1.5s...');
              await Future.delayed(const Duration(milliseconds: 1500));
              continue;
            }
            debugPrint('⚠️ [GEMINI SCAN NOTE] $modelName returned $lastError. Trying fallback model...');
            break;
          }
        } catch (e) {
          lastError = e.toString();
          debugPrint('⚠️ [GEMINI SCAN EXCEPTION] $modelName: $e');
          break;
        }
      }
    }

    debugPrint('ℹ️ [OFFLINE FALLBACK] Cloud scan unavailable ($lastError). Using 100% Local Offline OCR Engine...');
    return await _scanOfflineWithLocalEngine(imageBytes, defaultSeller);
  }

  /// 100% Pure Offline OCR Engine running locally on Windows
  Future<List<GeminiScannedItem>> _scanOfflineWithLocalEngine(Uint8List imageBytes, String defaultSeller) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempImagePath = p.join(tempDir.path, 'temp_ocr_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(tempImagePath).writeAsBytes(imageBytes);

      final currentDir = Directory.current.path;
      final nodeExe = File(p.join(currentDir, 'whatsapp_engine', 'node.exe'));
      final scriptPath = File(p.join(currentDir, 'whatsapp_engine', 'ocr_offline.js'));

      String execPath = 'node';
      if (nodeExe.existsSync()) {
        execPath = nodeExe.path;
      }

      if (scriptPath.existsSync()) {
        final result = await Process.run(
          execPath,
          [scriptPath.path, tempImagePath],
          workingDirectory: p.join(currentDir, 'whatsapp_engine'),
        );

        if (result.exitCode == 0 && result.stdout != null) {
          final String outStr = result.stdout.toString().trim();
          debugPrint('📸 [LOCAL OFFLINE OCR RESULT]: $outStr');
          try {
            final dynamic parsed = jsonDecode(outStr);
            if (parsed is List) {
              final List<GeminiScannedItem> items = [];
              for (final item in parsed) {
                items.add(GeminiScannedItem(
                  series: item['series']?.toString() ?? '12',
                  ticketNo: item['ticketNo']?.toString() ?? '',
                  amount: (item['amount'] as num?)?.toDouble() ?? 0.0,
                  sellerName: defaultSeller,
                ));
              }
              try { await File(tempImagePath).delete(); } catch (_) {}
              return items;
            }
          } catch (jsonErr) {
            debugPrint('⚠️ [OFFLINE OCR JSON PARSE ERROR] $jsonErr');
          }
        } else {
          debugPrint('⚠️ [OFFLINE OCR PROCESS ERROR]: ${result.stderr}');
        }
      }
      try { await File(tempImagePath).delete(); } catch (_) {}
    } catch (e) {
      debugPrint('⚠️ [OFFLINE OCR EXCEPTION] $e');
    }
    return [];
  }

  List<GeminiScannedItem> _parseExtractedText(String text, String defaultSeller) {
    final List<GeminiScannedItem> items = [];
    final lines = text.split(RegExp(r'\r?\n'));
    String currentSeries = '';

    for (final line in lines) {
      final l = line.trim();
      if (l.isEmpty) {
        currentSeries = '';
        continue;
      }

      // Standalone Header
      final headerMatch = RegExp(
        r'^(?:SERIES|SR|SER|SERI)?\s*[\(\[\{]?\s*([0-9]{1,3}\s*[A-Za-z]{0,8}|[A-Za-z]{1,4}\s*[0-9]{1,3})\s*[\)\]\}]?\s*[-:,\/=\s._~|*xX#@+]*$',
        caseSensitive: false,
      ).firstMatch(l);

      if (headerMatch != null && l.length <= 15 && !RegExp(r'\d{5}').hasMatch(l)) {
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

        if (end2 >= start2 && end2 - start2 <= 200) {
          for (int i = start2; i <= end2; i++) {
            items.add(GeminiScannedItem(
              series: s.isNotEmpty ? s : '?',
              ticketNo: '$prefix${i.toString().padLeft(2, '0')}',
              amount: 0.0,
              sellerName: defaultSeller,
            ));
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
        items.add(GeminiScannedItem(
          series: s.isNotEmpty ? s : '?',
          ticketNo: tNo,
          amount: 0.0,
          sellerName: defaultSeller,
        ));
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
        items.add(GeminiScannedItem(
          series: s.isNotEmpty ? s : '?',
          ticketNo: tNo,
          amount: 0.0,
          sellerName: defaultSeller,
        ));
        currentSeries = s.isNotEmpty ? s : currentSeries;
        matchedLeading = true;
      }
      if (matchedLeading) continue;

      // Standalone 5-digit tickets
      final all5s = RegExp(r'\b\d{5}\b').allMatches(l);
      if (all5s.isNotEmpty) {
        for (final m in all5s) {
          items.add(GeminiScannedItem(
            series: currentSeries.isNotEmpty ? currentSeries : '?',
            ticketNo: m.group(0)!,
            amount: 0.0,
            sellerName: defaultSeller,
          ));
        }
      }
    }

    return items;
  }
}
