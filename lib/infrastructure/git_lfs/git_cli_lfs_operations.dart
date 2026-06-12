import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git_lfs/git_lfs_models.dart';
import 'package:gitopen/application/git_lfs/git_lfs_operations.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/credential_helper.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/infrastructure/git/git_result_runner.dart';
import 'package:gitopen/infrastructure/git_lfs/git_lfs_parsers.dart';
import 'package:path/path.dart' as p;

/// Git LFS CLI adapter. All commands run `git lfs ...` through the shared
/// process runner; install is always `--local` so a missing global hook
/// setup is never mutated behind the user's back.
final class GitCliLfsOperations implements GitLfsOperations {
  GitCliLfsOperations({GitProcessRunner? runner})
    : _runner = runner ?? GitProcessRunner(),
      _git = GitResultRunner(runner ?? GitProcessRunner());

  final GitProcessRunner _runner;
  final GitResultRunner _git;

  @override
  Future<GitLfsStatus> status(RepoLocation repo) async {
    try {
      final versionRaw = await _runner.run(repo.path, ['lfs', 'version']);
      final version = parseGitLfsVersion(versionRaw);
      var configured = false;
      try {
        final clean = await _runner.run(repo.path, [
          'config',
          '--local',
          '--get',
          'filter.lfs.clean',
        ]);
        configured = clean.contains('git-lfs');
      } on GitProcessException {
        configured = false;
      }
      return GitLfsStatus(
        isInstalled: true,
        version: version,
        isRepoConfigured: configured,
        hasAttributes: File(p.join(repo.path, '.gitattributes')).existsSync(),
      );
    } on GitProcessException catch (e) {
      if (e.stderr.contains('not a git command')) {
        return const GitLfsStatus(
          isInstalled: false,
          version: null,
          isRepoConfigured: false,
          hasAttributes: false,
        );
      }
      rethrow;
    }
  }

  /// Reads the root `.gitattributes` instead of shelling out: `git lfs
  /// track --list` does not exist (git-lfs 3.7 rejects the flag) and the
  /// bare `git lfs track` listing drops the attribute string the UI shows.
  /// `git lfs track <pattern>` writes to the root file, so this stays in
  /// sync with every mutation the app can make.
  @override
  Future<List<GitLfsTrackedPattern>> trackedPatterns(RepoLocation repo) async {
    final file = File(p.join(repo.path, '.gitattributes'));
    if (!file.existsSync()) return const [];
    return parseGitLfsTrackList(await file.readAsString());
  }

  @override
  Future<List<GitLfsFile>> files(RepoLocation repo) async => parseGitLfsLsFiles(
    await _runner.run(repo.path, ['lfs', 'ls-files', '--long', '--size']),
  );

  @override
  Future<GitResult<void>> installLocal(RepoLocation repo) =>
      _git.runVoid(repo, ['lfs', 'install', '--local']);

  @override
  Future<GitResult<void>> track(RepoLocation repo, String pattern) =>
      _git.runVoid(repo, ['lfs', 'track', pattern]);

  @override
  Future<GitResult<void>> untrack(RepoLocation repo, String pattern) =>
      _git.runVoid(repo, ['lfs', 'untrack', pattern]);

  @override
  Stream<GitProgress> fetch(RepoLocation repo, {AuthSpec? auth}) =>
      _runLfsProgress(repo, ['lfs', 'fetch'], auth: auth);

  @override
  Stream<GitProgress> pull(RepoLocation repo, {AuthSpec? auth}) =>
      _runLfsProgress(repo, ['lfs', 'pull'], auth: auth);

  @override
  Stream<GitProgress> push(RepoLocation repo, {AuthSpec? auth}) =>
      _runLfsProgress(repo, ['lfs', 'push', 'origin'], auth: auth);

  /// Streams every output line of a `git lfs` sync command as a progress
  /// event. LFS reports transfer progress on stdout (unlike git itself,
  /// which uses stderr), so both pipes are surfaced.
  Stream<GitProgress> _runLfsProgress(
    RepoLocation repo,
    List<String> args, {
    AuthSpec? auth,
  }) async* {
    final helper = await CredentialHelper.setup(auth);
    final effectiveArgs = helper.extraArgs.isEmpty
        ? args
        : <String>[...helper.extraArgs, ...args];
    final stderrBuf = StringBuffer();
    try {
      final proc = await Process.start(
        _runner.executable,
        effectiveArgs,
        workingDirectory: repo.path,
        environment: buildGitEnvironment(helper.env),
      );
      // Merge stdout and stderr into one line stream so neither pipe can
      // fill up and block the child while the other is being read.
      final lines = StreamController<String>();
      var openPipes = 2;
      void onPipeDone() {
        openPipes--;
        if (openPipes == 0) unawaited(lines.close());
      }

      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(lines.add, onDone: onPipeDone, onError: lines.addError);
      proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              stderrBuf.writeln(line);
              lines.add(line);
            },
            onDone: onPipeDone,
            onError: lines.addError,
          );
      await for (final line in lines.stream) {
        if (line.trim().isEmpty) continue;
        yield GitProgress(phase: line, rawLine: line);
      }
      final exit = await proc.exitCode;
      if (exit != 0) {
        throw GitProcessException(
          effectiveArgs,
          exit,
          stderrBuf.toString().trim(),
        );
      }
    } finally {
      helper.dispose();
    }
  }
}
