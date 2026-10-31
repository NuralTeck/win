import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_service.dart';
import '../../operations/models/lottery_sambad_result_model.dart';

class TicketCoreAIService {
  TicketCoreAIService._internal();
  static final TicketCoreAIService instance = TicketCoreAIService._internal();

  // Custom AI Training Rules stored in memory
  final List<Map<String, String>> _customRules = [
    {
      'rule': 'Default Prize Hierarchy',
      'detail': '1st Prize (₹1 Crore), 2nd (₹9,000 / 10K), 3rd (₹500), 4th (₹250), 5th (₹120)'
    },
    {
      'rule': 'Commission Policy',
      'detail': 'Default seller commission is calculated based on ticket series setup'
    },
  ];

  // Optional Gemini API Key
  String _geminiApiKey = '';

  String get geminiApiKey => _geminiApiKey;
  List<Map<String, String>> get customRules => List.unmodifiable(_customRules);

  void setGeminiApiKey(String key) {
    _geminiApiKey = key.trim();
    debugPrint('🤖 [AI SERVICE] Updated Gemini API Key (Length: ${_geminiApiKey.length})');
  }

  void addCustomTrainingRule(String ruleName, String detail) {
    if (ruleName.trim().isNotEmpty && detail.trim().isNotEmpty) {
      _customRules.add({
        'rule': ruleName.trim(),
        'detail': detail.trim(),
      });
      debugPrint('🤖 [AI SERVICE] Added new training rule: "$ruleName"');
    }
  }

  void removeCustomTrainingRule(int index) {
    if (index >= 0 && index < _customRules.length) {
      final removed = _customRules.removeAt(index);
      debugPrint('🤖 [AI SERVICE] Removed training rule: "${removed['rule']}"');
    }
  }

  /// Generative Google Gemini 1.5 Flash AI Result Sheet Parser
  Future<LotterySambadResultModel?> parseSambadResultWithGemini(
    String rawText, {
    Uint8List? fileBytes,
    String? mimeType,
    String drawName = 'DEAR MORNING 1 PM',
  }) async {
    if (_geminiApiKey.isEmpty) {
      debugPrint('🤖 [GEMINI AI] No API key configured. Using local offline parser.');
      return null;
    }

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key=$_geminiApiKey',
      );

      final prompt = '''
You are an expert Nagaland State Lotteries result sheet parser.
Extract the winning lottery numbers from the provided document into strict JSON format with this exact schema:

{
  "drawName": "$drawName",
  "firstPrize": "82D 41997",
  "consolationPrize": "41997",
  "secondPrizeNumbers": ["07237", "12280", "23911", "31563", "54563", "69937", "77437", "82629", "90646", "93384"],
  "thirdPrizeNumbers": ["0532", "0733", "1270", "4125", "5195", "5801", "6430", "7646", "8709", "9842"],
  "fourthPrizeNumbers": ["0563", "1417", "1552", "1763", "2409", "4740", "5185", "6907", "9161", "9389"],
  "fifthPrizeNumbers": ["0043", "0414"]
}

Rules:
1. Ignore all seller pictures, promotional ads, and "4629 CROREPATIS" graphics.
2. 1st prize must include series and 5-digit number (e.g., 82D 41997).
3. 2nd prize must contain exactly 10 5-digit numbers.
4. 3rd prize must contain exactly 10 4-digit numbers.
5. 4th prize must contain exactly 10 4-digit numbers.
6. 5th prize must contain 100 4-digit numbers.
7. Return ONLY valid JSON with no markdown formatting.

Text:
$rawText
''';

      final List<Map<String, dynamic>> parts = [
        {"text": prompt}
      ];

      if (fileBytes != null && fileBytes.isNotEmpty) {
        final b64 = base64Encode(fileBytes);
        parts.add({
          "inlineData": {
            "mimeType": mimeType ?? 'application/pdf',
            "data": b64,
          }
        });
      }

      final client = HttpClient();
      final request = await client.postUrl(url);
      request.headers.contentType = ContentType.json;

      final body = jsonEncode({
        "contents": [
          {
            "parts": parts,
          }
        ],
        "generationConfig": {
          "temperature": 0.1,
          "responseMimeType": "application/json",
        }
      });

      request.write(body);
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseBody);
        final jsonText = decoded['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
        final parsedJson = jsonDecode(jsonText);

        return LotterySambadResultModel(
          drawId: DateTime.now().millisecondsSinceEpoch.toString(),
          drawName: parsedJson['drawName'] ?? drawName,
          drawDateStr: DateTime.now().toString().split(' ').first,
          drawTimeStr: '01:00 PM',
          firstPrize: parsedJson['firstPrize'] ?? '',
          consolationPrize: parsedJson['consolationPrize'] ?? '',
          secondPrizeNumbers: List<String>.from(parsedJson['secondPrizeNumbers'] ?? []),
          thirdPrizeNumbers: List<String>.from(parsedJson['thirdPrizeNumbers'] ?? []),
          fourthPrizeNumbers: List<String>.from(parsedJson['fourthPrizeNumbers'] ?? []),
          fifthPrizeNumbers: List<String>.from(parsedJson['fifthPrizeNumbers'] ?? []),
          publishedAt: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('🤖 [GEMINI AI ERROR] $e');
    }
    return null;
  }

  /// Primary AI Assistant Query Processor (100% Native Dart Offline Query Engine)
  Future<String> processQuery(String userQuery) async {
    final query = userQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return 'Hello! I am your TicketCore AI Assistant. How can I assist you with sales, winner tickets, or Sambad results today?';
    }

    try {
      // 1. Sales & Revenue Analytics Query
      if (query.contains('sale') || query.contains('revenue') || query.contains('total sold') || query.contains('bikri')) {
        final sales = await DatabaseService.instance.getTicketSales();
        double totalSalesAmount = 0.0;
        int totalTicketsSold = 0;
        for (var s in sales) {
          totalSalesAmount += s.totalAmount;
          totalTicketsSold += s.quantity;
        }
        final todayStr = DateFormat('dd/MM/yyyy').format(DateTime.now());
        return '📊 **TicketCore Sales Intelligence**\n\n'
            '• **Total Recorded Sales**: ₹${totalSalesAmount.toStringAsFixed(0)}\n'
            '• **Total Tickets Sold**: $totalTicketsSold tickets\n'
            '• **Total Transactions**: ${sales.length} receipts\n'
            '• **Database Status**: Saved in `opscore_pro.db` as of $todayStr.\n\n'
            '_Tip: You can ask "Who is the top seller?" or "Check ticket winner"._';
      }

      // 2. Winner Ticket Lookup Query
      if (query.contains('winner') || query.contains('ticket') || query.contains('check') || query.contains('inam')) {
        final numbersInQuery = RegExp(r'\b[0-9]{4,5}\b').allMatches(query).map((m) => m.group(0)!).toList();
        final results = await DatabaseService.instance.getLotteryResults();

        if (numbersInQuery.isNotEmpty) {
          final searchNum = numbersInQuery.first;
          bool foundWinner = false;
          String winnerInfo = '';

          for (var r in results) {
            final firstP = (r['firstPrize'] as String? ?? '');
            final secondP = (r['secondPrizeNumbers'] as String? ?? '').split(',');
            final thirdP = (r['thirdPrizeNumbers'] as String? ?? '').split(',');
            final fourthP = (r['fourthPrizeNumbers'] as String? ?? '').split(',');
            final fifthP = (r['fifthPrizeNumbers'] as String? ?? '').split(',');
            final drawName = r['drawName'] as String? ?? '';
            final drawDate = r['drawDateStr'] as String? ?? '';

            if (firstP.contains(searchNum)) {
              foundWinner = true;
              winnerInfo = '🏆 **JACKPOT WINNER!**\nTicket `$searchNum` matches 1st Prize (`$firstP`) in **$drawName** ($drawDate)!';
              break;
            } else if (secondP.contains(searchNum)) {
              foundWinner = true;
              winnerInfo = '🥈 **2nd PRIZE WINNER (₹9,000)!**\nTicket `$searchNum` matched in **$drawName** ($drawDate)!';
              break;
            } else if (thirdP.contains(searchNum)) {
              foundWinner = true;
              winnerInfo = '🥉 **3rd PRIZE WINNER (₹500)!**\nTicket `$searchNum` matched in **$drawName** ($drawDate)!';
              break;
            } else if (fourthP.contains(searchNum)) {
              foundWinner = true;
              winnerInfo = '🎖️ **4th PRIZE WINNER (₹250)!**\nTicket `$searchNum` matched in **$drawName** ($drawDate)!';
              break;
            } else if (fifthP.contains(searchNum)) {
              foundWinner = true;
              winnerInfo = '🎉 **5th PRIZE WINNER (₹120)!**\nTicket `$searchNum` matched in **$drawName** ($drawDate)!';
              break;
            }
          }

          if (foundWinner) {
            return winnerInfo;
          } else {
            return '🔍 **Winner Status**: Ticket number `$searchNum` was checked against all ${results.length} published draw results in database, but did not match a winning prize.';
          }
        } else {
          return '🔍 **Ticket Winner Checker**: Please include a 4-digit or 5-digit ticket number in your message (e.g., *"Check ticket 28311"* or *"Did 41997 win?"*).';
        }
      }

      // 3. Seller Performance & Customers Query
      if (query.contains('seller') || query.contains('customer') || query.contains('agent')) {
        final sellers = await DatabaseService.instance.getSellerCustomers();
        return '👥 **Seller & Customer Network**\n\n'
            '• **Registered Active Sellers**: ${sellers.length} seller accounts\n'
            '• **Access Keys Active**: ${sellers.map((s) => s.accessKey).take(3).join(', ')}...\n'
            '• All seller ledgers and transaction commissions are synchronized with local database `opscore_pro.db`.';
      }

      // 4. Published Results & Sambad Queries
      if (query.contains('result') || query.contains('sambad') || query.contains('draw') || query.contains('pdf')) {
        final results = await DatabaseService.instance.getLotteryResults();
        if (results.isEmpty) {
          return '📜 **Published Results Engine**: No published draw results found in database yet. You can upload a Sambad PDF or enter results in the Result Entry tab.';
        }
        final latest = results.first;
        final drawName = latest['drawName'] as String? ?? '';
        final drawDate = latest['drawDateStr'] as String? ?? '';
        final firstP = latest['firstPrize'] as String? ?? '';
        final winners = latest['verifiedWinnersCount'] as int? ?? 0;
        final payout = (latest['totalPayoutAmount'] as num? ?? 0.0).toDouble();

        return '📜 **Latest Official Result**: **$drawName** ($drawDate)\n\n'
            '• **1st Prize Winner**: `$firstP`\n'
            '• **Verified Sold Winners**: $winners tickets matched\n'
            '• **Total Prize Payout**: ₹${payout.toStringAsFixed(0)}\n'
            '• Total ${results.length} published draw sheets saved in database.';
      }

      // 5. Check Custom Rules
      for (var rule in _customRules) {
        if (query.contains(rule['rule']!.toLowerCase())) {
          return '🎓 **AI Trained Rule**: **${rule['rule']}**\n\n${rule['detail']}';
        }
      }

      // Default Intelligent Assistance Response
      return '🤖 **TicketCore Intelligence Assistant**\n\n'
          'I am your local offline AI assistant. You can ask me:\n'
          '1. *"Show today\'s total sales"* 📊\n'
          '2. *"Check winner ticket 28311"* 🏆\n'
          '3. *"Show latest Sambad draw result"* 📜\n'
          '4. *"Show seller network summary"* 👥\n\n'
          '_All queries are processed locally in 0ms with zero internet or API costs._';
    } catch (e) {
      debugPrint('Error in TicketCoreAIService: $e');
      return '🤖 Unable to process query: $e';
    }
  }
}
