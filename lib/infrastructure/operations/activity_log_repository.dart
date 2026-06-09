import 'package:drift/drift.dart';
import 'package:gitopen/application/operations/activity_log_store.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/infrastructure/persistence/database.dart';

class ActivityLogRepository implements ActivityLogStore {
  ActivityLogRepository(this._db);
  final AppDatabase _db;

  @override
  Future<void> upsert(RunningOperation op) async {
    final existing = await (_db.select(_db.activityLog)
          ..where((t) => t.opId.equals(op.id)))
        .getSingleOrNull();
    final companion = ActivityLogCompanion(
      opId: Value(op.id),
      kind: Value(op.kind.name),
      label: Value(op.label),
      repoId: Value(op.repo?.id.value),
      status: Value(op.status.name),
      startedAt: Value(op.startedAt),
      finishedAt: Value(op.finishedAt),
      stderr: Value(op.stderrTail.isEmpty ? null : op.stderrTail.join('\n')),
      errorMessage: Value(op.errorMessage),
    );
    if (existing == null) {
      await _db.into(_db.activityLog).insert(companion);
    } else {
      await (_db.update(_db.activityLog)
            ..where((t) => t.opId.equals(op.id)))
          .write(companion);
    }
  }

  @override
  Future<List<RunningOperation>> recent({int limit = 50}) async {
    final rows = await (_db.select(_db.activityLog)
          ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
          ..limit(limit))
        .get();
    return rows.map(_toOp).toList();
  }

  @override
  Future<void> clearCompleted() async {
    await (_db.delete(_db.activityLog)
          ..where((t) => t.status.isNotIn(['running', 'pending'])))
        .go();
  }

  RunningOperation _toOp(ActivityLogData row) {
    return RunningOperation(
      id: row.opId,
      kind: OpKind.values.byName(row.kind),
      label: row.label,
      status: OperationStatus.values.byName(row.status),
      startedAt: row.startedAt,
      finishedAt: row.finishedAt,
      stderrTail:
          (row.stderr ?? '').split('\n').where((s) => s.isNotEmpty).toList(),
      errorMessage: row.errorMessage,
    );
  }
}
