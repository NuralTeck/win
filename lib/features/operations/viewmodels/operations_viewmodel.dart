import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/operation_model.dart';
import '../../shared/repositories/operations_repository.dart';

class OperationsState {
  final bool isLoading;
  final List<OperationModel> operations;
  final String searchQuery;
  final OperationStatus? selectedStatus;
  final String? errorMessage;

  const OperationsState({
    this.isLoading = true,
    this.operations = const [],
    this.searchQuery = '',
    this.selectedStatus,
    this.errorMessage,
  });

  List<OperationModel> get filteredOperations {
    return operations.where((op) {
      final matchesSearch = op.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
          op.code.toLowerCase().contains(searchQuery.toLowerCase()) ||
          op.category.toLowerCase().contains(searchQuery.toLowerCase());

      final matchesStatus = selectedStatus == null || op.status == selectedStatus;
      return matchesSearch && matchesStatus;
    }).toList();
  }

  OperationsState copyWith({
    bool? isLoading,
    List<OperationModel>? operations,
    String? searchQuery,
    OperationStatus? selectedStatus,
    bool clearStatusFilter = false,
    String? errorMessage,
  }) {
    return OperationsState(
      isLoading: isLoading ?? this.isLoading,
      operations: operations ?? this.operations,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedStatus: clearStatusFilter ? null : (selectedStatus ?? this.selectedStatus),
      errorMessage: errorMessage,
    );
  }
}

class OperationsViewModel extends StateNotifier<OperationsState> {
  final OperationsRepository _operationsRepository;

  OperationsViewModel(this._operationsRepository) : super(const OperationsState()) {
    loadOperations();
  }

  Future<void> loadOperations() async {
    state = state.copyWith(isLoading: true);
    try {
      final list = await _operationsRepository.getOperations();
      state = state.copyWith(isLoading: false, operations: list);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to load operations.');
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setStatusFilter(OperationStatus? status) {
    if (status == null) {
      state = state.copyWith(clearStatusFilter: true);
    } else {
      state = state.copyWith(selectedStatus: status);
    }
  }

  Future<void> addOperation(OperationModel operation) async {
    final created = await _operationsRepository.createOperation(operation);
    state = state.copyWith(operations: [created, ...state.operations]);
  }

  Future<void> updateOperation(OperationModel operation) async {
    await _operationsRepository.updateOperation(operation);
    final updatedList = state.operations.map((op) {
      return op.id == operation.id ? operation : op;
    }).toList();
    state = state.copyWith(operations: updatedList);
  }
}

final operationsViewModelProvider =
    StateNotifierProvider<OperationsViewModel, OperationsState>((ref) {
  final repo = ref.watch(operationsRepositoryProvider);
  return OperationsViewModel(repo);
});
