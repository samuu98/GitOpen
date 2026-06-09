import 'package:gitopen/application/operations/running_operation.dart';

/// Persistence port for the activity log (implemented over the app database
/// in infrastructure), so the operations notifier stays storage-agnostic.
abstract interface class ActivityLogStore {
  /// Inserts or updates the row for [op] (keyed by its id).
  Future<void> upsert(RunningOperation op);

  /// The most recent operations, newest first.
  Future<List<RunningOperation>> recent({int limit = 50});

  /// Deletes every finished (non-running, non-pending) row.
  Future<void> clearCompleted();
}
