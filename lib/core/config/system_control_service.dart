import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SystemMasterConfigModel {
  final bool isSystemLocked;
  final Map<String, bool> allowedTabs;
  final String masterPin;
  final DateTime updatedAt;

  SystemMasterConfigModel({
    required this.isSystemLocked,
    required this.allowedTabs,
    required this.masterPin,
    required this.updatedAt,
  });

  factory SystemMasterConfigModel.defaultConfig() {
    return SystemMasterConfigModel(
      isSystemLocked: false,
      allowedTabs: {
        'ticket_booking': true,
        'company_forward': true,
        'result_entry': true,
        'customers_sellers': true,
        'money_collectors': true,
        'analytics': true,
        'settings': true,
      },
      masterPin: '1234',
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': 'global_config',
      'is_system_locked': isSystemLocked,
      'allowed_tabs': allowedTabs,
      'master_pin': masterPin,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory SystemMasterConfigModel.fromMap(Map<String, dynamic> map) {
    Map<String, bool> tabsMap = {
      'ticket_booking': true,
      'company_forward': true,
      'result_entry': true,
      'customers_sellers': true,
      'money_collectors': true,
      'analytics': true,
      'settings': true,
    };

    final rawTabs = map['allowed_tabs'];
    if (rawTabs != null) {
      if (rawTabs is Map) {
        rawTabs.forEach((k, v) {
          tabsMap[k.toString()] = (v == true || v == 1 || v == 'true' || v == '1');
        });
      } else if (rawTabs is String) {
        try {
          final decoded = json.decode(rawTabs);
          if (decoded is Map) {
            decoded.forEach((k, v) {
              tabsMap[k.toString()] = (v == true || v == 1 || v == 'true' || v == '1');
            });
          }
        } catch (_) {}
      }
    }

    return SystemMasterConfigModel(
      isSystemLocked: (map['is_system_locked'] == true || map['is_system_locked'] == 1 || map['is_system_locked'] == '1'),
      allowedTabs: tabsMap,
      masterPin: map['master_pin']?.toString() ?? '1234',
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class SystemControlService {
  static final SystemControlService instance = SystemControlService._init();
  SystemMasterConfigModel _cachedConfig = SystemMasterConfigModel.defaultConfig();
  final ValueNotifier<SystemMasterConfigModel> configNotifier = ValueNotifier(SystemMasterConfigModel.defaultConfig());
  Timer? _pollingTimer;

  SystemControlService._init() {
    _startAutoSync();
  }

  void _startAutoSync() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      loadConfig();
    });
    loadConfig();
  }

  SystemMasterConfigModel get currentConfig => _cachedConfig;

  /// Load and sync master configuration from Supabase Cloud
  Future<SystemMasterConfigModel> loadConfig() async {
    try {
      final client = Supabase.instance.client;
      final List res = await client.from('master_system_config').select().eq('id', 'global_config');
      if (res.isNotEmpty) {
        final newConfig = SystemMasterConfigModel.fromMap(Map<String, dynamic>.from(res.first));
        _cachedConfig = newConfig;
        if (configNotifier.value.updatedAt != newConfig.updatedAt ||
            configNotifier.value.isSystemLocked != newConfig.isSystemLocked ||
            configNotifier.value.allowedTabs.toString() != newConfig.allowedTabs.toString()) {
          configNotifier.value = newConfig;
        }
      }
    } catch (_) {
      // Silently fall back to cached local config when offline
    }
    return _cachedConfig;
  }

  /// Update Master System Lock state
  Future<void> updateMasterLock(bool isLocked) async {
    _cachedConfig = SystemMasterConfigModel(
      isSystemLocked: isLocked,
      allowedTabs: _cachedConfig.allowedTabs,
      masterPin: _cachedConfig.masterPin,
      updatedAt: DateTime.now(),
    );
    await _saveToCloud();
  }

  /// Update Tab Permission
  Future<void> updateTabPermission(String tabKey, bool isAllowed) async {
    final newTabs = Map<String, bool>.from(_cachedConfig.allowedTabs);
    newTabs[tabKey] = isAllowed;

    _cachedConfig = SystemMasterConfigModel(
      isSystemLocked: _cachedConfig.isSystemLocked,
      allowedTabs: newTabs,
      masterPin: _cachedConfig.masterPin,
      updatedAt: DateTime.now(),
    );
    await _saveToCloud();
  }

  Future<void> _saveToCloud() async {
    try {
      final client = Supabase.instance.client;
      await client.from('master_system_config').upsert(_cachedConfig.toMap());
      debugPrint('☁️ [SYSTEM CONTROL] Master Config Synced to Cloud!');
    } catch (e) {
      debugPrint('⚠️ [SYSTEM CONTROL] Master Config Cloud Save Error: $e');
    }
  }
}
