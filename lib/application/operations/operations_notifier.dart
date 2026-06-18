import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/legacy.dart';
import 'package:gitopen/application/operations/activity_log_store.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

class OperationsNotifier extends StateNotifier<List<RunningOperation>> {
  OperationsNotifier(this._log) : super(const []) {
    unawaited(_hydrate());
  }
  final ActivityLogStore _log;
  static const _stderrMax = 50;

  Future<void> _hydrate() async {
    final recent = await _log.recent();
    // Any "running" row from a previous session is stale — mark failed.
    final cleaned = recent.map((op) {
      if (op.status == OperationStatus.running ||
          op.status == OperationStatus.pending) {
        return op.copyWith(
          status: OperationStatus.failed,
          errorMessage: 'Interrupted by app close',
          finishedAt: DateTime.now(),
        );
      }
      return op;
    }).toList();
    state = cleaned;
  }

  String start(
    OpKind kind,
    String label, {
    RepoLocation? repo,
    void Function()? onCancel,
  }) {
    final id = _id();
    final op = RunningOperation(
      id: id,
      kind: kind,
      label: label,
      repo: repo,
      status: OperationStatus.running,
      startedAt: DateTime.now(),
      onCancel: onCancel,
    );
    state = [op, ...state];
    unawaited(_log.upsert(op));
    return id;
  }

  void updateProgress(String id, double? fraction, String phase) {
    _update(id, (op) => op.copyWith(progress: fraction, phase: phase));
  }

  void appendStderr(String id, String line) {
    _update(id, (op) {
      final next = [...op.stderrTail, line];
      if (next.length > _stderrMax) next.removeAt(0);
      return op.copyWith(stderrTail: next);
    });
  }

  void finishSuccess(String id) {
    _update(
      id,
      (op) => op.copyWith(
        status: OperationStatus.success,
        finishedAt: DateTime.now(),
      ),
    );
  }

  void finishFailure(String id, String message) {
    _update(
      id,
      (op) => op.copyWith(
        status: OperationStatus.failed,
        finishedAt: DateTime.now(),
        errorMessage: message,
      ),
    );
  }

  void cancel(String id) {
    final op = state.firstWhere(
      (o) => o.id == id,
      orElse: () => throw StateError('no op $id'),
    );
    op.onCancel?.call();
    _update(
      id,
      (o) => o.copyWith(
        status: OperationStatus.cancelled,
        finishedAt: DateTime.now(),
      ),
    );
  }

  Future<void> clearCompleted() async {
    state = state
        .where(
          (o) =>
              o.status == OperationStatus.running ||
              o.status == OperationStatus.pending,
        )
        .toList();
    await _log.clearCompleted();
  }

  void _update(String id, RunningOperation Function(RunningOperation) f) {
    state = state.map((o) => o.id == id ? f(o) : o).toList();
    final updated = state.firstWhere(
      (o) => o.id == id,
      orElse: () => throw StateError('no op $id'),
    );
    unawaited(_log.upsert(updated));
  }

  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}_'
      '${Random().nextInt(1 << 32).toRadixString(16)}';
}
