import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/series_price_model.dart';
import '../../shared/repositories/series_price_repository.dart';

class SeriesPriceState {
  final bool isLoading;
  final List<UniversalSeriesPriceModel> seriesList;
  final String? errorMessage;

  const SeriesPriceState({
    this.isLoading = true,
    this.seriesList = const [],
    this.errorMessage,
  });

  List<String> get availableSeriesNames =>
      seriesList.where((s) => s.isActive).map((s) => s.seriesName).toList();

  double getPriceForSeries(String seriesName) {
    // 1. Exact match in Settings
    final found = seriesList.where(
      (s) => s.seriesName.trim().toUpperCase() == seriesName.trim().toUpperCase(),
    );
    if (found.isNotEmpty) {
      return found.first.ticketPrice;
    }

    // 2. Dynamic formula: derive per-series rate from Series 100 price in Settings
    //    Any series price = (Series100Price / 100) × series_number
    final series100 = seriesList.where(
      (s) => s.seriesName.trim() == '100' && s.isActive,
    );
    if (series100.isNotEmpty && series100.first.ticketPrice > 0) {
      final perSeriesRate = series100.first.ticketPrice / 100.0;
      final digits = seriesName.replaceAll(RegExp(r'\D'), '');
      final seriesNum = double.tryParse(digits) ?? 0.0;
      if (seriesNum > 0) return perSeriesRate * seriesNum;
    }

    return 0.0; // No price configured
  }

  SeriesPriceState copyWith({
    bool? isLoading,
    List<UniversalSeriesPriceModel>? seriesList,
    String? errorMessage,
  }) {
    return SeriesPriceState(
      isLoading: isLoading ?? this.isLoading,
      seriesList: seriesList ?? this.seriesList,
      errorMessage: errorMessage,
    );
  }
}

class SeriesPriceViewModel extends StateNotifier<SeriesPriceState> {
  final SeriesPriceRepository _repo;

  SeriesPriceViewModel(this._repo) : super(const SeriesPriceState()) {
    loadSeriesPrices();
  }

  Future<void> loadSeriesPrices() async {
    state = state.copyWith(isLoading: true);
    try {
      final list = await _repo.getSeriesPrices();
      state = state.copyWith(isLoading: false, seriesList: list);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, errorMessage: 'Failed to load series & prices');
    }
  }

  Future<void> addSeriesPrice(UniversalSeriesPriceModel item) async {
    final created = await _repo.createSeriesPrice(item);
    state = state.copyWith(seriesList: [created, ...state.seriesList]);
  }

  Future<void> updateSeriesPrice(UniversalSeriesPriceModel item) async {
    await _repo.updateSeriesPrice(item);
    final updated =
        state.seriesList.map((i) => i.id == item.id ? item : i).toList();
    state = state.copyWith(seriesList: updated);
  }

  Future<void> deleteSeriesPrice(String id) async {
    await _repo.deleteSeriesPrice(id);
    final filtered = state.seriesList.where((i) => i.id != id).toList();
    state = state.copyWith(seriesList: filtered);
  }

  Future<void> toggleStatus(String id) async {
    final item = state.seriesList.firstWhere((i) => i.id == id);
    final updated = item.copyWith(isActive: !item.isActive);
    await updateSeriesPrice(updated);
  }
}

final seriesPriceViewModelProvider =
    StateNotifierProvider<SeriesPriceViewModel, SeriesPriceState>((ref) {
  final repo = ref.watch(seriesPriceRepositoryProvider);
  return SeriesPriceViewModel(repo);
});
