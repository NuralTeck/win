import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/operation_model.dart';
import '../../../core/services/mock_data_service.dart';

abstract class OperationsRepository {
  Future<List<OperationModel>> getOperations();
  Future<OperationModel> createOperation(OperationModel operation);
  Future<void> updateOperation(OperationModel operation);
  Future<void> updateOperationStatus(String id, OperationStatus status);
}

class MockOperationsRepository implements OperationsRepository {
  List<OperationModel> _items = MockDataService.getOperations();

  @override
  Future<List<OperationModel>> getOperations() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return List.from(_items);
  }

  @override
  Future<OperationModel> createOperation(OperationModel operation) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _items = [operation, ..._items];
    return operation;
  }

  @override
  Future<void> updateOperation(OperationModel operation) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _items = _items.map((item) => item.id == operation.id ? operation : item).toList();
  }

  @override
  Future<void> updateOperationStatus(String id, OperationStatus status) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _items = _items.map((item) {
      if (item.id == id) {
        return item.copyWith(status: status, updatedAt: DateTime.now());
      }
      return item;
    }).toList();
  }
}

final operationsRepositoryProvider = Provider<OperationsRepository>((ref) {
  return MockOperationsRepository();
});
