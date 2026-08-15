import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/booking_model.dart';
import '../../../core/services/mock_data_service.dart';

abstract class BookingsRepository {
  Future<List<BookingModel>> getBookings();
}

class MockBookingsRepository implements BookingsRepository {
  @override
  Future<List<BookingModel>> getBookings() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return MockDataService.getBookings();
  }
}

final bookingsRepositoryProvider = Provider<BookingsRepository>((ref) {
  return MockBookingsRepository();
});
