import 'package:gitopen/domain/refs/branch.dart';

final class BranchTreeNode {

  BranchTreeNode({required this.name, required this.fullPath, this.branch})
      : children = [];
  final String name;
  final String fullPath;
  final Branch? branch;
  final List<BranchTreeNode> children;

  bool get isLeaf => branch != null && children.isEmpty;
}

class BranchTree {
  /// Builds the folder forest for [branches], splitting each name on `/`.
  ///
  /// [stripPrefix] drops a leading `<prefix>/` segment from the *displayed*
  /// hierarchy while leaving [BranchTreeNode.fullPath] fully qualified. The
  /// REMOTES section needs this: remote branches are named `origin/main`, and
  /// the section already renders a header per remote, so without stripping the
  /// sidebar read "REMOTES > origin > origin > main". Keeping `fullPath`
  /// qualified means two remotes with same-named folders still get distinct
  /// collapse keys.
  static List<BranchTreeNode> build(
    Iterable<Branch> branches, {
    String stripPrefix = '',
  }) {
    final roots = <BranchTreeNode>[];
    final lookup = <String, BranchTreeNode>{};
    final prefix = stripPrefix.isEmpty ? '' : '$stripPrefix/';

    for (final b in branches) {
      final stripped = prefix.isNotEmpty && b.name.startsWith(prefix);
      // What the user sees: the name minus the stripped remote segment.
      final display = stripped ? b.name.substring(prefix.length) : b.name;
      if (display.isEmpty) continue;
      final parts = display.split('/');
      BranchTreeNode? parent;
      // …while the collapse key keeps the segment, so two remotes with a
      // same-named folder don't share one expand/collapse state.
      var currentPath = stripped ? stripPrefix : '';
      for (var i = 0; i < parts.length; i++) {
        currentPath =
            currentPath.isEmpty ? parts[0] : '$currentPath/${parts[i]}';
        final isLast = i == parts.length - 1;
        var node = lookup[currentPath];
        if (node == null) {
          node = BranchTreeNode(
            name: parts[i],
            fullPath: currentPath,
            branch: isLast ? b : null,
          );
          lookup[currentPath] = node;
          if (parent == null) {
            roots.add(node);
          } else {
            parent.children.add(node);
          }
        }
        parent = node;
      }
    }
    _sortRecursive(roots);
    return roots;
  }

  static void _sortRecursive(List<BranchTreeNode> nodes) {
    nodes.sort((a, b) {
      final aFolder = a.children.isNotEmpty;
      final bFolder = b.children.isNotEmpty;
      if (aFolder != bFolder) return aFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    for (final n in nodes) {
      _sortRecursive(n.children);
    }
  }

  static Iterable<String> allFolderPaths(Iterable<BranchTreeNode> nodes) sync* {
    for (final n in nodes) {
      if (n.children.isNotEmpty) {
        yield n.fullPath;
        yield* allFolderPaths(n.children);
      }
    }
  }
}
