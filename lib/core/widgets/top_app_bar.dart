import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/app_decorations.dart';
import '../constants/app_constants.dart';
import '../config/app_routes.dart';
import '../services/whatsapp_engine_service.dart';
import '../services/pending_photos_service.dart';
import '../process/widgets/process_status_pill.dart';
import '../../features/auth/viewmodels/auth_viewmodel.dart';
import '../../features/auth/models/user_model.dart';

class TopAppBar extends ConsumerWidget {
  final String title;
  final VoidCallback? onToggleSidebar;
  final bool isSidebarVisible;

  const TopAppBar({
    super.key,
    required this.title,
    this.onToggleSidebar,
    this.isSidebarVisible = true,
  });

  void _showUserProfileModal(BuildContext context, WidgetRef ref, UserModel? user) {
    final displayName = user?.fullName.isNotEmpty == true
        ? user!.fullName
        : (user?.username ?? 'Admin User');
    final emailOrUser = user?.username ?? 'admin@hms.com';
    final role = user?.role ?? 'Master Administrator';
    final initialLetter = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 36,
                spreadRadius: 6,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with Big Glowing Avatar
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF10B981)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.5),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  initialLetter,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // User Name & Role
              Text(
                displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                emailOrUser,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),

              // Role Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                ),
                child: Text(
                  role.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF34D399),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 16),

              // Account Details Info Box
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _buildInfoRow(Icons.security_rounded, 'Session Security', 'Supabase Cloud Auth (Active)'),
                    const SizedBox(height: 10),
                    _buildInfoRow(Icons.cloud_done_rounded, 'Persistence', 'Stay Logged In Enabled'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons: Close & Logout
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 3,
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text(
                        'LOGOUT',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await ref.read(authControllerProvider).logout();
                        final rootCtx = rootNavigatorKey.currentContext;
                        if (rootCtx != null && rootCtx.mounted) {
                          ScaffoldMessenger.of(rootCtx).showSnackBar(
                            const SnackBar(
                              content: Text('🔒 Logged out successfully. See you soon!'),
                              backgroundColor: AppColors.primary,
                              duration: Duration(seconds: 2),
                            ),
                          );
                          rootCtx.go(AppConstants.routeLogin);
                        } else if (context.mounted) {
                          context.go(AppConstants.routeLogin);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final displayName = user?.username ?? user?.fullName ?? 'Admin Command Center';
    final initialLetter = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A';

    return Container(
      height: AppConstants.topHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.glassPanelBg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Sidebar Toggle Button
          if (onToggleSidebar != null) ...[
            IconButton(
              icon: Icon(
                isSidebarVisible ? Icons.menu_open_rounded : Icons.menu_rounded,
                color: isSidebarVisible ? Colors.white70 : const Color(0xFF38BDF8),
                size: 22,
              ),
              tooltip: isSidebarVisible ? 'Hide Sidebar (Full Screen)' : 'Show Sidebar',
              onPressed: onToggleSidebar,
            ),
            const SizedBox(width: 8),
          ],

          // Platform Title
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleLg.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),

          Row(
            children: [
              // 📸 Quiet Pending WhatsApp Photos Badge (Keeps photos in one place until user wants to review)
              ValueListenableBuilder<int>(
                valueListenable: PendingPhotosService.instance.pendingCountNotifier,
                builder: (context, count, _) {
                  if (count <= 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: InkWell(
                      onTap: () {
                        PendingPhotosService.instance.requestOpenQueue();
                        context.go(AppConstants.routeBookings);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amberAccent, width: 1.2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_library_rounded, size: 16, color: Colors.amberAccent),
                            const SizedBox(width: 6),
                            Text(
                              '$count Photos Pending',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.amberAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

              // WhatsApp Engine Console Terminal Toggle Button
              ValueListenableBuilder<WhatsAppEngineStatus>(
                valueListenable: WhatsAppEngineService.instance.statusNotifier,
                builder: (context, engineStatus, _) {
                  final isLive = engineStatus.isConnected;
                  final isOnline = engineStatus.online;
                  final color = isLive
                      ? AppColors.success
                      : (isOnline ? Colors.orangeAccent : Colors.grey);

                  return InkWell(
                    onTap: () {
                      WhatsAppEngineService.instance.toggleConsoleVisibility();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.terminal_rounded, size: 16, color: color),
                          const SizedBox(width: 6),
                          Text(
                            isLive ? 'Bot Live' : 'Console',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 14),

              // 🚀 Real-time Process Manager & Queue Status Pill
              const ProcessStatusPill(),
              const SizedBox(width: 16),

              // System Live Operational Badge
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SYSTEM OPERATIONAL',
                    style: AppTypography.labelSm.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 24),

              // Dynamic User Profile Pill with Click-to-Logout
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showUserProfileModal(context, ref, user),
                  borderRadius: AppDecorations.radiusPill,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: AppDecorations.radiusPill,
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 1),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: AppColors.primary,
                          child: Text(
                            initialLetter,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            displayName,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
