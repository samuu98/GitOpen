import 'package:gitopen/application/operations/activity_log_store.dart';
import 'package:gitopen/application/operations/running_operation.dart';

/// In-memory activity log so a widget test that touches `operationsProvider`
/// does not pull in the real drift database.
class InMemoryActivityLog implements ActivityLogStore {
  final List<RunningOperation> saved = [];

  @override
  Future<void> upsert(RunningOperation op) async => saved.add(op);

  @override
  Future<List<RunningOperation>> recent({int limit = 50}) async => const [];

  @override
  Future<void> clearCompleted() async {}
}
