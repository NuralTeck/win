import 'package:flutter/material.dart';
import '../services/process_manager.dart';
import 'process_control_center_dialog.dart';

/// Compact, reactive Process Status Badge designed for TopAppBar
class ProcessStatusPill extends StatelessWidget {
  const ProcessStatusPill({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProcessManager.instance,
      builder: (context, _) {
        final state = ProcessManager.instance.state;
        final hasActive = state.isAnyRunning;
        final hasQueued = state.queuedCount > 0;
        final hasFailed = state.failedCount > 0;

        Color pillColor = Colors.grey.withValues(alpha: 0.15);
        Color borderColor = Colors.grey.withValues(alpha: 0.3);
        Color textColor = Colors.grey;
        Widget leadingWidget = const Icon(Icons.tune_rounded, size: 14, color: Colors.grey);

        String label = 'Tasks Idle';

        if (hasActive) {
          pillColor = const Color(0xFF7C3AED).withValues(alpha: 0.2);
          borderColor = const Color(0xFFC084FC).withValues(alpha: 0.6);
          textColor = const Color(0xFFC084FC);
          leadingWidget = const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC084FC)),
            ),
          );
          label = '${state.runningCount} Running (${(state.overallProgress * 100).toInt()}%)';
        } else if (hasQueued) {
          pillColor = Colors.amber.withValues(alpha: 0.15);
          borderColor = Colors.amber.withValues(alpha: 0.5);
          textColor = Colors.amberAccent;
          leadingWidget = const Icon(Icons.schedule_rounded, size: 14, color: Colors.amberAccent);
          label = '${state.queuedCount} Queued';
        } else if (hasFailed) {
          pillColor = Colors.redAccent.withValues(alpha: 0.15);
          borderColor = Colors.redAccent.withValues(alpha: 0.5);
          textColor = Colors.redAccent;
          leadingWidget = const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.redAccent);
          label = '${state.failedCount} Failed';
        } else if (state.completedCount > 0) {
          pillColor = const Color(0xFF10B981).withValues(alpha: 0.12);
          borderColor = const Color(0xFF10B981).withValues(alpha: 0.35);
          textColor = const Color(0xFF34D399);
          leadingWidget = const Icon(Icons.task_alt_rounded, size: 14, color: Color(0xFF34D399));
          label = '${state.completedCount} Done';
        }

        return Tooltip(
          message: state.activeSummary,
          child: InkWell(
            onTap: () {
              ProcessControlCenterDialog.show(context);
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: pillColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor, width: 1.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  leadingWidget,
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  if (ProcessManager.instance.isQueuePaused) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('PAUSED', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Colors.orangeAccent)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
