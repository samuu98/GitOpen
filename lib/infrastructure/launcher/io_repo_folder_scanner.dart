import 'dart:io';

import 'package:gitopen/application/launcher/repo_folder_scanner.dart';
import 'package:path/path.dart' as p;

/// Filesystem-backed [RepoFolderScanner]. Walks the chosen folder recursively
/// and reports every directory that is a git repository — one with a `.git`
/// entry (a directory for clones, a file for worktrees/submodules).
///
/// Recursion rules keep the walk cheap and the results meaningful:
///  - it does NOT descend into a directory once it is identified as a repo, so
///    submodules / nested working trees are not reported as separate repos;
///  - it skips hidden directories (names starting with `.`) and `node_modules`,
///    which never hold repos the user means to open and can be huge.
///
/// Recursion is why selecting a parent that only contains *grouping* folders
/// (e.g. `repos/Personal/<repo>`, `repos/Novomatic/<repo>`) still finds the
/// repos — the previous depth-1 scan returned nothing in that layout.
final class IoRepoFolderScanner implements RepoFolderScanner {
  const IoRepoFolderScanner();

  @override
  Future<List<String>> findRepositories(String parentPath) async {
    final parent = Directory(parentPath);
    if (!parent.existsSync()) return const [];
    final repos = <String>[];
    await _scan(parent, repos);
    repos.sort();
    return repos;
  }

  Future<void> _scan(Directory dir, List<String> out) async {
    final List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      return; // unreadable (permissions, race) — skip this branch
    }
    for (final entity in entries) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.') || name == 'node_modules') continue;
      final gitPath = p.join(entity.path, '.git');
      if (Directory(gitPath).existsSync() || File(gitPath).existsSync()) {
        out.add(entity.path);
        continue; // a repo: don't descend into it (skip submodules etc.)
      }
      await _scan(entity, out); // a plain folder: look deeper
    }
  }
}
