import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/workspaces/build_repo_tree.dart';
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/infrastructure/persistence/repo_tree_store_impl.dart';
import 'package:gitopen/infrastructure/persistence/repository_registry_impl.dart';
import '../../_helpers/in_memory_db.dart';

void main() {
  group('DriftRepoTreeStore move/reorder', () {
    test('moveRepo into a folder at index resequences siblings densely',
        () async {
      final db = newInMemoryDb();
      final registry = DriftRepositoryRegistry(db);
      final store = DriftRepoTreeStore(db);
      final work = await store.createFolder(name: 'Work');
      final a = await registry.add('/tmp/a');
      final b = await registry.add('/tmp/b');
      await store.moveRepo(a.id, toParent: work.id, atIndex: 0);
      await store.moveRepo(b.id, toParent: work.id, atIndex: 0); // b before a
      final tree = buildRepoTree(
        await store.loadFolders(),
        await store.loadPlacedRepos(),
      );
      final children = (tree.single as FolderNode).children;
      expect(
        children.map((n) => (n as RepoNode).location.path),
        ['/tmp/b', '/tmp/a'],
      );
      expect(children.map((n) => n.sortOrder), [0, 1]); // dense
      await db.close();
    });

    test('moveFolder onto its own descendant is a no-op', () async {
      final db = newInMemoryDb();
      final store = DriftRepoTreeStore(db);
      final outer = await store.createFolder(name: 'Outer');
      final inner = await store.createFolder(name: 'Inner', parentId: outer.id);
      await store.moveFolder(outer.id, toParent: inner.id, atIndex: 0);
      final folders = await store.loadFolders();
      final outerRow = folders.firstWhere((f) => f.id == outer.id);
      expect(outerRow.parentId, isNull); // unchanged
      await db.close();
    });

    test('moveFolder reparents and resequences destination', () async {
      final db = newInMemoryDb();
      final store = DriftRepoTreeStore(db);
      final a = await store.createFolder(name: 'A');
      final b = await store.createFolder(name: 'B');
      await store.moveFolder(b.id, toParent: a.id, atIndex: 0);
      final folders = await store.loadFolders();
      expect(folders.firstWhere((f) => f.id == b.id).parentId, a.id);
      await db.close();
    });
  });
}
