import 'dart:io';

import 'package:gitopen/application/launcher/repo_folder_scanner.dart';
import 'package:path/path.dart' as p;

/// Filesystem-backed [RepoFolderScanner]: an immediate subdirectory is a repo
/// when it contains a `.git` entry (a directory for clones, a file for
/// worktrees/submodules).
final class IoRepoFolderScanner implements RepoFolderScanner {
  const IoRepoFolderScanner();

  @override
  Future<List<String>> findRepositories(String parentPath) async {
    final parent = Directory(parentPath);
    if (!parent.existsSync()) return const [];
    final repos = <String>[];
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final gitPath = p.join(entity.path, '.git');
      if (Directory(gitPath).existsSync() || File(gitPath).existsSync()) {
        repos.add(entity.path);
      }
    }
    repos.sort();
    return repos;
  }
}
