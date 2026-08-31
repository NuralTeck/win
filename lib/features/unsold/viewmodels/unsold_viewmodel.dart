import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_service.dart';
import '../models/unsold_model.dart';

class UnsoldState {
  final List<UnsoldModel> unsoldList;
  final bool isLoading;
  final String? errorMessage;

  const UnsoldState({
    this.unsoldList = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  int get totalUnsoldTickets =>
      unsoldList.fold(0, (sum, u) => sum + u.totalQty);

  double get totalUnsoldAmount =>
      unsoldList.fold(0.0, (sum, u) => sum + u.totalAmount);

  UnsoldState copyWith({
    List<UnsoldModel>? unsoldList,
    bool? isLoading,
    String? errorMessage,
  }) {
    return UnsoldState(
      unsoldList: unsoldList ?? this.unsoldList,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class UnsoldViewModel extends StateNotifier<UnsoldState> {
  final DatabaseService _db = DatabaseService.instance;

  UnsoldViewModel() : super(const UnsoldState()) {
    loadUnsold();
  }

  Future<void> loadUnsold({
    String? date,
    String? startDate,
    String? endDate,
    String? drawShift,
    String? partyName,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final rows = await _db.getUnsoldTickets(
        date: date,
        startDate: startDate,
        endDate: endDate,
        drawShift: drawShift,
        partyName: partyName,
      );
      final list = rows.map((r) => UnsoldModel.fromMap(r)).toList();
      state = state.copyWith(unsoldList: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<bool> addUnsold(UnsoldModel unsold) async {
    try {
      final success = await _db.insertUnsoldTicket(unsold.toMap());
      if (success) {
        state = state.copyWith(
          unsoldList: [unsold, ...state.unsoldList],
        );
      }
      return success;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> addUnsoldBatch(List<UnsoldModel> newUnsoldList) async {
    if (newUnsoldList.isEmpty) return true;
    try {
      final maps = newUnsoldList.map((u) => u.toMap()).toList();
      final success = await _db.insertUnsoldTicketsBatch(maps);
      if (success) {
        state = state.copyWith(
          unsoldList: [...newUnsoldList, ...state.unsoldList],
        );
      }
      return success;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> deleteUnsold(String id) async {
    try {
      final success = await _db.deleteUnsoldTicket(id);
      if (success) {
        state = state.copyWith(
          unsoldList: state.unsoldList.where((u) => u.id != id).toList(),
        );
      }
      return success;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> lockShift(String date, String drawShift) async {
    try {
      final success = await _db.lockUnsoldForShift(date, drawShift);
      if (success) {
        state = state.copyWith(
          unsoldList: state.unsoldList.map((u) {
            if (u.date == date && u.drawShift == drawShift) {
              return UnsoldModel(
                id: u.id,
                returnNo: u.returnNo,
                date: u.date,
                drawShift: u.drawShift,
                partyName: u.partyName,
                series: u.series,
                fromTicket: u.fromTicket,
                toTicket: u.toTicket,
                totalQty: u.totalQty,
                pricePerTicket: u.pricePerTicket,
                totalAmount: u.totalAmount,
                isLocked: true,
                createdAt: u.createdAt,
              );
            }
            return u;
          }).toList(),
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
      final success = await _db.bulkUpdateUnsoldParty(ids, newParty);
      if (success) {
        state = state.copyWith(
          unsoldList: state.unsoldList.map((u) {
            if (ids.contains(u.id)) {
              return UnsoldModel(
                id: u.id,
                returnNo: u.returnNo,
                date: u.date,
                drawShift: u.drawShift,
                partyName: newParty,
                series: u.series,
                fromTicket: u.fromTicket,
                toTicket: u.toTicket,
                totalQty: u.totalQty,
                pricePerTicket: u.pricePerTicket,
                totalAmount: u.totalAmount,
                isLocked: u.isLocked,
                createdAt: u.createdAt,
              );
            }
            return u;
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
      final success = await _db.bulkUpdateUnsoldSeries(ids, newSeries, newRate);
      if (success) {
        state = state.copyWith(
          unsoldList: state.unsoldList.map((u) {
            if (ids.contains(u.id)) {
              return UnsoldModel(
                id: u.id,
                returnNo: u.returnNo,
                date: u.date,
                drawShift: u.drawShift,
                partyName: u.partyName,
                series: newSeries,
                fromTicket: u.fromTicket,
                toTicket: u.toTicket,
                totalQty: u.totalQty,
                pricePerTicket: newRate,
                totalAmount: u.totalQty * newRate,
                isLocked: u.isLocked,
                createdAt: u.createdAt,
              );
            }
            return u;
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
      final success = await _db.bulkDeleteUnsold(ids);
      if (success) {
        final idSet = ids.toSet();
        state = state.copyWith(
          unsoldList: state.unsoldList.where((u) => !idSet.contains(u.id)).toList(),
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
      final success = await _db.deleteAllUnsold(date: date, drawShift: drawShift, partyName: partyName);
      if (success) {
        await loadUnsold(date: date, drawShift: drawShift, partyName: partyName);
      }
      return success;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }
}

final unsoldViewModelProvider =
    StateNotifierProvider<UnsoldViewModel, UnsoldState>((ref) {
  return UnsoldViewModel();
});
