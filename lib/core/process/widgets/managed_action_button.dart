import 'package:flutter/material.dart';
import '../services/process_manager.dart';

/// Button that binds to an idempotency key to prevent double clicks and show loading state
class ManagedActionButton extends StatelessWidget {
  final String idempotencyKey;
  final Widget? icon;
  final String label;
  final Future<void> Function() onPressed;
  final ButtonStyle? style;
  final bool showProgressPercent;

  const ManagedActionButton({
    super.key,
    required this.idempotencyKey,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style,
    this.showProgressPercent = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProcessManager.instance,
      builder: (context, _) {
        final isRunning = ProcessManager.instance.isIdempotencyKeyActive(idempotencyKey);
        final process = ProcessManager.instance.allProcesses
            .where((p) => p.idempotencyKey == idempotencyKey)
            .firstOrNull;

        String buttonText = label;
        if (isRunning && process != null) {
          if (showProgressPercent && process.progress > 0) {
            buttonText = '${(process.progress * 100).toInt()}% • ${process.progressMessage}';
          } else {
            buttonText = process.progressMessage.isNotEmpty ? process.progressMessage : 'Processing...';
          }
        }

        return ElevatedButton(
          style: style,
          onPressed: isRunning
              ? null
              : () async {
                  await onPressed();
                },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRunning) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 8),
              ] else if (icon != null) ...[
                icon!,
                const SizedBox(width: 8),
              ],
              Text(buttonText),
            ],
          ),
        );
      },
    );
  }
}

