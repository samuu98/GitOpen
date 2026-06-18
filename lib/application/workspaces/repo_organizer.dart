import 'package:flutter_riverpod/legacy.dart';
import 'package:gitopen/application/workspaces/build_repo_tree.dart';
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/application/workspaces/repo_tree_store.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';

/// The single source the repo dropdown watches. Wraps [RepoTreeStore]; every
/// mutation persists then rebuilds the tree. On a store error the tree is
/// still reloaded (truth wins) and the error rethrows so the UI can surface it.
final class RepoOrganizer extends StateNotifier<List<RepoTreeNode>> {
  RepoOrganizer(this._store) : super(const []);
  final RepoTreeStore _store;

  Future<void> refresh() async {
    final folders = await _store.loadFolders();
    final repos = await _store.loadPlacedRepos();
    state = buildRepoTree(folders, repos);
  }

  Future<FolderId> createFolder(String name, {FolderId? parentId}) async {
    final folder = await _store.createFolder(name: name, parentId: parentId);
    await refresh();
    return folder.id;
  }

  Future<void> renameFolder(FolderId id, String name) =>
      _mutate(() => _store.renameFolder(id, name));

  Future<void> removeFolder(FolderId id) =>
      _mutate(() => _store.removeFolder(id));

  Future<void> setCollapsed(FolderId id, {required bool collapsed}) =>
      _mutate(() => _store.setCollapsed(id, collapsed: collapsed));

  Future<void> moveRepo(
    RepoId id, {
    required int atIndex,
    FolderId? toParent,
  }) =>
      _mutate(() => _store.moveRepo(id, atIndex: atIndex, toParent: toParent));

  Future<void> moveFolder(
    FolderId id, {
    required int atIndex,
    FolderId? toParent,
  }) =>
      _mutate(
        () => _store.moveFolder(id, atIndex: atIndex, toParent: toParent),
      );

  Future<void> _mutate(Future<void> Function() op) async {
    try {
      await op();
    } finally {
      await refresh(); // reload truth even if the op threw
    }
  }
}
