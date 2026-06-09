import 'dart:io';

import 'package:gitopen/application/git/git_dir_probe.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:path/path.dart' as p;

/// [GitDirProbe] over `dart:io`.
class IoGitDirProbe implements GitDirProbe {
  const IoGitDirProbe();

  @override
  bool fileExists(RepoLocation repo, String name) =>
      File(p.join(repo.path, '.git', name)).existsSync();

  @override
  bool dirExists(RepoLocation repo, String name) =>
      Directory(p.join(repo.path, '.git', name)).existsSync();
}
