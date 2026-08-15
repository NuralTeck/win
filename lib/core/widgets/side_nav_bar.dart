import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/app_decorations.dart';
import '../constants/app_constants.dart';
import 'app_button.dart';

import '../config/system_control_service.dart';

class SideNavBarItem {
  final String label;
  final IconData icon;
  final String routePath;
  final String permKey;

  const SideNavBarItem({
    required this.label,
    required this.icon,
    required this.routePath,
    required this.permKey,
  });
}

class SideNavBar extends StatefulWidget {
  final String currentRoute;
  final VoidCallback onNewOperationPressed;
  final StatefulNavigationShell? navigationShell;

  const SideNavBar({
    super.key,
    required this.currentRoute,
    required this.onNewOperationPressed,
    this.navigationShell,
  });

  static const List<SideNavBarItem> mainItems = [
    SideNavBarItem(
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      routePath: AppConstants.routeDashboard,
      permKey: 'dashboard',
    ),
    SideNavBarItem(
      label: 'Ticket Booking',
      icon: Icons.local_activity_outlined,
      routePath: AppConstants.routeBookings,
      permKey: 'ticket_booking',
    ),
    SideNavBarItem(
      label: 'Company Forward',
      icon: Icons.forward_to_inbox_outlined,
      routePath: AppConstants.routeCompanyForward,
      permKey: 'company_forward',
    ),
    SideNavBarItem(
      label: 'Result Entry',
      icon: Icons.emoji_events_outlined,
      routePath: AppConstants.routeResultEntry,
      permKey: 'result_entry',
    ),
    SideNavBarItem(
      label: 'Customers & Sellers',
      icon: Icons.people_alt_outlined,
      routePath: AppConstants.routeCustomers,
      permKey: 'customers_sellers',
    ),
    SideNavBarItem(
      label: 'Money Collectors',
      icon: Icons.payments_outlined,
      routePath: AppConstants.routeCollectors,
      permKey: 'money_collectors',
    ),
    SideNavBarItem(
      label: 'Revenue & Payouts',
      icon: Icons.bar_chart_outlined,
      routePath: AppConstants.routeAnalytics,
      permKey: 'analytics',
    ),
    SideNavBarItem(
      label: 'System Config',
      icon: Icons.tune_outlined,
      routePath: AppConstants.routeSettings,
      permKey: 'settings',
    ),
  ];

  @override
  State<SideNavBar> createState() => _SideNavBarState();
}

class _SideNavBarState extends State<SideNavBar> {
  bool _isOwnerUnlocked = false;
  Map<String, bool> _cloudPerms = {
    'dashboard': true,
    'ticket_booking': true,
    'company_forward': true,
    'result_entry': true,
    'customers_sellers': true,
    'money_collectors': true,
    'analytics': true,
    'settings': true,
  };

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    SystemControlService.instance.configNotifier.addListener(_onConfigUpdated);
  }

  @override
  void dispose() {
    SystemControlService.instance.configNotifier.removeListener(_onConfigUpdated);
    super.dispose();
  }

  void _onConfigUpdated() {
    if (mounted) {
      final config = SystemControlService.instance.configNotifier.value;
      setState(() {
        _cloudPerms = Map<String, bool>.from(config.allowedTabs);
        _cloudPerms['dashboard'] = true;
      });
    }
  }

  Future<void> _loadPermissions() async {
    final config = await SystemControlService.instance.loadConfig();
    if (mounted) {
      setState(() {
        _cloudPerms = Map<String, bool>.from(config.allowedTabs);
        _cloudPerms['dashboard'] = true;
      });
    }
  }

  void _showOwnerPinUnlockDialog() {
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
            Text('Owner Master PIN Unlock', style: AppTypography.titleLg),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter 4-Digit Owner PIN to unlock all administrative tabs on this workstation:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
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
            onPressed: () {
              if (pinCtrl.text.trim() == '1234' || pinCtrl.text.trim() == 'admin123' || pinCtrl.text.trim() == '8842') {
                setState(() => _isOwnerUnlocked = true);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🔓 OWNER UNLOCKED: All Administrative Tabs are now visible!'), backgroundColor: AppColors.success),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Incorrect Master PIN! (Default: 1234)'), backgroundColor: AppColors.error),
                );
              }
            },
            icon: const Icon(Icons.lock_open),
            label: const Text('UNLOCK ALL TABS'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppConstants.sidebarWidth,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          // App Header & Logo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: AppDecorations.radiusDefault,
                  ),
                  child: const Icon(
                    Icons.local_activity,
                    color: AppColors.onPrimaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppConstants.appName,
                        style: AppTypography.headlineMd.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _isOwnerUnlocked ? 'Owner Master Mode' : 'Staff Station Mode',
                        style: AppTypography.labelSm.copyWith(
                          color: _isOwnerUnlocked ? Colors.amberAccent : AppColors.textSecondary.withAlpha(150),
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Primary Action: New Operation
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AppPrimaryButton(
              label: 'New Draw Entry',
              icon: Icons.add,
              fullWidth: true,
              onPressed: widget.onNewOperationPressed,
            ),
          ),
          const SizedBox(height: 24),

          // Navigation Links (Filtered by Permission / Owner Mode)
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: SideNavBar.mainItems.length,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final item = SideNavBar.mainItems[index];
                final isAllowed = _isOwnerUnlocked || (_cloudPerms[item.permKey] ?? false);

                if (!isAllowed) {
                  return Opacity(
                    opacity: 0.5,
                    child: Tooltip(
                      message: 'Locked by Admin. Tap to unlock with Owner PIN.',
                      child: InkWell(
                        onTap: _showOwnerPinUnlockDialog,
                        borderRadius: AppDecorations.radiusDefault,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(borderRadius: AppDecorations.radiusDefault),
                          child: Row(
                            children: [
                              Icon(item.icon, size: 20, color: AppColors.textSecondary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.lock, size: 14, color: Colors.amberAccent),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }

                final isActive = widget.navigationShell != null
                    ? widget.navigationShell!.currentIndex == index
                    : widget.currentRoute == item.routePath;

                return _SideNavItemTile(
                  item: item,
                  isActive: isActive,
                  onTap: () {
                    if (widget.navigationShell != null && index < widget.navigationShell!.route.branches.length) {
                      widget.navigationShell!.goBranch(
                        index,
                        initialLocation: index == widget.navigationShell!.currentIndex,
                      );
                    } else {
                      context.go(item.routePath);
                    }
                  },
                );
              },
            ),
          ),

          // Bottom Quick Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(_isOwnerUnlocked ? Icons.verified : Icons.shield_outlined, color: _isOwnerUnlocked ? Colors.amberAccent : AppColors.success, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          _isOwnerUnlocked ? 'Owner Master' : 'Staff Operator',
                          style: AppTypography.labelSm.copyWith(color: _isOwnerUnlocked ? Colors.amberAccent : AppColors.textSecondary, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: _loadPermissions,
                      child: const Icon(Icons.refresh, size: 14, color: AppColors.secondary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: _isOwnerUnlocked
                      ? OutlinedButton.icon(
                          onPressed: () => setState(() => _isOwnerUnlocked = false),
                          icon: const Icon(Icons.lock, size: 14, color: Colors.amberAccent),
                          label: const Text('Lock Owner Mode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.amberAccent)),
                        )
                      : ElevatedButton.icon(
                          onPressed: _showOwnerPinUnlockDialog,
                          icon: const Icon(Icons.key, size: 14, color: Colors.white),
                          label: const Text('OWNER PIN UNLOCK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideNavItemTile extends StatelessWidget {
  final SideNavBarItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _SideNavItemTile({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isActive ? AppColors.primary : AppColors.textSecondary;
    final iconColor = isActive ? AppColors.primary : AppColors.textSecondary;

    return Material(
      color: Colors.transparent,
      borderRadius: AppDecorations.radiusDefault,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppDecorations.radiusDefault,
        hoverColor: AppColors.hover,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.surfaceContainerHighest
                : Colors.transparent,
            borderRadius: AppDecorations.radiusDefault,
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 20, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: AppTypography.bodyMd.copyWith(
                    color: textColor,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
