import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/process_model.dart';

/// Immutable snapshot of the current state of ProcessManager
class ProcessManagerState {
  final List<ManagedProcess> allProcesses;
  final bool isQueuePaused;
  final int maxConcurrency;

  const ProcessManagerState({
    required this.allProcesses,
    this.isQueuePaused = false,
    this.maxConcurrency = 3,
  });

  List<ManagedProcess> get activeProcesses =>
      allProcesses.where((p) => p.status.isActive).toList();

  List<ManagedProcess> get queuedProcesses =>
      allProcesses.where((p) => p.status == ProcessStatus.queued).toList();

  List<ManagedProcess> get completedProcesses =>
      allProcesses.where((p) => p.status == ProcessStatus.completed).toList();

  List<ManagedProcess> get failedProcesses =>
      allProcesses.where((p) => p.status == ProcessStatus.failed || p.status == ProcessStatus.timedOut).toList();

  List<ManagedProcess> get cancelledProcesses =>
      allProcesses.where((p) => p.status == ProcessStatus.cancelled).toList();

  bool get isAnyRunning => activeProcesses.isNotEmpty;

  int get runningCount => activeProcesses.length;
  int get queuedCount => queuedProcesses.length;
  int get completedCount => completedProcesses.length;
  int get failedCount => failedProcesses.length;

  double get overallProgress {
    final active = activeProcesses;
    if (active.isEmpty) return 0.0;
    final total = active.fold<double>(0.0, (acc, p) => acc + p.progress);
    return (total / active.length).clamp(0.0, 1.0);
  }

  String get activeSummary {
    final active = activeProcesses;
    if (active.isEmpty) {
      if (queuedProcesses.isNotEmpty) {
        return '${queuedProcesses.length} task(s) queued';
      }
      return 'All processes completed';
    }
    if (active.length == 1) {
      final p = active.first;
      return '${p.title} (${(p.progress * 100).toInt()}%)';
    }
    return '${active.length} tasks running • ${(overallProgress * 100).toInt()}%';
  }
}

/// Central Singleton and Orchestrator for Process Lifecycle, Queueing & Concurrency
class ProcessManager extends ChangeNotifier {
  static final ProcessManager instance = ProcessManager._internal();

  ProcessManager._internal();

  final Map<String, ManagedProcess> _processes = {};
  final Set<String> _activeProcessIds = {};
  bool _isQueuePaused = false;
  int _maxConcurrentProcesses = 3;
  int maxQueuedProcesses = 100;
  int maxFinishedHistory = 50;
  bool _isScheduling = false;
  DateTime _lastGlobalNotify = DateTime.fromMillisecondsSinceEpoch(0);

  void _notifyGlobalProgressThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastGlobalNotify).inMilliseconds >= 80) {
      _lastGlobalNotify = now;
      notifyListeners();
    }
  }

  int get maxConcurrentProcesses => _maxConcurrentProcesses;
  set maxConcurrentProcesses(int value) {
    _maxConcurrentProcesses = math.max(1, value);
    _scheduleNext();
    notifyListeners();
  }

  bool get isQueuePaused => _isQueuePaused;

  List<ManagedProcess> get allProcesses => _processes.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  ProcessManagerState get state => ProcessManagerState(
        allProcesses: allProcesses,
        isQueuePaused: _isQueuePaused,
        maxConcurrency: _maxConcurrentProcesses,
      );

  ManagedProcess? getProcess(String id) => _processes[id];

  /// Checks if any task with this idempotency key is currently running or queued
  bool isIdempotencyKeyActive(String? key) {
    if (key == null || key.isEmpty) return false;
    return _processes.values.any(
      (p) => p.idempotencyKey == key && (p.status.isActive || p.status == ProcessStatus.queued),
    );
  }

  /// 🚀 Enqueue a new managed task with priority, dependencies, retries and timeout
  Future<ManagedProcess> enqueue({
    required String title,
    String? description,
    String category = 'General',
    String? idempotencyKey,
    ProcessPriority priority = ProcessPriority.normal,
    List<String> dependencies = const [],
    Duration? timeout,
    int maxRetries = 0,
    Duration retryDelay = const Duration(seconds: 1),
    bool exponentialBackoff = true,
    bool isIndeterminate = false,
    required Future<dynamic> Function(ProcessExecutionContext context) action,
  }) async {
    // 🛡️ Prevent duplicate execution of identical actions
    if (idempotencyKey != null && isIdempotencyKeyActive(idempotencyKey)) {
      final existing = _processes.values.firstWhere((p) => p.idempotencyKey == idempotencyKey);
      debugPrint('[ProcessManager] Duplicate execution blocked for key "$idempotencyKey" (Process ID: ${existing.id})');
      return existing;
    }

    // 🛡️ Bounded Queue Budget: Prevent unbounded task accumulation
    final currentQueued = _processes.values.where((p) => p.status == ProcessStatus.queued).length;
    if (currentQueued >= maxQueuedProcesses) {
      throw ProcessQueueFullException('Process queue limit ($maxQueuedProcesses) reached. Please wait for pending tasks.');
    }

    final id = 'proc_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}';
    final process = ManagedProcess(
      id: id,
      title: title,
      description: description,
      category: category,
      idempotencyKey: idempotencyKey,
      priority: priority,
      dependencies: dependencies,
      timeout: timeout,
      maxRetries: maxRetries,
      retryDelay: retryDelay,
      exponentialBackoff: exponentialBackoff,
      isIndeterminate: isIndeterminate,
      action: action,
      status: ProcessStatus.queued,
      progressMessage: 'Queued for execution...',
    );

    process.addLog('Enqueued with priority ${priority.name.toUpperCase()} (Concurrency slot limit: $_maxConcurrentProcesses)');
    _processes[id] = process;
    notifyListeners();

    // Trigger queue scheduler
    _scheduleNext();
    return process;
  }

  /// 🛡️ Helper to run a user-triggered action exclusively (prevents double-clicks & spam)
  Future<T?> runExclusive<T>({
    required String idempotencyKey,
    required String title,
    String category = 'Action',
    ProcessPriority priority = ProcessPriority.high,
    required Future<T> Function(ProcessExecutionContext context) action,
    void Function(String message)? onDuplicateRejected,
  }) async {
    if (isIdempotencyKeyActive(idempotencyKey)) {
      final msg = 'Action "$title" is already running. Please wait for completion.';
      debugPrint('[ProcessManager] $msg');
      onDuplicateRejected?.call(msg);
      return null;
    }

    final completer = Completer<T?>();
    await enqueue(
      title: title,
      category: category,
      idempotencyKey: idempotencyKey,
      priority: priority,
      action: (ctx) async {
        try {
          final res = await action(ctx);
          completer.complete(res);
          return res;
        } catch (e, st) {
          if (!completer.isCompleted) completer.completeError(e, st);
          rethrow;
        }
      },
    );

    return completer.future;
  }

  /// Internal Queue Scheduler: Checks dependencies, priority, concurrency limits, and launches tasks
  void _scheduleNext() {
    if (_isScheduling || _isQueuePaused) return;
    _isScheduling = true;

    try {
      while (_activeProcessIds.length < _maxConcurrentProcesses) {
        // Collect candidate queued processes whose dependencies are satisfied
        final queued = _processes.values
            .where((p) => p.status == ProcessStatus.queued)
            .toList();

        if (queued.isEmpty) break;

        // Sort by Priority (High > Normal > Low), then FIFO (createdAt)
        queued.sort((a, b) {
          final pComp = b.priority.weight.compareTo(a.priority.weight);
          if (pComp != 0) return pComp;
          return a.createdAt.compareTo(b.createdAt);
        });

        ManagedProcess? selectedProcess;

        for (final candidate in queued) {
          if (candidate.dependencies.isEmpty) {
            selectedProcess = candidate;
            break;
          }

          // Verify dependencies
          bool allSatisfied = true;
          bool hasFailedDependency = false;
          String? failedDepId;

          for (final depId in candidate.dependencies) {
            final dep = _processes[depId];
            if (dep == null || dep.status == ProcessStatus.failed || dep.status == ProcessStatus.cancelled || dep.status == ProcessStatus.timedOut) {
              hasFailedDependency = true;
              failedDepId = depId;
              break;
            }
            if (dep.status != ProcessStatus.completed) {
              allSatisfied = false; // still waiting
            }
          }

          if (hasFailedDependency) {
            // Prerequisite failed -> fail dependent process immediately
            candidate.status = ProcessStatus.failed;
            candidate.errorMessage = 'Skipped: Prerequisite dependency "$failedDepId" failed or was cancelled.';
            candidate.completedAt = DateTime.now();
            candidate.addLog(candidate.errorMessage!);
            notifyListeners();
            continue;
          }

          if (allSatisfied) {
            selectedProcess = candidate;
            break;
          }
        }

        if (selectedProcess == null) {
          // No queued process has dependencies satisfied right now
          break;
        }

        // Launch selected process
        _executeProcess(selectedProcess);
      }
    } finally {
      _isScheduling = false;
    }
  }

  /// Executes an individual process with lifecycle updates, progress tracking, timeout and error handling
  Future<void> _executeProcess(ManagedProcess process) async {
    _activeProcessIds.add(process.id);
    process.status = ProcessStatus.starting;
    process.startedAt = DateTime.now();
    process.progressMessage = 'Starting...';
    process.addLog('Process started execution slot.');
    notifyListeners();

    // Prepare Execution Context
    final context = ProcessExecutionContext(
      processId: process.id,
      cancellationToken: process.cancellationToken,
      onProgressUpdate: (progress, {message, completedSteps, totalSteps}) {
        process.progress = progress;
        if (message != null) process.progressMessage = message;
        if (completedSteps != null) process.completedSteps = completedSteps;
        if (totalSteps != null) process.totalSteps = totalSteps;
        process.notifyProcessUpdated();
        _notifyGlobalProgressThrottled();
      },
      onLog: (msg) {
        process.addLog(msg);
        process.notifyProcessUpdated();
      },
      getPauseCompleter: () => process.pauseCompleter,
    );

    // Transition to Running state
    process.status = ProcessStatus.running;
    notifyListeners();

    try {
      // Execute with optional timeout
      dynamic result;
      if (process.timeout != null) {
        result = await process.action(context).timeout(
          process.timeout!,
          onTimeout: () {
            throw TimeoutException('Process exceeded maximum execution limit of ${process.timeout!.inSeconds}s');
          },
        );
      } else {
        result = await process.action(context);
      }

      if (process.cancellationToken.isCancelled) {
        process.status = ProcessStatus.cancelled;
        process.progressMessage = 'Cancelled';
        process.addLog('Execution completed with cancellation flag set.');
      } else {
        process.status = ProcessStatus.completed;
        process.progress = 1.0;
        process.progressMessage = 'Completed successfully';
        process.result = result;
        process.addLog('Execution completed successfully in ${process.duration?.inMilliseconds ?? 0}ms.');
      }
    } on ProcessCancelledException catch (e) {
      process.status = ProcessStatus.cancelled;
      process.errorMessage = e.message;
      process.progressMessage = 'Cancelled';
      process.addLog('Process was cancelled: ${e.message}');
    } on TimeoutException catch (e) {
      process.status = ProcessStatus.timedOut;
      process.errorMessage = e.message;
      process.progressMessage = 'Timed Out';
      process.addLog('Process timed out: ${e.message}');
    } catch (e, stack) {
      process.addLog('Execution error: $e');

      // Check retry policy
      if (process.retryCount < process.maxRetries && !process.cancellationToken.isCancelled) {
        final nextRetryCount = process.retryCount + 1;
        final backoffMultiplier = process.exponentialBackoff
            ? math.pow(2, process.retryCount).toInt()
            : 1;
        final delay = process.retryDelay * backoffMultiplier;

        final retryingProcess = process.copyWithResetForRetry();
        retryingProcess.progressMessage = 'Waiting to retry (Attempt #$nextRetryCount in ${delay.inSeconds}s)...';
        retryingProcess.addLog('Process failed: $e. Retrying in ${delay.inMilliseconds}ms (Attempt #$nextRetryCount/${process.maxRetries}).');
        _processes[process.id] = retryingProcess;
        _activeProcessIds.remove(process.id);
        notifyListeners();

        Future.delayed(delay, () {
          if (!retryingProcess.cancellationToken.isCancelled && retryingProcess.status == ProcessStatus.queued) {
            _scheduleNext();
          }
        });
        return;
      } else {
        process.status = ProcessStatus.failed;
        process.errorMessage = e.toString();
        process.errorStackTrace = stack.toString();
        process.progressMessage = 'Failed';
        process.addLog('Process terminated with failure: $e');
      }
    } finally {
      process.completedAt = DateTime.now();
      _activeProcessIds.remove(process.id);

      // Memory Budget Eviction: Keep finished history bounded to maxFinishedHistory
      final finished = _processes.values.where((p) => p.status.isFinished).toList()
        ..sort((a, b) => (a.completedAt ?? a.createdAt).compareTo(b.completedAt ?? b.createdAt));
      while (finished.length > maxFinishedHistory) {
        final oldest = finished.removeAt(0);
        _processes.remove(oldest.id);
      }

      notifyListeners();

      // Schedule next available tasks in queue
      _scheduleNext();
    }
  }

  /// Pause an active running process
  void pauseProcess(String id) {
    final p = _processes[id];
    if (p != null && p.status == ProcessStatus.running) {
      p.pause();
      notifyListeners();
    }
  }

  /// Resume a paused process
  void resumeProcess(String id) {
    final p = _processes[id];
    if (p != null && p.status == ProcessStatus.paused) {
      p.resume();
      notifyListeners();
    }
  }

  /// Cancel an individual process safely
  void cancelProcess(String id, [String? reason]) {
    final p = _processes[id];
    if (p != null && p.status.canCancel) {
      final wasRunning = p.status.isActive;
      p.cancel(reason);
      if (!wasRunning) {
        _activeProcessIds.remove(id);
      }
      notifyListeners();
      _scheduleNext();
    }
  }

  /// Manual Retry for failed or cancelled tasks
  void retryProcess(String id) {
    final p = _processes[id];
    if (p != null && p.status.canRetry) {
      final retried = p.copyWithResetForRetry();
      _processes[id] = retried;
      notifyListeners();
      _scheduleNext();
    }
  }

  /// Pause the global queue (prevents starting new tasks)
  void pauseQueue() {
    _isQueuePaused = true;
    notifyListeners();
  }

  /// Resume the global queue
  void resumeQueue() {
    _isQueuePaused = false;
    notifyListeners();
    _scheduleNext();
  }

  /// Cancel all active and queued processes
  void cancelAll([String? reason]) {
    for (final p in _processes.values) {
      if (p.status.canCancel) {
        p.cancel(reason ?? 'Bulk cancelled by user');
      }
    }
    _activeProcessIds.clear();
    notifyListeners();
  }

  /// Clear finished processes (completed, cancelled, failed) from history
  void clearCompleted() {
    _processes.removeWhere((_, p) => p.status.isFinished);
    notifyListeners();
  }

  /// Gracefully cancels running tasks, clears queue, and resets manager state
  void shutdown() {
    cancelAll('ProcessManager shutdown');
    _processes.clear();
    _activeProcessIds.clear();
    _isQueuePaused = false;
    notifyListeners();
  }
}

/// Riverpod Providers for ProcessManager
final processManagerProvider = ChangeNotifierProvider<ProcessManager>((ref) {
  return ProcessManager.instance;
});

final processStateProvider = Provider<ProcessManagerState>((ref) {
  final manager = ref.watch(processManagerProvider);
  return manager.state;
});
