import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/draw_model.dart';
import '../../../core/services/mock_data_service.dart';

abstract class DrawsRepository {
  Future<List<DrawModel>> getDraws();
  Future<DrawModel> createDraw(DrawModel draw);
  Future<void> updateDraw(DrawModel draw);
  Future<void> updateDrawStatus(String id, DrawStatus status);
}

class MockDrawsRepository implements DrawsRepository {
  List<DrawModel> _items = MockDataService.getDraws();

  @override
  Future<List<DrawModel>> getDraws() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return List.from(_items);
  }

  @override
  Future<DrawModel> createDraw(DrawModel draw) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _items = [draw, ..._items];
    return draw;
  }

  @override
  Future<void> updateDraw(DrawModel draw) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _items = _items.map((item) => item.id == draw.id ? draw : item).toList();
  }

  @override
  Future<void> updateDrawStatus(String id, DrawStatus status) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _items = _items.map((item) {
      if (item.id == id) {
        return item.copyWith(status: status, updatedAt: DateTime.now());
      }
      return item;
    }).toList();
  }
}

final drawsRepositoryProvider = Provider<DrawsRepository>((ref) {
  return MockDrawsRepository();
});
