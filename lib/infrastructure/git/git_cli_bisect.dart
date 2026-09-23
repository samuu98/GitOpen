import 'dart:math' as math;

import 'package:gitopen/application/git/bisect_state.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/infrastructure/git/git_result_runner.dart';
import 'package:gitopen/infrastructure/git/io_git_dir_probe.dart';

/// Bisect CLI commands and readback. Git owns the state in the worktree gitdir.
final class GitCliBisect {
  GitCliBisect(GitProcessRunner runner)
    : _runner = runner,
      _results = GitResultRunner(runner);

  final GitProcessRunner _runner;
  final GitResultRunner _results;

  Future<GitResult<void>> start(
    RepoLocation repo,
    String bad,
    String good,
  ) async {
    try {
      // Resolve user text to a commit before passing it to bisect, so a ref
      // beginning with '-' cannot be interpreted as a bisect option.
      final goodSha = (await _runner.run(repo.path, [
        'rev-parse',
        '--verify',
        '--end-of-options',
        '$good^{commit}',
      ])).trim();
      final badSha = (await _runner.run(repo.path, [
        'rev-parse',
        '--verify',
        '--end-of-options',
        '$bad^{commit}',
      ])).trim();
      return _results.runVoid(repo, [
        '-c',
        'core.editor=true',
        'bisect',
        'start',
        badSha,
        goodSha,
      ]);
    } on GitProcessException catch (e) {
      return GitFailure(_results.classify(e), e.stderr, e.stderr);
    }
  }

  Future<GitResult<void>> good(RepoLocation repo) =>
      _results.runVoid(repo, ['-c', 'core.editor=true', 'bisect', 'good']);

  Future<GitResult<void>> bad(RepoLocation repo) =>
      _results.runVoid(repo, ['-c', 'core.editor=true', 'bisect', 'bad']);

  Future<GitResult<void>> skip(RepoLocation repo) =>
      _results.runVoid(repo, ['-c', 'core.editor=true', 'bisect', 'skip']);

  Future<GitResult<void>> reset(RepoLocation repo) =>
      _results.runVoid(repo, ['-c', 'core.editor=true', 'bisect', 'reset']);

  Future<BisectState?> state(RepoLocation repo) async {
    const probe = IoGitDirProbe();
    if (!probe.fileExists(repo, 'BISECT_LOG') &&
        !probe.fileExists(repo, 'BISECT_START')) {
      return null;
    }
    final refs = await _runner.run(repo.path, [
      'for-each-ref',
      '--format=%(refname) %(objectname)',
      'refs/bisect',
    ]);
    CommitSha? bad;
    final good = <CommitSha>[];
    for (final line in refs.split('\n')) {
      final parts = line.trim().split(' ');
      if (parts.length != 2) continue;
      if (parts[0] == 'refs/bisect/bad') {
        bad = CommitSha(parts[1]);
      } else if (parts[0].startsWith('refs/bisect/good-')) {
        good.add(CommitSha(parts[1]));
      }
    }
    if (bad == null) return null;
    final candidate = CommitSha(
      (await _runner.run(
        repo.path,
        ['rev-parse', 'HEAD'],
      )).trim(),
    );
    final subject = (await _runner.run(
      repo.path,
      ['show', '-s', '--format=%s', candidate.value],
    )).trim();
    final log = await _runner.run(repo.path, ['bisect', 'log']);
    final match = RegExp(
      r'^# first bad commit: \[([0-9a-f]{40})\]',
      multiLine: true,
    ).firstMatch(log);
    final firstBad = match == null ? null : CommitSha(match.group(1)!);
    final count = int.parse(
      (await _runner.run(repo.path, [
        'rev-list',
        '--count',
        bad.value,
        for (final sha in good) '^${sha.value}',
      ])).trim(),
    );
    final stepsLeft = firstBad != null || count <= 1
        ? 0
        : (math.log(count) / math.ln2).ceil();
    return BisectState(
      candidate: candidate,
      subject: subject,
      good: good,
      bad: bad,
      stepsLeft: stepsLeft,
      firstBad: firstBad,
    );
  }
}
