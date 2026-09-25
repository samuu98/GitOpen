import 'dart:io';

import 'package:gitopen/application/git/branch_deletion_flow.dart';
import 'package:gitopen/domain/refs/branch.dart';
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
    final local = branches.where((b) => b.name == branch).firstOrNull;
    if (local == null) {
      return const BranchDeleteStatus(exists: false, merged: false);
    }
    final worktrees = await _read.getWorktrees(repo);
    final match = worktrees.where((w) => w.branch == branch).firstOrNull;
    final path = match?.path;
    return BranchDeleteStatus(
      exists: true,
      merged: await _merged(repo, local),
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

  /// `git branch -d`'s own safety valve (`branch_merged` in builtin/branch.c):
  /// a branch is checked against its upstream when it has one that still
  /// resolves, and against HEAD otherwise. Checking HEAD unconditionally both
  /// refused merged branches and — worse — reported a branch as deletable that
  /// git then refused, after the dialog had already removed its worktree.
  Future<bool> _merged(RepoLocation repo, Branch branch) async {
    if (branch.upstreamFullName case final upstream?) {
      final mergedIntoUpstream = await _mergedInto(repo, branch.name, upstream);
      if (mergedIntoUpstream != null) return mergedIntoUpstream;
    }
    return await _mergedInto(repo, branch.name, 'HEAD') ?? false;
  }

  /// Null when [reference] does not resolve — a deleted upstream, for which
  /// git falls back to HEAD.
  Future<bool?> _mergedInto(
    RepoLocation repo,
    String branch,
    String reference,
  ) async {
    try {
      final output = await _runner.run(repo.path, [
        'branch',
        '--merged',
        reference,
        '--format=%(refname:short)',
      ]);
      return output.split('\n').map((s) => s.trim()).contains(branch);
    } on GitProcessException {
      return null;
    }
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
