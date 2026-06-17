import 'package:drift/drift.dart';
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/application/workspaces/repo_tree_store.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/persistence/database.dart';

final class DriftRepoTreeStore implements RepoTreeStore {
  DriftRepoTreeStore(this._db);
  final AppDatabase _db;

  @override
  Future<List<Folder>> loadFolders() async {
    final rows = await _db.select(_db.folders).get();
    return rows.map(_toFolder).toList();
  }

  @override
  Future<List<PlacedRepo>> loadPlacedRepos() async {
    final rows = await _db.select(_db.repositories).get();
    return rows
        .map((r) => PlacedRepo(
              location: RepoLocation(RepoId(r.id), r.path, r.displayName),
              parentId:
                  r.parentFolderId == null ? null : FolderId(r.parentFolderId!),
              sortOrder: r.tabOrder,
            ))
        .toList();
  }

  @override
  Future<Folder> createFolder({
    required String name,
    FolderId? parentId,
  }) async {
    final id = FolderId.newId();
    final order = await _nextOrderUnder(parentId);
    final now = DateTime.now().toUtc();
    await _db.into(_db.folders).insert(FoldersCompanion.insert(
          id: id.value,
          name: name,
          parentId: Value(parentId?.value),
          sortOrder: order,
          createdUtc: now,
        ));
    return Folder(
      id: id,
      name: name,
      parentId: parentId,
      sortOrder: order,
      collapsed: false,
    );
  }

  @override
  Future<void> renameFolder(FolderId id, String name) async {
    await (_db.update(_db.folders)..where((f) => f.id.equals(id.value)))
        .write(FoldersCompanion(name: Value(name)));
  }

  @override
  Future<void> setCollapsed(FolderId id, {required bool collapsed}) async {
    await (_db.update(_db.folders)..where((f) => f.id.equals(id.value)))
        .write(FoldersCompanion(collapsed: Value(collapsed)));
  }

  @override
  Future<void> removeFolder(FolderId id) async {
    await _db.transaction(() async {
      final row = await (_db.select(_db.folders)
            ..where((f) => f.id.equals(id.value)))
          .getSingleOrNull();
      if (row == null) return;
      final grandparent = row.parentId; // String?
      var next = await _nextOrderUnder(
        grandparent == null ? null : FolderId(grandparent),
      );
      // Re-parent child folders.
      final childFolders = await (_db.select(_db.folders)
            ..where((f) => f.parentId.equals(id.value)))
          .get();
      for (final c in childFolders) {
        await (_db.update(_db.folders)..where((f) => f.id.equals(c.id))).write(
          FoldersCompanion(
            parentId: Value(grandparent),
            sortOrder: Value(next++),
          ),
        );
      }
      // Re-parent child repos.
      final childRepos = await (_db.select(_db.repositories)
            ..where((r) => r.parentFolderId.equals(id.value)))
          .get();
      for (final c in childRepos) {
        await (_db.update(_db.repositories)..where((r) => r.id.equals(c.id)))
            .write(RepositoriesCompanion(
          parentFolderId: Value(grandparent),
          tabOrder: Value(next++),
        ));
      }
      await (_db.delete(_db.folders)..where((f) => f.id.equals(id.value))).go();
    });
  }

  @override
  Future<void> moveRepo(
    RepoId id, {
    required int atIndex,
    FolderId? toParent,
  }) async {
    await _db.transaction(() async {
      await (_db.update(_db.repositories)..where((r) => r.id.equals(id.value)))
          .write(RepositoriesCompanion(parentFolderId: Value(toParent?.value)));
      await _resequence(toParent, moved: _MovedRef.repo(id), atIndex: atIndex);
    });
  }

  @override
  Future<void> moveFolder(
    FolderId id, {
    required int atIndex,
    FolderId? toParent,
  }) async {
    if (await _wouldCycle(id, toParent)) return;
    await _db.transaction(() async {
      await (_db.update(_db.folders)..where((f) => f.id.equals(id.value)))
          .write(FoldersCompanion(parentId: Value(toParent?.value)));
      await _resequence(
        toParent,
        moved: _MovedRef.folder(id),
        atIndex: atIndex,
      );
    });
  }

  /// True if [toParent] is [id] itself or any descendant of [id].
  Future<bool> _wouldCycle(FolderId id, FolderId? toParent) async {
    if (toParent == null) return false;
    if (toParent == id) return true;
    final all = await loadFolders();
    final byId = {for (final f in all) f.id: f};
    var cursor = toParent;
    final seen = <FolderId>{};
    while (true) {
      if (cursor == id) return true;
      if (!seen.add(cursor)) return false; // pre-existing loop, bail safely
      final parent = byId[cursor]?.parentId;
      if (parent == null) return false;
      cursor = parent;
    }
  }

  /// Rewrites the dense `0..n-1` order of [parent]'s children, placing [moved]
  /// at [atIndex] (clamped). Children are ordered by current sortOrder, with
  /// the moved node extracted first. Assumes [moved]'s parent column was
  /// already updated to [parent].
  Future<void> _resequence(
    FolderId? parent, {
    required _MovedRef moved,
    required int atIndex,
  }) async {
    final folders = await (_db.select(_db.folders)
          ..where((f) => parent == null
              ? f.parentId.isNull()
              : f.parentId.equals(parent.value)))
        .get();
    final repos = await (_db.select(_db.repositories)
          ..where((r) => parent == null
              ? r.parentFolderId.isNull()
              : r.parentFolderId.equals(parent.value)))
        .get();

    final siblings = <_MovedRef>[
      for (final f in folders)
        _MovedRef.folder(FolderId(f.id)).withOrder(f.sortOrder),
      for (final r in repos) _MovedRef.repo(RepoId(r.id)).withOrder(r.tabOrder),
    ]
      ..sort((a, b) => a.order.compareTo(b.order))
      ..removeWhere((s) => s.sameTarget(moved));
    final index = atIndex.clamp(0, siblings.length);
    siblings.insert(index, moved);

    for (var i = 0; i < siblings.length; i++) {
      final s = siblings[i];
      if (s.isFolder) {
        await (_db.update(_db.folders)
              ..where((f) => f.id.equals(s.folderId!.value)))
            .write(FoldersCompanion(sortOrder: Value(i)));
      } else {
        await (_db.update(_db.repositories)
              ..where((r) => r.id.equals(s.repoId!.value)))
            .write(RepositoriesCompanion(tabOrder: Value(i)));
      }
    }
  }

  Future<int> _nextOrderUnder(FolderId? parent) async {
    final folders = await (_db.select(_db.folders)
          ..where((f) => parent == null
              ? f.parentId.isNull()
              : f.parentId.equals(parent.value)))
        .get();
    final repos = await (_db.select(_db.repositories)
          ..where((r) => parent == null
              ? r.parentFolderId.isNull()
              : r.parentFolderId.equals(parent.value)))
        .get();
    final orders = <int>[
      ...folders.map((f) => f.sortOrder),
      ...repos.map((r) => r.tabOrder),
    ];
    return orders.isEmpty ? 0 : (orders.reduce((a, b) => a > b ? a : b) + 1);
  }

  Folder _toFolder(FolderRow r) => Folder(
        id: FolderId(r.id),
        name: r.name,
        parentId: r.parentId == null ? null : FolderId(r.parentId!),
        sortOrder: r.sortOrder,
        collapsed: r.collapsed,
      );
}

class _MovedRef {
  _MovedRef.folder(this.folderId)
      : repoId = null,
        order = 0;
  _MovedRef.repo(this.repoId)
      : folderId = null,
        order = 0;
  final FolderId? folderId;
  final RepoId? repoId;
  int order;

  bool get isFolder => folderId != null;
  _MovedRef withOrder(int o) => this..order = o;
  bool sameTarget(_MovedRef other) =>
      isFolder ? folderId == other.folderId : repoId == other.repoId;
}
