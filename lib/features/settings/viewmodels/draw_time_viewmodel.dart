import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/draw_time_model.dart';

class DrawTimeState {
  final List<DrawTimeModel> times;

  const DrawTimeState({
    this.times = const [],
  });

  List<DrawTimeModel> get activeTimes => times.where((t) => t.isActive).toList();

  List<String> get activeTimeLabels =>
      activeTimes.map((t) => t.timeLabel).toList();

  List<String> get activeShifts =>
      activeTimes.map((t) => t.shiftName).toSet().toList();

  DrawTimeState copyWith({
    List<DrawTimeModel>? times,
  }) {
    return DrawTimeState(
      times: times ?? this.times,
    );
  }
}

class DrawTimeViewModel extends StateNotifier<DrawTimeState> {
  DrawTimeViewModel() : super(const DrawTimeState()) {
    _loadDefaults();
  }

  void _loadDefaults() {
    final now = DateTime.now();
    final defaultTimes = [
      DrawTimeModel(
        id: 'dt_1',
        timeLabel: 'Dear 1 PM',
        timeCode: '1PM',
        shiftName: 'Morning',
        isActive: true,
        createdAt: now,
      ),
      DrawTimeModel(
        id: 'dt_2',
        timeLabel: 'Dear 6 PM',
        timeCode: '6PM',
        shiftName: 'Day',
        isActive: true,
        createdAt: now,
      ),
      DrawTimeModel(
        id: 'dt_3',
        timeLabel: 'Dear 8 PM',
        timeCode: '8PM',
        shiftName: 'Evening',
        isActive: true,
        createdAt: now,
      ),
    ];
    state = state.copyWith(times: defaultTimes);
  }

  void addDrawTime({
    required String timeLabel,
    required String timeCode,
    required String shiftName,
  }) {
    final newTime = DrawTimeModel(
      id: 'dt_${DateTime.now().millisecondsSinceEpoch}',
      timeLabel: timeLabel,
      timeCode: timeCode.toUpperCase(),
      shiftName: shiftName,
      isActive: true,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(times: [...state.times, newTime]);
  }

  void toggleStatus(String id) {
    final updated = state.times.map((t) {
      if (t.id == id) {
        return t.copyWith(isActive: !t.isActive);
      }
      return t;
    }).toList();
    state = state.copyWith(times: updated);
  }

  void deleteDrawTime(String id) {
    final updated = state.times.where((t) => t.id != id).toList();
    state = state.copyWith(times: updated);
  }
}

final drawTimeViewModelProvider =
    StateNotifierProvider<DrawTimeViewModel, DrawTimeState>((ref) {
  return DrawTimeViewModel();
});
