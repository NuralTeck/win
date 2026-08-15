import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/seller_model.dart';
import '../../shared/repositories/sellers_repository.dart';

class SellersState {
  final bool isLoading;
  final List<SellerModel> sellers;
  final String searchQuery;
  final SellerTier? selectedTier;

  const SellersState({
    this.isLoading = true,
    this.sellers = const [],
    this.searchQuery = '',
    this.selectedTier,
  });

  List<SellerModel> get filteredSellers {
    return sellers.where((seller) {
      final matchesSearch = seller.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
          seller.code.toLowerCase().contains(searchQuery.toLowerCase()) ||
          seller.category.toLowerCase().contains(searchQuery.toLowerCase());
      final matchesTier = selectedTier == null || seller.tier == selectedTier;
      return matchesSearch && matchesTier;
    }).toList();
  }

  SellersState copyWith({
    bool? isLoading,
    List<SellerModel>? sellers,
    String? searchQuery,
    SellerTier? selectedTier,
    bool clearTier = false,
  }) {
    return SellersState(
      isLoading: isLoading ?? this.isLoading,
      sellers: sellers ?? this.sellers,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedTier: clearTier ? null : (selectedTier ?? this.selectedTier),
    );
  }
}

class SellersViewModel extends StateNotifier<SellersState> {
  final SellersRepository _sellersRepository;

  SellersViewModel(this._sellersRepository) : super(const SellersState()) {
    loadSellers();
  }

  Future<void> loadSellers() async {
    state = state.copyWith(isLoading: true);
    final data = await _sellersRepository.getSellers();
    state = state.copyWith(isLoading: false, sellers: data);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setTierFilter(SellerTier? tier) {
    if (tier == null) {
      state = state.copyWith(clearTier: true);
    } else {
      state = state.copyWith(selectedTier: tier);
    }
  }
}

final sellersViewModelProvider =
    StateNotifierProvider<SellersViewModel, SellersState>((ref) {
  final repo = ref.watch(sellersRepositoryProvider);
  return SellersViewModel(repo);
});
