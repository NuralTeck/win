import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsState {
  final int selectedTabIndex;
  final bool enable2FA;
  final bool enableTelemetry;
  final bool autoBackup;

  const SettingsState({
    this.selectedTabIndex = 0,
    this.enable2FA = true,
    this.enableTelemetry = true,
    this.autoBackup = true,
  });

  SettingsState copyWith({
    int? selectedTabIndex,
    bool? enable2FA,
    bool? enableTelemetry,
    bool? autoBackup,
  }) {
    return SettingsState(
      selectedTabIndex: selectedTabIndex ?? this.selectedTabIndex,
      enable2FA: enable2FA ?? this.enable2FA,
      enableTelemetry: enableTelemetry ?? this.enableTelemetry,
      autoBackup: autoBackup ?? this.autoBackup,
    );
  }
}

class SettingsViewModel extends StateNotifier<SettingsState> {
  SettingsViewModel() : super(const SettingsState());

  void setTab(int index) {
    state = state.copyWith(selectedTabIndex: index);
  }

  void toggle2FA(bool value) => state = state.copyWith(enable2FA: value);
  void toggleTelemetry(bool value) => state = state.copyWith(enableTelemetry: value);
  void toggleAutoBackup(bool value) => state = state.copyWith(autoBackup: value);
}

final settingsViewModelProvider =
    StateNotifierProvider<SettingsViewModel, SettingsState>((ref) {
  return SettingsViewModel();
});
