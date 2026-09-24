import 'dart:io';

import 'package:gitopen/application/git/branch_deletion_flow.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:path/path.dart' as p;

/// Git's porcelain worktree list is authoritative for checkout ownership.
class GitCliBranchDeletionInspector implements BranchDeletionInspector {
  GitCliBranchDeletionInspector({
    GitCliReadOperations? read,
    GitProcessRunner? runner,
  }) : _read = read ?? GitCliReadOperations(),
       _runner = runner ?? GitProcessRunner();

  final GitCliReadOperations _read;
  final GitProcessRunner _runner;

  @override
  Future<BranchDeleteStatus> inspect(
    RepoLocation repo,
    String branch,
  ) async {
    final branches = await _read.getLocalBranches(repo);
    if (!branches.any((b) => b.name == branch)) {
      return const BranchDeleteStatus(exists: false, merged: false);
    }
    final worktrees = await _read.getWorktrees(repo);
    final match = worktrees.where((w) => w.branch == branch).firstOrNull;
    final mergedOutput = await _runner.run(
      repo.path,
      ['branch', '--merged', 'HEAD', '--format=%(refname:short)'],
    );
    final merged = mergedOutput
        .split('\n')
        .map((s) => s.trim())
        .contains(branch);
    final path = match?.path;
    return BranchDeleteStatus(
      exists: true,
      merged: merged,
      worktreePath: path,
      isMainWorktree:
          match != null && _isProtected(repo, match.path, worktrees),
      worktreeDirty: path != null && await _dirty(path),
      worktreeLocked: path != null && await _locked(repo, path),
    );
  }

  @override
  Future<WorktreeDeleteStatus?> inspectWorktree(
    RepoLocation repo,
    String path,
  ) async {
    final worktrees = await _read.getWorktrees(repo);
    final match = worktrees.where((w) => _samePath(w.path, path)).firstOrNull;
    if (match == null) return null;
    return WorktreeDeleteStatus(
      path: match.path,
      branch: match.branch,
      isMain: _isProtected(repo, match.path, worktrees),
      dirty: await _dirty(match.path),
      locked: await _locked(repo, match.path),
    );
  }

  /// The main worktree and the one open in the app are never removed.
  bool _isProtected(
    RepoLocation repo,
    String path,
    List<Worktree> worktrees,
  ) => _samePath(path, worktrees.first.path) || _samePath(path, repo.path);

  Future<bool> _dirty(String path) async {
    final output = await _runner.run(
      path,
      ['--no-optional-locks', 'status', '--porcelain', '--untracked-files=all'],
    );
    return output.isNotEmpty;
  }

  Future<bool> _locked(RepoLocation repo, String path) async {
    final output = await _runner.run(
      repo.path,
      ['worktree', 'list', '--porcelain'],
    );
    var inRecord = false;
    for (final line in output.split('\n')) {
      if (line.startsWith('worktree ')) {
        inRecord = _samePath(line.substring(9).trim(), path);
      } else if (line.isEmpty) {
        inRecord = false;
      } else if (inRecord && (line == 'locked' || line.startsWith('locked '))) {
        return true;
      }
    }
    return false;
  }

  bool _samePath(String left, String right) {
    if (p.equals(left, right)) return true;
    try {
      return FileSystemEntity.identicalSync(left, right);
    } on FileSystemException {
      return false;
    }
  }
}
