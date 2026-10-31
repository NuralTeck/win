import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../database/database_service.dart';
import '../database/supabase_service.dart';

/// AntiTheftSecurityService — Instant Brute-Force & Blocked Account Defense
/// Enforces:
/// 1. Progressive rate limiting & lockout timers on failed attempts.
/// 2. Account lockout cooldowns (5m after 3 attempts, 15m after 5 attempts).
/// 3. Secure Emergency Rescue Archive creation prior to any forensic wipeout.
/// 4. Incident reporting to Supabase Cloud when online.
class AntiTheftSecurityService {
  AntiTheftSecurityService._internal();
  static final AntiTheftSecurityService instance = AntiTheftSecurityService._internal();

  static const int maxAllowedAttempts = 3;
  static const int maxBruteForceThreshold = 6;
  static const String _securityFileName = '.security_guard';

  int _cachedAttempts = 0;
  DateTime? _lockoutUntil;
  bool _isInitialized = false;

  int get currentFailedAttempts => _cachedAttempts;
  int get remainingAttempts => (maxAllowedAttempts - _cachedAttempts).clamp(0, maxAllowedAttempts);

  bool get isLockedOut => _lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!);
  Duration get remainingLockoutDuration => isLockedOut ? _lockoutUntil!.difference(DateTime.now()) : Duration.zero;

  Future<File> _getGuardFile() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return File(p.join(docsDir.path, _securityFileName));
  }

  /// Initialize security state from persisted storage on disk
  Future<int> init() async {
    if (_isInitialized) return _cachedAttempts;
    try {
      final file = await _getGuardFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        _cachedAttempts = (map['failed_attempts'] as num?)?.toInt() ?? 0;
        final lockUntilStr = map['lockout_until']?.toString();
        if (lockUntilStr != null) {
          final parsedDate = DateTime.tryParse(lockUntilStr);
          if (parsedDate != null && parsedDate.isAfter(DateTime.now())) {
            _lockoutUntil = parsedDate;
          }
        }
      } else {
        _cachedAttempts = 0;
        _lockoutUntil = null;
      }
    } catch (e) {
      debugPrint('⚠️ [SECURITY GUARD INIT ERROR]: $e');
      _cachedAttempts = 0;
    }
    _isInitialized = true;
    return _cachedAttempts;
  }

  /// Register an unauthorized or blocked login attempt
  Future<int> registerFailedAttempt({
    required String email,
    required String reason,
  }) async {
    await init();
    _cachedAttempts++;

    // Progressive lockout policy
    if (_cachedAttempts >= 5) {
      _lockoutUntil = DateTime.now().add(const Duration(minutes: 15));
    } else if (_cachedAttempts >= 3) {
      _lockoutUntil = DateTime.now().add(const Duration(minutes: 5));
    }

    try {
      final file = await _getGuardFile();
      await file.writeAsString(jsonEncode({
        'failed_attempts': _cachedAttempts,
        'lockout_until': _lockoutUntil?.toUtc().toIso8601String(),
        'last_email': email,
        'last_reason': reason,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      }));
    } catch (e) {
      debugPrint('⚠️ [SECURITY GUARD WRITE ERROR]: $e');
    }

    debugPrint('🚨 [SECURITY ATTEMPT] Attempt $_cachedAttempts registered for: $email (Locked out: $isLockedOut)');
    return _cachedAttempts;
  }

  /// Reset failed attempts upon successful authorized login
  Future<void> resetAttempts() async {
    _cachedAttempts = 0;
    _lockoutUntil = null;
    try {
      final file = await _getGuardFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// 🚨 EMERGENCY DATA WIPEOUT & HARD CRASH
  /// Archives data safely to emergency rescue storage before sanitizing live files.
  Future<void> executeEmergencyWipeoutAndCrash({
    required String email,
    required String reason,
  }) async {
    debugPrint('🚨🚨🚨 [ANTI-THEFT PROTOCOL ENGAGED] Security threshold reached. Initiating Forensic Sanitization! 🚨🚨🚨');

    // 1. Report breach incident to Cloud
    try {
      await SupabaseService.instance.recordSecurityBreach(
        email: email,
        reason: reason,
        attemptsCount: _cachedAttempts,
      );
    } catch (_) {}

    // 2. 🛡️ Safety Pre-Wipeout Rescue: Archive database before forensic purge
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(docsDir.path, 'opscore_pro.db'));
      if (await dbFile.exists()) {
        final rescueDir = Directory(p.join(docsDir.path, 'emergency_rescue'));
        if (!await rescueDir.exists()) await rescueDir.create(recursive: true);
        final rescuePath = p.join(rescueDir.path, 'opscore_emergency_rescue_${DateTime.now().millisecondsSinceEpoch}.db.gz');
        await DatabaseService.instance.createCompressedBackup(rescuePath);
        debugPrint('🛡️ [EMERGENCY RESCUE ARCHIVE] Secured rescue snapshot at: $rescuePath');
      }
    } catch (rescueErr) {
      debugPrint('⚠️ [EMERGENCY RESCUE ARCHIVE NOTICE] $rescueErr');
    }

    // 3. Erase local SQLite live database files permanently
    try {
      await DatabaseService.instance.emergencySecurityWipeout();
    } catch (e) {
      debugPrint('🚨 [CRITICAL WIPEOUT ERROR] $e');
    }

    // 4. Reset local security guard file
    try {
      final file = await _getGuardFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}

    // 5. Force termination / instant shutdown
    debugPrint('💥 [ANTI-THEFT DEFENSE] Local data wiped. Terminating process...');
    exit(0);
  }
}
