import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/database/database_service.dart';
import '../../../core/database/supabase_service.dart';
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
          return {'success': true, 'user': user};
        }
      } on AuthException catch (authErr) {
        debugPrint('⚠️ [AUTH LOG] Supabase AuthException: ${authErr.message}');
        return {
          'success': false,
          'message': 'Access Denied: ${authErr.message}\n(Make sure this account is registered in Supabase by the Owner)',
        };
      } catch (e) {
        debugPrint('⚠️ [AUTH LOG] Supabase connection notice: $e');
      }
    }

    // 2. Secondary Local Database Verification (Master offline fallback)
    try {
      final userMap = await DatabaseService.instance.authenticateUser(cleanEmail, cleanPass);
      if (userMap != null) {
        final user = UserModel.fromMap(userMap);
        ref.read(currentUserProvider.notifier).state = user;
        return {'success': true, 'user': user};
      }
    } catch (_) {}

    return {
      'success': false,
      'message': 'Access Denied: Unauthorized Account.\nOnly accounts created by the System Owner in Supabase can access this software.',
    };
  }

  /// Check and restore persisted Supabase session on app startup
  Future<void> checkInitialAuth() async {
    final supabase = SupabaseService.instance.client;
    if (supabase != null) {
      try {
        final u = supabase.auth.currentUser;
        if (u != null) {
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
        }
      } catch (e) {
        debugPrint('⚠️ [AUTH RESTORE] Notice: $e');
      }
    }
  }

  Future<void> logout() async {
    try {
      final supabase = SupabaseService.instance.client;
      if (supabase != null) {
        await supabase.auth.signOut();
      }
    } catch (_) {}

    try {
      await DatabaseService.instance.wipeAllLocalDataOnLogout();
    } catch (e) {
      debugPrint('⚠️ Error wiping local data on logout: $e');
    }

    ref.read(currentUserProvider.notifier).state = null;
  }
}

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(ref);
});
