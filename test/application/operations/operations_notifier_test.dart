import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/operations/activity_log_store.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/infrastructure/operations/activity_log_repository.dart';
import '../../_helpers/in_memory_db.dart';

final class _DelayedLogStore implements ActivityLogStore {
  final recentResult = Completer<List<RunningOperation>>();

  @override
  Future<void> clearCompleted() async {}

  @override
  Future<List<RunningOperation>> recent({int limit = 50}) =>
      recentResult.future;

  @override
  Future<void> upsert(RunningOperation op) async {}
}

void main() {
  test(
    'hydration does not discard an operation started concurrently',
    () async {
      final store = _DelayedLogStore();
      final notifier = OperationsNotifier(store);
      final id = notifier.start(OpKind.other, 'Opening repository');

      store.recentResult.complete(const []);
      await Future<void>.delayed(Duration.zero);
      notifier.finishSuccess(id);

      expect(notifier.state, hasLength(1));
      expect(notifier.state.single.id, id);
      expect(notifier.state.single.status, OperationStatus.success);
    },
  );

  test('start + finishSuccess transitions state and persists', () async {
    final db = newInMemoryDb();
    final notifier = OperationsNotifier(ActivityLogRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50)); // hydrate
    final id = notifier.start(OpKind.fetch, 'Fetching origin');
    expect(notifier.state, hasLength(1));
    expect(notifier.state.first.status, OperationStatus.running);
    notifier.finishSuccess(id);
    expect(notifier.state.first.status, OperationStatus.success);
    await Future<void>.delayed(const Duration(milliseconds: 50)); // upsert
    await db.close();
  });

  test('start prepends new operations (most-recent-first)', () async {
    final db = newInMemoryDb();
    final notifier = OperationsNotifier(ActivityLogRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final first = notifier.start(OpKind.fetch, 'first');
    final second = notifier.start(OpKind.push, 'second');
    expect(notifier.state, hasLength(2));
    expect(notifier.state.first.id, second);
    expect(notifier.state.last.id, first);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.close();
  });

  test('start returns unique ids', () async {
    final db = newInMemoryDb();
    final notifier = OperationsNotifier(ActivityLogRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final ids = {
      notifier.start(OpKind.fetch, 'a'),
      notifier.start(OpKind.fetch, 'b'),
      notifier.start(OpKind.fetch, 'c'),
    };
    expect(ids, hasLength(3));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.close();
  });

  test('updateProgress sets fraction and phase', () async {
    final db = newInMemoryDb();
    final notifier = OperationsNotifier(ActivityLogRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final id = notifier.start(OpKind.clone, 'Cloning');
    notifier.updateProgress(id, 0.42, 'Receiving objects');
    final op = notifier.state.firstWhere((o) => o.id == id);
    expect(op.progress, 0.42);
    expect(op.phase, 'Receiving objects');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.close();
  });

  test('appendStderr accumulates lines in order', () async {
    final db = newInMemoryDb();
    final notifier = OperationsNotifier(ActivityLogRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final id = notifier.start(OpKind.push, 'Pushing');
    notifier
      ..appendStderr(id, 'line 1')
      ..appendStderr(id, 'line 2');
    final op = notifier.state.firstWhere((o) => o.id == id);
    expect(op.stderrTail, ['line 1', 'line 2']);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.close();
  });

  test('appendStderr caps the tail at 50 lines, dropping the oldest', () async {
    final db = newInMemoryDb();
    final notifier = OperationsNotifier(ActivityLogRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final id = notifier.start(OpKind.push, 'Pushing');
    for (var i = 0; i < 60; i++) {
      notifier.appendStderr(id, 'line $i');
    }
    final op = notifier.state.firstWhere((o) => o.id == id);
    expect(op.stderrTail, hasLength(50));
    expect(op.stderrTail.first, 'line 10');
    expect(op.stderrTail.last, 'line 59');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.close();
  });

  test('finishFailure records status, finishedAt and error message', () async {
    final db = newInMemoryDb();
    final notifier = OperationsNotifier(ActivityLogRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final id = notifier.start(OpKind.pull, 'Pulling');
    notifier.finishFailure(id, 'network down');
    final op = notifier.state.firstWhere((o) => o.id == id);
    expect(op.status, OperationStatus.failed);
    expect(op.errorMessage, 'network down');
    expect(op.finishedAt, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.close();
  });

  test('cancel marks the operation cancelled', () async {
    final db = newInMemoryDb();
    final notifier = OperationsNotifier(ActivityLogRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final id = notifier.start(OpKind.fetch, 'Fetching');
    notifier.cancel(id);
    final op = notifier.state.firstWhere((o) => o.id == id);
    expect(op.status, OperationStatus.cancelled);
    expect(op.finishedAt, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.close();
  });

  test('cancel throws StateError for an unknown id', () async {
    final db = newInMemoryDb();
    final notifier = OperationsNotifier(ActivityLogRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(() => notifier.cancel('nope'), throwsStateError);
    await db.close();
  });

  test('clearCompleted keeps running/pending and drops the rest', () async {
    final db = newInMemoryDb();
    final notifier = OperationsNotifier(ActivityLogRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final running = notifier.start(OpKind.fetch, 'still running');
    final done = notifier.start(OpKind.push, 'finished');
    notifier.finishSuccess(done);
    await notifier.clearCompleted();
    expect(notifier.state, hasLength(1));
    expect(notifier.state.single.id, running);
    expect(notifier.state.single.status, OperationStatus.running);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.close();
  });

  test('hydration marks stale running rows as failed on reload', () async {
    final db = newInMemoryDb();
    final first = OperationsNotifier(ActivityLogRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // A running op left behind from a previous session.
    first.start(OpKind.clone, 'interrupted clone');
    await Future<void>.delayed(const Duration(milliseconds: 50)); // insert

    // A fresh notifier on the same DB should treat it as stale -> failed.
    final reloaded = OperationsNotifier(ActivityLogRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50)); // hydrate
    expect(reloaded.state, hasLength(1));
    final op = reloaded.state.single;
    expect(op.status, OperationStatus.failed);
    expect(op.errorMessage, 'Interrupted by app close');
    expect(op.finishedAt, isNotNull);
    await db.close();
  });

  test('hydration preserves already-terminal rows unchanged', () async {
    final db = newInMemoryDb();
    final first = OperationsNotifier(ActivityLogRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final id = first.start(OpKind.push, 'done push');
    await Future<void>.delayed(const Duration(milliseconds: 50)); // insert
    first.finishSuccess(id);
    await Future<void>.delayed(const Duration(milliseconds: 50)); // update

    final reloaded = OperationsNotifier(ActivityLogRepository(db));
    await Future<void>.delayed(const Duration(milliseconds: 50)); // hydrate
    expect(reloaded.state.single.status, OperationStatus.success);
    expect(reloaded.state.single.errorMessage, isNull);
    await db.close();
  });
}
