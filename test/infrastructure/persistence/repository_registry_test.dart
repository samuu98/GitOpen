import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/persistence/repository_registry_impl.dart';
import '../../_helpers/in_memory_db.dart';

void main() {
  group('DriftRepositoryRegistry', () {
    test('add persists and returns location', () async {
      final db = newInMemoryDb();
      final sut = DriftRepositoryRegistry(db);
      final loc = await sut.add('/tmp/foo');
      expect(loc.path, '/tmp/foo');
      final all = await sut.list();
      expect(all, hasLength(1));
      await db.close();
    });

    test('add returns existing when path already known', () async {
      final db = newInMemoryDb();
      final sut = DriftRepositoryRegistry(db);
      final first = await sut.add('/tmp/dup');
      final second = await sut.add('/tmp/dup');
      expect(second.id, first.id);
      expect((await sut.list()), hasLength(1));
      await db.close();
    });

    test('remove deletes the repo', () async {
      final db = newInMemoryDb();
      final sut = DriftRepositoryRegistry(db);
      final loc = await sut.add('/tmp/gone');
      await sut.remove(loc.id);
      expect(await sut.list(), isEmpty);
      await db.close();
    });

    test('touchLastOpened updates timestamp', () async {
      final db = newInMemoryDb();
      final sut = DriftRepositoryRegistry(db);
      final loc = await sut.add('/tmp/x');
      await Future.delayed(const Duration(milliseconds: 100));
      await sut.touchLastOpened(loc.id);
      final raw = await (db.select(db.repositories)..where((r) => r.id.equals(loc.id.value))).getSingle();
      expect(raw.lastOpenedUtc.isAfter(raw.createdUtc), isTrue);
      await db.close();
    });
  });
}
