import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../../shared/repositories/ticket_sales_repository.dart';

class TicketSalesState {
  final bool isLoading;
  final List<TicketSaleModel> sales;
  final String searchQuery;
  final TicketStatus? selectedStatus;
  final DateTime? selectedDate;
  final String? errorMessage;

  final int currentPage;
  final int pageSize;
  final int totalCount;

  final List<TicketSaleModel>? cachedFilteredSales;
  final double? cachedTotalRevenue;
  final double? cachedTotalCommissions;
  final int? cachedTotalTicketsCount;

  const TicketSalesState({
    this.isLoading = true,
    this.sales = const [],
    this.searchQuery = '',
    this.selectedStatus,
    this.selectedDate,
    this.errorMessage,
    this.currentPage = 0,
    this.pageSize = 50,
    this.totalCount = 0,
    this.cachedFilteredSales,
    this.cachedTotalRevenue,
    this.cachedTotalCommissions,
    this.cachedTotalTicketsCount,
  });

  bool get hasMorePages => (currentPage + 1) * pageSize < totalCount;
  int get totalPages => pageSize > 0 ? (totalCount / pageSize).ceil() : 0;

  List<TicketSaleModel> get filteredSales {
    if (cachedFilteredSales != null) return cachedFilteredSales!;
    if (searchQuery.isEmpty && selectedStatus == null) return sales;
    final q = searchQuery.toLowerCase();
    return sales.where((s) {
      final matchesSearch = q.isEmpty ||
          s.receiptNumber.toLowerCase().contains(q) ||
          s.buyerName.toLowerCase().contains(q) ||
          s.ticketNumber.toLowerCase().contains(q) ||
          s.drawName.toLowerCase().contains(q) ||
          s.agentName.toLowerCase().contains(q);
      final matchesStatus = selectedStatus == null || s.status == selectedStatus;
      return matchesSearch && matchesStatus;
    }).toList();
  }

  double get totalRevenue =>
      cachedTotalRevenue ?? filteredSales.fold(0.0, (sum, s) => sum + s.totalAmount);

  double get totalCommissions =>
      cachedTotalCommissions ?? filteredSales.fold(0.0, (sum, s) => sum + s.commissionAmount);

  int get totalTicketsCount =>
      cachedTotalTicketsCount ?? filteredSales.fold(0, (sum, s) => sum + s.quantity);

  TicketSalesState copyWith({
    bool? isLoading,
    List<TicketSaleModel>? sales,
    String? searchQuery,
    TicketStatus? selectedStatus,
    bool clearStatusFilter = false,
    DateTime? selectedDate,
    bool clearDateFilter = false,
    String? errorMessage,
    int? currentPage,
    int? pageSize,
    int? totalCount,
  }) {
    final nextSales = sales ?? this.sales;
    final nextQuery = searchQuery ?? this.searchQuery;
    final nextStatus =
        clearStatusFilter ? null : (selectedStatus ?? this.selectedStatus);
    final nextDate =
        clearDateFilter ? null : (selectedDate ?? this.selectedDate);

    final q = nextQuery.toLowerCase();
    final List<TicketSaleModel> computedFiltered;
    if (q.isEmpty && nextStatus == null) {
      computedFiltered = nextSales;
    } else {
      computedFiltered = nextSales.where((s) {
        final matchesSearch = q.isEmpty ||
            s.receiptNumber.toLowerCase().contains(q) ||
            s.buyerName.toLowerCase().contains(q) ||
            s.ticketNumber.toLowerCase().contains(q) ||
            s.drawName.toLowerCase().contains(q) ||
            s.agentName.toLowerCase().contains(q);
        final matchesStatus = nextStatus == null || s.status == nextStatus;
        return matchesSearch && matchesStatus;
      }).toList();
    }

    double rev = 0.0;
    double comm = 0.0;
    int tCount = 0;
    for (final s in computedFiltered) {
      rev += s.totalAmount;
      comm += s.commissionAmount;
      tCount += s.quantity;
    }

    return TicketSalesState(
      isLoading: isLoading ?? this.isLoading,
      sales: nextSales,
      searchQuery: nextQuery,
      selectedStatus: nextStatus,
      selectedDate: nextDate,
      errorMessage: errorMessage,
      currentPage: currentPage ?? this.currentPage,
      pageSize: pageSize ?? this.pageSize,
      totalCount: totalCount ?? this.totalCount,
      cachedFilteredSales: computedFiltered,
      cachedTotalRevenue: rev,
      cachedTotalCommissions: comm,
      cachedTotalTicketsCount: tCount,
    );
  }
}

class TicketSalesViewModel extends StateNotifier<TicketSalesState> {
  final TicketSalesRepository _repo;

  TicketSalesViewModel(this._repo) : super(const TicketSalesState()) {
    loadSales();
  }

  Future<void> loadSales({int? page}) async {
    if (!mounted) return;
    final targetPage = page ?? state.currentPage;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final offset = targetPage * state.pageSize;
      final q = state.searchQuery.trim().isEmpty ? null : state.searchQuery.trim();
      final list = await _repo.getTicketSales(
        limit: state.pageSize,
        offset: offset,
        searchQuery: q,
        status: state.selectedStatus,
        targetDate: state.selectedDate,
      );
      final count = await _repo.getTicketSalesCount(
        searchQuery: q,
        status: state.selectedStatus,
        targetDate: state.selectedDate,
      );
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        sales: list,
        currentPage: targetPage,
        totalCount: count,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load ticket sales: $e',
      );
    }
  }

  Future<void> nextPage() async {
    if (state.hasMorePages) {
      await loadSales(page: state.currentPage + 1);
    }
  }

  Future<void> previousPage() async {
    if (state.currentPage > 0) {
      await loadSales(page: state.currentPage - 1);
    }
  }

  Future<void> goToPage(int page) async {
    if (page >= 0 && (state.totalPages == 0 || page < state.totalPages)) {
      await loadSales(page: page);
    }
  }

  Future<void> setPageSize(int size) async {
    if (size > 0 && size != state.pageSize) {
      state = state.copyWith(pageSize: size);
      await loadSales(page: 0);
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    loadSales(page: 0);
  }

  void setStatusFilter(TicketStatus? status) {
    if (status == null) {
      state = state.copyWith(clearStatusFilter: true);
    } else {
      state = state.copyWith(selectedStatus: status);
    }
    loadSales(page: 0);
  }

  void setDateFilter(DateTime? date) {
    if (date == null) {
      state = state.copyWith(clearDateFilter: true);
    } else {
      state = state.copyWith(selectedDate: date);
    }
    loadSales(page: 0);
  }

  Future<void> addTicketSale(TicketSaleModel sale) async {
    await _repo.createTicketSale(sale);
    await loadSales();
  }

  Future<void> addTicketSalesBulk(List<TicketSaleModel> sales) async {
    if (sales.isEmpty) return;
    await _repo.createTicketSalesBulk(sales);
    await loadSales();
  }

  Future<void> updateTicketSale(TicketSaleModel sale) async {
    await _repo.updateTicketSale(sale);
    await loadSales();
  }

  Future<void> deleteTicketSale(String id) async {
    await _repo.deleteTicketSale(id);
    await loadSales();
  }
}

final ticketSalesViewModelProvider =
    StateNotifierProvider<TicketSalesViewModel, TicketSalesState>((ref) {
  final repo = ref.watch(ticketSalesRepositoryProvider);
  return TicketSalesViewModel(repo);
});
