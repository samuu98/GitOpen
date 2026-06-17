import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';

/// Pure: builds the root-level node list from folders + placed repos.
/// Defensive against corrupt data — orphan folders (missing parent) and
/// folders caught in a parent cycle are treated as root-level.
List<RepoTreeNode> buildRepoTree(
  List<Folder> folders,
  List<PlacedRepo> repos,
) {
  final byId = {for (final f in folders) f.id: f};

  // A folder's effective parent is null if the chain is broken or loops.
  FolderId? effectiveParent(Folder f) {
    if (f.parentId == null) return null;
    final seen = <FolderId>{f.id};
    var cursor = f.parentId;
    while (cursor != null) {
      if (seen.contains(cursor)) return null; // cycle -> re-root
      final parent = byId[cursor];
      if (parent == null) return null; // missing ancestor -> re-root
      seen.add(cursor);
      cursor = parent.parentId;
    }
    return f.parentId; // chain reaches a root cleanly
  }

  final childFolders = <FolderId?, List<Folder>>{};
  for (final f in folders) {
    childFolders.putIfAbsent(effectiveParent(f), () => []).add(f);
  }
  final childRepos = <FolderId?, List<PlacedRepo>>{};
  for (final r in repos) {
    final parentExists = r.parentId != null && byId.containsKey(r.parentId);
    childRepos.putIfAbsent(parentExists ? r.parentId : null, () => []).add(r);
  }

  List<RepoTreeNode> nodesUnder(FolderId? parent) {
    final nodes = <RepoTreeNode>[
      for (final f in childFolders[parent] ?? const <Folder>[])
        FolderNode(f, nodesUnder(f.id)),
      for (final r in childRepos[parent] ?? const <PlacedRepo>[])
        RepoNode(r.location, r.sortOrder),
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return nodes;
  }

  return nodesUnder(null);
}
