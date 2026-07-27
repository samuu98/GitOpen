import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/ui/sidebar/branch_tree.dart';

Branch b(String name, {bool isCurrent = false, bool isRemote = false}) =>
    Branch(
      name: name,
      fullName: isRemote ? 'refs/remotes/$name' : 'refs/heads/$name',
      isRemote: isRemote,
      isCurrent: isCurrent,
      tipSha: CommitSha('aaaaaaaa'),
      ahead: 0,
      behind: 0,
    );

void main() {
  group('BranchTree.build', () {
    test('flat names produce flat roots', () {
      final tree = BranchTree.build([b('master'), b('main')]);
      expect(tree, hasLength(2));
      expect(tree.every((n) => n.isLeaf), isTrue);
    });

    test('slashed names produce nested folders', () {
      final tree = BranchTree.build([
        b('feature/auth'),
        b('feature/ui'),
        b('task/refactoring-opt'),
      ]);
      expect(tree, hasLength(2));
      final feature = tree.firstWhere((n) => n.name == 'feature');
      expect(feature.children, hasLength(2));
      expect(feature.isLeaf, isFalse);
      expect(feature.children.map((c) => c.name).toSet(), {'auth', 'ui'});
    });

    test('folders sort before leaves', () {
      final tree = BranchTree.build([
        b('master'),
        b('feature/auth'),
      ]);
      expect(tree.first.name, 'feature'); // folder first
      expect(tree.last.name, 'master');
    });
  });

  group('BranchTree.build stripPrefix', () {
    // Remote branches are named with their remote included ("origin/main"),
    // and the REMOTES section already renders a header per remote. Without
    // stripping, the tree adds a redundant "origin" folder underneath it, so
    // the sidebar read "REMOTES > origin > origin > main".
    test('drops the remote segment from remote branch nodes', () {
      final tree = BranchTree.build(
        [b('origin/main', isRemote: true), b('origin/develop', isRemote: true)],
        stripPrefix: 'origin',
      );
      expect(tree.map((n) => n.name).toSet(), {'main', 'develop'});
      expect(tree.every((n) => n.isLeaf), isTrue);
    });

    test('keeps folders below the stripped segment', () {
      final tree = BranchTree.build(
        [
          b('origin/feature/auth', isRemote: true),
          b('origin/feature/ui', isRemote: true),
          b('origin/main', isRemote: true),
        ],
        stripPrefix: 'origin',
      );
      expect(tree.map((n) => n.name).toList(), ['feature', 'main']);
      final feature = tree.first;
      expect(feature.children.map((c) => c.name).toSet(), {'auth', 'ui'});
    });

    test('fullPath stays fully qualified so remotes cannot collide', () {
      final tree = BranchTree.build(
        [b('upstream/feature/auth', isRemote: true)],
        stripPrefix: 'upstream',
      );
      expect(tree.single.fullPath, 'upstream/feature');
      expect(tree.single.children.single.fullPath, 'upstream/feature/auth');
    });

    test('a branch that does not carry the prefix is left alone', () {
      final tree = BranchTree.build([b('main')], stripPrefix: 'origin');
      expect(tree.single.name, 'main');
    });
  });
}
