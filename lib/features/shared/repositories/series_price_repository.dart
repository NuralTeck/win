import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/series_price_model.dart';
import '../../../core/database/database_service.dart';

abstract class SeriesPriceRepository {
  Future<List<UniversalSeriesPriceModel>> getSeriesPrices();
  Future<UniversalSeriesPriceModel> createSeriesPrice(UniversalSeriesPriceModel item);
  Future<void> updateSeriesPrice(UniversalSeriesPriceModel item);
  Future<void> deleteSeriesPrice(String id);
}

class SqliteSeriesPriceRepository implements SeriesPriceRepository {
  final DatabaseService _dbService = DatabaseService.instance;

  @override
  Future<List<UniversalSeriesPriceModel>> getSeriesPrices() async {
    return await _dbService.getSeriesPrices();
  }

  @override
  Future<UniversalSeriesPriceModel> createSeriesPrice(UniversalSeriesPriceModel item) async {
    return await _dbService.insertSeriesPrice(item);
  }

  @override
  Future<void> updateSeriesPrice(UniversalSeriesPriceModel item) async {
    await _dbService.updateSeriesPrice(item);
  }

  @override
  Future<void> deleteSeriesPrice(String id) async {
    await _dbService.deleteSeriesPrice(id);
  }
}

final seriesPriceRepositoryProvider = Provider<SeriesPriceRepository>((ref) {
  return SqliteSeriesPriceRepository();
});
