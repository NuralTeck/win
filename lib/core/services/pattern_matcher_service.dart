import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/database_service.dart';

/// Represents a dynamic regex pattern learned from operator feedback
class LearnedPattern {
  final int? id;
  final String patternName;
  final String regexPattern;
  final int seriesGroupIndex;
  final int ticketGroupIndex;
  final int qtyGroupIndex;
  final String? sampleText;
  final DateTime? createdAt;

  const LearnedPattern({
    this.id,
    required this.patternName,
    required this.regexPattern,
    this.seriesGroupIndex = 1,
    this.ticketGroupIndex = 2,
    this.qtyGroupIndex = 3,
    this.sampleText,
    this.createdAt,
  });

  factory LearnedPattern.fromMap(Map<String, dynamic> map) {
    return LearnedPattern(
      id: map['id'] is int ? map['id'] : int.tryParse(map['id']?.toString() ?? ''),
      patternName: map['pattern_name']?.toString() ?? 'Custom Pattern',
      regexPattern: map['regex_pattern']?.toString() ?? '',
      seriesGroupIndex: map['series_group_index'] is int ? map['series_group_index'] : (int.tryParse(map['series_group_index']?.toString() ?? '1') ?? 1),
      ticketGroupIndex: map['ticket_group_index'] is int ? map['ticket_group_index'] : (int.tryParse(map['ticket_group_index']?.toString() ?? '2') ?? 2),
      qtyGroupIndex: map['qty_group_index'] is int ? map['qty_group_index'] : (int.tryParse(map['qty_group_index']?.toString() ?? '3') ?? 3),
      sampleText: map['sample_text']?.toString(),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'pattern_name': patternName,
      'regex_pattern': regexPattern,
      'series_group_index': seriesGroupIndex,
      'ticket_group_index': ticketGroupIndex,
      'qty_group_index': qtyGroupIndex,
      'sample_text': sampleText,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    };
  }
}

/// Represents an unparsed raw message pending resolution
class UnparsedMessage {
  final int id;
  final String rawText;
  final String senderPhone;
  final String? senderName;
  final String status;
  final DateTime receivedAt;

  const UnparsedMessage({
    required this.id,
    required this.rawText,
    required this.senderPhone,
    this.senderName,
    required this.status,
    required this.receivedAt,
  });

  factory UnparsedMessage.fromMap(Map<String, dynamic> map) {
    return UnparsedMessage(
      id: map['id'] is int ? map['id'] : (int.tryParse(map['id']?.toString() ?? '0') ?? 0),
      rawText: (map['raw_text'] ?? map['raw_message'])?.toString() ?? '',
      senderPhone: (map['sender_phone'] ?? map['sender'])?.toString() ?? 'Unknown',
      senderName: (map['sender_name'])?.toString(),
      status: map['status']?.toString() ?? 'pending',
      receivedAt: map['received_at'] != null
          ? DateTime.tryParse(map['received_at'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Item parsed by pattern matcher
class ParsedTicketItem {
  final String series;
  final String ticketNo;
  final int quantity;

  const ParsedTicketItem({
    required this.series,
    required this.ticketNo,
    this.quantity = 1,
  });
}

/// High-performance Pattern Matcher & Dynamic Self-Learning Service (100% Offline SQLite)
class PatternMatcherService {
  PatternMatcherService._internal();
  static final PatternMatcherService instance = PatternMatcherService._internal();

  final List<LearnedPattern> _cachedPatterns = [];
  bool _isInitialized = false;

  final ValueNotifier<int> pendingUnparsedCountNotifier = ValueNotifier<int>(0);
  Timer? _pollingTimer;

  List<LearnedPattern> get cachedPatterns => List.unmodifiable(_cachedPatterns);

  /// Initialize and start background synchronization
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await loadLearnedPatterns();
    await refreshPendingCount();

    // Periodic poll for unparsed count every 30s
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      refreshPendingCount();
    });
  }

  void dispose() {
    _pollingTimer?.cancel();
  }

  /// Load all dynamic patterns from local SQLite
  Future<List<LearnedPattern>> loadLearnedPatterns() async {
    try {
      final db = await DatabaseService.instance.database;
      final res = await db.query(
        'learned_patterns',
        orderBy: 'created_at DESC',
      );

      final List<LearnedPattern> loaded = [];
      for (final row in res) {
        loaded.add(LearnedPattern.fromMap(row));
      }

      _cachedPatterns.clear();
      _cachedPatterns.addAll(loaded);
      debugPrint('🧠 [PATTERN MATCHER] Loaded ${_cachedPatterns.length} learned dynamic regex rule(s) from SQLite');
      return _cachedPatterns;
    } catch (e) {
      debugPrint('⚠️ [PATTERN MATCHER] SQLite query error: $e');
      return _cachedPatterns;
    }
  }

  /// Refresh pending unparsed messages badge count from SQLite
  Future<int> refreshPendingCount() async {
    try {
      final db = await DatabaseService.instance.database;
      final res = await db.rawQuery(
        "SELECT COUNT(*) as count FROM unparsed_messages WHERE status = 'pending'",
      );
      final count = (res.isNotEmpty ? (res.first['count'] as int? ?? 0) : 0);
      pendingUnparsedCountNotifier.value = count;
      return count;
    } catch (e) {
      return pendingUnparsedCountNotifier.value;
    }
  }

  /// Fetch all pending unparsed messages from SQLite
  Future<List<UnparsedMessage>> fetchPendingUnparsedMessages() async {
    try {
      final db = await DatabaseService.instance.database;
      final res = await db.query(
        'unparsed_messages',
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy: 'received_at DESC',
        limit: 50,
      );

      final List<UnparsedMessage> list = [];
      for (final r in res) {
        list.add(UnparsedMessage.fromMap(r));
      }
      pendingUnparsedCountNotifier.value = list.length;
      return list;
    } catch (e) {
      debugPrint('⚠️ Error fetching unparsed messages from SQLite: $e');
      return [];
    }
  }

  /// Strip letters from series e.g. "12c" -> "12", "12s" -> "12", "12se" -> "12", "83L" -> "83", "SR-36" -> "36"
  String cleanSeriesNumber(String rawSeries, {String fallback = '12'}) {
    final digits = rawSeries.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty && digits.length <= 4) {
      return digits;
    }
    return digits.isNotEmpty ? digits.substring(0, 3) : fallback;
  }

  /// Test or parse text using learned dynamic patterns
  List<ParsedTicketItem> parseWithLearnedPatterns(String text, {String defaultSeries = '12'}) {
    final items = <ParsedTicketItem>[];
    final lines = text.split(RegExp(r'[\r\n]+'));

    for (final pattern in _cachedPatterns) {
      try {
        final regex = RegExp(pattern.regexPattern, caseSensitive: false, multiLine: true);
        for (final line in lines) {
          final l = line.trim();
          if (l.isEmpty) continue;

          final match = regex.firstMatch(l);
          if (match != null) {
            String s = defaultSeries;
            if (pattern.seriesGroupIndex > 0 && match.groupCount >= pattern.seriesGroupIndex) {
              final rawS = match.group(pattern.seriesGroupIndex);
              if (rawS != null && rawS.isNotEmpty) {
                s = cleanSeriesNumber(rawS, fallback: defaultSeries);
              }
            }

            String tNo = '';
            if (pattern.ticketGroupIndex > 0 && match.groupCount >= pattern.ticketGroupIndex) {
              tNo = match.group(pattern.ticketGroupIndex) ?? '';
            }

            int qty = 1;
            if (pattern.qtyGroupIndex > 0 && match.groupCount >= pattern.qtyGroupIndex) {
              final rawQty = match.group(pattern.qtyGroupIndex);
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
            }
          }
        }
        if (items.isNotEmpty) {
          return items;
        }
      } catch (e) {
        debugPrint('⚠️ Invalid Regex in Pattern #${pattern.id}: $e');
      }
    }
    return items;
  }

  /// Save new learned pattern to SQLite and memory cache
  Future<bool> saveLearnedPattern(LearnedPattern pattern) async {
    try {
      final db = await DatabaseService.instance.database;
      final id = await db.insert('learned_patterns', pattern.toMap());
      final newPattern = LearnedPattern(
        id: id,
        patternName: pattern.patternName,
        regexPattern: pattern.regexPattern,
        seriesGroupIndex: pattern.seriesGroupIndex,
        ticketGroupIndex: pattern.ticketGroupIndex,
        qtyGroupIndex: pattern.qtyGroupIndex,
        sampleText: pattern.sampleText,
        createdAt: DateTime.now(),
      );
      _cachedPatterns.insert(0, newPattern);
      debugPrint('✅ [PATTERN MATCHER] Saved new pattern "${newPattern.patternName}" (ID: $id) to local SQLite');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to save learned pattern to SQLite: $e');
      return false;
    }
  }

  /// Mark unparsed message as resolved or ignored in SQLite
  Future<bool> updateUnparsedStatus(int id, {String status = 'resolved'}) async {
    try {
      final db = await DatabaseService.instance.database;
      await db.update(
        'unparsed_messages',
        {
          'status': status,
          'resolved_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await refreshPendingCount();
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to update unparsed message status in SQLite: $e');
      return false;
    }
  }

  /// Dismiss / Clear all pending unparsed messages in batch in SQLite
  Future<bool> clearAllPendingUnparsedMessages() async {
    try {
      final db = await DatabaseService.instance.database;
      await db.update(
        'unparsed_messages',
        {
          'status': 'ignored',
          'resolved_at': DateTime.now().toIso8601String(),
        },
        where: 'status = ?',
        whereArgs: ['pending'],
      );

      await refreshPendingCount();
      return true;
    } catch (e) {
      debugPrint('⚠️ Error clearing all unparsed messages in SQLite: $e');
      return false;
    }
  }

  /// Log an unknown message to unparsed_messages table in SQLite
  Future<void> logUnparsedMessage(String rawText, String senderPhone, {String? senderName}) async {
    try {
      final db = await DatabaseService.instance.database;
      await db.insert('unparsed_messages', {
        'raw_message': rawText.trim(),
        'sender': senderPhone,
        'sender_name': senderName,
        'status': 'pending',
        'received_at': DateTime.now().toIso8601String(),
      });
      await refreshPendingCount();
    } catch (e) {
      debugPrint('⚠️ Error logging unparsed message to SQLite: $e');
    }
  }
}
