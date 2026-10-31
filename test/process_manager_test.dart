import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:opscore_pro/core/process/models/process_model.dart';
import 'package:opscore_pro/core/process/services/process_manager.dart';

void main() {
  setUp(() {
    ProcessManager.instance.clearCompleted();
    ProcessManager.instance.resumeQueue();
    ProcessManager.instance.maxConcurrentProcesses = 2;
  });

  tearDown(() {
    ProcessManager.instance.cancelAll('Tear down');
    ProcessManager.instance.clearCompleted();
  });

  group('Process Execution & Concurrency', () {
    test('Parallel execution respects concurrency limit', () async {
      final manager = ProcessManager.instance;
      manager.maxConcurrentProcesses = 2;

      int maxConcurrentSeen = 0;
      int currentConcurrent = 0;

      Future<void> dummyTask(ProcessExecutionContext ctx) async {
        currentConcurrent++;
        if (currentConcurrent > maxConcurrentSeen) {
          maxConcurrentSeen = currentConcurrent;
        }
        await Future.delayed(const Duration(milliseconds: 50));
        currentConcurrent--;
      }

      final p1 = manager.enqueue(title: 'Task 1', action: dummyTask);
      final p2 = manager.enqueue(title: 'Task 2', action: dummyTask);
      final p3 = manager.enqueue(title: 'Task 3', action: dummyTask);
      final p4 = manager.enqueue(title: 'Task 4', action: dummyTask);

      final processes = await Future.wait([p1, p2, p3, p4]);

      while (manager.state.isAnyRunning || manager.state.queuedCount > 0) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      expect(maxConcurrentSeen, lessThanOrEqualTo(2));
      for (final p in processes) {
        expect(p.status, ProcessStatus.completed);
      }
    });

    test('Priority Queue: High priority processes execute before Low priority', () async {
      final manager = ProcessManager.instance;
      manager.pauseQueue();
      manager.maxConcurrentProcesses = 1;

      final executionOrder = <String>[];

      await manager.enqueue(
        title: 'Low Task',
        priority: ProcessPriority.low,
        action: (ctx) async {
          executionOrder.add('Low');
        },
      );

      await manager.enqueue(
        title: 'Normal Task',
        priority: ProcessPriority.normal,
        action: (ctx) async {
          executionOrder.add('Normal');
        },
      );

      await manager.enqueue(
        title: 'High Task',
        priority: ProcessPriority.high,
        action: (ctx) async {
          executionOrder.add('High');
        },
      );

      manager.resumeQueue();

      while (manager.state.isAnyRunning || manager.state.queuedCount > 0) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      expect(executionOrder, equals(['High', 'Normal', 'Low']));
    });

    test('Dependency Management: Task waits for prerequisite and fails if prerequisite fails', () async {
      final manager = ProcessManager.instance;
      manager.maxConcurrentProcesses = 3;

      final stepLog = <String>[];

      final parentTask = await manager.enqueue(
        title: 'Parent Task',
        action: (ctx) async {
          await Future.delayed(const Duration(milliseconds: 30));
          stepLog.add('ParentDone');
        },
      );

      final dependentTask = await manager.enqueue(
        title: 'Dependent Task',
        dependencies: [parentTask.id],
        action: (ctx) async {
          stepLog.add('DependentDone');
        },
      );

      while (manager.state.isAnyRunning || manager.state.queuedCount > 0) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      expect(parentTask.status, ProcessStatus.completed);
      expect(dependentTask.status, ProcessStatus.completed);
      expect(stepLog, equals(['ParentDone', 'DependentDone']));
    });

    test('Dependency Failure: Dependent task fails immediately if prerequisite fails', () async {
      final manager = ProcessManager.instance;
      manager.maxConcurrentProcesses = 2;

      final failingParent = await manager.enqueue(
        title: 'Failing Parent',
        action: (ctx) async {
          throw Exception('Database connection dropped');
        },
      );

      final dependentTask = await manager.enqueue(
        title: 'Dependent Task',
        dependencies: [failingParent.id],
        action: (ctx) async {
          // Should not be called!
        },
      );

      while (manager.state.isAnyRunning || manager.state.queuedCount > 0) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      expect(failingParent.status, ProcessStatus.failed);
      expect(dependentTask.status, ProcessStatus.failed);
      expect(dependentTask.errorMessage, contains('Prerequisite dependency'));
    });
  });

  group('Cancellation, Pause, Resume & Timeouts', () {
    test('Cooperative cancellation stops execution safely', () async {
      final manager = ProcessManager.instance;
      bool wasCancelledFlagDetected = false;
      final completer = Completer<void>();

      final task = await manager.enqueue(
        title: 'Long Task',
        action: (ctx) async {
          try {
            for (int i = 0; i < 20; i++) {
              await Future.delayed(const Duration(milliseconds: 10));
              if (ctx.isCancelled) {
                wasCancelledFlagDetected = true;
                ctx.throwIfCancelled();
              }
            }
          } finally {
            if (!completer.isCompleted) completer.complete();
          }
        },
      );

      await Future.delayed(const Duration(milliseconds: 25));
      manager.cancelProcess(task.id, 'User clicked stop');

      await completer.future;

      expect(task.status, ProcessStatus.cancelled);
      expect(wasCancelledFlagDetected, isTrue);
    });

    test('Pause and resume allows cooperative pausing', () async {
      final manager = ProcessManager.instance;
      bool wasPausedCheckpointPassed = false;
      final startedCompleter = Completer<void>();
      final finishedCompleter = Completer<void>();

      final task = await manager.enqueue(
        title: 'Pausable Task',
        action: (ctx) async {
          startedCompleter.complete();
          await Future.delayed(const Duration(milliseconds: 20));
          await ctx.checkPause();
          wasPausedCheckpointPassed = true;
          finishedCompleter.complete();
        },
      );

      await startedCompleter.future;
      manager.pauseProcess(task.id);
      expect(task.status, ProcessStatus.paused);

      // Verify task doesn't proceed while paused
      await Future.delayed(const Duration(milliseconds: 30));
      expect(wasPausedCheckpointPassed, isFalse);

      // Resume task
      manager.resumeProcess(task.id);
      await finishedCompleter.future;

      expect(wasPausedCheckpointPassed, isTrue);
      expect(task.status, ProcessStatus.completed);
    });

    test('Timeout policy terminates processes that exceed duration', () async {
      final manager = ProcessManager.instance;

      final task = await manager.enqueue(
        title: 'Timeout Task',
        timeout: const Duration(milliseconds: 30),
        action: (ctx) async {
          await Future.delayed(const Duration(milliseconds: 150));
        },
      );

      while (manager.state.isAnyRunning || manager.state.queuedCount > 0) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      expect(task.status, ProcessStatus.timedOut);
      expect(task.errorMessage, contains('exceeded maximum execution limit'));
    });

    test('Idempotency prevents duplicate action execution (double-clicks)', () async {
      final manager = ProcessManager.instance;

      int executions = 0;
      Future<void> clickAction() async {
        await manager.runExclusive(
          idempotencyKey: 'export_hisab_lock',
          title: 'Export Hisab',
          action: (ctx) async {
            executions++;
            await Future.delayed(const Duration(milliseconds: 60));
          },
        );
      }

      final f1 = clickAction();
      final f2 = clickAction();
      final f3 = clickAction();

      await Future.wait([f1, f2, f3]);

      expect(executions, equals(1));
    });

    test('Retry policy re-enqueues failed task up to maxRetries', () async {
      final manager = ProcessManager.instance;
      int attempts = 0;

      final task = await manager.enqueue(
        title: 'Retryable Network Task',
        maxRetries: 2,
        retryDelay: const Duration(milliseconds: 10),
        exponentialBackoff: false,
        action: (ctx) async {
          attempts++;
          if (attempts < 3) {
            throw Exception('Temporary timeout');
          }
          return 'Success on 3rd attempt';
        },
      );

      while (manager.state.isAnyRunning || manager.state.queuedCount > 0) {
        await Future.delayed(const Duration(milliseconds: 20));
      }

      final finishedProcess = manager.getProcess(task.id);
      expect(finishedProcess?.status, ProcessStatus.completed);
      expect(attempts, equals(3));
      expect(finishedProcess?.result, equals('Success on 3rd attempt'));
    });
  });

  group('Queue Limits, Memory Bounding & Shutdown', () {
    test('Queue Limit: Enqueueing beyond maxQueuedProcesses throws ProcessQueueFullException', () async {
      final manager = ProcessManager.instance;
      manager.pauseQueue();
      manager.maxQueuedProcesses = 3;

      await manager.enqueue(title: 'Queue 1', action: (ctx) async {});
      await manager.enqueue(title: 'Queue 2', action: (ctx) async {});
      await manager.enqueue(title: 'Queue 3', action: (ctx) async {});

      expect(
        () => manager.enqueue(title: 'Queue 4 (Overflow)', action: (ctx) async {}),
        throwsA(isA<ProcessQueueFullException>()),
      );

      manager.maxQueuedProcesses = 100;
      manager.resumeQueue();
    });

    test('Memory Bounding: Finished process history is evicted when exceeding maxFinishedHistory', () async {
      final manager = ProcessManager.instance;
      manager.maxFinishedHistory = 3;
      manager.maxConcurrentProcesses = 1;

      for (int i = 1; i <= 6; i++) {
        await manager.enqueue(
          title: 'Finished Task $i',
          action: (ctx) async {},
        );
      }

      while (manager.state.isAnyRunning || manager.state.queuedCount > 0) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      final completed = manager.state.completedProcesses;
      expect(completed.length, lessThanOrEqualTo(3));

      // Reset default limit
      manager.maxFinishedHistory = 50;
    });

    test('Shutdown cancels active tasks and clears queue state', () async {
      final manager = ProcessManager.instance;
      manager.pauseQueue();

      await manager.enqueue(title: 'Task A', action: (ctx) async {});
      await manager.enqueue(title: 'Task B', action: (ctx) async {});

      expect(manager.state.queuedCount, equals(2));

      manager.shutdown();

      expect(manager.allProcesses, isEmpty);
      expect(manager.state.isAnyRunning, isFalse);
      expect(manager.state.isQueuePaused, isFalse);
    });
  });
}
