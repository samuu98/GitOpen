import 'dart:io';

import 'package:gitopen/application/git/commit_request.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/infrastructure/git/git_result_runner.dart';
import 'package:path/path.dart' as p;

/// Working-tree and index mutations (write/stage/unstage/discard/commit) for
/// the write-operations facade.  Moved verbatim from `GitCliWriteOperations`.
final class GitCliWorktreeWriter {
  GitCliWorktreeWriter(this._git);
  final GitResultRunner _git;

  Future<GitResult<void>> addWorktree(
    RepoLocation r,
    String path, {
    String? newBranch,
    String? ref,
  }) {
    final args = <String>['worktree', 'add'];
    if (newBranch != null) args.addAll(['-b', newBranch]);
    args.add(path);
    if (newBranch == null && ref != null) args.add(ref);
    return _git.runVoid(r, args);
  }

  Future<GitResult<void>> removeWorktree(
    RepoLocation r,
    String path, {
    bool force = false,
  }) {
    final args = <String>['worktree', 'remove'];
    if (force) args.add('--force');
    args.add(path);
    return _git.runVoid(r, args);
  }

  Future<GitResult<void>> initRepo(String directory) async {
    try {
      // Run from the system temp dir: the target may not exist yet (git
      // creates it), but Process.start needs an existing working directory.
      await _git.runner.run(Directory.systemTemp.path, ['init', directory]);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_git.classify(e), e.stderr, e.stderr);
    }
  }

  Future<GitResult<void>> writeWorkingFile(
    RepoLocation r,
    String relativePath,
    String content,
  ) async {
    try {
      final file = File(p.join(r.path, relativePath));
      // Write the bytes verbatim (UTF-8) so the caller's chosen line endings
      // survive — the merge editor assembles CRLF/LF exactly as the original
      // file had them. `flush: true` so a subsequent `git add` sees the data.
      await file.writeAsString(content, flush: true);
      return const GitSuccess(null);
    } on FileSystemException catch (e) {
      return GitFailure(GitErrorKind.other, e.message, '$e');
    }
  }

  Future<GitResult<void>> stageFiles(
    RepoLocation r,
    List<String> paths,
  ) async {
    if (paths.isEmpty) return const GitSuccess(null);
    return _git.runVoid(r, ['add', '--', ...paths]);
  }

  Future<GitResult<void>> unstageFiles(
    RepoLocation r,
    List<String> paths,
  ) async {
    if (paths.isEmpty) return const GitSuccess(null);
    return _git.runVoid(r, ['restore', '--staged', '--', ...paths]);
  }

  Future<GitResult<void>> stagePatch(RepoLocation r, String unifiedDiff) =>
      _applyPatch(r, ['apply', '--cached', '--whitespace=nowarn', '-'],
          unifiedDiff);

  Future<GitResult<void>> unstagePatch(RepoLocation r, String unifiedDiff) =>
      _applyPatch(
          r,
          ['apply', '--cached', '--reverse', '--whitespace=nowarn', '-'],
          unifiedDiff);

  /// Pipes [unifiedDiff] into `git apply` via stdin, mapping a failure to a
  /// classified [GitFailure] like [GitResultRunner.runVoid] does.
  Future<GitResult<void>> _applyPatch(
    RepoLocation r,
    List<String> args,
    String unifiedDiff,
  ) async {
    try {
      await _git.runner.runWithStdin(r.path, args, unifiedDiff);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_git.classify(e), e.stderr, e.stderr);
    }
  }

  Future<GitResult<void>> discardChanges(
    RepoLocation r,
    List<String> paths,
  ) async {
    if (paths.isEmpty) return const GitSuccess(null);
    return _git.runVoid(r, ['checkout', '--', ...paths]);
  }

  Future<GitResult<void>> cleanUntracked(
    RepoLocation r,
    List<String> paths,
  ) async {
    if (paths.isEmpty) return const GitSuccess(null);
    // `--` separates paths so leading dashes can't be mistaken for flags.
    return _git.runVoid(r, ['clean', '-f', '--', ...paths]);
  }

  Future<GitResult<CommitSha>> commit(RepoLocation r, CommitRequest req) {
    final args = <String>['commit', '-m', req.message];
    if (req.amend) args.add('--amend');
    if (req.signOff) args.add('--signoff');
    if (req.sign) args.add('-S');
    if (req.authorName != null && req.authorEmail != null) {
      args.addAll(['--author', '${req.authorName} <${req.authorEmail}>']);
    }
    // Allow empty commits only on amend (to update msg of last commit)
    if (req.amend) args.add('--allow-empty');
    return _git.runThenHead(r, args);
  }
}
