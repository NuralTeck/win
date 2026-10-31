import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../services/security_crypto_service.dart';

/// Execution state of a managed process
enum ProcessStatus {
  idle,
  queued,
  starting,
  running,
  paused,
  completed,
  failed,
  cancelled,
  timedOut,
}

extension ProcessStatusX on ProcessStatus {
  bool get isActive => this == ProcessStatus.starting || this == ProcessStatus.running;
  bool get isPending => this == ProcessStatus.queued || this == ProcessStatus.idle;
  bool get isFinished =>
      this == ProcessStatus.completed ||
      this == ProcessStatus.failed ||
      this == ProcessStatus.cancelled ||
      this == ProcessStatus.timedOut;
  bool get isSuccess => this == ProcessStatus.completed;
  bool get canCancel => isActive || isPending || this == ProcessStatus.paused;
  bool get canPause => this == ProcessStatus.running;
  bool get canResume => this == ProcessStatus.paused;
  bool get canRetry => this == ProcessStatus.failed || this == ProcessStatus.cancelled || this == ProcessStatus.timedOut;
}

/// Execution priority for scheduling
enum ProcessPriority {
  high(3),
  normal(2),
  low(1);

  final int weight;
  const ProcessPriority(this.weight);
}

/// Execution mode
enum ProcessExecutionMode {
  sequential,
  parallel,
  background,
}

/// Cooperative cancellation token allowing processes to safely terminate without corrupting state
class ProcessCancellationToken {
  bool _isCancelled = false;
  String? _reason;
  final List<VoidCallback> _listeners = [];

  bool get isCancelled => _isCancelled;
  String? get reason => _reason;

  void cancel([String? reason]) {
    if (_isCancelled) return;
    _isCancelled = true;
    _reason = reason;
    for (final listener in List.of(_listeners)) {
      try {
        listener();
      } catch (e) {
        debugPrint('[ProcessCancellationToken] Listener error: $e');
      }
    }
  }

  void addListener(VoidCallback listener) {
    if (_isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw ProcessCancelledException(_reason ?? 'Process cancelled by user.');
    }
  }
}

/// Exception thrown when process is cancelled cooperatively
class ProcessCancelledException implements Exception {
  final String message;
  ProcessCancelledException([this.message = 'Process cancelled.']);

  @override
  String toString() => message;
}

/// Exception thrown when process prerequisite dependency fails
class ProcessDependencyException implements Exception {
  final String dependencyId;
  final String message;
  ProcessDependencyException(this.dependencyId, [this.message = 'Required dependency failed.']);

  @override
  String toString() => 'ProcessDependencyException(dep: $dependencyId): $message';
}

/// Exception thrown when enqueuing into a full process queue
class ProcessQueueFullException implements Exception {
  final String message;
  ProcessQueueFullException([this.message = 'Process queue is full.']);

  @override
  String toString() => 'ProcessQueueFullException: $message';
}

/// Execution context passed to each managed action
class ProcessExecutionContext {
  final String processId;
  final ProcessCancellationToken cancellationToken;
  final void Function(double progress, {String? message, int? completedSteps, int? totalSteps}) onProgressUpdate;
  final void Function(String logMessage) onLog;
  final Completer<void>? Function() getPauseCompleter;
  DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  ProcessExecutionContext({
    required this.processId,
    required this.cancellationToken,
    required this.onProgressUpdate,
    required this.onLog,
    required this.getPauseCompleter,
  });

  bool get isCancelled => cancellationToken.isCancelled;

  void throwIfCancelled() => cancellationToken.throwIfCancelled();

  void updateProgress(
    double progress, {
    String? message,
    int? completedSteps,
    int? totalSteps,
  }) {
    final now = DateTime.now();
    final isEdge = progress <= 0.0 || progress >= 1.0;
    final isStepChange = completedSteps != null;
    final isTimeElapsed = now.difference(_lastProgressUpdate).inMilliseconds >= 30;

    if (isEdge || isStepChange || isTimeElapsed) {
      _lastProgressUpdate = now;
      onProgressUpdate(
        progress.clamp(0.0, 1.0),
        message: message,
        completedSteps: completedSteps,
        totalSteps: totalSteps,
      );
    }
  }

  void log(String message) {
    onLog(message);
  }

  /// Cooperative pause checkpoint. If process is paused, execution awaits until resumed.
  Future<void> checkPause() async {
    throwIfCancelled();
    final completer = getPauseCompleter();
    if (completer != null && !completer.isCompleted) {
      onLog('Process execution suspended (paused). Waiting for user resume...');
      await completer.future;
      onLog('Process execution resumed.');
    }
    throwIfCancelled();
  }
}

/// Represents a managed, tracked, queued process
class ManagedProcess extends ChangeNotifier {
  final String id;
  final String title;
  final String? description;
  final String category;
  final String? idempotencyKey;
  final ProcessPriority priority;
  final List<String> dependencies;
  final Future<dynamic> Function(ProcessExecutionContext context) action;

  ProcessStatus status;
  double progress;
  String progressMessage;
  int completedSteps;
  int totalSteps;
  bool isIndeterminate;

  final DateTime createdAt;
  DateTime? startedAt;
  DateTime? completedAt;

  final Duration? timeout;
  final int maxRetries;
  int retryCount;
  final Duration retryDelay;
  final bool exponentialBackoff;

  String? errorMessage;
  String? errorStackTrace;
  final List<String> logs;
  dynamic result;

  ProcessCancellationToken cancellationToken;
  Completer<void>? _pauseCompleter;

  ManagedProcess({
    required this.id,
    required this.title,
    this.description,
    this.category = 'General',
    this.idempotencyKey,
    this.priority = ProcessPriority.normal,
    this.dependencies = const [],
    required this.action,
    this.status = ProcessStatus.queued,
    this.progress = 0.0,
    this.progressMessage = 'Queued...',
    this.completedSteps = 0,
    this.totalSteps = 0,
    this.isIndeterminate = false,
    DateTime? createdAt,
    this.startedAt,
    this.completedAt,
    this.timeout,
    this.maxRetries = 0,
    this.retryCount = 0,
    this.retryDelay = const Duration(seconds: 1),
    this.exponentialBackoff = true,
    this.errorMessage,
    this.errorStackTrace,
    List<String>? logs,
    this.result,
    ProcessCancellationToken? cancellationToken,
  })  : createdAt = createdAt ?? DateTime.now(),
        logs = logs ?? [],
        cancellationToken = cancellationToken ?? ProcessCancellationToken();

  Duration? get duration {
    if (startedAt == null) return null;
    final end = completedAt ?? DateTime.now();
    return end.difference(startedAt!);
  }

  void pause() {
    if (status == ProcessStatus.running && _pauseCompleter == null) {
      status = ProcessStatus.paused;
      _pauseCompleter = Completer<void>();
      progressMessage = 'Paused by user';
      addLog('Process paused by user.');
      notifyListeners();
    }
  }

  void resume() {
    if (status == ProcessStatus.paused && _pauseCompleter != null) {
      status = ProcessStatus.running;
      final c = _pauseCompleter;
      _pauseCompleter = null;
      if (c != null && !c.isCompleted) {
        c.complete();
      }
      progressMessage = 'Resumed, continuing...';
      addLog('Process resumed by user.');
      notifyListeners();
    }
  }

  Completer<void>? get pauseCompleter => _pauseCompleter;

  void cancel([String? reason]) {
    cancellationToken.cancel(reason);
    if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      _pauseCompleter!.complete();
    }
    status = ProcessStatus.cancelled;
    completedAt = DateTime.now();
    errorMessage = reason ?? 'Cancelled by user';
    progressMessage = 'Cancelled';
    addLog('Process cancelled: ${errorMessage ?? "User request"}');
    notifyListeners();
  }

  void notifyProcessUpdated() {
    notifyListeners();
  }

  void addLog(String message) {
    final timestamp = DateFormat('HH:mm:ss.SSS').format(DateTime.now());
    final sanitizedMessage = SecurityCryptoService.instance.redactSensitiveData(message);
    logs.add('[$timestamp] $sanitizedMessage');
    if (logs.length > 200) {
      logs.removeAt(0); // Cap log entries to prevent memory growth
    }
  }

  ManagedProcess copyWithResetForRetry() {
    return ManagedProcess(
      id: id,
      title: title,
      description: description,
      category: category,
      idempotencyKey: idempotencyKey,
      priority: priority,
      dependencies: dependencies,
      action: action,
      status: ProcessStatus.queued,
      progress: 0.0,
      progressMessage: 'Queued for retry...',
      completedSteps: 0,
      totalSteps: totalSteps,
      isIndeterminate: isIndeterminate,
      createdAt: DateTime.now(),
      timeout: timeout,
      maxRetries: maxRetries,
      retryCount: retryCount + 1,
      retryDelay: retryDelay,
      exponentialBackoff: exponentialBackoff,
      logs: ['[${DateFormat("HH:mm:ss").format(DateTime.now())}] Re-enqueued for retry (Attempt #${retryCount + 1})'],
      cancellationToken: ProcessCancellationToken(),
    );
  }
}
