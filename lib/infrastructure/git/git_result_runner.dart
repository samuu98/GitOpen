import 'dart:convert';
import 'dart:io';

import 'package:gitopen/application/git/auth_failure_classifier.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';

/// Shared plumbing for the CLI write collaborators: maps process failures to
/// classified [GitFailure]s and centralises the capture/HEAD/unmerged-paths
/// helpers the sequencing commands repeat.  Moved verbatim from
/// `GitCliWriteOperations`.
final class GitResultRunner {
  GitResultRunner(this.runner);
  final GitProcessRunner runner;

  /// Runs [args] in [r] and returns success, mapping any process failure to a
  /// classified [GitFailure]. Collapses the repeated try/run/catch block used
  /// by the many fire-and-forget git commands.
  Future<GitResult<void>> runVoid(RepoLocation r, List<String> args) async {
    try {
      await runner.run(r.path, args);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(classify(e), e.stderr, e.stderr);
    }
  }

  /// Runs [args] in [r] then resolves the new HEAD, returning it as a
  /// [CommitSha]. Used by the commands that report the commit they produced.
  Future<GitResult<CommitSha>> runThenHead(
    RepoLocation r,
    List<String> args,
  ) async {
    try {
      await runner.run(r.path, args);
      return GitSuccess(CommitSha(await head(r)));
    } on GitProcessException catch (e) {
      return GitFailure(classify(e), e.stderr, e.stderr);
    }
  }

  /// Resolves the current HEAD sha of [r].
  Future<String> head(RepoLocation r) async =>
      (await runner.run(r.path, ['rev-parse', 'HEAD'])).trim();

  /// Runs [args] via `Process.run`, capturing BOTH stdout and stderr — the
  /// sequencing commands (merge/rebase/cherry-pick/revert) need stdout for
  /// conflict detection, which the exception-throwing runner discards.
  Future<ProcessResult> capture(
    String cwd,
    List<String> args, {
    Map<String, String>? environment,
  }) {
    return Process.run(
      runner.executable,
      args,
      workingDirectory: cwd,
      environment: environment ?? buildGitEnvironment(),
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  /// Lists the unique paths git reports as unmerged via `ls-files --unmerged`,
  /// which always exits 0. Each raw line is
  /// `<mode> <sha> <stage>` then a tab then the path; we take the path after
  /// the tab and de-duplicate across the (up to three) stage entries per file.
  Future<List<String>> listUnmergedPaths(RepoLocation r) async {
    final raw = await runner.run(r.path, ['ls-files', '--unmerged']);
    return raw
        .split('\n')
        .where((l) => l.isNotEmpty)
        .map((l) => l.split('\t').last)
        .toSet()
        .toList();
  }

  GitErrorKind classify(GitProcessException e) {
    final s = e.stderr.toLowerCase();
    // Auth detection reuses the shared classifier's specific phrases, so the
    // old `contains('auth')` no longer matches the word "author" in commit
    // errors. Bare `401` is kept as an extra signal.
    if (const AuthFailureClassifier().classify(e.stderr) != null ||
        s.contains('401')) {
      return GitErrorKind.auth;
    }
    if (s.contains('network') ||
        s.contains('could not resolve') ||
        s.contains('connection')) {
      return GitErrorKind.network;
    }
    if (s.contains('non-fast-forward') || s.contains('rejected')) {
      return GitErrorKind.nonFastForward;
    }
    if (s.contains('conflict')) return GitErrorKind.conflict;
    if (s.contains('would be overwritten')) {
      return GitErrorKind.dirtyWorkingTree;
    }
    if (s.contains('unknown revision') || s.contains('not a valid ref')) {
      return GitErrorKind.unknownRef;
    }
    return GitErrorKind.other;
  }
}
