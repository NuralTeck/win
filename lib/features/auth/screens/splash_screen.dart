import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/constants/app_constants.dart';
import '../viewmodels/auth_viewmodel.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _pulseAnimation;

  double _progressValue = 0.0;
  String _statusText = 'Starting system engines...';
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();

    // Auto-maximize window on desktop
    try {
      windowManager.isMaximized().then((isMax) {
        if (!isMax) windowManager.maximize();
      });
    } catch (_) {}

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _startLoadingSequence();
  }

  void _startLoadingSequence() {
    const totalSteps = 100;
    int currentStep = 0;

    _progressTimer = Timer.periodic(const Duration(milliseconds: 48), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      currentStep++;
      final progress = currentStep / totalSteps;

      String status = 'Initializing system...';
      if (progress < 0.25) {
        status = 'Starting local SQLite database engine...';
      } else if (progress < 0.55) {
        status = 'Verifying Supabase cloud sync bridge...';
      } else if (progress < 0.85) {
        status = 'Loading Gemini AI Vision & WhatsApp Bot services...';
      } else {
        status = 'System ready. Launching application...';
      }

      setState(() {
        _progressValue = progress.clamp(0.0, 1.0);
        _statusText = status;
      });

      if (currentStep >= totalSteps) {
        timer.cancel();
        _navigateToNextScreen();
      }
    });
  }

  void _navigateToNextScreen() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    try {
      await ref.read(authControllerProvider).checkInitialAuth();
    } catch (_) {}

    if (!mounted) return;

    final currentUser = ref.read(currentUserProvider);
    if (currentUser != null) {
      context.go(AppConstants.routeDashboard);
    } else {
      context.go(AppConstants.routeLogin);
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B12),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Ambient Background Radial Glows
          Positioned(
            top: -120,
            left: -100,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF0072FF).withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -100,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00E676).withValues(alpha: 0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 2. Central Logo, Title & Progress Indicator
          Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated PM Emblem Card
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          width: 140,
                          height: 140,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(32),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF0072FF),
                                Color(0xFF00C6FF),
                                Color(0xFF00E676),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0072FF).withValues(alpha: 0.5),
                                blurRadius: 40,
                                spreadRadius: 6,
                              ),
                              BoxShadow(
                                color: const Color(0xFF00E676).withValues(alpha: 0.3),
                                blurRadius: 45,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.asset(
                              'assets/images/pm_royal_logo.png',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                // High-tech vector fallback if image is loading
                                return Container(
                                  color: const Color(0xFF0B132B),
                                  child: const Center(
                                    child: Text(
                                      'PM',
                                      style: TextStyle(
                                        color: Color(0xFF00E676),
                                        fontSize: 48,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 36),

                  // Brand Title
                  const Text(
                    'PHANTOM MANAGEMENT',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.5,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Brand Subtitle
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0072FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF00C6FF).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Text(
                      'ENTERPRISE OPERATIONS & LOTTERY PLATFORM',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Progress Bar & Dynamic Status
                  SizedBox(
                    width: 340,
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _progressValue,
                            minHeight: 6,
                            backgroundColor: Colors.white.withValues(alpha: 0.1),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00E676)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _statusText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Bottom Version Tag
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'v1.0.0 (Release Build) • Radhe Radhe Enterprises',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
