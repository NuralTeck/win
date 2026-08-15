import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ticket_sale_model.dart';
import '../../../core/database/database_service.dart';
import '../../../core/database/supabase_service.dart';

abstract class TicketSalesRepository {
  Future<List<TicketSaleModel>> getTicketSales();
  Future<TicketSaleModel> createTicketSale(TicketSaleModel sale);
  Future<void> updateTicketSale(TicketSaleModel sale);
  Future<void> deleteTicketSale(String id);
}

class SqliteTicketSalesRepository implements TicketSalesRepository {
  final DatabaseService _dbService = DatabaseService.instance;
  final SupabaseService _supabaseService = SupabaseService.instance;

  @override
  Future<List<TicketSaleModel>> getTicketSales() async {
    // 1. Instant local read from SQLite Database (0ms latency)
    final localSales = await _dbService.getTicketSales();

    // 2. Background Cloud Sync (Non-blocking)
    if (_supabaseService.isInitialized) {
      _supabaseService.fetchCloudSales().catchError((e) {
        debugPrint('⚠️ [CLOUD SYNC] Note: $e');
        return <TicketSaleModel>[];
      });
    }
    return localSales;
  }

  @override
  Future<TicketSaleModel> createTicketSale(TicketSaleModel sale) async {
    await _supabaseService.insertTicketBooking(sale);
    return sale;
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
