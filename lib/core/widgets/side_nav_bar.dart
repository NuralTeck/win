import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/app_decorations.dart';
import '../constants/app_constants.dart';
import 'app_button.dart';

class SideNavBarItem {
  final String label;
  final IconData icon;
  final String routePath;

  const SideNavBarItem({
    required this.label,
    required this.icon,
    required this.routePath,
  });
}

class SideNavBar extends StatelessWidget {
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
    ),
    SideNavBarItem(
      label: 'Ticket Booking',
      icon: Icons.local_activity_outlined,
      routePath: AppConstants.routeBookings,
    ),
    SideNavBarItem(
      label: 'Result Entry',
      icon: Icons.emoji_events_outlined,
      routePath: AppConstants.routeResultEntry,
    ),
    SideNavBarItem(
      label: 'Generated Hisab',
      icon: Icons.receipt_long_outlined,
      routePath: AppConstants.routeGeneratedHisab,
    ),
    SideNavBarItem(
      label: 'System Config',
      icon: Icons.tune_outlined,
      routePath: AppConstants.routeSettings,
    ),
  ];

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
                        'Hisab Management Platform',
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.textSecondary.withAlpha(150),
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
              onPressed: onNewOperationPressed,
            ),
          ),
          const SizedBox(height: 24),

          // Navigation Links
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: mainItems.length,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final item = mainItems[index];
                final isActive = navigationShell != null
                    ? navigationShell!.currentIndex == index
                    : currentRoute == item.routePath;

                return _SideNavItemTile(
                  item: item,
                  isActive: isActive,
                  onTap: () {
                    if (navigationShell != null &&
                        index < navigationShell!.route.branches.length) {
                      navigationShell!.goBranch(
                        index,
                        initialLocation: index == navigationShell!.currentIndex,
                      );
                    } else {
                      context.go(item.routePath);
                    }
                  },
                );
              },
            ),
          ),

          // Bottom Status Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.circle, color: AppColors.success, size: 8),
                const SizedBox(width: 8),
                Text(
                  'System Online',
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
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
