import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/widgets/side_nav_bar.dart';
import '../core/widgets/top_app_bar.dart';
import '../core/widgets/bottom_status_bar.dart';
import '../core/config/system_control_service.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/app_decorations.dart';
import '../features/bookings/screens/ticket_sales_screen.dart';
import '../features/operations/widgets/floating_engine_console.dart';

class MainLayoutScreen extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainLayoutScreen({
    super.key,
    required this.navigationShell,
  });

  @override
  ConsumerState<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends ConsumerState<MainLayoutScreen> {
  Timer? _lockCheckTimer;
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    _checkLockStatus();
    _lockCheckTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _checkLockStatus();
    });
  }

  @override
  void dispose() {
    _lockCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkLockStatus() async {
    final config = await SystemControlService.instance.loadConfig();
    if (mounted && _isLocked != config.isSystemLocked) {
      setState(() {
        _isLocked = config.isSystemLocked;
      });
    }
  }

  void _openNewTicketDialog(BuildContext context) {
    if (_isLocked) return;
    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(153),
      builder: (context) => const NewTicketSaleDialog(),
    );
  }

  void _showOwnerUnlockPinDialog() {
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg),
        title: Row(
          children: [
            const Icon(Icons.key, color: Colors.amberAccent),
            const SizedBox(width: 10),
            Text('Owner Emergency Unlock', style: AppTypography.titleLg),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter 4-Digit Owner Passcode / PIN to unlock system operations:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            TextField(
              controller: pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.amberAccent),
              decoration: const InputDecoration(labelText: 'Owner Master PIN', prefixIcon: Icon(Icons.security, color: Colors.amberAccent)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () async {
              if (pinCtrl.text.trim() == '1234' || pinCtrl.text.trim() == 'admin123' || pinCtrl.text.trim() == '8842') {
                await SystemControlService.instance.updateMasterLock(false);
                if (mounted) {
                  setState(() => _isLocked = false);
                }
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Incorrect Master PIN! (Default: 1234)'), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            icon: const Icon(Icons.lock_open),
            label: const Text('UNLOCK SYSTEM NOW'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentRoute = GoRouterState.of(context).uri.toString();

    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              // Fixed Sidebar Navigation
              SideNavBar(
                currentRoute: currentRoute,
                onNewOperationPressed: () => _openNewTicketDialog(context),
                navigationShell: widget.navigationShell,
              ),

              // Main Workspace Area
              Expanded(
                child: Column(
                  children: [
                    const TopAppBar(
                      title: 'NagaLand TicketCore — Lottery Management Platform',
                    ),

                    Expanded(
                      child: Container(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: widget.navigationShell,
                      ),
                    ),

                    const BottomStatusBar(),
                  ],
                ),
              ),
            ],
          ),

          // FLOATING DRAGGABLE WHATSAPP ENGINE CONSOLE OVERLAY
          const FloatingEngineConsole(),

          // FULL-SCREEN SYSTEM MASTER LOCK OVERLAY
          if (_isLocked)
            Positioned.fill(
              child: Container(
                color: Colors.black.withAlpha(235),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 540),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppDecorations.radiusLg,
                      border: Border.all(color: Colors.redAccent, width: 2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(40),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.redAccent, width: 2),
                          ),
                          child: const Icon(Icons.lock, size: 64, color: Colors.redAccent),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '🚨 SYSTEM MASTER LOCKED',
                          style: AppTypography.headlineLg.copyWith(color: Colors.redAccent, fontWeight: FontWeight.w900),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Operations, ticket bookings, and sales entries have been remotely locked by the System Owner via Admin App.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _checkLockStatus,
                                icon: const Icon(Icons.refresh, color: Colors.white),
                                label: const Text('Refresh Status', style: TextStyle(color: Colors.white)),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _showOwnerUnlockPinDialog,
                                icon: const Icon(Icons.key, color: Colors.white),
                                label: const Text('OWNER UNLOCK PIN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
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
