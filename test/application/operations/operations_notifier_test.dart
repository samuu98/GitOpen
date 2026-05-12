import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/infrastructure/operations/activity_log_repository.dart';
import '../../_helpers/in_memory_db.dart';

void main() {
  test('start + finishSuccess transitions state and persists', () async {
    final db = newInMemoryDb();
    final notifier = OperationsNotifier(ActivityLogRepository(db));
    await Future.delayed(const Duration(milliseconds: 50)); // let hydrate
    final id = notifier.start(OpKind.fetch, 'Fetching origin');
    expect(notifier.state, hasLength(1));
    expect(notifier.state.first.status, OperationStatus.running);
    notifier.finishSuccess(id);
    expect(notifier.state.first.status, OperationStatus.success);
    await Future.delayed(const Duration(milliseconds: 50)); // let upsert complete
    await db.close();
  });
}
