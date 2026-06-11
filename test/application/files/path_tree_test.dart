import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/files/path_tree.dart';

List<String> names(List<PathTreeNode<String>> nodes) =>
    [for (final n in nodes) n.name];

void main() {
  group('buildFileTree', () {
    test('empty input yields an empty forest', () {
      expect(buildFileTree(<String>[], (p) => p), isEmpty);
    });

    test('flat files only: sorted case-insensitively, items attached', () {
      final nodes = buildFileTree(['b.txt', 'A.txt'], (p) => p);
      expect(names(nodes), ['A.txt', 'b.txt']);
      expect(nodes[0].item, 'A.txt');
      expect(nodes[0].isDirectory, isFalse);
      expect(nodes[0].path, 'A.txt');
    });

    test('folds directories, dirs sort before files', () {
      final nodes = buildFileTree(
        ['b.txt', 'a/y.txt', 'a/x.txt'],
        (p) => p,
      );
      expect(names(nodes), ['a', 'b.txt']);
      expect(nodes[0].isDirectory, isTrue);
      expect(nodes[0].path, 'a');
      expect(names(nodes[0].children), ['x.txt', 'y.txt']);
      expect(nodes[0].children[0].path, 'a/x.txt');
    });

    test('compresses single-child directory chains', () {
      final nodes = buildFileTree(
        ['src/app/main.dart', 'src/app/util.dart'],
        (p) => p,
      );
      expect(names(nodes), ['src/app']);
      expect(nodes[0].path, 'src/app');
      expect(names(nodes[0].children), ['main.dart', 'util.dart']);
    });

    test('does not compress a dir that also holds a file', () {
      final nodes = buildFileTree(
        ['a/b/x.txt', 'a/y.txt'],
        (p) => p,
      );
      expect(names(nodes), ['a']);
      expect(names(nodes[0].children), ['b', 'y.txt']);
      expect(nodes[0].children[0].path, 'a/b');
    });

    test('carries an arbitrary payload type', () {
      final nodes = buildFileTree(
        [(path: 'dir/f.txt', tag: 7)],
        (r) => r.path,
      );
      expect(nodes[0].children[0].item!.tag, 7);
    });
  });
}
