import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/database/database_service.dart';
import '../../../core/database/supabase_service.dart';
import '../../../core/services/session_tracking_service.dart';
import '../models/user_model.dart';

final currentUserProvider = StateProvider<UserModel?>((ref) => null);

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});

final userRoleProvider = Provider<String>((ref) {
  return ref.watch(currentUserProvider)?.role ?? 'Administrator';
});

class AuthController {
  final Ref ref;
  AuthController(this.ref);

  /// Authenticate using Supabase Cloud Email & Password
  Future<Map<String, dynamic>> login({
    required String emailOrUsername,
    required String password,
  }) async {
    final cleanEmail = emailOrUsername.trim();
    final cleanPass = password.trim();

    if (cleanEmail.isEmpty || cleanPass.isEmpty) {
      return {'success': false, 'message': 'Email/Username and Password cannot be empty.'};
    }

    // 0. Pre-Check: Check if entered email/username is blocked by Owner
    final isPreBlocked = await SupabaseService.instance.isUserBlocked(cleanEmail);
    if (isPreBlocked) {
      return {
        'success': false,
        'isBlocked': true,
        'message': '🔒 ACCESS LOCKED: This account has been deactivated or blocked by the System Owner.',
      };
    }

    // 1. Primary: Authenticate via Supabase Cloud Auth
    final supabase = SupabaseService.instance.client;
    if (supabase != null) {
      try {
        final authRes = await supabase.auth.signInWithPassword(
          email: cleanEmail.contains('@') ? cleanEmail : '$cleanEmail@opscore.com',
          password: cleanPass,
        );

        if (authRes.user != null) {
          final u = authRes.user!;

          // 🛡️ Remote License Check: Check if this account is blocked by Owner
          final isBlocked = await SupabaseService.instance.isUserBlocked(u.email ?? cleanEmail);
          if (isBlocked) {
            await supabase.auth.signOut();
            return {
              'success': false,
              'isBlocked': true,
              'message': '🔒 ACCESS LOCKED: This account has been deactivated or blocked by the System Owner.',
            };
          }

          // 🔐 SINGLE DEVICE POLICY CHECK:
          // Check if this account is actively running on another computer right now
          final activeDevice = await SupabaseService.instance.getActiveDeviceForEmail(cleanEmail);
          if (activeDevice != null && activeDevice.toLowerCase() != Platform.localHostname.toLowerCase()) {
            await supabase.auth.signOut();
            return {
              'success': false,
              'isBlocked': false,
              'message': '🚫 SINGLE DEVICE POLICY:\n\nYeh account pehle se computer "$activeDevice" par LIVE chal raha hai.\n\nEk ID se ek samay me keval ek hi computer par login allow hai.\nKripya pehle us computer se software band karein, ya Master Admin panel se doosre PC ke liye naya account banwayein.',
            };
          }

          final user = UserModel(
            id: u.id,
            username: u.email ?? cleanEmail,
            fullName: (u.userMetadata?['full_name'] as String?) ?? (u.userMetadata?['name'] as String?) ?? cleanEmail.split('@').first,
            role: (u.userMetadata?['role'] as String?) ?? 'Administrator',
            phone: u.phone ?? '',
            isActive: true,
            createdAt: DateTime.tryParse(u.createdAt) ?? DateTime.now(),
          );

          ref.read(currentUserProvider.notifier).state = user;
          debugPrint('⚡ [AUTH LOG] Supabase Cloud login successful for: ${user.username}');

          // Persist verified user record locally so this authorized account can work offline if needed
          try {
            await DatabaseService.instance.registerAppUser({
              'id': user.id,
              'username': cleanEmail.toLowerCase(),
              'fullName': user.fullName,
              'role': user.role,
              'phone': user.phone,
              'password': cleanPass,
              'isActive': 1,
              'createdAt': DateTime.now().toIso8601String(),
            });
          } catch (_) {}

          // Start Live User Activity & Device Tracking
          SessionTrackingService.instance.startSession(
            userEmail: user.username,
            userName: user.fullName,
          );

          return {'success': true, 'user': user};
        }
      } on AuthException catch (authErr) {
        debugPrint('⚠️ [AUTH LOG] Supabase AuthException: ${authErr.message}');
        return {
          'success': false,
          'isBlocked': false,
          'message': 'Invalid email or password. Please check your credentials and try again.',
        };
      } catch (e) {
        debugPrint('⚠️ [AUTH LOG] Supabase connection notice: $e');
      }
    }

    // 2. Secondary Local Database Verification (Master offline fallback)
    try {
      // Check if user has been blocked remotely
      final isBlockedRemotely = await SupabaseService.instance.isUserBlocked(cleanEmail);
      if (isBlockedRemotely) {
        return {
          'success': false,
          'isBlocked': true,
          'message': '🔒 Account Disabled: Please contact your system administrator.',
        };
      }

      final userMap = await DatabaseService.instance.authenticateUser(cleanEmail, cleanPass);
      if (userMap != null) {
        final user = UserModel.fromMap(userMap);
        ref.read(currentUserProvider.notifier).state = user;

        SessionTrackingService.instance.startSession(
          userEmail: user.username,
          userName: user.fullName,
        );

        return {'success': true, 'user': user};
      }
    } catch (_) {}

    return {
      'success': false,
      'isBlocked': false,
      'message': 'Invalid email or password. Please try again.',
    };
  }

  /// Check and restore persisted Supabase session on app startup
  Future<void> checkInitialAuth() async {
    final supabase = SupabaseService.instance.client;
    if (supabase != null) {
      try {
        final u = supabase.auth.currentUser;
        if (u != null) {
          // Verify if user's license is active before restoring session
          final isBlocked = await SupabaseService.instance.isUserBlocked(u.email ?? '');
          if (isBlocked) {
            debugPrint('🔒 [AUTH RESTORE] Account blocked by Owner: ${u.email}');
            await supabase.auth.signOut();
            return;
          }

          final user = UserModel(
            id: u.id,
            username: u.email ?? 'Administrator',
            fullName: (u.userMetadata?['full_name'] as String?) ??
                (u.userMetadata?['name'] as String?) ??
                (u.email?.split('@').first ?? 'Admin'),
            role: (u.userMetadata?['role'] as String?) ?? 'Administrator',
            phone: u.phone ?? '',
            isActive: true,
            createdAt: DateTime.tryParse(u.createdAt) ?? DateTime.now(),
          );
          ref.read(currentUserProvider.notifier).state = user;
          debugPrint('⚡ [AUTH RESTORE] Restored active session for: ${user.username}');

          SessionTrackingService.instance.startSession(
            userEmail: user.username,
            userName: user.fullName,
          );
        }
      } catch (e) {
        debugPrint('⚠️ [AUTH RESTORE] Notice: $e');
      }
    }
  }

  Future<void> logout() async {
    try {
      await SessionTrackingService.instance.stopSession();
      final supabase = SupabaseService.instance.client;
      if (supabase != null) {
        await supabase.auth.signOut();
      }
    } catch (_) {}

    // Local database records are preserved across user sessions and logins

    ref.read(currentUserProvider.notifier).state = null;
  }
}

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(ref);
});
