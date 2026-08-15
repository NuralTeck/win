import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/booking_model.dart';
import '../../shared/repositories/bookings_repository.dart';

class BookingsState {
  final bool isLoading;
  final List<BookingModel> bookings;
  final String searchQuery;
  final BookingStatus? selectedStatus;

  const BookingsState({
    this.isLoading = true,
    this.bookings = const [],
    this.searchQuery = '',
    this.selectedStatus,
  });

  List<BookingModel> get filteredBookings {
    return bookings.where((booking) {
      final matchesSearch = booking.referenceNumber.toLowerCase().contains(searchQuery.toLowerCase()) ||
          booking.customerName.toLowerCase().contains(searchQuery.toLowerCase()) ||
          booking.sellerName.toLowerCase().contains(searchQuery.toLowerCase());
      final matchesStatus = selectedStatus == null || booking.status == selectedStatus;
      return matchesSearch && matchesStatus;
    }).toList();
  }

  double get totalVolume {
    return filteredBookings.fold(0.0, (sum, item) => sum + item.amount);
  }

  double get totalCommissions {
    return filteredBookings.fold(0.0, (sum, item) => sum + item.commissionFee);
  }

  BookingsState copyWith({
    bool? isLoading,
    List<BookingModel>? bookings,
    String? searchQuery,
    BookingStatus? selectedStatus,
    bool clearStatus = false,
  }) {
    return BookingsState(
      isLoading: isLoading ?? this.isLoading,
      bookings: bookings ?? this.bookings,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedStatus: clearStatus ? null : (selectedStatus ?? this.selectedStatus),
    );
  }
}

class BookingsViewModel extends StateNotifier<BookingsState> {
  final BookingsRepository _bookingsRepository;

  BookingsViewModel(this._bookingsRepository) : super(const BookingsState()) {
    loadBookings();
  }

  Future<void> loadBookings() async {
    state = state.copyWith(isLoading: true);
    final data = await _bookingsRepository.getBookings();
    state = state.copyWith(isLoading: false, bookings: data);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setStatusFilter(BookingStatus? status) {
    if (status == null) {
      state = state.copyWith(clearStatus: true);
    } else {
      state = state.copyWith(selectedStatus: status);
    }
  }
}

final bookingsViewModelProvider =
    StateNotifierProvider<BookingsViewModel, BookingsState>((ref) {
  final repo = ref.watch(bookingsRepositoryProvider);
  return BookingsViewModel(repo);
});
