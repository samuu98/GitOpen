import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

/// A repo plus where it sits in the tree (its parent folder + order within
/// that parent's shared sort space). Input to `buildRepoTree`.
class PlacedRepo {
  const PlacedRepo({
    required this.location,
    required this.parentId,
    required this.sortOrder,
  });
  final RepoLocation location;
  final FolderId? parentId;
  final int sortOrder;
}

sealed class RepoTreeNode {
  int get sortOrder;
}

final class FolderNode extends RepoTreeNode {
  FolderNode(this.folder, this.children);
  final Folder folder;
  final List<RepoTreeNode> children;
  @override
  int get sortOrder => folder.sortOrder;
}

final class RepoNode extends RepoTreeNode {
  RepoNode(this.location, this.sortOrder);
  final RepoLocation location;
  @override
  final int sortOrder;
}
