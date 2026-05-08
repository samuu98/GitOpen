import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/persistence/workspace_persistence_impl.dart';
import '../../_helpers/in_memory_db.dart';

void main() {
  test('roundtrip open paths', () async {
    final db = newInMemoryDb();
    final sut = DriftWorkspacePersistence(db);
    await sut.saveOpenPaths(['/a', '/b']);
    final read = await sut.getOpenPaths();
    expect(read, ['/a', '/b']);
    await db.close();
  });
}
