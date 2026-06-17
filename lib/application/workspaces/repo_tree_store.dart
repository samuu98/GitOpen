import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';

/// Persistence port for the repo organization tree (folders + repo placement).
/// All ordering lives in a shared integer space per parent: a folder's
/// children (subfolders + repos) interleave by [Folder.sortOrder] /
/// repo `tabOrder`.
abstract interface class RepoTreeStore {
  Future<List<Folder>> loadFolders();
  Future<List<PlacedRepo>> loadPlacedRepos();

  /// Creates a folder appended last in its parent's shared order.
  Future<Folder> createFolder({required String name, FolderId? parentId});
  Future<void> renameFolder(FolderId id, String name);
  Future<void> setCollapsed(FolderId id, {required bool collapsed});

  /// Deletes the folder, re-parenting its children (folders + repos) to the
  /// folder's own parent, appended after existing siblings. Non-destructive
  /// to repos.
  Future<void> removeFolder(FolderId id);

  /// Moves [id] under [toParent] (null = root) at [atIndex] within the
  /// destination's shared child order; resequences siblings to a dense
  /// `0..n-1`.
  Future<void> moveRepo(RepoId id, {required int atIndex, FolderId? toParent});

  /// Like [moveRepo] for a folder. No-op if [toParent] is [id] itself or any
  /// descendant of [id] (would create a cycle).
  Future<void> moveFolder(
    FolderId id, {
    required int atIndex,
    FolderId? toParent,
  });
}
