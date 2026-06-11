/// A node in a folder tree folded from flat git paths ('/'-separated).
/// Directories carry [children]; file leaves carry the [item] they were
/// built from. Single-child directory chains are compressed into one node
/// whose [name] joins the segments ('src/app'), GitHub-style.
final class PathTreeNode<T> {
  const PathTreeNode({
    required this.name,
    required this.path,
    this.item,
    this.children = const [],
  });

  /// Display name. Compressed chains contain '/' ('src/app').
  final String name;

  /// Full path from the root ('src/app' or 'src/app/main.dart').
  final String path;

  /// The source item for file leaves; null for directories.
  final T? item;
  final List<PathTreeNode<T>> children;

  bool get isDirectory => item == null;
}

/// Folds flat paths into a directory forest: directories first, then files,
/// both sorted case-insensitively by name. Paths are assumed unique.
List<PathTreeNode<T>> buildFileTree<T>(
  Iterable<T> items,
  String Function(T) pathOf,
) {
  final root = _Dir<T>();
  for (final item in items) {
    final segments = pathOf(item).split('/');
    var dir = root;
    for (var i = 0; i < segments.length - 1; i++) {
      dir = dir.dirs.putIfAbsent(segments[i], _Dir<T>.new);
    }
    dir.files.add((name: segments.last, item: item));
  }
  return _emit(root, '');
}

final class _Dir<T> {
  final Map<String, _Dir<T>> dirs = {};
  final List<({String name, T item})> files = [];
}

List<PathTreeNode<T>> _emit<T>(_Dir<T> dir, String prefix) {
  final out = <PathTreeNode<T>>[];
  for (final entry in dir.dirs.entries) {
    var name = entry.key;
    var node = entry.value;
    var path = prefix.isEmpty ? name : '$prefix/$name';
    // Compress while the directory holds exactly one subdirectory and no
    // files — the chain reads as a single breadcrumb ('src/app').
    while (node.files.isEmpty && node.dirs.length == 1) {
      final only = node.dirs.entries.first;
      name = '$name/${only.key}';
      path = '$path/${only.key}';
      node = only.value;
    }
    out.add(PathTreeNode(name: name, path: path, children: _emit(node, path)));
  }
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final files = [
    for (final f in dir.files)
      PathTreeNode<T>(
        name: f.name,
        path: prefix.isEmpty ? f.name : '$prefix/${f.name}',
        item: f.item,
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return [...out, ...files];
}
