import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/seller_customer_model.dart';
import '../../../core/database/database_service.dart';
import '../../../core/database/supabase_service.dart';

class SellerCustomerState {
  final List<SellerCustomerModel> sellers;
  final bool isLoading;
  final String? errorMessage;
  final String searchQuery;

  SellerCustomerState({
    required this.sellers,
    this.isLoading = true,
    this.errorMessage,
    this.searchQuery = '',
  });

  SellerCustomerState copyWith({
    List<SellerCustomerModel>? sellers,
    bool? isLoading,
    String? errorMessage,
    String? searchQuery,
  }) {
    return SellerCustomerState(
      sellers: sellers ?? this.sellers,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  List<SellerCustomerModel> get filteredSellers {
    if (searchQuery.trim().isEmpty) return sellers;
    final q = searchQuery.toLowerCase().trim();
    return sellers.where((s) {
      return s.name.toLowerCase().contains(q) ||
          s.accessKey.toLowerCase().contains(q) ||
          s.phone.contains(q);
    }).toList();
  }
}

class SellerCustomerViewModel extends StateNotifier<SellerCustomerState> {
  final DatabaseService _dbService = DatabaseService.instance;

  SellerCustomerViewModel()
      : super(SellerCustomerState(sellers: [], isLoading: true)) {
    loadSellers();
  }

  Future<void> loadSellers() async {
    if (state.sellers.isEmpty) {
      state = state.copyWith(isLoading: true);
    }
    try {
      final list = await _dbService.getSellerCustomers();
      state = state.copyWith(isLoading: false, sellers: list);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, errorMessage: 'Failed to load sellers');
    }
  }


  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  Future<void> addSeller({
    required String name,
    required String accessKey,
    required String password,
    required String phone,
    bool isActive = true,
  }) async {
    final newSeller = SellerCustomerModel(
      id: 'sc_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      accessKey: accessKey.trim().toUpperCase(),
      password: password.trim(),
      phone: phone.trim(),
      isActive: isActive,
      createdAt: DateTime.now(),
    );

    await _dbService.insertSellerCustomer(newSeller);
    await SupabaseService.instance.upsertSeller(newSeller);
    state = state.copyWith(
      sellers: [newSeller, ...state.sellers],
    );
  }

  Future<void> updateSeller({
    required String id,
    required String name,
    required String accessKey,
    required String password,
    required String phone,
    required bool isActive,
  }) async {
    final updated = SellerCustomerModel(
      id: id,
      name: name.trim(),
      accessKey: accessKey.trim().toUpperCase(),
      password: password.trim(),
      phone: phone.trim(),
      isActive: isActive,
      createdAt: DateTime.now(),
    );

    await _dbService.updateSellerCustomer(updated);
    await SupabaseService.instance.upsertSeller(updated);
    final updatedList = state.sellers.map((s) {
      return s.id == id ? updated : s;
    }).toList();

    state = state.copyWith(sellers: updatedList);
  }

  Future<void> deleteSeller(String id) async {
    await _dbService.deleteSellerCustomer(id);
    await SupabaseService.instance.deleteSeller(id);
    state = state.copyWith(
      sellers: state.sellers.where((s) => s.id != id).toList(),
    );
  }

  Future<void> toggleSellerStatus(String id) async {
    final seller = state.sellers.firstWhere((s) => s.id == id);
    final updated = seller.copyWith(isActive: !seller.isActive);
    await _dbService.updateSellerCustomer(updated);
    await SupabaseService.instance.upsertSeller(updated);

    final updatedList = state.sellers.map((s) {
      return s.id == id ? updated : s;
    }).toList();

    state = state.copyWith(sellers: updatedList);
  }
}

final sellerCustomerViewModelProvider =
    StateNotifierProvider<SellerCustomerViewModel, SellerCustomerState>((ref) {
  return SellerCustomerViewModel();
});
