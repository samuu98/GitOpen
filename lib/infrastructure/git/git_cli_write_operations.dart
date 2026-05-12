import 'dart:convert';
import 'dart:io';

import '../../application/git/auth_spec.dart';
import '../../application/git/commit_request.dart';
import '../../application/git/git_progress.dart';
import '../../application/git/git_result.dart';
import '../../application/git/git_write_operations.dart';
import '../../application/git/merge_outcome.dart';
import '../../domain/commits/commit_sha.dart';
import '../../domain/repositories/repo_location.dart';
import 'credential_helper.dart';
import 'git_process_runner.dart';
import 'git_progress_parser.dart';

final class GitCliWriteOperations implements GitWriteOperations {
  // ignore: unused_field
  final GitProcessRunner _runner;
  GitCliWriteOperations({GitProcessRunner? runner})
      : _runner = runner ?? GitProcessRunner();

  @override
  Future<GitResult<void>> stageFiles(RepoLocation r, List<String> paths) async {
    if (paths.isEmpty) return const GitSuccess(null);
    try {
      await _runner.run(r.path, ['add', '--', ...paths]);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }

  @override
  Future<GitResult<void>> unstageFiles(RepoLocation r, List<String> paths) async {
    if (paths.isEmpty) return const GitSuccess(null);
    try {
      await _runner.run(r.path, ['restore', '--staged', '--', ...paths]);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }

  GitErrorKind _classify(GitProcessException e) {
    final s = e.stderr.toLowerCase();
    if (s.contains('auth') || s.contains('401') || s.contains('permission denied')) return GitErrorKind.auth;
    if (s.contains('network') || s.contains('could not resolve') || s.contains('connection')) return GitErrorKind.network;
    if (s.contains('non-fast-forward') || s.contains('rejected')) return GitErrorKind.nonFastForward;
    if (s.contains('conflict')) return GitErrorKind.conflict;
    if (s.contains('would be overwritten')) return GitErrorKind.dirtyWorkingTree;
    if (s.contains('unknown revision') || s.contains('not a valid ref')) return GitErrorKind.unknownRef;
    return GitErrorKind.other;
  }
  @override
  Future<GitResult<void>> stagePatch(RepoLocation r, String unifiedDiff) async {
    try {
      await _runner.runWithStdin(
          r.path, ['apply', '--cached', '--whitespace=nowarn', '-'], unifiedDiff);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }

  @override
  Future<GitResult<void>> unstagePatch(RepoLocation r, String unifiedDiff) async {
    try {
      await _runner.runWithStdin(r.path,
          ['apply', '--cached', '--reverse', '--whitespace=nowarn', '-'], unifiedDiff);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }
  @override
  Future<GitResult<void>> discardChanges(RepoLocation r, List<String> paths) async {
    if (paths.isEmpty) return const GitSuccess(null);
    try {
      await _runner.run(r.path, ['checkout', '--', ...paths]);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }

  @override
  Future<GitResult<CommitSha>> commit(RepoLocation r, CommitRequest req) async {
    final args = <String>['commit', '-m', req.message];
    if (req.amend) args.add('--amend');
    if (req.signOff) args.add('--signoff');
    if (req.authorName != null && req.authorEmail != null) {
      args.addAll(['--author', '${req.authorName} <${req.authorEmail}>']);
    }
    // Allow empty commits only on amend (to update msg of last commit)
    if (req.amend) args.add('--allow-empty');
    try {
      await _runner.run(r.path, args);
      final sha = (await _runner.run(r.path, ['rev-parse', 'HEAD'])).trim();
      return GitSuccess(CommitSha(sha));
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }
  @override
  Future<GitResult<void>> createBranch(RepoLocation r, String name, {CommitSha? at, bool checkout = false}) async {
    try {
      final args = checkout ? ['checkout', '-b', name] : ['branch', name];
      if (at != null) args.add(at.value);
      await _runner.run(r.path, args);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }

  @override
  Future<GitResult<void>> checkout(RepoLocation r, String ref, {bool force = false}) async {
    try {
      final args = <String>['checkout'];
      if (force) args.add('--force');
      args.add(ref);
      await _runner.run(r.path, args);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }

  @override
  Future<GitResult<void>> deleteBranch(RepoLocation r, String name, {bool force = false, bool remote = false}) async {
    try {
      if (remote) {
        // Delete remote branch via push --delete
        final parts = name.split('/');
        if (parts.length < 2) {
          return const GitFailure(GitErrorKind.invalidArgument, 'remote branch name must be <remote>/<branch>');
        }
        final remoteName = parts.first;
        final branchName = parts.sublist(1).join('/');
        await _runner.run(r.path, ['push', remoteName, '--delete', branchName]);
      } else {
        final flag = force ? '-D' : '-d';
        await _runner.run(r.path, ['branch', flag, name]);
      }
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }

  @override
  Future<GitResult<void>> renameBranch(RepoLocation r, String oldName, String newName) async {
    try {
      await _runner.run(r.path, ['branch', '-m', oldName, newName]);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }

  @override
  Future<GitResult<void>> setUpstream(RepoLocation r, String branch, String upstream) async {
    try {
      await _runner.run(r.path, ['branch', '--set-upstream-to=$upstream', branch]);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }
  @override
  Future<GitResult<void>> createTag(RepoLocation r, String name, {CommitSha? at, String? message}) async {
    try {
      final args = <String>['tag'];
      if (message != null) args.addAll(['-a', '-m', message]);
      args.add(name);
      if (at != null) args.add(at.value);
      await _runner.run(r.path, args);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }

  @override
  Future<GitResult<void>> deleteTag(RepoLocation r, String name) async {
    try {
      await _runner.run(r.path, ['tag', '-d', name]);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }
  @override
  Stream<GitProgress> fetch(RepoLocation r,
      {String? remote, bool all = false, AuthSpec? auth}) async* {
    final args = <String>['fetch', '--progress'];
    if (all) {
      args.add('--all');
    } else if (remote != null) {
      args.add(remote);
    }
    await for (final p in _runProgressStream(r.path, args, auth: auth)) {
      yield p;
    }
  }

  @override
  Stream<GitProgress> pull(RepoLocation r, PullStrategy strategy,
      {AuthSpec? auth}) async* {
    final args = <String>['pull', '--progress'];
    switch (strategy) {
      case PullStrategy.ffOnly:
        args.add('--ff-only');
      case PullStrategy.merge:
        args.add('--no-rebase');
      case PullStrategy.rebase:
        args.add('--rebase');
    }
    await for (final p in _runProgressStream(r.path, args, auth: auth)) {
      yield p;
    }
  }

  @override
  Stream<GitProgress> push(RepoLocation r,
      {String? remote,
      String? branch,
      bool forceWithLease = false,
      bool pushTags = false,
      AuthSpec? auth}) async* {
    final args = <String>['push', '--progress'];
    if (forceWithLease) args.add('--force-with-lease');
    if (pushTags) args.add('--tags');
    if (remote != null) {
      args.add(remote);
      if (branch != null) args.add(branch);
    }
    await for (final p in _runProgressStream(r.path, args, auth: auth)) {
      yield p;
    }
  }

  Stream<GitProgress> _runProgressStream(String cwd, List<String> args,
      {AuthSpec? auth}) async* {
    final helper = await CredentialHelper.setup(auth, '');
    try {
      final proc = await Process.start(
        _runner.executable,
        args,
        workingDirectory: cwd,
        environment: helper.env.isEmpty ? null : helper.env,
      );
      await for (final line in proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final parsed = GitProgressParser.parse(line);
        if (parsed != null) yield parsed;
      }
      final exit = await proc.exitCode;
      if (exit != 0) {
        throw GitProcessException(args, exit, '');
      }
    } finally {
      helper.dispose();
    }
  }
  @override
  Future<GitResult<void>> stashSave(RepoLocation r, String message, {bool includeUntracked = false}) async {
    try {
      final args = <String>['stash', 'push', '-m', message];
      if (includeUntracked) args.add('-u');
      await _runner.run(r.path, args);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }

  @override
  Future<GitResult<void>> stashPop(RepoLocation r, int index) async {
    try { await _runner.run(r.path, ['stash', 'pop', 'stash@{$index}']); return const GitSuccess(null); }
    on GitProcessException catch (e) { return GitFailure(_classify(e), e.stderr, e.stderr); }
  }

  @override
  Future<GitResult<void>> stashApply(RepoLocation r, int index) async {
    try { await _runner.run(r.path, ['stash', 'apply', 'stash@{$index}']); return const GitSuccess(null); }
    on GitProcessException catch (e) { return GitFailure(_classify(e), e.stderr, e.stderr); }
  }

  @override
  Future<GitResult<void>> stashDrop(RepoLocation r, int index) async {
    try { await _runner.run(r.path, ['stash', 'drop', 'stash@{$index}']); return const GitSuccess(null); }
    on GitProcessException catch (e) { return GitFailure(_classify(e), e.stderr, e.stderr); }
  }

  @override
  Future<GitResult<MergeOutcome>> merge(RepoLocation r, String ref, {bool ffOnly = false, bool noCommit = false}) => throw UnimplementedError();
  @override
  Future<GitResult<void>> mergeAbort(RepoLocation r) => throw UnimplementedError();
  @override
  Future<GitResult<CommitSha>> mergeContinue(RepoLocation r) => throw UnimplementedError();
  @override
  Future<GitResult<CherryPickOutcome>> cherryPick(RepoLocation r, CommitSha sha) => throw UnimplementedError();
  @override
  Future<GitResult<void>> cherryPickAbort(RepoLocation r) => throw UnimplementedError();
  @override
  Future<GitResult<CommitSha>> cherryPickContinue(RepoLocation r) => throw UnimplementedError();
  @override
  Future<GitResult<void>> reset(RepoLocation r, CommitSha to, ResetMode mode) => throw UnimplementedError();
  @override
  Stream<GitProgress> clone(String url, String destination, {AuthSpec? auth}) => throw UnimplementedError();
}
