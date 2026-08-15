import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/agent_model.dart';
import '../../shared/repositories/agents_repository.dart';

class AgentsState {
  final bool isLoading;
  final List<AgentModel> agents;
  final String searchQuery;
  final AgentLicense? selectedLicense;
  final String? errorMessage;

  const AgentsState({
    this.isLoading = true,
    this.agents = const [],
    this.searchQuery = '',
    this.selectedLicense,
    this.errorMessage,
  });

  List<AgentModel> get filteredAgents {
    return agents.where((a) {
      final q = searchQuery.toLowerCase();
      final matchesSearch = a.agentName.toLowerCase().contains(q) ||
          a.agentCode.toLowerCase().contains(q) ||
          a.ownerName.toLowerCase().contains(q) ||
          a.district.toLowerCase().contains(q);
      final matchesLicense = selectedLicense == null || a.license == selectedLicense;
      return matchesSearch && matchesLicense;
    }).toList();
  }

  AgentsState copyWith({
    bool? isLoading,
    List<AgentModel>? agents,
    String? searchQuery,
    AgentLicense? selectedLicense,
    bool clearLicenseFilter = false,
    String? errorMessage,
  }) {
    return AgentsState(
      isLoading: isLoading ?? this.isLoading,
      agents: agents ?? this.agents,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedLicense: clearLicenseFilter ? null : (selectedLicense ?? this.selectedLicense),
      errorMessage: errorMessage,
    );
  }
}

class AgentsViewModel extends StateNotifier<AgentsState> {
  final AgentsRepository _repo;

  AgentsViewModel(this._repo) : super(const AgentsState()) {
    loadAgents();
  }

  Future<void> loadAgents() async {
    state = state.copyWith(isLoading: true);
    try {
      final list = await _repo.getAgents();
      state = state.copyWith(isLoading: false, agents: list);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to load agents.');
    }
  }

  void setSearchQuery(String query) => state = state.copyWith(searchQuery: query);

  void setLicenseFilter(AgentLicense? license) {
    if (license == null) {
      state = state.copyWith(clearLicenseFilter: true);
    } else {
      state = state.copyWith(selectedLicense: license);
    }
  }

  Future<void> updateAgent(AgentModel agent) async {
    await _repo.updateAgent(agent);
    final updated = state.agents.map((a) => a.id == agent.id ? agent : a).toList();
    state = state.copyWith(agents: updated);
  }
}

final agentsViewModelProvider =
    StateNotifierProvider<AgentsViewModel, AgentsState>((ref) {
  final repo = ref.watch(agentsRepositoryProvider);
  return AgentsViewModel(repo);
});
