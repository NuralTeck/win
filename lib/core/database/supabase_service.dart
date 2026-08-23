import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// SupabaseService — Handles ONLY:
/// Authentication (login / logout / user session restore).
///
/// Sabhi operational data (Tickets, Prices, Sellers, Hisab, Bot AI)
/// 100% Local SQLite Database me process aur store hota hai.
class SupabaseService {
  SupabaseService._internal();
  static final SupabaseService instance = SupabaseService._internal();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  SupabaseClient? get client {
    if (!_isInitialized) return null;
    return Supabase.instance.client;
  }

  /// Initialize Supabase Flutter SDK strictly for Authentication
  Future<void> initialize({String? url, String? anonKey}) async {
    final targetUrl = url ?? dotenv.env['SUPABASE_URL'] ?? '';
    final targetKey = anonKey ?? dotenv.env['SUPABASE_ANON_KEY'] ?? '';

    if (targetUrl.isEmpty || targetUrl.contains('YOUR_SUPABASE_PROJECT_ID')) {
      debugPrint('ℹ️ [SUPABASE] Demo / Offline mode. No Supabase Auth configured.');
      return;
    }

    try {
      await Supabase.initialize(
        url: targetUrl,
        // ignore: deprecated_member_use
        anonKey: targetKey,
      );
      _isInitialized = true;
      debugPrint('⚡ [SUPABASE] Connected strictly for User Authentication.');
    } catch (e) {
      debugPrint('⚠️ [SUPABASE] Auth initialization note: $e');
    }
  }
}
