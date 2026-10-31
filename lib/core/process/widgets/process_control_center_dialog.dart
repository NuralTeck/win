import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../models/process_model.dart';
import '../services/process_manager.dart';

enum ProcessFilterTab {
  all,
  running,
  queued,
  completed,
  failed,
}

class ProcessControlCenterDialog extends StatefulWidget {
  const ProcessControlCenterDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => const ProcessControlCenterDialog(),
    );
  }

  @override
  State<ProcessControlCenterDialog> createState() => _ProcessControlCenterDialogState();
}

class _ProcessControlCenterDialogState extends State<ProcessControlCenterDialog> {
  ProcessFilterTab _activeTab = ProcessFilterTab.all;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProcessManager.instance,
      builder: (context, _) {
        final manager = ProcessManager.instance;
        final state = manager.state;

        // Apply Tab Filter
        List<ManagedProcess> filteredList = state.allProcesses;
        switch (_activeTab) {
          case ProcessFilterTab.running:
            filteredList = state.activeProcesses;
            break;
          case ProcessFilterTab.queued:
            filteredList = state.queuedProcesses;
            break;
          case ProcessFilterTab.completed:
            filteredList = state.completedProcesses;
            break;
          case ProcessFilterTab.failed:
            filteredList = state.failedProcesses;
            break;
          case ProcessFilterTab.all:
            filteredList = state.allProcesses;
            break;
        }

        // Apply Search
        if (_searchQuery.trim().isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          filteredList = filteredList.where((p) {
            return p.title.toLowerCase().contains(q) ||
                p.category.toLowerCase().contains(q) ||
                p.progressMessage.toLowerCase().contains(q) ||
                (p.errorMessage ?? '').toLowerCase().contains(q);
          }).toList();
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 880,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.90,
            ),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.4), width: 1.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.85),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Dialog Header ──────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.manage_history_rounded, color: Color(0xFFC084FC), size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'PROCESS CONTROL & QUEUE MANAGER',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (manager.isQueuePaused)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.orangeAccent),
                                  ),
                                  child: const Text(
                                    'QUEUE PAUSED',
                                    style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Lifecycle monitoring • Priority queue • Concurrency control • Instant task recovery',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    // Concurrency dropdown selector
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.speed_rounded, size: 14, color: Color(0xFFC084FC)),
                          const SizedBox(width: 6),
                          const Text('Max Slots:', style: TextStyle(fontSize: 11, color: Colors.white70)),
                          const SizedBox(width: 6),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: manager.maxConcurrentProcesses,
                              dropdownColor: const Color(0xFF1E293B),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                              items: const [1, 2, 3, 5, 8].map((c) {
                                return DropdownMenuItem(value: c, child: Text('$c Concurrent'));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) manager.maxConcurrentProcesses = val;
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF334155), height: 1),
                const SizedBox(height: 14),

                // ── KPI Summary Cards & Global Actions ───────────────────────
                Row(
                  children: [
                    _buildKpiCard('RUNNING', '${state.runningCount}', const Color(0xFFC084FC), Icons.play_arrow_rounded),
                    const SizedBox(width: 8),
                    _buildKpiCard('QUEUED', '${state.queuedCount}', Colors.amberAccent, Icons.schedule_rounded),
                    const SizedBox(width: 8),
                    _buildKpiCard('COMPLETED', '${state.completedCount}', const Color(0xFF34D399), Icons.check_circle_outline_rounded),
                    const SizedBox(width: 8),
                    _buildKpiCard('FAILED', '${state.failedCount}', Colors.redAccent, Icons.error_outline_rounded),
                    const Spacer(),

                    // Global Queue Controls
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: manager.isQueuePaused ? Colors.green : Colors.orange),
                        foregroundColor: manager.isQueuePaused ? Colors.greenAccent : Colors.orangeAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: Icon(manager.isQueuePaused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 16),
                      label: Text(
                        manager.isQueuePaused ? 'RESUME QUEUE' : 'PAUSE QUEUE',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                      ),
                      onPressed: () {
                        if (manager.isQueuePaused) {
                          manager.resumeQueue();
                        } else {
                          manager.pauseQueue();
                        }
                      },
                    ),
                    const SizedBox(width: 8),

                    if (state.activeProcesses.isNotEmpty || state.queuedProcesses.isNotEmpty)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent),
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.cancel_outlined, size: 16),
                        label: const Text('CANCEL ALL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                        onPressed: () => manager.cancelAll('Cancelled via Process Control Center'),
                      ),
                    const SizedBox(width: 8),

                    if (state.completedCount > 0 || state.failedCount > 0)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: Colors.white60),
                        label: const Text('Clear Finished', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        onPressed: () => manager.clearCompleted(),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Filter Chips & Search Bar ────────────────────────────────
                Row(
                  children: [
                    _buildFilterChip('All (${state.allProcesses.length})', ProcessFilterTab.all),
                    const SizedBox(width: 6),
                    _buildFilterChip('Running (${state.runningCount})', ProcessFilterTab.running, color: const Color(0xFFC084FC)),
                    const SizedBox(width: 6),
                    _buildFilterChip('Queued (${state.queuedCount})', ProcessFilterTab.queued, color: Colors.amberAccent),
                    const SizedBox(width: 6),
                    _buildFilterChip('Completed (${state.completedCount})', ProcessFilterTab.completed, color: const Color(0xFF34D399)),
                    const SizedBox(width: 6),
                    _buildFilterChip('Failed (${state.failedCount})', ProcessFilterTab.failed, color: Colors.redAccent),
                    const Spacer(),

                    // Search input
                    SizedBox(
                      width: 220,
                      height: 36,
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        style: const TextStyle(fontSize: 12.5, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search tasks...',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                          prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white54),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Process List Area ────────────────────────────────────────
                Expanded(
                  child: filteredList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.task_rounded, size: 48, color: Colors.white.withValues(alpha: 0.15)),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isNotEmpty ? 'No tasks matching "$_searchQuery"' : 'No tasks in this category.',
                                style: const TextStyle(color: Colors.white54, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: filteredList.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final process = filteredList[idx];
                            return _buildProcessItemCard(process, manager);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildKpiCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 9.5, fontWeight: FontWeight.bold)),
              Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, ProcessFilterTab tab, {Color? color}) {
    final isSelected = _activeTab == tab;
    return InkWell(
      onTap: () => setState(() => _activeTab = tab),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? (color ?? const Color(0xFF7C3AED)).withValues(alpha: 0.25) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? (color ?? const Color(0xFFC084FC)) : const Color(0xFF334155),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildProcessItemCard(ManagedProcess process, ProcessManager manager) {
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.help_outline;
    switch (process.status) {
      case ProcessStatus.idle:
      case ProcessStatus.queued:
        statusColor = Colors.amberAccent;
        statusIcon = Icons.schedule_rounded;
        break;
      case ProcessStatus.starting:
      case ProcessStatus.running:
        statusColor = const Color(0xFFC084FC);
        statusIcon = Icons.sync_rounded;
        break;
      case ProcessStatus.paused:
        statusColor = Colors.orangeAccent;
        statusIcon = Icons.pause_circle_outline_rounded;
        break;
      case ProcessStatus.completed:
        statusColor = const Color(0xFF34D399);
        statusIcon = Icons.check_circle_rounded;
        break;
      case ProcessStatus.failed:
      case ProcessStatus.timedOut:
        statusColor = Colors.redAccent;
        statusIcon = Icons.error_rounded;
        break;
      case ProcessStatus.cancelled:
        statusColor = Colors.grey;
        statusIcon = Icons.cancel_rounded;
        break;
    }

    final durationStr = process.duration != null
        ? '${(process.duration!.inMilliseconds / 1000).toStringAsFixed(1)}s'
        : '0s';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: process.status.isActive
              ? const Color(0xFF7C3AED).withValues(alpha: 0.6)
              : const Color(0xFF334155),
          width: process.status.isActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Title, Category, Priority, Status Badge & Actions
          Row(
            children: [
              // Category tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Text(
                  process.category.toUpperCase(),
                  style: const TextStyle(fontSize: 9.5, color: Colors.white70, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),

              // Priority indicator
              if (process.priority == ProcessPriority.high)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                  ),
                  child: const Text('HIGH PRIORITY', style: TextStyle(fontSize: 9, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                ),
              if (process.priority == ProcessPriority.high) const SizedBox(width: 8),

              // Process Title
              Expanded(
                child: Text(
                  process.title,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      process.status.name.toUpperCase(),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Action Buttons
              if (process.status == ProcessStatus.running)
                IconButton(
                  icon: const Icon(Icons.pause_rounded, size: 18, color: Colors.orangeAccent),
                  tooltip: 'Pause Process',
                  onPressed: () => manager.pauseProcess(process.id),
                ),
              if (process.status == ProcessStatus.paused)
                IconButton(
                  icon: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.greenAccent),
                  tooltip: 'Resume Process',
                  onPressed: () => manager.resumeProcess(process.id),
                ),
              if (process.status.canCancel)
                IconButton(
                  icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.redAccent),
                  tooltip: 'Cancel Process',
                  onPressed: () => manager.cancelProcess(process.id, 'Cancelled by user'),
                ),
              if (process.status.canRetry)
                IconButton(
                  icon: const Icon(Icons.replay_rounded, size: 18, color: Colors.amberAccent),
                  tooltip: 'Retry Process',
                  onPressed: () => manager.retryProcess(process.id),
                ),
              IconButton(
                icon: const Icon(Icons.terminal_rounded, size: 18, color: Colors.cyanAccent),
                tooltip: 'View Execution Logs',
                onPressed: () => _showLogsDialog(process),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Middle Row: Progress Bar & Progress Details
          if (process.status.isActive || process.status == ProcessStatus.paused) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: process.isIndeterminate ? null : process.progress,
                minHeight: 5,
                backgroundColor: const Color(0xFF0F172A),
                valueColor: AlwaysStoppedAnimation<Color>(
                  process.status == ProcessStatus.paused ? Colors.orangeAccent : const Color(0xFFC084FC),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Bottom Row: Status Message & Timing
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  process.progressMessage.isNotEmpty ? process.progressMessage : 'Executing...',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: process.status == ProcessStatus.failed ? Colors.redAccent : Colors.white70,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (process.totalSteps > 0) ...[
                    Text(
                      '${process.completedSteps} / ${process.totalSteps} steps',
                      style: const TextStyle(fontSize: 10.5, color: Colors.white54),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (process.startedAt != null)
                    Text(
                      'Duration: $durationStr',
                      style: const TextStyle(fontSize: 10.5, color: Colors.white54),
                    ),
                  if (process.retryCount > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '(Retry #${process.retryCount})',
                      style: const TextStyle(fontSize: 10.5, color: Colors.amberAccent),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showLogsDialog(ManagedProcess process) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 680,
          constraints: const BoxConstraints(maxHeight: 540),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.terminal_rounded, size: 20, color: Colors.cyanAccent),
                      const SizedBox(width: 10),
                      Text(
                        'EXECUTION AUDIT LOGS: ${process.title.toUpperCase()}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF334155), height: 1),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF020617),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: process.logs.isEmpty
                      ? const Center(child: Text('No logs recorded yet.', style: TextStyle(color: Colors.white38, fontSize: 12)))
                      : ListView.builder(
                          itemCount: process.logs.length,
                          itemBuilder: (context, i) {
                            final line = process.logs[i];
                            Color textColor = Colors.greenAccent;
                            if (line.contains('error') || line.contains('Failed') || line.contains('failed')) {
                              textColor = Colors.redAccent;
                            } else if (line.contains('paused') || line.contains('Queued')) {
                              textColor = Colors.amberAccent;
                            }
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: SelectableText(
                                line,
                                style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: textColor),
                              ),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('Copy Logs', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: process.logs.join('\n')));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Logs copied to clipboard'), backgroundColor: Color(0xFF1E1B4B)),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
