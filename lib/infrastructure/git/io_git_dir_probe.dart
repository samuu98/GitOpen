import 'dart:io';

import 'package:gitopen/application/git/git_dir_probe.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:path/path.dart' as p;

/// [GitDirProbe] over `dart:io`.
class IoGitDirProbe implements GitDirProbe {
  const IoGitDirProbe();

  @override
  bool fileExists(RepoLocation repo, String name) {
    final gitDir = _gitDir(repo);
    return gitDir != null && File(p.join(gitDir, name)).existsSync();
  }

  @override
  bool dirExists(RepoLocation repo, String name) {
    final gitDir = _gitDir(repo);
    return gitDir != null && Directory(p.join(gitDir, name)).existsSync();
  }

  String? _gitDir(RepoLocation repo) {
    final dotGit = p.join(repo.path, '.git');
    if (Directory(dotGit).existsSync()) return dotGit;
    final pointer = File(dotGit);
    if (!pointer.existsSync()) return null;
    final String content;
    try {
      content = pointer.readAsStringSync();
    } on FileSystemException {
      return null;
    }
    if (!content.startsWith('gitdir:')) return null;
    final path = content.substring('gitdir:'.length).trim();
    if (path.isEmpty) return null;
    return p.normalize(p.isAbsolute(path) ? path : p.join(repo.path, path));
  }
}
