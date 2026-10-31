import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ticket_sale_model.dart';
import '../../../core/database/database_service.dart';

abstract class TicketSalesRepository {
  Future<List<TicketSaleModel>> getTicketSales({
    int? limit,
    int? offset,
    String? searchQuery,
    TicketStatus? status,
    DateTime? targetDate,
  });
  Future<int> getTicketSalesCount({
    String? searchQuery,
    TicketStatus? status,
    DateTime? targetDate,
  });
  Future<TicketSaleModel> createTicketSale(TicketSaleModel sale);
  Future<void> createTicketSalesBulk(List<TicketSaleModel> sales);
  Future<void> updateTicketSale(TicketSaleModel sale);
  Future<void> deleteTicketSale(String id);
}

/// SQLite-only repository — all ticket data stays local, no cloud sync.
class SqliteTicketSalesRepository implements TicketSalesRepository {
  final DatabaseService _dbService = DatabaseService.instance;

  @override
  Future<List<TicketSaleModel>> getTicketSales({
    int? limit,
    int? offset,
    String? searchQuery,
    TicketStatus? status,
    DateTime? targetDate,
  }) async {
    return await _dbService.getTicketSales(
      limit: limit,
      offset: offset,
      searchQuery: searchQuery,
      status: status,
      targetDate: targetDate,
    );
  }

  @override
  Future<int> getTicketSalesCount({
    String? searchQuery,
    TicketStatus? status,
    DateTime? targetDate,
  }) async {
    return await _dbService.getTicketSalesCount(
      searchQuery: searchQuery,
      status: status,
      targetDate: targetDate,
    );
  }

  @override
  Future<TicketSaleModel> createTicketSale(TicketSaleModel sale) async {
    await _dbService.insertTicketSale(sale);
    return sale;
  }

  @override
  Future<void> createTicketSalesBulk(List<TicketSaleModel> sales) async {
    await _dbService.insertTicketSalesBulk(sales);
  }

  @override
  Future<void> updateTicketSale(TicketSaleModel sale) async {
    await _dbService.updateTicketSale(sale);
  }

  @override
  Future<void> deleteTicketSale(String id) async {
    await _dbService.deleteTicketSale(id);
  }
}

final ticketSalesRepositoryProvider = Provider<TicketSalesRepository>((ref) {
  return SqliteTicketSalesRepository();
});
