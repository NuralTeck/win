import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/constants/app_constants.dart';

final isAdminAuthenticatedProvider = StateProvider<bool>((ref) => false);

class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _userCtrl = TextEditingController(text: 'admin');
  final _passCtrl = TextEditingController(text: 'admin123');
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _handleAdminLogin() {
    final user = _userCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text.trim();

    if (user.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = 'Please enter both Admin Username ID and Password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;

      // Allow admin / admin123 OR owner / owner123 OR admin / admin
      final isValid = (user == 'admin' && (pass == 'admin123' || pass == 'admin')) ||
          (user == 'owner' && (pass == 'owner123' || pass == 'admin123'));

      if (isValid) {
        ref.read(isAdminAuthenticatedProvider.notifier).state = true;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.verified, color: Colors.greenAccent),
                const SizedBox(width: 10),
                Text('Admin Access Granted! Welcome to $user session.', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            backgroundColor: AppColors.surfaceContainerHigh,
            duration: const Duration(seconds: 2),
          ),
        );

        context.go(AppConstants.routeDashboard);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Invalid Admin ID or Password!\nDefault Credentials: User ID = admin | Password = admin123';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Stack(
        children: [
          // Background Gradient Orbs
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withAlpha(25),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.purple.withAlpha(20),
              ),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: SizedBox(
                width: 460,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App Logo Header
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: AppDecorations.radiusXl,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withAlpha(90),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      AppConstants.appName.toUpperCase(),
                      style: AppTypography.headlineLg.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        fontSize: 26,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Enterprise Master Control & Admin Portal',
                      style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Admin Login Card
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.admin_panel_settings_outlined, color: AppColors.primary, size: 22),
                                const SizedBox(width: 10),
                                Text(
                                  'OWNER / ADMIN LOGIN',
                                  style: AppTypography.titleLg.copyWith(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Enter your administrator credentials to access system controls',
                              style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary),
                            ),
                            const Divider(height: 28, color: AppColors.border),

                            if (_errorMessage != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withAlpha(30),
                                  borderRadius: AppDecorations.radiusDefault,
                                  border: Border.all(color: Colors.red.withAlpha(100)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                            ],

                            // Admin Username Input
                            const Text(
                              'Admin Username / ID',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _userCtrl,
                              decoration: InputDecoration(
                                hintText: 'e.g. admin',
                                prefixIcon: const Icon(Icons.person_outline, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: AppDecorations.radiusDefault,
                                  borderSide: const BorderSide(color: AppColors.border),
                                ),
                                filled: true,
                                fillColor: AppColors.surfaceContainerLow,
                              ),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 18),

                            // Admin Password Input
                            const Text(
                              'Admin Password',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _passCtrl,
                              obscureText: _obscurePassword,
                              onSubmitted: (_) => _handleAdminLogin(),
                              decoration: InputDecoration(
                                hintText: 'Enter admin password',
                                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: AppDecorations.radiusDefault,
                                  borderSide: const BorderSide(color: AppColors.border),
                                ),
                                filled: true,
                                fillColor: AppColors.surfaceContainerLow,
                              ),
                            ),
                            const SizedBox(height: 28),

                            // Submit Button
                            ElevatedButton(
                              onPressed: _isLoading ? null : _handleAdminLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppDecorations.radiusDefault,
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.login, size: 20, color: Colors.white),
                                        SizedBox(width: 10),
                                        Text(
                                          'AUTHENTICATE & ENTER',
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.8),
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Default Credentials Hint Box
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh.withAlpha(120),
                        borderRadius: AppDecorations.radiusDefault,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.info_outline, color: AppColors.textSecondary, size: 16),
                          const SizedBox(width: 8),
                          RichText(
                            text: const TextSpan(
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              children: [
                                TextSpan(text: 'Default Access Credentials: '),
                                TextSpan(text: 'ID: ', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                                TextSpan(text: 'admin', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                TextSpan(text: '  |  Password: '),
                                TextSpan(text: 'admin123', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
        ],
      ),
    );
  }
}
