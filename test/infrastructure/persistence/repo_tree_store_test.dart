import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/persistence/repo_tree_store_impl.dart';
import 'package:gitopen/infrastructure/persistence/repository_registry_impl.dart';
import '../../_helpers/in_memory_db.dart';

void main() {
  group('DriftRepoTreeStore folder CRUD', () {
    test('createFolder persists and appends in parent order', () async {
      final db = newInMemoryDb();
      final sut = DriftRepoTreeStore(db);
      final a = await sut.createFolder(name: 'Work');
      final b = await sut.createFolder(name: 'Personal');
      final folders = await sut.loadFolders();
      expect(folders.map((f) => f.name), containsAll(['Work', 'Personal']));
      expect(a.sortOrder, 0);
      expect(b.sortOrder, 1);
      await db.close();
    });

    test('renameFolder and setCollapsed update the row', () async {
      final db = newInMemoryDb();
      final sut = DriftRepoTreeStore(db);
      final f = await sut.createFolder(name: 'Work');
      await sut.renameFolder(f.id, 'Job');
      await sut.setCollapsed(f.id, collapsed: true);
      final loaded = (await sut.loadFolders()).single;
      expect(loaded.name, 'Job');
      expect(loaded.collapsed, isTrue);
      await db.close();
    });

    test('removeFolder re-parents children to the grandparent', () async {
      final db = newInMemoryDb();
      final registry = DriftRepositoryRegistry(db);
      final sut = DriftRepoTreeStore(db);
      final outer = await sut.createFolder(name: 'Outer');
      final inner = await sut.createFolder(name: 'Inner', parentId: outer.id);
      // Put a repo inside inner.
      final loc = await registry.add('/tmp/r');
      await sut.moveRepo(loc.id, toParent: inner.id, atIndex: 0);
      await sut.removeFolder(inner.id);
      final folders = await sut.loadFolders();
      expect(folders.map((f) => f.id), [outer.id]);
      final placed = await sut.loadPlacedRepos();
      expect(placed.single.parentId, outer.id); // moved up to outer
      await db.close();
    });
  });
}
