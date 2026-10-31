import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// WhatsApp Engine Connection State
enum WhatsAppBotStatus {
  disconnected,
  connecting,
  qrReady,
  connected,
  offline,
}

class WhatsAppEngineStatus {
  final bool online;
  final WhatsAppBotStatus botStatus;
  final bool isConnected;
  final bool hasQr;
  final String? qrDataUrl;
  final int processedCount;
  final int currentBufferSize;
  final String? lastFlushTime;
  final int uptimeSeconds;
  final int port;

  WhatsAppEngineStatus({
    required this.online,
    required this.botStatus,
    required this.isConnected,
    required this.hasQr,
    this.qrDataUrl,
    required this.processedCount,
    required this.currentBufferSize,
    this.lastFlushTime,
    required this.uptimeSeconds,
    required this.port,
  });

  factory WhatsAppEngineStatus.offline({int port = 4000}) {
    return WhatsAppEngineStatus(
      online: false,
      botStatus: WhatsAppBotStatus.offline,
      isConnected: false,
      hasQr: false,
      processedCount: 0,
      currentBufferSize: 0,
      uptimeSeconds: 0,
      port: port,
    );
  }
}

class WhatsAppEngineLogItem {
  final String time;
  final String level;
  final String message;

  WhatsAppEngineLogItem({
    required this.time,
    required this.level,
    required this.message,
  });

  factory WhatsAppEngineLogItem.fromJson(Map<String, dynamic> json) {
    return WhatsAppEngineLogItem(
      time: json['time'] ?? '',
      level: json['level'] ?? 'info',
      message: json['message'] ?? '',
    );
  }
}

class WhatsAppEngineService {
  WhatsAppEngineService._();
  static final WhatsAppEngineService instance = WhatsAppEngineService._();

  int _activePort = 4000;
  int get activePort => _activePort;
  String get baseUrl => 'http://127.0.0.1:$_activePort';

  Process? _engineProcess;
  Timer? _pollTimer;
  final HttpClient _httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  int _countOffset = 0;
  int _lastRawCount = 0;

  final ValueNotifier<WhatsAppEngineStatus> statusNotifier =
      ValueNotifier(WhatsAppEngineStatus.offline());
  final ValueNotifier<List<WhatsAppEngineLogItem>> logsNotifier =
      ValueNotifier([]);
  final ValueNotifier<bool> isConsoleVisibleNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isConsoleMinimizedNotifier = ValueNotifier<bool>(false);

  void toggleConsoleVisibility() {
    isConsoleVisibleNotifier.value = !isConsoleVisibleNotifier.value;
  }

  void setConsoleVisible(bool visible) {
    isConsoleVisibleNotifier.value = visible;
  }

  void toggleConsoleMinimized() {
    isConsoleMinimizedNotifier.value = !isConsoleMinimizedNotifier.value;
  }

  bool get isEngineProcessRunning => _engineProcess != null;

  /// Find an open port dynamically or fallback to 4000..4005
  Future<int> findAvailablePort([int startPort = 4000]) async {
    final envPortStr = dotenv.env['WHATSAPP_ENGINE_PORT'];
    if (envPortStr != null && int.tryParse(envPortStr) != null) {
      return int.parse(envPortStr);
    }

    for (int port = startPort; port < startPort + 10; port++) {
      try {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await server.close();
        return port;
      } catch (_) {
        // Port is occupied or in use by existing engine
        if (await _isPortResponding(port)) {
          return port; // Existing bot engine is already running on this port!
        }
      }
    }
    return startPort;
  }

  Future<bool> _isPortResponding(int port) async {
    try {
      final req = await _httpClient.getUrl(Uri.parse('http://127.0.0.1:$port/status'));
      final res = await req.close();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Resolve absolute paths for both Dev environment and Production Windows Bundles
  List<String> _candidateEnginePaths() {
    final List<String> candidates = [];
    
    final currentDir = Directory.current.path;
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    // 1. Release standalone EXE paths
    candidates.add(pathJoin(currentDir, 'assets', 'bin', 'whatsapp_engine.exe'));
    candidates.add(pathJoin(exeDir, 'assets', 'bin', 'whatsapp_engine.exe'));
    candidates.add(pathJoin(exeDir, 'whatsapp_engine.exe'));
    candidates.add(pathJoin(currentDir, 'whatsapp_engine', 'dist', 'whatsapp_engine.exe'));

    // 2. Node.js script paths (Development fallback)
    candidates.add(pathJoin(currentDir, 'whatsapp_engine', 'bot_engine.js'));
    candidates.add(pathJoin(exeDir, 'whatsapp_engine', 'bot_engine.js'));
    candidates.add(pathJoin(exeDir, 'data', 'flutter_assets', 'whatsapp_engine', 'bot_engine.js'));

    return candidates;
  }

  /// Find bundled portable node.exe or fallback to system node
  String _findNodeExecutable() {
    final currentDir = Directory.current.path;
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    final candidateNodePaths = [
      pathJoin(exeDir, 'whatsapp_engine', 'node.exe'),
      pathJoin(exeDir, 'node.exe'),
      pathJoin(currentDir, 'whatsapp_engine', 'node.exe'),
      pathJoin(currentDir, 'assets', 'bin', 'node.exe'),
      pathJoin(exeDir, 'assets', 'bin', 'node.exe'),
      r'C:\Program Files\nodejs\node.exe',
      r'C:\Program Files (x86)\nodejs\node.exe',
    ];

    for (final p in candidateNodePaths) {
      if (File(p).existsSync()) {
        debugPrint('🔍 [WHATSAPP SERVICE] Found Node.js binary at: $p');
        return p;
      }
    }
    return 'node';
  }

  /// Launch background executable or node script with dynamic port
  Future<bool> launchBackgroundEngine() async {
    // If already responding on active port, no need to spawn duplicate process
    if (await _isPortResponding(_activePort)) {
      debugPrint('⚡ [WHATSAPP SERVICE] Bot engine is already active on http://127.0.0.1:$_activePort');
      startPolling();
      return true;
    }

    _activePort = await findAvailablePort(4000);
    debugPrint('🚀 [WHATSAPP SERVICE] Initializing Engine on dynamic port: $_activePort');

    String? foundTarget;
    bool isExe = false;

    for (final p in _candidateEnginePaths()) {
      if (File(p).existsSync()) {
        foundTarget = p;
        isExe = p.endsWith('.exe');
        break;
      }
    }

    if (foundTarget == null) {
      debugPrint('⚠️ [WHATSAPP SERVICE] Engine script or binary not found in candidate paths.');
      return false;
    }

    try {
      final envMap = {
        ...Platform.environment,
        'PORT': '$_activePort',
      };

      if (isExe) {
        debugPrint('🚀 Spawning Standalone WhatsApp Engine: $foundTarget (Port: $_activePort)');
        _engineProcess = await Process.start(
          foundTarget,
          [],
          environment: envMap,
          workingDirectory: File(foundTarget).parent.path,
          mode: ProcessStartMode.normal,
        );
      } else {
        final nodeBinary = _findNodeExecutable();
        debugPrint('🚀 Spawning Node.js WhatsApp Engine using ($nodeBinary): $foundTarget (Port: $_activePort)');
        _engineProcess = await Process.start(
          nodeBinary,
          [foundTarget],
          environment: envMap,
          workingDirectory: File(foundTarget).parent.path,
          mode: ProcessStartMode.normal,
        );
      }

      _engineProcess?.stdout.transform(utf8.decoder).listen((data) {
        debugPrint('🤖 [WHATSAPP ENGINE STDOUT]: $data');
      });

      _engineProcess?.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('⚠️ [WHATSAPP ENGINE STDERR]: $data');
      });

      // Wait up to 6 seconds for the HTTP server to bind and respond
      for (int i = 0; i < 12; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (await _isPortResponding(_activePort)) {
          debugPrint('✅ [WHATSAPP SERVICE] Engine is successfully online on port $_activePort!');
          break;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Could not spawn WhatsApp Engine process: $e');
      return false;
    }

    startPolling();
    return true;
  }

  void startPolling() {
    _pollTimer?.cancel();
    // Immediate first fetch without waiting for timer tick
    fetchStatus();
    fetchLogs();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      await fetchStatus();
      await fetchLogs();
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> fetchStatus() async {
    try {
      final req = await _httpClient.getUrl(Uri.parse('$baseUrl/status'));
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        String? qrUrl = data['qrDataUrl'] as String?;
        if (qrUrl == null && data['hasQr'] == true) {
          try {
            final qrReq = await _httpClient.getUrl(Uri.parse('$baseUrl/qr'));
            final qrRes = await qrReq.close();
            if (qrRes.statusCode == 200) {
              final qrBody = await qrRes.transform(utf8.decoder).join();
              final qrData = jsonDecode(qrBody);
              qrUrl = qrData['qrDataUrl'];
            }
          } catch (_) {}
        }

        final rawStatus = data['connectionStatus'] as String? ?? 'disconnected';
        WhatsAppBotStatus botStat;
        if (data['isConnected'] == true || rawStatus == 'connected') {
          botStat = WhatsAppBotStatus.connected;
        } else if (qrUrl != null && qrUrl.isNotEmpty) {
          botStat = WhatsAppBotStatus.qrReady;
        } else if (rawStatus == 'connecting') {
          botStat = WhatsAppBotStatus.connecting;
        } else {
          botStat = WhatsAppBotStatus.disconnected;
        }

        final isConn = data['isConnected'] == true;
        final hasQr = data['hasQr'] == true;
        _lastRawCount = (data['processedTotalCount'] as num?)?.toInt() ?? 0;
        final pCount = (_lastRawCount - _countOffset).clamp(0, 9999999);
        final bSize = (data['currentBufferSize'] as num?)?.toInt() ?? 0;
        final upSec = (data['uptimeSeconds'] as num?)?.toInt() ?? 0;
        final prev = statusNotifier.value;

        // Skip unnecessary notifier emissions if state is completely identical
        if (prev.online &&
            prev.botStatus == botStat &&
            prev.isConnected == isConn &&
            prev.hasQr == hasQr &&
            prev.qrDataUrl == qrUrl &&
            prev.processedCount == pCount &&
            prev.currentBufferSize == bSize &&
            (prev.uptimeSeconds - upSec).abs() < 2) {
          return;
        }

        statusNotifier.value = WhatsAppEngineStatus(
          online: true,
          botStatus: botStat,
          isConnected: isConn,
          hasQr: hasQr,
          qrDataUrl: qrUrl,
          processedCount: pCount,
          currentBufferSize: bSize,
          lastFlushTime: data['lastFlushTimestamp'],
          uptimeSeconds: upSec,
          port: _activePort,
        );
        return;
      }
    } catch (_) {
      // Backend offline
    }
    if (statusNotifier.value.online) {
      statusNotifier.value = WhatsAppEngineStatus.offline(port: _activePort);
    }
  }

  Future<void> fetchLogs() async {
    try {
      final req = await _httpClient.getUrl(Uri.parse('$baseUrl/logs'));
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        final rawLogs = (data['logs'] as List? ?? []);
        logsNotifier.value = rawLogs
            .map((item) => WhatsAppEngineLogItem.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
  }

  Future<bool> startBot() async {
    // 1. Ensure engine process is running and responding
    if (!await _isPortResponding(_activePort)) {
      debugPrint('🔄 Engine offline, automatically launching background process...');
      final launched = await launchBackgroundEngine();
      if (!launched) {
        debugPrint('❌ Failed to launch background engine process.');
        return false;
      }
    }

    try {
      final req = await _httpClient.postUrl(Uri.parse('$baseUrl/start'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'localOnly': true,
      }));
      final res = await req.close();
      await fetchStatus();
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('⚠️ Start Bot HTTP Error: $e');
      return false;
    }
  }

  Future<bool> stopBot() async {
    _countOffset = 0;
    _lastRawCount = 0;
    try {
      final req = await _httpClient.postUrl(Uri.parse('$baseUrl/stop'));
      final res = await req.close();
      await fetchStatus();
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('⚠️ Stop Bot HTTP Error: $e');
      statusNotifier.value = WhatsAppEngineStatus.offline(port: _activePort);
      return false;
    }
  }

  /// Cleanly kill and restart the background WhatsApp engine to reload updated code & reset uptime
  Future<bool> restartEngineServer() async {
    try {
      final req = await _httpClient.postUrl(Uri.parse('$baseUrl/restart-server'));
      await req.close();
    } catch (_) {}
    _engineProcess?.kill();
    _engineProcess = null;
    statusNotifier.value = WhatsAppEngineStatus.offline(port: _activePort);
    await Future.delayed(const Duration(milliseconds: 1000));
    return await launchBackgroundEngine();
  }

  Future<void> clearLogs() async {
    logsNotifier.value = [];
    try {
      final req = await _httpClient.postUrl(Uri.parse('$baseUrl/clear-logs'));
      await req.close();
    } catch (_) {}
  }

  Future<bool> resetProcessedCount() async {
    _countOffset = _lastRawCount;
    final cur = statusNotifier.value;
    statusNotifier.value = WhatsAppEngineStatus(
      online: cur.online,
      botStatus: cur.botStatus,
      isConnected: cur.isConnected,
      hasQr: cur.hasQr,
      qrDataUrl: cur.qrDataUrl,
      processedCount: 0,
      currentBufferSize: cur.currentBufferSize,
      lastFlushTime: cur.lastFlushTime,
      uptimeSeconds: cur.uptimeSeconds,
      port: _activePort,
    );

    try {
      final req = await _httpClient.postUrl(Uri.parse('$baseUrl/reset-count'));
      final res = await req.close();
      if (res.statusCode == 200) {
        _countOffset = 0;
      }
      return true;
    } catch (e) {
      return true;
    }
  }

  Future<bool> unlinkAndSwitchAccount() async {
    try {
      final req = await _httpClient.postUrl(Uri.parse('$baseUrl/unlink'));
      final res = await req.close();
      await fetchStatus();
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('⚠️ Unlink Account Error: $e');
      return false;
    }
  }

  /// Get Active Target Lock configuration from WhatsApp Bot Engine
  Future<Map<String, dynamic>?> getTargetLock() async {
    try {
      final req = await _httpClient.getUrl(Uri.parse('$baseUrl/api/bot/target-lock'));
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        return data['targetConfig'] as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }

  /// Lock Active Shift, Date & Customer on WhatsApp Bot Engine (Strictly ignores in-message shift & party tags)
  Future<bool> setTargetLock({
    required String lockedShift,
    required String lockedDate,
    required String lockedBuyerName,
    bool strictLockEnabled = true,
  }) async {
    try {
      final req = await _httpClient.postUrl(Uri.parse('$baseUrl/api/bot/target-lock'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'lockedShift': lockedShift,
        'lockedDate': lockedDate,
        'lockedBuyerName': lockedBuyerName,
        'strictLockEnabled': strictLockEnabled,
      }));
      final res = await req.close();
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('⚠️ Set Target Lock Error: $e');
      return false;
    }
  }

  void dispose() {
    stopPolling();
    _httpClient.close(force: true);
    _engineProcess?.kill();
    _engineProcess = null;
  }

  static String pathJoin(String part1, [String? p2, String? p3, String? p4, String? p5]) {
    String res = part1.replaceAll('/', Platform.pathSeparator).replaceAll('\\', Platform.pathSeparator);
    for (final p in [p2, p3, p4, p5]) {
      if (p != null) {
        res += '${Platform.pathSeparator}$p';
      }
    }
    return res;
  }
}
