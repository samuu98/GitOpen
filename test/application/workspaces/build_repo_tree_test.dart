import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/workspaces/build_repo_tree.dart';
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

Folder _folder(String id, String name, {String? parent, int order = 0}) =>
    Folder(
      id: FolderId(id),
      name: name,
      parentId: parent == null ? null : FolderId(parent),
      sortOrder: order,
      collapsed: false,
    );

PlacedRepo _repo(String id, {String? parent, int order = 0}) => PlacedRepo(
      location: RepoLocation(RepoId(id), '/p/$id', id),
      parentId: parent == null ? null : FolderId(parent),
      sortOrder: order,
    );

void main() {
  group('buildRepoTree', () {
    test('nests repos under their folders', () {
      final tree = buildRepoTree(
        [_folder('w', 'Work')],
        [_repo('a', parent: 'w')],
      );
      expect(tree, hasLength(1));
      final work = tree.single as FolderNode;
      expect(work.folder.name, 'Work');
      expect(work.children.single, isA<RepoNode>());
    });

    test('interleaves folders and repos by shared sortOrder', () {
      final tree = buildRepoTree(
        [_folder('w', 'Work', order: 1)],
        [_repo('a'), _repo('b', order: 2)],
      );
      expect(tree.map((n) => n.sortOrder), [0, 1, 2]);
      expect(tree[0], isA<RepoNode>());
      expect(tree[1], isA<FolderNode>());
      expect(tree[2], isA<RepoNode>());
    });

    test('re-roots a folder whose parent is missing', () {
      final tree = buildRepoTree(
        [_folder('child', 'Child', parent: 'ghost')],
        const [],
      );
      expect(tree, hasLength(1));
      expect((tree.single as FolderNode).folder.id, const FolderId('child'));
    });

    test('breaks a parent cycle by re-rooting', () {
      // a -> b -> a (cycle)
      final tree = buildRepoTree(
        [
          _folder('a', 'A', parent: 'b'),
          _folder('b', 'B', parent: 'a'),
        ],
        const [],
      );
      // No infinite loop; both folders surface (re-rooted) without duplication.
      final ids = <FolderId>[];
      void walk(List<RepoTreeNode> nodes) {
        for (final n in nodes) {
          if (n is FolderNode) {
            ids.add(n.folder.id);
            walk(n.children);
          }
        }
      }

      walk(tree);
      expect(ids.toSet(), {const FolderId('a'), const FolderId('b')});
    });
  });
}
