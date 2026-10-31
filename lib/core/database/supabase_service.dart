import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// SupabaseService — Handles ONLY:
/// 1. Authentication & License Protection (Login, session restore, user authorization)
/// 2. Party Name & Kitna Hisab Ban Raha Hai (Party hisab summaries in 'party_hisab' table)
///
/// Sabhi heavy operational data (raw tickets, drawings, vouchers, unparsed whatsapp messages)
/// 100% Local SQLite Database me process aur store hote hain.
class SupabaseService {
  SupabaseService._internal();
  static final SupabaseService instance = SupabaseService._internal();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  SupabaseClient? get client {
    if (!_isInitialized) return null;
    return Supabase.instance.client;
  }

  /// Initialize Supabase Flutter SDK strictly for Authentication & Party Hisab
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
      debugPrint('⚡ [SUPABASE] Connected for Authentication & Party Hisab Cloud Sync.');
    } catch (e) {
      debugPrint('⚠️ [SUPABASE] Initialization note: $e');
    }
  }

  // ─── ☁️ PARTY NAME & HISAB SUMMARY CLOUD SYNC ──────────────────────────────

  /// Sync single Party / Dealer Hisab summary to Supabase table 'party_hisab'
  Future<bool> syncPartyHisab({
    required String partyName,
    String? dealerName,
    int totalTickets = 0,
    double totalSales = 0.0,
    double totalPrize = 0.0,
    required double netHisab,
    String category = 'Party Hisab',
    String? date,
  }) async {
    final sb = client;
    if (sb == null || partyName.trim().isEmpty) return false;

    try {
      final user = sb.auth.currentUser;
      final payload = {
        'party_name': partyName.trim(),
        'dealer_name': dealerName?.trim(),
        'total_tickets': totalTickets,
        'total_sales': totalSales,
        'total_prize': totalPrize,
        'net_hisab': netHisab,
        'category': category,
        'last_active_date': date ?? DateTime.now().toIso8601String().substring(0, 10),
        'updated_at': DateTime.now().toIso8601String(),
        'synced_by': user?.email ?? 'authorized_client',
      };

      await sb.from('party_hisab').upsert(
        payload,
        onConflict: 'party_name',
      );
      debugPrint('☁️ [SUPABASE HISAB] Synced party: "$partyName" | Net Hisab: ₹$netHisab');
      return true;
    } catch (e) {
      debugPrint('⚠️ [SUPABASE HISAB ERROR] Failed to sync "$partyName": $e');
      return false;
    }
  }

  /// Bulk sync multiple Party Hisab summaries to Supabase
  Future<int> syncPartyHisabBatch(List<Map<String, dynamic>> records) async {
    final sb = client;
    if (sb == null || records.isEmpty) return 0;

    try {
      final user = sb.auth.currentUser;
      final nowStr = DateTime.now().toIso8601String();

      final cleanRows = records.map((r) {
        return {
          'party_name': (r['party_name'] ?? '').toString().trim(),
          'dealer_name': r['dealer_name']?.toString().trim(),
          'total_tickets': r['total_tickets'] ?? 0,
          'total_sales': (r['total_sales'] as num?)?.toDouble() ?? 0.0,
          'total_prize': (r['total_prize'] as num?)?.toDouble() ?? 0.0,
          'net_hisab': (r['net_hisab'] as num?)?.toDouble() ?? 0.0,
          'category': (r['category'] ?? 'Party Hisab').toString(),
          'last_active_date': (r['last_active_date'] ?? nowStr.substring(0, 10)).toString(),
          'updated_at': nowStr,
          'synced_by': user?.email ?? 'authorized_client',
        };
      }).where((r) => (r['party_name'] as String).isNotEmpty).toList();

      if (cleanRows.isEmpty) return 0;

      await sb.from('party_hisab').upsert(
        cleanRows,
        onConflict: 'party_name',
      );
      debugPrint('☁️ [SUPABASE HISAB] Batch synced ${cleanRows.length} party records to Cloud.');
      return cleanRows.length;
    } catch (e) {
      debugPrint('⚠️ [SUPABASE BULK HISAB ERROR]: $e');
      return 0;
    }
  }

  /// Retrieve all party hisabs stored in Supabase
  Future<List<Map<String, dynamic>>> fetchPartyHisabs() async {
    final sb = client;
    if (sb == null) return [];

    try {
      final response = await sb
          .from('party_hisab')
          .select()
          .order('updated_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('⚠️ [SUPABASE FETCH HISAB ERROR]: $e');
      return [];
    }
  }

  /// Delete a party hisab from Supabase
  Future<bool> deletePartyHisab(String partyName) async {
    final sb = client;
    if (sb == null || partyName.trim().isEmpty) return false;

    try {
      await sb.from('party_hisab').delete().eq('party_name', partyName.trim());
      debugPrint('🗑️ [SUPABASE HISAB] Deleted party hisab: "$partyName"');
      return true;
    } catch (e) {
      debugPrint('⚠️ [SUPABASE DELETE HISAB ERROR]: $e');
      return false;
    }
  }

  // ─── 🟢 APP SESSIONS & ACTIVITY TRACKING (WHO LOGGED IN & ONLINE TIME) ───────

  /// Record user login and new active session in Supabase 'app_sessions' table
  Future<bool> recordSessionStart({
    required String sessionId,
    required String userEmail,
    required String userName,
    required String deviceName,
    required String osInfo,
  }) async {
    final sb = client;
    if (sb == null) return false;

    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();
      final trimmedEmail = userEmail.trim().toLowerCase();

      // ✅ FIX: Close ALL previous sessions for this email OR this device so they don't show as duplicates
      // This handles app restart / online-offline cycles on the same machine
      try {
        await sb
            .from('app_sessions')
            .update({
              'is_online': false,
              'status': 'Offline',
              'logout_time': nowStr,
            })
            .or('user_email.ilike.$trimmedEmail,device_name.ilike.$deviceName')
            .neq('session_id', sessionId);
        debugPrint('🧹 [SESSION] Cleared old sessions for $userEmail on $deviceName');
      } catch (cleanupErr) {
        // Fallback: try updating by email only
        try {
          await sb
              .from('app_sessions')
              .update({'is_online': false, 'status': 'Offline', 'logout_time': nowStr})
              .ilike('user_email', trimmedEmail)
              .neq('session_id', sessionId);
        } catch (_) {}
      }

      // Insert new session record
      await sb.from('app_sessions').upsert({
        'session_id': sessionId,
        'user_email': userEmail,
        'user_name': userName,
        'device_name': deviceName,
        'os_info': osInfo,
        'login_time': nowStr,
        'last_heartbeat': nowStr,
        'is_online': true,
        'total_online_seconds': 0,
        'app_version': '2.0.0',
        'status': 'Online',
      }, onConflict: 'session_id');

      debugPrint('🟢 [SUPABASE SESSIONS] Logged in: $userEmail on $deviceName (Session: $sessionId)');
      return true;
    } catch (e) {
      debugPrint('⚠️ [SUPABASE SESSIONS ERROR] Failed to record session start: $e');
      return false;
    }
  }

  /// Periodic Heartbeat ping to keep session alive, update online time, and check remote lock status
  Future<Map<String, dynamic>?> pingSessionHeartbeat({
    required String sessionId,
    required int onlineSeconds,
  }) async {
    final sb = client;
    if (sb == null) return null;

    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();

      // Step 1: Read current status FIRST before updating
      final res = await sb
          .from('app_sessions')
          .select('status, is_blocked')
          .eq('session_id', sessionId)
          .maybeSingle();

      if (res != null) {
        final st = res['status']?.toString();
        final isTerminated = res['is_blocked'] == true ||
            st == 'Blocked' ||
            st == 'Killed' ||
            st == 'Kicked' ||
            st == 'Offline';

        if (isTerminated) {
          // DO NOT mark is_online=true! This session was terminated or kicked by another device
          return res;
        }
      }

      // Step 2: Session is healthy and active, update heartbeat timestamp
      await sb
          .from('app_sessions')
          .update({
            'last_heartbeat': nowStr,
            'is_online': true,
            'total_online_seconds': onlineSeconds,
          })
          .eq('session_id', sessionId);

      return res;
    } catch (e) {
      debugPrint('⚠️ [SUPABASE HEARTBEAT ERROR]: $e');
      return null;
    }
  }

  /// Check if this email currently has an active session on another device (within last 2 minutes)
  Future<String?> getActiveDeviceForEmail(String email) async {
    final sb = client;
    final trimmed = email.trim().toLowerCase();
    if (sb == null || trimmed.isEmpty) return null;

    try {
      final res = await sb
          .from('app_sessions')
          .select('device_name, last_heartbeat, status, is_online')
          .ilike('user_email', trimmed)
          .eq('status', 'Online')
          .eq('is_online', true)
          .order('last_heartbeat', ascending: false)
          .limit(1)
          .maybeSingle();

      if (res != null) {
        final hbStr = res['last_heartbeat']?.toString();
        final deviceName = res['device_name']?.toString() ?? 'Another PC';
        if (hbStr != null) {
          final hbDate = DateTime.tryParse(hbStr);
          if (hbDate != null) {
            final diffSecs = DateTime.now().toUtc().difference(hbDate.toUtc()).inSeconds;
            // Active if heartbeat pinged within last 120 seconds
            if (diffSecs <= 120) {
              return deviceName;
            }
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ [ACTIVE DEVICE CHECK ERROR]: $e');
      return null;
    }
  }

  /// Check if a user's license is blocked in Supabase
  /// Check if a user's license or access has been blocked by the Owner
  Future<bool> isUserBlocked(String email) async {
    final sb = client;
    final trimmed = email.trim().toLowerCase();
    if (sb == null || trimmed.isEmpty) return false;

    final fullEmail = trimmed.contains('@') ? trimmed : '$trimmed@opscore.com';

    try {
      final res = await sb
          .from('app_licenses')
          .select('is_blocked, license_status')
          .or('user_email.ilike.$trimmed,user_email.ilike.$fullEmail')
          .limit(1)
          .maybeSingle();

      if (res != null) {
        return res['is_blocked'] == true || res['license_status'] == 'Blocked';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ─── 🔐 SINGLE DEVICE LOGIN ENFORCEMENT ─────────────────────────────────────

  /// Enforce single-device login: kick out all other active sessions for this email.
  /// Called before creating a new session. Marks all existing Online sessions as Offline.
  Future<int> kickOtherSessions({
    required String userEmail,
    required String newSessionId,
  }) async {
    final sb = client;
    if (sb == null) return 0;

    try {
      final trimmed = userEmail.trim().toLowerCase();
      final nowStr = DateTime.now().toUtc().toIso8601String();

      // Find all active sessions for this email (not the new one)
      final existing = await sb
          .from('app_sessions')
          .select('session_id')
          .ilike('user_email', trimmed)
          .neq('session_id', newSessionId)
          .or('status.eq.Online,status.eq.Active,is_online.eq.true');

      if (existing == null || (existing as List).isEmpty) return 0;

      // Mark them all as Offline / Kicked
      await sb
          .from('app_sessions')
          .update({
            'is_online': false,
            'status': 'Kicked',
            'logout_time': nowStr,
          })
          .ilike('user_email', trimmed)
          .neq('session_id', newSessionId)
          .or('status.eq.Online,status.eq.Active,is_online.eq.true');

      debugPrint('🔐 [SINGLE DEVICE] Kicked ${existing.length} other session(s) for $userEmail');
      return (existing as List).length;
    } catch (e) {
      debugPrint('⚠️ [SINGLE DEVICE ERROR] $e');
      return 0;
    }
  }

  /// Record emergency security breach & local data wipeout incident to Cloud
  Future<void> recordSecurityBreach({
    required String email,
    required String reason,
    required int attemptsCount,
  }) async {
    final sb = client;
    if (sb == null) return;

    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();
      await sb.from('app_sessions').insert({
        'session_id': 'BREACH_${DateTime.now().millisecondsSinceEpoch}_${Platform.localHostname.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}',
        'user_email': email.trim().isEmpty ? 'unknown@unauthorized.local' : email.trim(),
        'user_name': 'ANTI-THEFT DEFENSE PROTOCOL',
        'device_name': Platform.localHostname,
        'os_info': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        'login_time': nowStr,
        'last_heartbeat': nowStr,
        'logout_time': nowStr,
        'is_online': false,
        'status': 'Killed',
        'is_blocked': true,
        'notes': '🚨 [EMERGENCY WIPEOUT] $reason (Failed Attempts: $attemptsCount). Local database destroyed.',
      });
      debugPrint('🚨 [SUPABASE] Logged security breach event to Cloud.');
    } catch (e) {
      debugPrint('⚠️ [SUPABASE BREACH LOG ERROR] $e');
    }
  }

  /// Record user logout and session close
  Future<void> recordSessionEnd({
    required String sessionId,
    required int totalOnlineSeconds,
  }) async {
    final sb = client;
    if (sb == null) return;

    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();
      await sb.from('app_sessions').update({
        'is_online': false,
        'status': 'Offline',
        'logout_time': nowStr,
        'last_heartbeat': nowStr,
        'total_online_seconds': totalOnlineSeconds,
      }).eq('session_id', sessionId);
      debugPrint('⚪ [SUPABASE SESSIONS] Session ended: $sessionId (Duration: ${totalOnlineSeconds}s)');
    } catch (e) {
      debugPrint('⚠️ [SUPABASE SESSIONS ERROR] Failed to record session end: $e');
    }
  }

  /// Fetch active sessions from Supabase
  Future<List<Map<String, dynamic>>> fetchActiveSessions() async {
    final sb = client;
    if (sb == null) return [];

    try {
      final response = await sb
          .from('app_sessions')
          .select()
          .order('login_time', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('⚠️ [SUPABASE SESSIONS FETCH ERROR]: $e');
      return [];
    }
  }
}
