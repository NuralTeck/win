import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/series_price_model.dart';
import '../../shared/repositories/series_price_repository.dart';
import '../../../core/services/series_color_registry.dart';
import '../../../core/database/database_service.dart';

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

  /// ⚡ Dynamic per-unit series rate (e.g. ₹3.80 per 1 unit if Series 100 = ₹380)
  double get perUnitRate {
    // 1. Check Series 100
    final s100 = seriesList.where(
      (s) => s.isActive && (s.seriesName.trim() == '100' || s.seriesName.replaceAll(RegExp(r'\D'), '') == '100'),
    );
    if (s100.isNotEmpty && s100.first.ticketPrice > 0) {
      return s100.first.ticketPrice / 100.0;
    }

    // 2. Derive dynamically from any other active numeric series
    for (final s in seriesList.where((s) => s.isActive && s.ticketPrice > 0)) {
      final numVal = double.tryParse(s.seriesName.replaceAll(RegExp(r'\D'), ''));
      if (numVal != null && numVal > 0) {
        return s.ticketPrice / numVal;
      }
    }

    // 3. Fallback standard unit rate if database is completely empty
    return 3.75;
  }

  /// Current configured price for Series 100
  double get series100Price => perUnitRate * 100.0;

  double getPriceForSeries(String seriesName) {
    if (seriesName.trim().isEmpty) return 0.0;

    // 1. Exact match in Settings (custom explicit price configured by user)
    final clean = seriesName.trim().toUpperCase();
    final found = seriesList.where(
      (s) => s.isActive && s.seriesName.trim().toUpperCase() == clean,
    );
    if (found.isNotEmpty && found.first.ticketPrice > 0) {
      return found.first.ticketPrice;
    }

    // 2. Dynamic formula: multiply series numeric value by dynamic perUnitRate
    // e.g. 12 -> 12 * 3.80 = 45.60, 24 -> 24 * 3.80 = 91.20, 50 -> 50 * 3.80 = 190.00
    final digits = seriesName.replaceAll(RegExp(r'\D'), '');
    final seriesNum = double.tryParse(digits) ?? 0.0;
    if (seriesNum > 0) {
      return perUnitRate * seriesNum;
    }

    // Default 12 series multiplier if no digits present
    return perUnitRate * 12.0;
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
      SeriesColorRegistry.updateFromList(list);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, errorMessage: 'Failed to load series & prices');
    }
  }

  Future<void> addSeriesPrice(UniversalSeriesPriceModel item) async {
    final created = await _repo.createSeriesPrice(item);
    state = state.copyWith(seriesList: [created, ...state.seriesList]);
    SeriesColorRegistry.updateFromList(state.seriesList);
  }

  Future<void> updateSeriesPrice(UniversalSeriesPriceModel item) async {
    await _repo.updateSeriesPrice(item);
    final updated =
        state.seriesList.map((i) => i.id == item.id ? item : i).toList();
    state = state.copyWith(seriesList: updated);
    SeriesColorRegistry.updateFromList(state.seriesList);
  }

  Future<void> updateSeriesColor(String seriesName, Color color, {double? newPrice}) async {
    final clean = seriesName.replaceAll(RegExp(r'\D'), '');
    final found = state.seriesList.where(
      (s) => s.seriesName.trim().toUpperCase() == seriesName.trim().toUpperCase() ||
             (clean.isNotEmpty && s.seriesName.replaceAll(RegExp(r'\D'), '') == clean),
    );

    if (found.isNotEmpty) {
      final existing = found.first;
      final updated = existing.copyWith(
        colorValue: color.toARGB32(),
        ticketPrice: newPrice ?? existing.ticketPrice,
      );
      await updateSeriesPrice(updated);
    } else {
      final price = newPrice ?? state.getPriceForSeries(seriesName);
      final newItem = UniversalSeriesPriceModel(
        id: 'sp_${DateTime.now().millisecondsSinceEpoch}',
        seriesName: seriesName,
        ticketPrice: price > 0 ? price : 45.0,
        colorValue: color.toARGB32(),
        isActive: true,
        createdAt: DateTime.now(),
      );
      await addSeriesPrice(newItem);
    }
    SeriesColorRegistry.setCustomColor(seriesName, color);
  }

  Future<void> deleteSeriesPrice(String id) async {
    await _repo.deleteSeriesPrice(id);
    final filtered = state.seriesList.where((i) => i.id != id).toList();
    state = state.copyWith(seriesList: filtered);
    SeriesColorRegistry.updateFromList(state.seriesList);
  }

  Future<void> toggleStatus(String id) async {
    final item = state.seriesList.firstWhere((i) => i.id == id);
    final updated = item.copyWith(isActive: !item.isActive);
    await updateSeriesPrice(updated);
  }

  /// ⚡ Bulk Recalculate & Sync Rates for existing entries across the system
  Future<Map<String, int>> recalculateRatesAcrossSystem({
    String? date,
    String? startDate,
    String? endDate,
    String? drawShift,
    String? partyName,
    List<String>? partyNames,
    double? customSeries100Price,
    bool updateVouchers = true,
    bool updateUnsold = true,
    bool updateSales = true,
  }) async {
    return await DatabaseService.instance.recalculateRatesAcrossSystem(
      date: date,
      startDate: startDate,
      endDate: endDate,
      drawShift: drawShift,
      partyName: partyName,
      partyNames: partyNames,
      customSeries100Price: customSeries100Price,
      updateVouchers: updateVouchers,
      updateUnsold: updateUnsold,
      updateSales: updateSales,
    );
  }

  /// 🔍 Fetch distinct parties present in vouchers / unsold / sales for target date / range
  Future<List<String>> getActivePartiesForSelection({
    String? date,
    String? startDate,
    String? endDate,
    String? drawShift,
  }) async {
    return await DatabaseService.instance.getActivePartiesForSelection(
      date: date,
      startDate: startDate,
      endDate: endDate,
      drawShift: drawShift,
    );
  }
}

final seriesPriceViewModelProvider =
    StateNotifierProvider<SeriesPriceViewModel, SeriesPriceState>((ref) {
  final repo = ref.watch(seriesPriceRepositoryProvider);
  return SeriesPriceViewModel(repo);
});
