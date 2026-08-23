import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class InternetConnectivityService {
  InternetConnectivityService._();
  static final InternetConnectivityService instance = InternetConnectivityService._();

  final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isDismissedByUserNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isCheckingNotifier = ValueNotifier<bool>(false);

  Timer? _timer;
  bool _initialized = false;

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    // Initial check
    checkConnectivity();

    // Check periodically every 4 seconds
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      checkConnectivity();
    });
  }

  void dispose() {
    _timer?.cancel();
  }

  Future<bool> checkConnectivity() async {
    isCheckingNotifier.value = true;
    bool online = false;

    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(milliseconds: 2500));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        online = true;
      }
    } on SocketException catch (_) {
      online = false;
    } on TimeoutException catch (_) {
      online = false;
    } catch (_) {
      online = false;
    }

    // Secondary fallback check if first check failed
    if (!online) {
      try {
        final result = await InternetAddress.lookup('1.1.1.1')
            .timeout(const Duration(milliseconds: 1500));
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          online = true;
        }
      } catch (_) {
        online = false;
      }
    }

    final previousState = isOnlineNotifier.value;
    isOnlineNotifier.value = online;
    isCheckingNotifier.value = false;

    // If internet just came back, reset dismissal so next time it goes offline it alerts again
    if (online && !previousState) {
      isDismissedByUserNotifier.value = false;
    }

    return online;
  }

  void dismissOfflineModal() {
    isDismissedByUserNotifier.value = true;
  }

  void showOfflineModalAgain() {
    isDismissedByUserNotifier.value = false;
  }
}
