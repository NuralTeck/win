import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../shared/models/ticket_sale_model.dart';
import '../../shared/repositories/ticket_sales_repository.dart';
import '../../../core/database/supabase_service.dart';
import '../../../core/database/database_service.dart';

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
  StreamSubscription? _realtimeSubscription;

  TicketSalesViewModel(this._repo) : super(const TicketSalesState()) {
    loadSales();
    _subscribeToLiveRealtimeStream();
  }

  void _subscribeToLiveRealtimeStream() {
    try {
      final stream = SupabaseService.instance.streamIncomingSales();
      if (stream != null) {
        _realtimeSubscription = stream.listen((rawList) async {
          if (!mounted || rawList.isEmpty) return;

          try {
            final db = await DatabaseService.instance.database;
            final batch = db.batch();

            for (final item in rawList) {
              final seriesName = item['ticketSeries'] as String? ?? '';
              final qty = (item['quantity'] as num?)?.toInt() ?? 1;
              final pricePerTicket = (item['pricePerTicket'] as num?)?.toDouble() ?? 0.0;
              final totalAmt = (item['totalAmount'] as num?)?.toDouble() ?? 0.0;
              final finalTotal = totalAmt > 0.0 ? totalAmt : (pricePerTicket * qty);

              final sale = TicketSaleModel(
                id: item['id'] as String,
                receiptNumber: item['receiptNumber'] as String? ?? '',
                buyerName: item['buyerName'] as String? ?? '',
                buyerPhone: item['buyerPhone'] as String? ?? '',
                agentCode: item['agentCode'] as String? ?? '',
                agentName: item['agentName'] as String? ?? '',
                drawCode: item['drawCode'] as String? ?? '',
                drawName: item['drawName'] as String? ?? '',
                ticketSeries: seriesName,
                ticketNumber: item['ticketNumber'] as String? ?? '',
                quantity: qty,
                pricePerTicket: pricePerTicket,
                totalAmount: finalTotal,
                commissionAmount: finalTotal * 0.05,
                status: TicketStatus.values.firstWhere(
                  (e) => e.name == item['status'],
                  orElse: () => TicketStatus.sold,
                ),
                paymentMode: PaymentMode.values.firstWhere(
                  (e) => e.name == item['paymentMode'],
                  orElse: () => PaymentMode.cash,
                ),
                saleDate: item['saleDate'] != null ? DateTime.parse(item['saleDate'].toString()) : DateTime.now(),
                drawDate: item['drawDate'] != null ? DateTime.parse(item['drawDate'].toString()) : DateTime.now(),
              );

              batch.insert(
                'ticket_sales',
                {
                  'id': sale.id,
                  'receiptNumber': sale.receiptNumber,
                  'buyerName': sale.buyerName,
                  'buyerPhone': sale.buyerPhone,
                  'agentCode': sale.agentCode,
                  'agentName': sale.agentName,
                  'drawCode': sale.drawCode,
                  'drawName': sale.drawName,
                  'ticketSeries': sale.ticketSeries,
                  'ticketNumber': sale.ticketNumber,
                  'quantity': sale.quantity,
                  'pricePerTicket': sale.pricePerTicket,
                  'totalAmount': sale.totalAmount,
                  'commissionAmount': sale.commissionAmount,
                  'status': sale.status.name,
                  'paymentMode': sale.paymentMode.name,
                  'saleDate': sale.saleDate.toIso8601String(),
                  'drawDate': sale.drawDate.toIso8601String(),
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }

            await batch.commit(noResult: true);

            final localSales = await DatabaseService.instance.getTicketSales();
            if (mounted) {
              state = state.copyWith(sales: localSales, isLoading: false);
            }
          } catch (e) {
            debugPrint('⚠️ [LIVE STREAM PROCESS ERROR] $e');
          }
        }, onError: (err) {
          debugPrint('⚠️ [LIVE STREAM ERROR] $err');
        });
      }
    } catch (e) {
      debugPrint('⚠️ [LIVE STREAM INIT] $e');
    }
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

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    super.dispose();
  }
}

final ticketSalesViewModelProvider =
    StateNotifierProvider<TicketSalesViewModel, TicketSalesState>((ref) {
  final repo = ref.watch(ticketSalesRepositoryProvider);
  return TicketSalesViewModel(repo);
});
