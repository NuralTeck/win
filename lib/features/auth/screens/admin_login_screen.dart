import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/anti_theft_security_service.dart';
import '../viewmodels/auth_viewmodel.dart';

// Retain legacy provider for backwards compatibility
final isAdminAuthenticatedProvider = StateProvider<bool>((ref) => false);

class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _loginEmailCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();
  bool _loginObscure = true;

  bool _isLoading = false;
  bool _isWipingOut = false;
  int _failedAttempts = 0;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _initSecurityGuard();
  }

  Future<void> _initSecurityGuard() async {
    final attempts = await AntiTheftSecurityService.instance.init();
    if (!mounted) return;
    setState(() {
      _failedAttempts = attempts;
      if (_failedAttempts == 2) {
        _errorMessage = '🚨 CRITICAL SECURITY ALERT: 2 of 3 attempts used!\n1 more unauthorized attempt will PERMANENTLY WIPE OUT local company data and shut down software.';
      } else if (_failedAttempts == 1) {
        _errorMessage = '⚠️ Security Notice: 1 unauthorized attempt recorded (1 of 3).';
      }
    });
  }

  @override
  void dispose() {
    _loginEmailCtrl.dispose();
    _loginPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (_isWipingOut) return;

    if (AntiTheftSecurityService.instance.isLockedOut) {
      final mins = AntiTheftSecurityService.instance.remainingLockoutDuration.inMinutes + 1;
      setState(() {
        _errorMessage = '🔒 ACCESS TEMPORARILY LOCKED: Too many failed login attempts.\nPlease wait $mins minute(s) before trying again.';
      });
      return;
    }

    final email = _loginEmailCtrl.text.trim();
    final pass = _loginPassCtrl.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = 'Please enter both Email and Password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final res = await ref.read(authControllerProvider).login(
      emailOrUsername: email,
      password: pass,
    );

    if (!mounted) return;

    if (res['success'] == true) {
      // Reset security attempts on verified login
      await AntiTheftSecurityService.instance.resetAttempts();
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _failedAttempts = 0;
      });

      ref.read(isAdminAuthenticatedProvider.notifier).state = true;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: Colors.greenAccent),
              const SizedBox(width: 10),
              Text(
                'Welcome, ${res['user']?.fullName ?? email}! Cloud Access Granted.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          backgroundColor: AppColors.surfaceContainerHigh,
          duration: const Duration(seconds: 2),
        ),
      );

      context.go(AppConstants.routeDashboard);
    } else {
      final isBlocked = res['isBlocked'] == true;
      final rawMsg = res['message']?.toString() ?? 'Invalid credentials.';

      // Register failed trial
      final newCount = await AntiTheftSecurityService.instance.registerFailedAttempt(
        email: email,
        reason: isBlocked
            ? 'Unauthorized login attempt on BLOCKED account'
            : 'Invalid password credentials attempt',
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _failedAttempts = newCount;
      });

      if (newCount >= AntiTheftSecurityService.maxBruteForceThreshold) {
        // 🚨 MAXIMUM BRUTE FORCE THRESHOLD EXCEEDED: INITIATE EMERGENCY WIPEOUT & CRASH
        setState(() => _isWipingOut = true);
        await Future.delayed(const Duration(milliseconds: 2200));
        await AntiTheftSecurityService.instance.executeEmergencyWipeoutAndCrash(
          email: email,
          reason: isBlocked
              ? 'Blocked account attempted brute force access $newCount times'
              : '$newCount consecutive failed password login attempts',
        );
      } else if (AntiTheftSecurityService.instance.isLockedOut) {
        final mins = AntiTheftSecurityService.instance.remainingLockoutDuration.inMinutes + 1;
        setState(() {
          _errorMessage = '$rawMsg\n\n🔒 ACCOUNT LOCKED: $newCount failed attempts recorded.\nCooldown active: Access locked for $mins minute(s) to protect database.';
        });
      } else if (newCount == 2) {
        setState(() {
          _errorMessage = '$rawMsg\n\n⚠️ Security Notice: Attempt 2 of 3 used before account cooldown lockout.';
        });
      } else {
        setState(() {
          _errorMessage = '$rawMsg\n\n⚠️ Security Notice: Attempt 1 used. Repeated failed attempts will trigger a security cooldown lockout.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      body: Stack(
        children: [
          // 1. Ambient Background Gradient Orbs
          Positioned(
            top: -120,
            right: -100,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF0072FF).withValues(alpha: 0.20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -100,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF43E97B).withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 2. Central Login Card
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: SizedBox(
                width: 480,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Brand Logo & Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0072FF), Color(0xFF43E97B)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0072FF).withValues(alpha: 0.4),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Image.asset(
                              'assets/images/pm_royal_logo.png',
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) => const Icon(
                                Icons.shield_rounded,
                                color: Colors.cyanAccent,
                                size: 30,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppConstants.appName.toUpperCase(),
                              style: AppTypography.headlineLg.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                fontSize: 24,
                              ),
                            ),
                            Text(
                              'ENTERPRISE MANAGEMENT',
                              style: AppTypography.labelSm.copyWith(
                                color: const Color(0xFF43E97B),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Main Glassmorphism Login Container
                    GlassCard(
                      borderRadius: AppDecorations.radiusXl,
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Enter your email and password to access the system.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Error Banner
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: const TextStyle(
                                        color: AppColors.error,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],

                          // Success Banner
                          if (_successMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_outline, color: AppColors.success, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _successMessage!,
                                      style: const TextStyle(
                                        color: AppColors.success,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],

                          // Email / Username Input
                          TextField(
                            controller: _loginEmailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            decoration: InputDecoration(
                              labelText: 'Email Address *',
                              hintText: 'Enter your email',
                              prefixIcon: const Icon(Icons.email_outlined, color: AppColors.primary),
                              filled: true,
                              fillColor: AppColors.surfaceContainerLow,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Password Input
                          TextField(
                            controller: _loginPassCtrl,
                            obscureText: _loginObscure,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _handleSignIn(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            decoration: InputDecoration(
                              labelText: 'Password *',
                              hintText: 'Enter your password',
                              prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primary),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _loginObscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  color: AppColors.textSecondary,
                                  size: 18,
                                ),
                                onPressed: () => setState(() => _loginObscure = !_loginObscure),
                              ),
                              filled: true,
                              fillColor: AppColors.surfaceContainerLow,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),

                          // Submit Button
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleSignIn,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0072FF),
                                foregroundColor: Colors.white,
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.lock_open_rounded, size: 18),
                                        SizedBox(width: 10),
                                        Text(
                                          'SIGN IN',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.1,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),

                          // Security Trials Badge
                          if (_failedAttempts > 0) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: _failedAttempts >= 2
                                    ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                                    : Colors.amber.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _failedAttempts >= 2
                                      ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                                      : Colors.amber.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _failedAttempts >= 2 ? Icons.warning_rounded : Icons.shield_outlined,
                                    size: 16,
                                    color: _failedAttempts >= 2 ? const Color(0xFFEF4444) : Colors.amber,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Anti-Theft Guard: $_failedAttempts of 3 trials used (${3 - _failedAttempts} remaining)',
                                    style: TextStyle(
                                      color: _failedAttempts >= 2 ? const Color(0xFFFCA5A5) : Colors.amber.shade200,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // Admin-Only Password Policy Notice
                          const SizedBox(height: 16),
                          const Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.admin_panel_settings_outlined, size: 14, color: Color(0xFF64748B)),
                                SizedBox(width: 6),
                                Text(
                                  'Password resets are strictly controlled by System Admin',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Full-Screen Emergency Anti-Theft Wipeout Barrier
          if (_isWipingOut)
            Positioned.fill(
              child: Container(
                color: const Color(0xF50A0000),
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 500),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E0808),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFEF4444), width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                          blurRadius: 40,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFEF4444), width: 2.5),
                          ),
                          child: const Icon(
                            Icons.gpp_bad_rounded,
                            size: 42,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'ANTI-THEFT WIPEOUT ENGAGED',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '3 UNAUTHORIZED / BLOCKED ATTEMPTS EXCEEDED',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Company Data Protection Protocol:',
                                style: TextStyle(
                                  color: Color(0xFFFCA5A5),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                '• Purging local database (opscore_pro.db)\n'
                                '• Sanitizing all ticket & party ledgers\n'
                                '• Force crashing terminal to prevent data theft\n'
                                '• Re-opening will require new Owner credentials',
                                style: TextStyle(
                                  color: Color(0xFFE2E8F0),
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                            SizedBox(width: 14),
                            Text(
                              'Destroying local files & crashing terminal...',
                              style: TextStyle(
                                color: Color(0xFFFCA5A5),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
