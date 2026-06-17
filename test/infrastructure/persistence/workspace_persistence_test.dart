import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/persistence/workspace_persistence_impl.dart';
import '../../_helpers/in_memory_db.dart';

void main() {
  group('DriftWorkspacePersistence', () {
    test('round-trips the last active repo id', () async {
      final db = newInMemoryDb();
      final sut = DriftWorkspacePersistence(db);
      expect(await sut.getLastActiveRepoId(), isNull);
      await sut.saveLastActiveRepoId('abc123');
      expect(await sut.getLastActiveRepoId(), 'abc123');
      await sut.saveLastActiveRepoId(null);
      expect(await sut.getLastActiveRepoId(), isNull);
      await db.close();
    });
  });
}
