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
      final sbUrl = dotenv.env['SUPABASE_URL'] ?? '';
      final sbKey = dotenv.env['SUPABASE_ANON_KEY'] ?? dotenv.env['SUPABASE_SERVICE_ROLE_KEY'] ?? '';

      final envMap = {
        ...Platform.environment,
        'PORT': '$_activePort',
        'SUPABASE_URL': sbUrl,
        'SUPABASE_KEY': sbKey,
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
        debugPrint('🚀 Spawning Node.js WhatsApp Engine: $foundTarget (Port: $_activePort)');
        _engineProcess = await Process.start(
          'node',
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
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
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

        String? qrUrl;
        if (data['hasQr'] == true) {
          final qrReq = await _httpClient.getUrl(Uri.parse('$baseUrl/qr'));
          final qrRes = await qrReq.close();
          if (qrRes.statusCode == 200) {
            final qrBody = await qrRes.transform(utf8.decoder).join();
            final qrData = jsonDecode(qrBody);
            qrUrl = qrData['qrDataUrl'];
          }
        }

        final rawStatus = data['connectionStatus'] as String? ?? 'disconnected';
        WhatsAppBotStatus botStat;
        switch (rawStatus) {
          case 'connected':
            botStat = WhatsAppBotStatus.connected;
            break;
          case 'connecting':
            botStat = WhatsAppBotStatus.connecting;
            break;
          case 'qr_ready':
            botStat = WhatsAppBotStatus.qrReady;
            break;
          default:
            botStat = WhatsAppBotStatus.disconnected;
        }

        statusNotifier.value = WhatsAppEngineStatus(
          online: true,
          botStatus: botStat,
          isConnected: data['isConnected'] ?? false,
          hasQr: data['hasQr'] ?? false,
          qrDataUrl: qrUrl,
          processedCount: data['processedTotalCount'] ?? 0,
          currentBufferSize: data['currentBufferSize'] ?? 0,
          lastFlushTime: data['lastFlushTimestamp'],
          uptimeSeconds: data['uptimeSeconds'] ?? 0,
          port: _activePort,
        );
        return;
      }
    } catch (_) {
      // Backend offline
    }
    statusNotifier.value = WhatsAppEngineStatus.offline(port: _activePort);
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
      final sbUrl = dotenv.env['SUPABASE_URL'] ?? '';
      final sbKey = dotenv.env['SUPABASE_ANON_KEY'] ?? dotenv.env['SUPABASE_SERVICE_ROLE_KEY'] ?? '';

      final req = await _httpClient.postUrl(Uri.parse('$baseUrl/start'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'supabaseUrl': sbUrl,
        'supabaseKey': sbKey,
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
    try {
      final req = await _httpClient.postUrl(Uri.parse('$baseUrl/stop'));
      final res = await req.close();
      await fetchStatus();
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('⚠️ Stop Bot HTTP Error: $e');
      return false;
    }
  }

  Future<void> clearLogs() async {
    logsNotifier.value = [];
    try {
      final req = await _httpClient.postUrl(Uri.parse('$baseUrl/clear-logs'));
      await req.close();
    } catch (_) {}
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
