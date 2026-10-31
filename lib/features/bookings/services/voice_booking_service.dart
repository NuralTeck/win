import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../core/database/database_service.dart';
import 'gemini_scanner_service.dart';

class VoiceParsedTicketResult {
  final List<GeminiScannedItem> tickets;
  final String? detectedShift;
  final DateTime? detectedDate;
  final String? detectedSeller;
  final String rawSpokenText;
  final bool isOnlineAiUsed;

  VoiceParsedTicketResult({
    required this.tickets,
    this.detectedShift,
    this.detectedDate,
    this.detectedSeller,
    required this.rawSpokenText,
    required this.isOnlineAiUsed,
  });
}

class VoiceBookingService {
  VoiceBookingService._();
  static final VoiceBookingService instance = VoiceBookingService._();

  Process? _activeProcess;

  /// Stop any running listening process
  void stopListening() {
    try {
      _activeProcess?.kill();
      _activeProcess = null;
    } catch (_) {}
  }

  /// 100% Offline Speech-to-Text via Windows Native Speech API
  Future<String?> listenFromMicrophoneOffline({int timeoutSeconds = 8}) async {
    try {
      final scriptDir = Directory(p.join(Directory.current.path, 'scripts'));
      final scriptPath = p.join(scriptDir.path, 'win_voice_listen.ps1');

      if (!await File(scriptPath).exists()) {
        debugPrint('⚠️ Voice script not found at $scriptPath');
        return null;
      }

      final tempDir = await getTemporaryDirectory();
      final outputFile = p.join(tempDir.path, 'voice_result_${DateTime.now().millisecondsSinceEpoch}.txt');

      final process = await Process.start('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptPath,
        '-TimeoutSeconds',
        timeoutSeconds.toString(),
        '-OutputFile',
        outputFile,
      ]);
      _activeProcess = process;

      final stdoutOutput = await process.stdout.transform(utf8.decoder).join();
      await process.exitCode;
      _activeProcess = null;

      // Check output file first
      final f = File(outputFile);
      if (await f.exists()) {
        final text = await f.readAsString();
        await f.delete().catchError((_) => f);
        if (text.trim().isNotEmpty) return text.trim();
      }

      // Check stdout match
      if (stdoutOutput.contains('RECOGNIZED:')) {
        final match = RegExp(r'RECOGNIZED:\s*(.*)', caseSensitive: false).firstMatch(stdoutOutput);
        if (match != null && match.group(1) != null) {
          final res = match.group(1)!.trim();
          if (res.isNotEmpty && res != 'NO_SPEECH_DETECTED') return res;
        }
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error in listenFromMicrophoneOffline: $e');
      return null;
    }
  }

  /// Parse spoken text into structured numbers (Respects selected Bot Mode: Offline, Online, or Auto-Hybrid)
  Future<VoiceParsedTicketResult> parseSpokenTicketText({
    required String spokenText,
    String defaultSeries = '12',
    String defaultSeller = 'Walk-in Customer',
    double defaultPrice = 45.0,
    String? overrideMode, // 'offline', 'online', 'auto'
  }) async {
    final mode = overrideMode ?? await DatabaseService.instance.getBotMode();
    final apiKey = await DatabaseService.instance.getGeminiApiKey();

    if (mode != 'offline' && apiKey != null && apiKey.trim().isNotEmpty) {
      try {
        final onlineResult = await _parseOnlineWithGemini(
          spokenText: spokenText,
          apiKey: apiKey.trim(),
          defaultSeries: defaultSeries,
          defaultSeller: defaultSeller,
        );
        if (onlineResult != null && onlineResult.tickets.isNotEmpty) {
          return onlineResult;
        }
      } catch (e) {
        debugPrint('⚠️ Online Gemini Voice parser failed, falling back to Offline NLP parser: $e');
      }
    }

    // High-Accuracy Offline NLP Regex Parser
    return _parseOfflineWithRuleEngine(
      spokenText: spokenText,
      defaultSeries: defaultSeries,
      defaultSeller: defaultSeller,
      defaultPrice: defaultPrice,
    );
  }

  /// 🌐 ONLINE AI NLP PARSER: Uses Gemini to understand complex Hindi/Hinglish spoken ticket orders
  Future<VoiceParsedTicketResult?> _parseOnlineWithGemini({
    required String spokenText,
    required String apiKey,
    required String defaultSeries,
    required String defaultSeller,
  }) async {
    const systemPrompt = '''
You are an expert NLP voice parser for an Indian Lottery Ticket Booking Counter.
Extract all ticket numbers, series, draw shifts, dates, and customer names from spoken Hindi/Hinglish/English speech.

Rules:
1. Every ticket number MUST be a 5-DIGIT number (e.g. 56185, 46185, 04560).
2. Spoken ranges like "56581 se 56585", "56581 to 56585", or "56576 dash 81" MUST be expanded into all individual 5-digit tickets.
3. Series is a 2 to 3 digit number (e.g. 12, 24, 36, 100).
4. Shift is one of: "Dear 1 PM", "Dear 6 PM", "Dear 8 PM".
5. Return JSON format ONLY with this exact structure:
{
  "detectedShift": "Dear 1 PM",
  "detectedSeller": "Ramesh",
  "tickets": [
    {"series": "12", "ticketNo": "56581", "quantity": 1, "amount": 45.0},
    {"series": "12", "ticketNo": "56582", "quantity": 1, "amount": 45.0}
  ]
}
''';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': systemPrompt},
            {'text': 'User Spoken Voice Input:\n"$spokenText"'}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'responseMimeType': 'application/json',
      }
    });

    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key=$apiKey');
    final response = await http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: body,
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final rawJsonText = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
      if (rawJsonText.isNotEmpty) {
        final parsed = jsonDecode(rawJsonText);
        final shift = parsed['detectedShift'] as String?;
        final seller = (parsed['detectedSeller'] as String?) ?? defaultSeller;
        final list = (parsed['tickets'] as List?) ?? [];

        final tickets = list.map<GeminiScannedItem>((t) {
          return GeminiScannedItem(
            series: (t['series'] ?? defaultSeries).toString(),
            ticketNo: (t['ticketNo'] ?? '').toString(),
            amount: (t['amount'] as num?)?.toDouble() ?? 45.0,
            quantity: (t['quantity'] as num?)?.toInt() ?? 1,
            sellerName: seller,
          );
        }).where((t) => t.ticketNo.length == 5).toList();

        return VoiceParsedTicketResult(
          tickets: tickets,
          detectedShift: shift,
          detectedSeller: seller,
          rawSpokenText: spokenText,
          isOnlineAiUsed: true,
        );
      }
    }
    return null;
  }

  /// 💻 OFFLINE RULE-BASED NLP PARSER: 100% Pure local logic
  VoiceParsedTicketResult _parseOfflineWithRuleEngine({
    required String spokenText,
    required String defaultSeries,
    required String defaultSeller,
    required double defaultPrice,
  }) {
    String currentSeries = defaultSeries;
    String detectedSeller = defaultSeller;
    String? detectedShift;
    final List<GeminiScannedItem> items = [];

    // Normalize Hindi/English numbers and separator words
    String clean = spokenText.toLowerCase();
    clean = clean.replaceAll(RegExp(r'\b(?:se|to|tak|dash|minus|thru|through)\b'), '-');
    clean = clean.replaceAll(RegExp(r'\b(?:series|sereis|sere|sery|sr)\b'), 'series');
    clean = clean.replaceAll(RegExp(r'\b(?:number|tkt|ticket|tickets|tick|no|nos)\b'), '');

    // Check Shift
    if (RegExp(r'\b(?:1\s*pm|1\s*baje|morning|1:00\s*pm|dear\s*1)\b').hasMatch(clean)) {
      detectedShift = 'Dear 1 PM';
    } else if (RegExp(r'\b(?:6\s*pm|6\s*baje|day|6:00\s*pm|dear\s*6)\b').hasMatch(clean)) {
      detectedShift = 'Dear 6 PM';
    } else if (RegExp(r'\b(?:8\s*pm|8\s*baje|night|evening|8:00\s*pm|dear\s*8)\b').hasMatch(clean)) {
      detectedShift = 'Dear 8 PM';
    }

    // Check Customer/Seller Name
    final sellerMatch = RegExp(r'\b(?:customer|party|seller|name|party\s*name)\s*[:=-]?\s*([a-zA-Z\s]{2,20})\b').firstMatch(clean);
    if (sellerMatch != null && sellerMatch.group(1) != null) {
      detectedSeller = sellerMatch.group(1)!.trim();
    }

    // Check Series Tag (Supports both "series 12" and "12 series" / "100 series")
    final seriesMatch = RegExp(r'(?:\bseries\s*(\d{1,3})\b|\b(\d{1,3})\s*series\b)').firstMatch(clean);
    if (seriesMatch != null) {
      currentSeries = (seriesMatch.group(1) ?? seriesMatch.group(2))!;
    }

    // Match Ranges e.g. "56581-56585" or "56581-85" or "56581-5"
    final rangeMatches = RegExp(r'\b(\d{5})\s*-\s*(\d{1,5})\b').allMatches(clean);
    final Set<String> rangeProcessedTickets = {};

    for (final rm in rangeMatches) {
      final startStr = rm.group(1)!;
      final endStr = rm.group(2)!;
      final startNum = int.tryParse(startStr);
      int? endNum;

      if (endStr.length == 5) {
        endNum = int.tryParse(endStr);
      } else if (endStr.length == 2) {
        final prefix = startStr.substring(0, 3);
        endNum = int.tryParse('$prefix$endStr');
      } else if (endStr.length == 1) {
        final prefix = startStr.substring(0, 4);
        endNum = int.tryParse('$prefix$endStr');
      }

      if (startNum != null && endNum != null && endNum >= startNum && (endNum - startNum) <= 100) {
        for (int i = startNum; i <= endNum; i++) {
          final tNo = i.toString().padLeft(5, '0');
          rangeProcessedTickets.add(tNo);
          items.add(GeminiScannedItem(
            series: currentSeries,
            ticketNo: tNo,
            amount: defaultPrice,
            quantity: 1,
            sellerName: detectedSeller,
          ));
        }
      }
    }

    // Match Individual 5-Digit Numbers
    final single5Digits = RegExp(r'\b\d{5}\b').allMatches(clean);
    for (final sm in single5Digits) {
      final tNo = sm.group(0)!;
      if (!rangeProcessedTickets.contains(tNo)) {
        items.add(GeminiScannedItem(
          series: currentSeries,
          ticketNo: tNo,
          amount: defaultPrice,
          quantity: 1,
          sellerName: detectedSeller,
        ));
      }
    }

    return VoiceParsedTicketResult(
      tickets: items,
      detectedShift: detectedShift,
      detectedSeller: detectedSeller,
      rawSpokenText: spokenText,
      isOnlineAiUsed: false,
    );
  }
}
