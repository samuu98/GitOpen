import 'package:gitopen/domain/repositories/repo_location.dart';

/// Probes the `.git` bookkeeping entries that signal an in-progress
/// operation (MERGE_HEAD, rebase-merge/, …). Implemented over the file
/// system in infrastructure; injected so repo-state detection is testable
/// without touching disk.
abstract interface class GitDirProbe {
  /// True when `.git/<name>` exists as a file.
  bool fileExists(RepoLocation repo, String name);

  /// True when `.git/<name>` exists as a directory.
  bool dirExists(RepoLocation repo, String name);
}
