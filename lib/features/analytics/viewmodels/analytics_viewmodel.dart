import 'package:flutter_riverpod/flutter_riverpod.dart';

class AnalyticsState {
  final bool isLoading;
  final String selectedTimeframe;

  const AnalyticsState({
    this.isLoading = false,
    this.selectedTimeframe = 'Last 30 Days',
  });

  AnalyticsState copyWith({
    bool? isLoading,
    String? selectedTimeframe,
  }) {
    return AnalyticsState(
      isLoading: isLoading ?? this.isLoading,
      selectedTimeframe: selectedTimeframe ?? this.selectedTimeframe,
    );
  }
}

class AnalyticsViewModel extends StateNotifier<AnalyticsState> {
  AnalyticsViewModel() : super(const AnalyticsState());

  void setTimeframe(String timeframe) {
    state = state.copyWith(selectedTimeframe: timeframe);
  }
}

final analyticsViewModelProvider =
    StateNotifierProvider<AnalyticsViewModel, AnalyticsState>((ref) {
  return AnalyticsViewModel();
});
