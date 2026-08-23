import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/whatsapp_engine_service.dart';
import '../screens/whatsapp_engine_screen.dart';

class FloatingEngineConsole extends StatefulWidget {
  const FloatingEngineConsole({super.key});

  @override
  State<FloatingEngineConsole> createState() => _FloatingEngineConsoleState();
}

class _FloatingEngineConsoleState extends State<FloatingEngineConsole> {
  final WhatsAppEngineService _engineService = WhatsAppEngineService.instance;
  final ScrollController _scrollController = ScrollController();

  double _x = 24.0;
  double _y = 60.0;
  double _width = 640.0;
  double _height = 460.0;

  double _prevX = 24.0;
  double _prevY = 60.0;
  double _prevWidth = 640.0;
  double _prevHeight = 460.0;
  bool _isMaximized = false;

  bool _isAutoScroll = true;
  bool _isLoadingAction = false;
  bool _showQrCode = false;

  @override
  void initState() {
    super.initState();
    _engineService.logsNotifier.addListener(_handleNewLogs);
  }

  @override
  void dispose() {
    _engineService.logsNotifier.removeListener(_handleNewLogs);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleNewLogs() {
    if (_isAutoScroll && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _handleToggleBot(bool isRunning) async {
    setState(() => _isLoadingAction = true);
    if (isRunning) {
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
        setState(() {
          _isLoadingAction = false;
          _showQrCode = true;
        });
      }
    }
  }

  void _toggleMaximize(Size screenSize) {
    setState(() {
      if (_isMaximized) {
        // Restore previous dimensions
        _x = _prevX;
        _y = _prevY;
        _width = _prevWidth;
        _height = _prevHeight;
        _isMaximized = false;
      } else {
        // Save current dimensions
        _prevX = _x;
        _prevY = _y;
        _prevWidth = _width;
        _prevHeight = _height;

        // Maximize across window bounds
        _x = 10.0;
        _y = 50.0;
        _width = (screenSize.width - 20.0).clamp(400.0, double.infinity);
        _height = (screenSize.height - 60.0).clamp(300.0, double.infinity);
        _isMaximized = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return ValueListenableBuilder<bool>(
      valueListenable: _engineService.isConsoleVisibleNotifier,
      builder: (context, isVisible, _) {
        if (!isVisible) return const SizedBox.shrink();

        return ValueListenableBuilder<bool>(
          valueListenable: _engineService.isConsoleMinimizedNotifier,
          builder: (context, isMinimized, _) {
            return ValueListenableBuilder<WhatsAppEngineStatus>(
              valueListenable: _engineService.statusNotifier,
              builder: (context, status, _) {
                // Ensure floating coordinates stay within screen bounds
                final maxX = isMinimized ? (screenSize.width - 280) : (screenSize.width - 100);
                final maxY = isMinimized ? (screenSize.height - 70) : (screenSize.height - 100);
                final clampedX = _x.clamp(10.0, maxX > 10 ? maxX : 10.0);
                final clampedY = _y.clamp(50.0, maxY > 50 ? maxY : 50.0);

                return Positioned(
                  left: clampedX,
                  top: clampedY,
                  child: isMinimized
                      ? _buildMinimizedPill(status)
                      : _buildExpandedWindow(status, screenSize),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Compact Draggable Minimized Floating Pill
  Widget _buildMinimizedPill(WhatsAppEngineStatus status) {
    final bool isLive = status.isConnected;
    final bool isOnline = status.online;

    Color badgeColor = Colors.redAccent;
    String statusLabel = 'Engine Offline';
    if (isLive) {
      badgeColor = AppColors.success;
      statusLabel = 'Engine Live (:${status.port})';
    } else if (isOnline) {
      badgeColor = Colors.amberAccent;
      statusLabel = 'Engine Ready (:${status.port})';
    }

    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _x += details.delta.dx;
          _y += details.delta.dy;
        });
      },
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(30),
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: badgeColor.withValues(alpha: 0.8), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drag_indicator, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: badgeColor.withValues(alpha: 0.6), blurRadius: 6, spreadRadius: 1),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusLabel,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 10),
              // Maximize / Expand
              InkWell(
                onTap: () => _engineService.toggleConsoleMinimized(),
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.open_in_full_rounded, size: 16, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 4),
              // Close
              InkWell(
                onTap: () => _engineService.setConsoleVisible(false),
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 16, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Full-Featured Floating & Resizable Terminal Window
  Widget _buildExpandedWindow(WhatsAppEngineStatus status, Size screenSize) {
    final bool isLive = status.isConnected;
    final bool isOnline = status.online;
    final bool isConnecting = status.botStatus == WhatsAppBotStatus.connecting;

    Color badgeColor = Colors.redAccent;
    String statusTitle = 'OFFLINE';
    if (isLive) {
      badgeColor = AppColors.success;
      statusTitle = 'LIVE & STREAMING';
    } else if (isConnecting) {
      badgeColor = Colors.amberAccent;
      statusTitle = 'CONNECTING...';
    } else if (isOnline) {
      badgeColor = Colors.orangeAccent;
      statusTitle = 'ENGINE READY';
    }

    final effectiveWidth = _width.clamp(380.0, (screenSize.width - 20.0).clamp(380.0, double.infinity));
    final effectiveHeight = _height.clamp(280.0, (screenSize.height - 60.0).clamp(280.0, double.infinity));

    return Material(
      elevation: 16,
      borderRadius: BorderRadius.circular(14),
      color: Colors.transparent,
      child: Container(
        width: effectiveWidth,
        height: effectiveHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A), // Dark slate terminal theme
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // 1. Draggable Header Bar
                GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _isMaximized = false;
                      _x += details.delta.dx;
                      _y += details.delta.dy;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E293B),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.terminal_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'WhatsApp Engine Console',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: badgeColor.withValues(alpha: 0.6)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                statusTitle,
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),

                        // Minimize Button
                        IconButton(
                          icon: const Icon(Icons.remove_rounded, size: 18, color: Colors.grey),
                          tooltip: 'Minimize Console',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _engineService.toggleConsoleMinimized(),
                        ),
                        // Maximize / Restore Button
                        IconButton(
                          icon: Icon(
                            _isMaximized ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                            size: 18,
                            color: Colors.grey,
                          ),
                          tooltip: _isMaximized ? 'Restore Window' : 'Maximize Window',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _toggleMaximize(screenSize),
                        ),
                        // Close Button
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
                          tooltip: 'Hide Console',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _engineService.setConsoleVisible(false),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Metrics & Engine Control Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  color: const Color(0xFF131D31),
                  width: double.infinity,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // KPI pills
                        _buildQuickKpi('PORT', ':${status.port}', AppColors.tertiary),
                        const SizedBox(width: 12),
                        _buildQuickKpi('BUFFER', '${status.currentBufferSize}/100', Colors.orangeAccent),
                        const SizedBox(width: 12),
                        _buildQuickKpi('SAVED', '${status.processedCount}', AppColors.success),
                        const SizedBox(width: 16),

                        // QR Code Button (if available)
                        if (status.botStatus == WhatsAppBotStatus.qrReady && status.qrDataUrl != null)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: Colors.amberAccent,
                            ),
                            icon: const Icon(Icons.qr_code_scanner, size: 16),
                            label: Text(_showQrCode ? 'Hide QR' : 'Show QR'),
                            onPressed: () => setState(() => _showQrCode = !_showQrCode),
                          ),

                        const SizedBox(width: 8),

                        // Switch Account Button
                        if (isOnline) ...[
                          IconButton(
                            icon: const Icon(Icons.swap_horiz_rounded, size: 18, color: Colors.orangeAccent),
                            tooltip: 'Switch / Change WhatsApp Account',
                            visualDensity: VisualDensity.compact,
                            onPressed: _isLoadingAction ? null : _handleUnlinkAccount,
                          ),
                          const SizedBox(width: 4),
                        ],

                        // START / STOP Button
                        if (_isLoadingAction)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (isLive || isOnline) ? Colors.redAccent.withValues(alpha: 0.8) : AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: Icon(
                              (isLive || isOnline) ? Icons.stop_rounded : Icons.play_arrow_rounded,
                              size: 16,
                            ),
                            label: Text(
                              (isLive || isOnline) ? 'Stop Engine' : 'Start Engine',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                            onPressed: () => _handleToggleBot(isLive || isOnline),
                          ),
                      ],
                    ),
                  ),
                ),

                if (_showQrCode && status.qrDataUrl != null)
                  Container(
                    margin: const EdgeInsets.all(10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        const Text('Scan with WhatsApp App:', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 6),
                        StableQrDisplay(
                          qrDataUrl: status.qrDataUrl!,
                          size: 140,
                        ),
                      ],
                    ),
                  ),

                // 4. Live Terminal Logs Feed
                Expanded(
                  child: Container(
                    color: const Color(0xFF0A0F1D),
                    padding: const EdgeInsets.all(10),
                    child: ValueListenableBuilder<List<WhatsAppEngineLogItem>>(
                      valueListenable: _engineService.logsNotifier,
                      builder: (context, logs, _) {
                        if (logs.isEmpty) {
                          return const Center(
                            child: Text(
                              'No engine logs yet. Click "Start Engine" to launch background bot.',
                              style: TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'monospace'),
                            ),
                          );
                        }
                        return ListView.builder(
                          controller: _scrollController,
                          itemCount: logs.length,
                          itemBuilder: (context, index) {
                            final log = logs[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70),
                                  children: [
                                    TextSpan(
                                      text: '[${log.time}] ',
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                    TextSpan(
                                      text: '[${log.level.toUpperCase()}] ',
                                      style: TextStyle(
                                        color: _getLogLevelColor(log.level),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(text: log.message),
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

                // 5. Terminal Footer Toolbar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => setState(() => _isAutoScroll = !_isAutoScroll),
                        child: Row(
                          children: [
                            Icon(
                              _isAutoScroll ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            const Text('Auto-scroll', style: TextStyle(fontSize: 11, color: Colors.white70)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: Colors.grey),
                        tooltip: 'Clear Console Logs',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _engineService.clearLogs();
                        },
                      ),
                      const SizedBox(width: 16), // Padding for resize handle
                    ],
                  ),
                ),
              ],
            ),

            // 6. Right Edge Horizontal Resize Area
            Positioned(
              right: 0,
              top: 40,
              bottom: 24,
              width: 8,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeRight,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _isMaximized = false;
                      _width = (_width + details.delta.dx).clamp(380.0, screenSize.width - _x - 10.0);
                    });
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),

            // 7. Bottom Edge Vertical Resize Area
            Positioned(
              left: 20,
              right: 24,
              bottom: 0,
              height: 8,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDown,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _isMaximized = false;
                      _height = (_height + details.delta.dy).clamp(280.0, screenSize.height - _y - 10.0);
                    });
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),

            // 8. Bottom-Right Corner Resize Grip Handle
            Positioned(
              right: 0,
              bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _isMaximized = false;
                      _width = (_width + details.delta.dx).clamp(380.0, screenSize.width - _x - 10.0);
                      _height = (_height + details.delta.dy).clamp(280.0, screenSize.height - _y - 10.0);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E293B),
                      borderRadius: BorderRadius.only(bottomRight: Radius.circular(12)),
                    ),
                    child: const Icon(
                      Icons.south_east_rounded,
                      size: 14,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickKpi(String label, String val, Color color) {
    return Row(
      children: [
        Text('$label: ', style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        Text(val, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Color _getLogLevelColor(String level) {
    switch (level.toLowerCase()) {
      case 'error':
        return Colors.redAccent;
      case 'warn':
        return Colors.orangeAccent;
      case 'success':
        return AppColors.success;
      case 'ticket':
        return AppColors.tertiary;
      default:
        return AppColors.primary;
    }
  }
}
