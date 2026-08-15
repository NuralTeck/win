import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/app_decorations.dart';
import '../constants/app_constants.dart';
import '../services/whatsapp_engine_service.dart';

class TopAppBar extends StatelessWidget {
  final String title;

  const TopAppBar({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
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
          // Platform Title
          Text(
            title,
            style: AppTypography.titleLg.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),

          Row(
            children: [
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

              // User Profile Pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: AppDecorations.radiusPill,
                  border: Border.all(color: AppColors.border, width: 1),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.primaryContainer,
                      child: Text(
                        'A',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Admin Command Center',
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
