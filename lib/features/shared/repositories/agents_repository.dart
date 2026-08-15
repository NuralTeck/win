import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/agent_model.dart';
import '../../../core/services/mock_data_service.dart';

abstract class AgentsRepository {
  Future<List<AgentModel>> getAgents();
  Future<void> updateAgent(AgentModel agent);
}

class MockAgentsRepository implements AgentsRepository {
  List<AgentModel> _items = MockDataService.getAgents();

  @override
  Future<List<AgentModel>> getAgents() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return List.from(_items);
  }

  @override
  Future<void> updateAgent(AgentModel agent) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _items = _items.map((item) => item.id == agent.id ? agent : item).toList();
  }
}

final agentsRepositoryProvider = Provider<AgentsRepository>((ref) {
  return MockAgentsRepository();
});
