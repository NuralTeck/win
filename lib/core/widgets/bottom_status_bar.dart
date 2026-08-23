import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../constants/app_constants.dart';
import '../services/internet_connectivity_service.dart';

class BottomStatusBar extends StatelessWidget {
  const BottomStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppConstants.bottomStatusBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: InternetConnectivityService.instance.isOnlineNotifier,
                builder: (context, isOnline, _) {
                  return InkWell(
                    onTap: () {
                      if (!isOnline) {
                        InternetConnectivityService.instance.showOfflineModalAgain();
                      } else {
                        InternetConnectivityService.instance.checkConnectivity();
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                          size: 14,
                          color: isOnline ? AppColors.success : Colors.redAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isOnline ? 'Supabase Cloud Connected' : 'Offline (No Internet)',
                          style: AppTypography.labelSm.copyWith(
                            color: isOnline ? AppColors.textSecondary : Colors.redAccent,
                            fontWeight: isOnline ? FontWeight.normal : FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
              Container(width: 1, height: 12, color: AppColors.border),
              const SizedBox(width: 16),
              const Icon(Icons.storage_rounded, size: 13, color: Color(0xFF4ADE80)),
              const SizedBox(width: 5),
              Text(
                'SQLite Local Database Active',
                style: AppTypography.labelSm.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          Text(
            'PhantomManagement v1.0.0',
            style: AppTypography.labelSm.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
