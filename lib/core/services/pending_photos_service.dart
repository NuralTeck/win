import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/database_service.dart';

class PendingPhotosService {
  static final PendingPhotosService instance = PendingPhotosService._();
  PendingPhotosService._();

  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> openQueueRequestNotifier = ValueNotifier<int>(0);
  bool shouldOpenQueueOnMount = false;
  Timer? _timer;

  void requestOpenQueue() {
    shouldOpenQueueOnMount = true;
    openQueueRequestNotifier.value++;
  }

  void initialize() {
    refresh();
    _timer ??= Timer.periodic(const Duration(seconds: 4), (_) => refresh());
  }

  Future<void> refresh() async {
    try {
      final photos = await DatabaseService.instance.getPendingPhotoBookings();
      if (pendingCountNotifier.value != photos.length) {
        pendingCountNotifier.value = photos.length;
      }
    } catch (_) {}
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
