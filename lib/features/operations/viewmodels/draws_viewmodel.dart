import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/draw_model.dart';
import '../../shared/repositories/draws_repository.dart';
import '../models/lottery_sambad_result_model.dart';
import '../models/winning_claim_model.dart';
import '../utils/lottery_result_parser.dart';
import '../utils/winner_verification_engine.dart';
import '../../shared/models/ticket_sale_model.dart';

class DrawsState {
  final bool isLoading;
  final List<DrawModel> draws;
  final Map<String, LotterySambadResultModel> resultsMap;
  final Map<String, List<WinningClaimModel>> winningClaimsMap;
  final String searchQuery;
  final DrawStatus? selectedStatus;
  final String? errorMessage;

  const DrawsState({
    this.isLoading = true,
    this.draws = const [],
    this.resultsMap = const {},
    this.winningClaimsMap = const {},
    this.searchQuery = '',
    this.selectedStatus,
    this.errorMessage,
  });

  List<DrawModel> get filteredDraws {
    return draws.where((d) {
      final q = searchQuery.toLowerCase();
      final matchesSearch = d.drawName.toLowerCase().contains(q) ||
          d.drawCode.toLowerCase().contains(q) ||
          d.schemeType.toLowerCase().contains(q) ||
          d.district.toLowerCase().contains(q);
      final matchesStatus = selectedStatus == null || d.status == selectedStatus;
      return matchesSearch && matchesStatus;
    }).toList();
  }

  DrawsState copyWith({
    bool? isLoading,
    List<DrawModel>? draws,
    Map<String, LotterySambadResultModel>? resultsMap,
    Map<String, List<WinningClaimModel>>? winningClaimsMap,
    String? searchQuery,
    DrawStatus? selectedStatus,
    bool clearStatusFilter = false,
    String? errorMessage,
  }) {
    return DrawsState(
      isLoading: isLoading ?? this.isLoading,
      draws: draws ?? this.draws,
      resultsMap: resultsMap ?? this.resultsMap,
      winningClaimsMap: winningClaimsMap ?? this.winningClaimsMap,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedStatus: clearStatusFilter ? null : (selectedStatus ?? this.selectedStatus),
      errorMessage: errorMessage,
    );
  }
}

class DrawsViewModel extends StateNotifier<DrawsState> {
  final DrawsRepository _repo;

  DrawsViewModel(this._repo) : super(const DrawsState()) {
    loadDraws();
  }

  Future<void> loadDraws() async {
    state = state.copyWith(isLoading: true);
    try {
      final list = await _repo.getDraws();

      // Initialize mock results & claims for completed draws
      final initialResults = <String, LotterySambadResultModel>{};
      final initialClaims = <String, List<WinningClaimModel>>{};

      for (final d in list) {
        if (d.status == DrawStatus.completed) {
          final res = LotteryResultParser.parseSambadText(
            LotteryResultParser.sampleSambadResultText,
            drawId: d.id,
            drawName: d.drawName,
          );
          initialResults[d.id] = res;

          // Generate sample claims for demo
          initialClaims[d.id] = [
            WinningClaimModel(
              id: 'win_1',
              drawId: d.id,
              drawName: d.drawName,
              prizeTier: '🥇 1st Prize',
              winningNumber: res.firstPrize,
              prizeAmount: 10000000.0,
              buyerName: 'Amit Sharma',
              sellerName: 'Rajiv',
              ticketSeries: '83L',
              ticketNumber: '28311',
              verifiedAt: DateTime.now(),
            ),
            WinningClaimModel(
              id: 'win_2',
              drawId: d.id,
              drawName: d.drawName,
              prizeTier: '🥈 2nd Prize',
              winningNumber: '04812',
              prizeAmount: 9000.0,
              buyerName: 'Rahul Verma',
              sellerName: 'Rajiv',
              ticketSeries: '12',
              ticketNumber: '04812',
              verifiedAt: DateTime.now(),
            ),
          ];
        }
      }

      state = state.copyWith(
        isLoading: false,
        draws: list,
        resultsMap: initialResults,
        winningClaimsMap: initialClaims,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to load draws.');
    }
  }

  void setSearchQuery(String query) => state = state.copyWith(searchQuery: query);

  void setStatusFilter(DrawStatus? status) {
    if (status == null) {
      state = state.copyWith(clearStatusFilter: true);
    } else {
      state = state.copyWith(selectedStatus: status);
    }
  }

  Future<void> addDraw(DrawModel draw) async {
    final created = await _repo.createDraw(draw);
    state = state.copyWith(draws: [created, ...state.draws]);
  }

  Future<void> updateDraw(DrawModel draw) async {
    await _repo.updateDraw(draw);
    final updated = state.draws.map((d) => d.id == draw.id ? draw : d).toList();
    state = state.copyWith(draws: updated);
  }

  List<WinningClaimModel> publishResultAndCheckWinners(
    String drawId,
    LotterySambadResultModel result,
    List<TicketSaleModel> soldTickets,
  ) {
    final updatedDraws = state.draws.map((d) {
      if (d.id == drawId) {
        return d.copyWith(status: DrawStatus.completed, updatedAt: DateTime.now());
      }
      return d;
    }).toList();

    final updatedResults = Map<String, LotterySambadResultModel>.from(state.resultsMap);
    updatedResults[drawId] = result;

    // Run winner verification engine against sold tickets
    final winners = WinnerVerificationEngine.verifyWinners(
      result: result,
      soldTickets: soldTickets,
    );

    final updatedClaims = Map<String, List<WinningClaimModel>>.from(state.winningClaimsMap);
    updatedClaims[drawId] = winners;

    state = state.copyWith(
      draws: updatedDraws,
      resultsMap: updatedResults,
      winningClaimsMap: updatedClaims,
    );

    return winners;
  }
}

final drawsViewModelProvider =
    StateNotifierProvider<DrawsViewModel, DrawsState>((ref) {
  final repo = ref.watch(drawsRepositoryProvider);
  return DrawsViewModel(repo);
});
