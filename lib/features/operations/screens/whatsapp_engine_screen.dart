import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/services/whatsapp_engine_service.dart';

class WhatsAppEngineScreen extends StatefulWidget {
  const WhatsAppEngineScreen({super.key});

  @override
  State<WhatsAppEngineScreen> createState() => _WhatsAppEngineScreenState();
}

class _WhatsAppEngineScreenState extends State<WhatsAppEngineScreen> {
  final WhatsAppEngineService _engineService = WhatsAppEngineService.instance;
  final ScrollController _logScrollController = ScrollController();
  bool _isLoadingAction = false;
  bool _autoScrollLogs = true;

  @override
  void initState() {
    super.initState();
    _engineService.launchBackgroundEngine();
  }

  void _scrollToBottom() {
    if (_autoScrollLogs && _logScrollController.hasClients) {
      _logScrollController.animateTo(
        _logScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _handleToggleBot(bool isConnected) async {
    setState(() => _isLoadingAction = true);
    if (isConnected) {
      await _engineService.stopBot();
    } else {
      await _engineService.startBot();
    }
    if (mounted) {
      setState(() => _isLoadingAction = false);
    }
  }

  Future<void> _handleUnlinkAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Row(
          children: [
            Icon(Icons.swap_horiz_rounded, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text('Switch WhatsApp Account?', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: const Text(
          'This will logout the active WhatsApp account, purge saved session credentials, and generate a new QR Code immediately so you can link another WhatsApp number.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
            icon: const Icon(Icons.qr_code_2_rounded, color: Colors.black, size: 18),
            onPressed: () => Navigator.of(ctx).pop(true),
            label: const Text('Unlink & Show New QR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isLoadingAction = true);
      await _engineService.unlinkAndSwitchAccount();
      if (mounted) {
        setState(() => _isLoadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔄 WhatsApp session purged! Scan the new QR code on screen.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WhatsAppEngineStatus>(
      valueListenable: _engineService.statusNotifier,
      builder: (context, status, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Top Header Banner
            _buildHeaderBar(status),
            const SizedBox(height: 20),

            // 2. Metrics & KPI Grid (4 Cards)
            _buildKpiMetrics(status),
            const SizedBox(height: 20),

            // 3. QR Code Scan Card (Only visible when status is qrReady)
            if (status.botStatus == WhatsAppBotStatus.qrReady && status.qrDataUrl != null) ...[
              _buildQrScanCard(status.qrDataUrl!),
              const SizedBox(height: 20),
            ],

            // 4. Live Terminal Log Console
            _buildTerminalLogsView(),
          ],
        );
      },
    );
  }

  Widget _buildHeaderBar(WhatsAppEngineStatus status) {
    final bool isOnline = status.online;
    final bool isConnected = status.isConnected;
    final bool isConnecting = status.botStatus == WhatsAppBotStatus.connecting;

    Color badgeColor = Colors.redAccent;
    String badgeText = 'DISCONNECTED';
    IconData badgeIcon = Icons.cancel_outlined;

    if (!isOnline) {
      badgeColor = Colors.grey;
      badgeText = 'ENGINE OFFLINE';
      badgeIcon = Icons.power_off;
    } else if (isConnected) {
      badgeColor = AppColors.success;
      badgeText = 'LIVE & STREAMING';
      badgeIcon = Icons.check_circle_rounded;
    } else if (isConnecting) {
      badgeColor = Colors.orangeAccent;
      badgeText = 'CONNECTING...';
      badgeIcon = Icons.sync;
    } else if (status.botStatus == WhatsAppBotStatus.qrReady) {
      badgeColor = Colors.cyanAccent;
      badgeText = 'SCAN QR CODE';
      badgeIcon = Icons.qr_code_2_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: AppDecorations.radiusLg,
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 14,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade900.withAlpha(120),
                  borderRadius: AppDecorations.radiusDefault,
                  border: Border.all(color: Colors.greenAccent.withAlpha(100)),
                ),
                child: const Icon(
                  Icons.mark_chat_unread_rounded,
                  color: Colors.greenAccent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'WHATSAPP ENTRY LOGGING ENGINE',
                    style: AppTypography.titleLg.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'High-Throughput Ingestion | Supabase Bulk Buffer (2s / 100 msgs)',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Connection Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: badgeColor.withAlpha(30),
                  borderRadius: AppDecorations.radiusPill,
                  border: Border.all(color: badgeColor, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 15, color: badgeColor),
                    const SizedBox(width: 6),
                    Text(
                      badgeText,
                      style: TextStyle(
                        color: badgeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              // Dynamic Port Indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(12),
                  borderRadius: AppDecorations.radiusPill,
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lan_outlined, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'PORT: ${status.port}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Switch WhatsApp Account Button (Visible when bot is running or connected)
              if (isOnline) ...[
                SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: _isLoadingAction ? null : _handleUnlinkAccount,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      side: const BorderSide(color: Colors.orangeAccent),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppDecorations.radiusDefault,
                      ),
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text(
                      'SWITCH ACCOUNT',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              // START / STOP Toggle Button
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: _isLoadingAction
                      ? null
                      : () => _handleToggleBot(isConnected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConnected
                        ? Colors.redAccent.shade700
                        : Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppDecorations.radiusDefault,
                    ),
                  ),
                  icon: _isLoadingAction
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          isConnected ? Icons.stop_rounded : Icons.play_arrow_rounded,
                          size: 18,
                        ),
                  label: Text(
                    isConnected ? 'STOP BOT ENGINE' : 'START BOT ENGINE',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiMetrics(WhatsAppEngineStatus status) {
    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            title: 'TOTAL TICKETS BOOKED',
            value: status.processedCount.toString(),
            subtitle: 'Valid entries saved to Local Database',
            icon: Icons.done_all_rounded,
            color: Colors.greenAccent,
            onReset: () async {
              await _engineService.resetProcessedCount();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔄 Booked tickets counter reset to 0!'),
                    backgroundColor: Color(0xFF22C55E),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _kpiCard(
            title: 'ACTIVE QUEUE BUFFER',
            value: '${status.currentBufferSize} / 100',
            subtitle: 'Auto-flushes at 100 or 2000ms',
            icon: Icons.memory_rounded,
            color: Colors.amberAccent,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _kpiCard(
            title: 'FLUSH INTERVAL',
            value: '2.0s Bulk',
            subtitle: 'Zero write lag guarantee',
            icon: Icons.speed_rounded,
            color: Colors.cyanAccent,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _kpiCard(
            title: 'ENGINE UPTIME',
            value: _formatUptime(status.uptimeSeconds),
            subtitle: 'Node.js Baileys Backend',
            icon: Icons.timer_outlined,
            color: Colors.purpleAccent,
          ),
        ),
      ],
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onReset,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: AppDecorations.radiusDefault,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: AppDecorations.radiusDefault,
              border: Border.all(color: color.withAlpha(80)),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onReset != null)
                      InkWell(
                        onTap: onReset,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.restart_alt_rounded, size: 13, color: Colors.greenAccent),
                              SizedBox(width: 3),
                              Text(
                                'RESET',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.greenAccent,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTypography.headlineMd.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.textSecondary.withAlpha(150),
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrScanCard(String qrDataUrl) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: AppDecorations.radiusLg,
        border: Border.all(color: Colors.cyanAccent.withAlpha(120), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withAlpha(40),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: StableQrDisplay(
              qrDataUrl: qrDataUrl,
              size: 200,
            ),
          ),
          const SizedBox(width: 32),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.qr_code_scanner_rounded, color: Colors.cyanAccent, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'LINK WHATSAPP DEVICE',
                    style: AppTypography.titleLg.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.cyanAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('1. Open WhatsApp on your phone', style: TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 6),
              const Text('2. Go to Settings > Linked Devices > Link a Device', style: TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 6),
              const Text('3. Point your phone camera at this QR code', style: TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withAlpha(20),
                  borderRadius: AppDecorations.radiusPill,
                ),
                child: const Text(
                  '⚡ Auto-refreshes every 20 seconds',
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalLogsView() {
    return Container(
      height: 420,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117), // GitHub Dark Terminal Color
        borderRadius: AppDecorations.radiusLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Terminal Top Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.terminal_rounded, size: 18, color: Colors.greenAccent),
                    const SizedBox(width: 8),
                    const Text(
                      'STREAM CONSOLE & INGESTION LOGS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    InkWell(
                      onTap: () {
                        final logs = _engineService.logsNotifier.value;
                        if (logs.isEmpty) return;
                        final fullText = logs
                            .map((l) => '[${l.time}] [${l.level.toUpperCase()}] ${l.message}')
                            .join('\n');
                        Clipboard.setData(ClipboardData(text: fullText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: AppColors.success,
                            content: Text('📋 All console logs copied to clipboard!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.copy_all_rounded, size: 13, color: Colors.cyanAccent),
                            SizedBox(width: 4),
                            Text(
                              'Copy Logs',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _engineService.clearLogs(),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.cleaning_services_rounded, size: 13, color: Colors.orangeAccent),
                            SizedBox(width: 4),
                            Text(
                              'Clear Logs',
                              style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Auto-Scroll: ',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                    Switch(
                      value: _autoScrollLogs,
                      onChanged: (val) => setState(() => _autoScrollLogs = val),
                      activeThumbColor: Colors.greenAccent,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Terminal Output Stream (Selectable Text Area)
          Expanded(
            child: SelectionArea(
              child: ValueListenableBuilder<List<WhatsAppEngineLogItem>>(
                valueListenable: _engineService.logsNotifier,
                builder: (context, logs, _) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                  if (logs.isEmpty) {
                    return const Center(
                      child: Text(
                        'Waiting for incoming messages stream...',
                        style: TextStyle(
                          color: Colors.white38,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _logScrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final item = logs[index];
                      Color msgColor = Colors.white70;
                      if (item.level == 'error') msgColor = Colors.redAccent;
                      if (item.level == 'warn') msgColor = Colors.amberAccent;
                      if (item.level == 'success') msgColor = Colors.greenAccent;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: SelectableText.rich(
                          TextSpan(
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              height: 1.4,
                            ),
                            children: [
                              TextSpan(
                                text: '[${item.time}] ',
                                style: const TextStyle(color: Colors.white38),
                              ),
                              TextSpan(
                                text: '[${item.level.toUpperCase()}] ',
                                style: TextStyle(
                                  color: msgColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(
                                text: item.message,
                                style: TextStyle(color: msgColor),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatUptime(int seconds) {
    final m = (seconds / 60).floor();
    final s = seconds % 60;
    final h = (m / 60).floor();
    if (h > 0) return '${h}h ${m % 60}m';
    return '${m}m ${s}s';
  }
}

class StableQrDisplay extends StatefulWidget {
  final String qrDataUrl;
  final double size;

  const StableQrDisplay({
    super.key,
    required this.qrDataUrl,
    this.size = 200,
  });

  @override
  State<StableQrDisplay> createState() => _StableQrDisplayState();
}

class _StableQrDisplayState extends State<StableQrDisplay> {
  Uint8List? _cachedBytes;
  String? _lastQrUrl;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  @override
  void didUpdateWidget(covariant StableQrDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.qrDataUrl != widget.qrDataUrl) {
      _decodeImage();
    }
  }

  void _decodeImage() {
    if (_lastQrUrl == widget.qrDataUrl && _cachedBytes != null) return;
    try {
      final base64Str = widget.qrDataUrl.split(',').last;
      _cachedBytes = base64Decode(base64Str);
      _lastQrUrl = widget.qrDataUrl;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedBytes == null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Image.memory(
      _cachedBytes!,
      key: ValueKey(_lastQrUrl),
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
    );
  }
}
