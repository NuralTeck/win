import 'package:flutter/material.dart';
import '../services/internet_connectivity_service.dart';
import '../theme/app_colors.dart';

class OfflineAlertOverlay extends StatelessWidget {
  const OfflineAlertOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: InternetConnectivityService.instance.isOnlineNotifier,
      builder: (context, isOnline, _) {
        if (isOnline) return const SizedBox.shrink();

        return ValueListenableBuilder<bool>(
          valueListenable: InternetConnectivityService.instance.isDismissedByUserNotifier,
          builder: (context, isDismissed, _) {
            if (isDismissed) {
              // Subtle Floating Top Warning Strip when user chose to continue working offline
              return Positioned(
                top: 54,
                right: 24,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => InternetConnectivityService.instance.showOfflineModalAgain(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.4),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Offline Mode (Local DB Safe) • Click to Check',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            // Full Cyber-Modern Offline Modal Popup
            return Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.75),
                child: Center(
                  child: Container(
                    width: 480,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.35),
                          blurRadius: 40,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Animated Offline Glowing Icon
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4), width: 2),
                          ),
                          child: const Icon(
                            Icons.wifi_off_rounded,
                            color: Colors.redAccent,
                            size: 44,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Title
                        const Text(
                          'No Internet Connection',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Explanation & Local Safety Guarantee
                        Text(
                          'Your device is currently disconnected from the internet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary.withValues(alpha: 0.9),
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Local SQLite Safety Card
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F2937),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.shield_rounded, color: Color(0xFF4ADE80), size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text(
                                      'Offline Mode Is Safe & Active',
                                      style: TextStyle(
                                        color: Color(0xFF4ADE80),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      'All ticket bookings, ledger entries, and bills will continue saving safely to your local SQLite database without any interruption.',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11.5,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Action Buttons
                        Row(
                          children: [
                            // Retry Button
                            Expanded(
                              child: ValueListenableBuilder<bool>(
                                valueListenable: InternetConnectivityService.instance.isCheckingNotifier,
                                builder: (context, isChecking, _) {
                                  return ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      elevation: 3,
                                    ),
                                    onPressed: isChecking
                                        ? null
                                        : () async {
                                            final online = await InternetConnectivityService.instance.checkConnectivity();
                                            if (context.mounted && !online) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('⚠️ Still no internet connection detected. Please check your WiFi / Ethernet cables.'),
                                                  backgroundColor: AppColors.error,
                                                  duration: Duration(seconds: 3),
                                                ),
                                              );
                                            }
                                          },
                                    icon: isChecking
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.refresh_rounded, size: 18),
                                    label: Text(
                                      isChecking ? 'Checking...' : 'Retry Connection',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Continue Offline Button
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: const BorderSide(color: AppColors.border, width: 1.5),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () {
                                  InternetConnectivityService.instance.dismissOfflineModal();
                                },
                                icon: const Icon(Icons.cloud_off_rounded, size: 18),
                                label: const Text(
                                  'Work Offline',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
