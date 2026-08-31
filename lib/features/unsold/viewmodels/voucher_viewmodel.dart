import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_service.dart';
import '../models/voucher_model.dart';

class VoucherState {
  final List<VoucherModel> vouchers;
  final bool isLoading;
  final String? errorMessage;

  const VoucherState({
    this.vouchers = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  int get totalIssuedTickets =>
      vouchers.fold(0, (sum, v) => sum + v.totalQty);

  double get totalIssuedAmount =>
      vouchers.fold(0.0, (sum, v) => sum + v.totalAmount);

  VoucherState copyWith({
    List<VoucherModel>? vouchers,
    bool? isLoading,
    String? errorMessage,
  }) {
    return VoucherState(
      vouchers: vouchers ?? this.vouchers,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class VoucherViewModel extends StateNotifier<VoucherState> {
  final DatabaseService _db = DatabaseService.instance;

  VoucherViewModel() : super(const VoucherState()) {
    loadVouchers();
  }

  Future<void> loadVouchers({
    String? date,
    String? startDate,
    String? endDate,
    String? drawShift,
    String? partyName,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final rows = await _db.getVouchers(
        date: date,
        startDate: startDate,
        endDate: endDate,
        drawShift: drawShift,
        partyName: partyName,
      );
      final list = rows.map((r) => VoucherModel.fromMap(r)).toList();
      state = state.copyWith(vouchers: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<bool> addVoucher(VoucherModel voucher) async {
    try {
      final success = await _db.insertVoucher(voucher.toMap());
      if (success) {
        state = state.copyWith(
          vouchers: [voucher, ...state.vouchers],
        );
      }
      return success;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> addVouchersBatch(List<VoucherModel> newVouchers) async {
    if (newVouchers.isEmpty) return true;
    try {
      final maps = newVouchers.map((v) => v.toMap()).toList();
      final success = await _db.insertVouchersBatch(maps);
      if (success) {
        state = state.copyWith(
          vouchers: [...newVouchers, ...state.vouchers],
        );
      }
      return success;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> deleteVoucher(String id) async {
    try {
      final success = await _db.deleteVoucher(id);
      if (success) {
        state = state.copyWith(
          vouchers: state.vouchers.where((v) => v.id != id).toList(),
        );
      }
      return success;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> bulkUpdateParty(List<String> ids, String newParty) async {
    try {
      final success = await _db.bulkUpdateVoucherParty(ids, newParty);
      if (success) {
        state = state.copyWith(
          vouchers: state.vouchers.map((v) {
            if (ids.contains(v.id)) {
              return VoucherModel(
                id: v.id,
                voucherNo: v.voucherNo,
                date: v.date,
                drawShift: v.drawShift,
                partyName: newParty,
                series: v.series,
                fromTicket: v.fromTicket,
                toTicket: v.toTicket,
                totalQty: v.totalQty,
                pricePerTicket: v.pricePerTicket,
                totalAmount: v.totalAmount,
                createdAt: v.createdAt,
              );
            }
            return v;
          }).toList(),
        );
      }
      return success;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> bulkUpdateSeries(List<String> ids, String newSeries, double newRate) async {
    try {
      final success = await _db.bulkUpdateVoucherSeries(ids, newSeries, newRate);
      if (success) {
        state = state.copyWith(
          vouchers: state.vouchers.map((v) {
            if (ids.contains(v.id)) {
              return VoucherModel(
                id: v.id,
                voucherNo: v.voucherNo,
                date: v.date,
                drawShift: v.drawShift,
                partyName: v.partyName,
                series: newSeries,
                fromTicket: v.fromTicket,
                toTicket: v.toTicket,
                totalQty: v.totalQty,
                pricePerTicket: newRate,
                totalAmount: v.totalQty * newRate,
                createdAt: v.createdAt,
              );
            }
            return v;
          }).toList(),
        );
      }
      return success;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> bulkDelete(List<String> ids) async {
    try {
      final success = await _db.bulkDeleteVouchers(ids);
      if (success) {
        final idSet = ids.toSet();
        state = state.copyWith(
          vouchers: state.vouchers.where((v) => !idSet.contains(v.id)).toList(),
        );
      }
      return success;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> deleteAll({String? date, String? drawShift, String? partyName}) async {
    try {
      final success = await _db.deleteAllVouchers(date: date, drawShift: drawShift, partyName: partyName);
      if (success) {
        await loadVouchers(date: date, drawShift: drawShift, partyName: partyName);
      }
      return success;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }
}

final voucherViewModelProvider =
    StateNotifierProvider<VoucherViewModel, VoucherState>((ref) {
  return VoucherViewModel();
});
