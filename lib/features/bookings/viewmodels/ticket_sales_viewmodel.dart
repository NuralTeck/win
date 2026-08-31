import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../../shared/repositories/ticket_sales_repository.dart';

class TicketSalesState {
  final bool isLoading;
  final List<TicketSaleModel> sales;
  final String searchQuery;
  final TicketStatus? selectedStatus;
  final String? errorMessage;

  const TicketSalesState({
    this.isLoading = true,
    this.sales = const [],
    this.searchQuery = '',
    this.selectedStatus,
    this.errorMessage,
  });

  List<TicketSaleModel> get filteredSales {
    return sales.where((s) {
      final q = searchQuery.toLowerCase();
      final matchesSearch = s.receiptNumber.toLowerCase().contains(q) ||
          s.buyerName.toLowerCase().contains(q) ||
          s.ticketNumber.toLowerCase().contains(q) ||
          s.drawName.toLowerCase().contains(q) ||
          s.agentName.toLowerCase().contains(q);
      final matchesStatus = selectedStatus == null || s.status == selectedStatus;
      return matchesSearch && matchesStatus;
    }).toList();
  }

  double get totalRevenue =>
      filteredSales.fold(0.0, (sum, s) => sum + s.totalAmount);

  double get totalCommissions =>
      filteredSales.fold(0.0, (sum, s) => sum + s.commissionAmount);

  int get totalTicketsCount =>
      filteredSales.fold(0, (sum, s) => sum + s.quantity);

  TicketSalesState copyWith({
    bool? isLoading,
    List<TicketSaleModel>? sales,
    String? searchQuery,
    TicketStatus? selectedStatus,
    bool clearStatusFilter = false,
    String? errorMessage,
  }) {
    return TicketSalesState(
      isLoading: isLoading ?? this.isLoading,
      sales: sales ?? this.sales,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedStatus:
          clearStatusFilter ? null : (selectedStatus ?? this.selectedStatus),
      errorMessage: errorMessage,
    );
  }
}

class TicketSalesViewModel extends StateNotifier<TicketSalesState> {
  final TicketSalesRepository _repo;

  TicketSalesViewModel(this._repo) : super(const TicketSalesState()) {
    loadSales();
  }

  Future<void> loadSales() async {
    if (!mounted) return;
    if (state.sales.isEmpty) {
      state = state.copyWith(isLoading: true);
    }
    try {
      final list = await _repo.getTicketSales();
      if (!mounted) return;
      state = state.copyWith(isLoading: false, sales: list);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to load ticket sales.');
    }
  }

  void setSearchQuery(String query) => state = state.copyWith(searchQuery: query);

  void setStatusFilter(TicketStatus? status) {
    if (status == null) {
      state = state.copyWith(clearStatusFilter: true);
    } else {
      state = state.copyWith(selectedStatus: status);
    }
  }

  Future<void> addTicketSale(TicketSaleModel sale) async {
    final created = await _repo.createTicketSale(sale);
    state = state.copyWith(sales: [created, ...state.sales]);
  }

  Future<void> addTicketSalesBulk(List<TicketSaleModel> sales) async {
    if (sales.isEmpty) return;
    await _repo.createTicketSalesBulk(sales);
    state = state.copyWith(sales: [...sales, ...state.sales]);
  }

  Future<void> updateTicketSale(TicketSaleModel sale) async {
    await _repo.updateTicketSale(sale);
    final updated = state.sales.map((s) => s.id == sale.id ? sale : s).toList();
    state = state.copyWith(sales: updated);
  }

  Future<void> deleteTicketSale(String id) async {
    await _repo.deleteTicketSale(id);
    state = state.copyWith(
      sales: state.sales.where((s) => s.id != id).toList(),
    );
  }

}

final ticketSalesViewModelProvider =
    StateNotifierProvider<TicketSalesViewModel, TicketSalesState>((ref) {
  final repo = ref.watch(ticketSalesRepositoryProvider);
  return TicketSalesViewModel(repo);
});
