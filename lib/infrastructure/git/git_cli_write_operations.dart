import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gitopen/application/git/auth_spec.dart';
import 'package:gitopen/application/git/commit_request.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/credential_helper.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/infrastructure/git/git_progress_parser.dart';
import 'package:gitopen/infrastructure/logging/app_logger.dart';
import 'package:path/path.dart' as p;

final class GitCliWriteOperations implements GitWriteOperations {
  GitCliWriteOperations({GitProcessRunner? runner})
      : _runner = runner ?? GitProcessRunner();
  final GitProcessRunner _runner;

  @override
  Future<GitResult<void>> stageFiles(
    RepoLocation r,
    List<String> paths,
  ) async {
    if (paths.isEmpty) return const GitSuccess(null);
    return _runVoid(r, ['add', '--', ...paths]);
  }

  @override
  Future<GitResult<void>> unstageFiles(
    RepoLocation r,
    List<String> paths,
  ) async {
    if (paths.isEmpty) return const GitSuccess(null);
    return _runVoid(r, ['restore', '--staged', '--', ...paths]);
  }

  /// Runs [args] in [r] and returns success, mapping any process failure to a
  /// classified [GitFailure]. Collapses the repeated try/run/catch block used
  /// by the many fire-and-forget git commands.
  Future<GitResult<void>> _runVoid(RepoLocation r, List<String> args) async {
    try {
      await _runner.run(r.path, args);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }

  /// Runs [args] in [r] then resolves the new HEAD, returning it as a
  /// [CommitSha]. Used by the commands that report the commit they produced.
  Future<GitResult<CommitSha>> _runThenHead(
    RepoLocation r,
    List<String> args,
  ) async {
    try {
      await _runner.run(r.path, args);
      final head = (await _runner.run(r.path, ['rev-parse', 'HEAD'])).trim();
      return GitSuccess(CommitSha(head));
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }

  /// Lists the unique paths git reports as unmerged via `ls-files --unmerged`,
  /// which always exits 0. Each raw line is
  /// `<mode> <sha> <stage>` then a tab then the path; we take the path after
  /// the tab and de-duplicate across the (up to three) stage entries per file.
  Future<List<String>> _listUnmergedPaths(RepoLocation r) async {
    final raw = await _runner.run(r.path, ['ls-files', '--unmerged']);
    return raw
        .split('\n')
        .where((l) => l.isNotEmpty)
        .map((l) => l.split('\t').last)
        .toSet()
        .toList();
  }

  GitErrorKind _classify(GitProcessException e) {
    final s = e.stderr.toLowerCase();
    if (s.contains('auth') ||
        s.contains('401') ||
        s.contains('permission denied')) {
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

  @override
  Future<GitResult<void>> stagePatch(RepoLocation r, String unifiedDiff) async {
    try {
      await _runner.runWithStdin(
        r.path,
        ['apply', '--cached', '--whitespace=nowarn', '-'],
        unifiedDiff,
      );
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }

  @override
  Future<GitResult<void>> unstagePatch(
    RepoLocation r,
    String unifiedDiff,
  ) async {
    try {
      await _runner.runWithStdin(
        r.path,
        ['apply', '--cached', '--reverse', '--whitespace=nowarn', '-'],
        unifiedDiff,
      );
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      return GitFailure(_classify(e), e.stderr, e.stderr);
    }
  }
  @override
  Future<GitResult<void>> discardChanges(
    RepoLocation r,
    List<String> paths,
  ) async {
    if (paths.isEmpty) return const GitSuccess(null);
    return _runVoid(r, ['checkout', '--', ...paths]);
  }

  @override
  Future<GitResult<void>> cleanUntracked(
    RepoLocation r,
    List<String> paths,
  ) async {
    if (paths.isEmpty) return const GitSuccess(null);
    // `--` separates paths so leading dashes can't be mistaken for flags.
    return _runVoid(r, ['clean', '-f', '--', ...paths]);
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
    return _runThenHead(r, args);
  }
  @override
  Future<GitResult<void>> createBranch(
    RepoLocation r,
    String name, {
    CommitSha? at,
    bool checkout = false,
  }) async {
    final args = checkout ? ['checkout', '-b', name] : ['branch', name];
    if (at != null) args.add(at.value);
    return _runVoid(r, args);
  }

  @override
  Future<GitResult<void>> checkout(
    RepoLocation r,
    String ref, {
    bool force = false,
  }) async {
    final args = <String>['checkout'];
    if (force) args.add('--force');
    args.add(ref);
    return _runVoid(r, args);
  }

  @override
  Future<GitResult<void>> deleteBranch(
    RepoLocation r,
    String name, {
    bool force = false,
    bool remote = false,
  }) async {
    if (remote) {
      // Delete remote branch via push --delete
      final parts = name.split('/');
      if (parts.length < 2) {
        return const GitFailure(
          GitErrorKind.invalidArgument,
          'remote branch name must be <remote>/<branch>',
        );
      }
      final remoteName = parts.first;
      final branchName = parts.sublist(1).join('/');
      return _runVoid(r, ['push', remoteName, '--delete', branchName]);
    }
    final flag = force ? '-D' : '-d';
    return _runVoid(r, ['branch', flag, name]);
  }

  @override
  Future<GitResult<void>> renameBranch(
    RepoLocation r,
    String oldName,
    String newName,
  ) async {
    return _runVoid(r, ['branch', '-m', oldName, newName]);
  }

  @override
  Future<GitResult<void>> setUpstream(
    RepoLocation r,
    String branch,
    String upstream,
  ) async {
    return _runVoid(r, ['branch', '--set-upstream-to=$upstream', branch]);
  }
  @override
  Future<GitResult<void>> addRemote(
    RepoLocation r,
    String name,
    String url,
  ) async {
    return _runVoid(r, ['remote', 'add', name, url]);
  }

  @override
  Future<GitResult<void>> removeRemote(RepoLocation r, String name) async {
    return _runVoid(r, ['remote', 'remove', name]);
  }

  @override
  Future<GitResult<void>> renameRemote(
    RepoLocation r,
    String oldName,
    String newName,
  ) async {
    return _runVoid(r, ['remote', 'rename', oldName, newName]);
  }

  @override
  Future<GitResult<void>> setRemoteUrl(
    RepoLocation r,
    String name,
    String url,
  ) async {
    return _runVoid(r, ['remote', 'set-url', name, url]);
  }

  @override
  Future<GitResult<void>> createTag(
    RepoLocation r,
    String name, {
    CommitSha? at,
    String? message,
  }) async {
    final args = <String>['tag'];
    if (message != null) args.addAll(['-a', '-m', message]);
    args.add(name);
    if (at != null) args.add(at.value);
    return _runVoid(r, args);
  }

  @override
  Future<GitResult<void>> deleteTag(RepoLocation r, String name) async {
    return _runVoid(r, ['tag', '-d', name]);
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
    // `push.autoSetupRemote=true` makes a bare `git push` on a branch with
    // no upstream behave like `git push --set-upstream origin <branch>` —
    // it picks the default push remote, pushes to the same-name branch,
    // and records the upstream. Without it, the first push on a freshly
    // created branch fails with "no upstream branch" even when auth and
    // remote are configured correctly. The `-c` override must come before
    // the subcommand, like the credential helper's own overrides.
    final args = <String>[
      '-c',
      'push.autoSetupRemote=true',
      'push',
      '--progress',
    ];
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
    final helper = await CredentialHelper.setup(auth);
    // The helper-supplied `-c key=value` overrides must come BEFORE the
    // git subcommand. They inject the Authorization header and reset
    // inherited credential helpers (so GCM is bypassed).
    final effectiveArgs = helper.extraArgs.isEmpty
        ? args
        : <String>[...helper.extraArgs, ...args];
    // Log the effective argv with the Authorization secret redacted so we
    // can see whether the helper actually injected the header (and which
    // auth kind reached this layer) without leaking the token.
    final redacted = effectiveArgs
        .map((a) => a.startsWith('http.extraheader=Authorization:')
            ? 'http.extraheader=Authorization: <redacted>'
            : a)
        .join(' ');
    appLog.d('git[progress] auth=${auth?.runtimeType ?? 'none'} '
        'env_keys=${helper.env.keys.toList()} '
        'cmd: git $redacted');
    final stderrBuf = StringBuffer();
    try {
      final proc = await Process.start(
        _runner.executable,
        effectiveArgs,
        workingDirectory: cwd,
        environment: buildGitEnvironment(helper.env),
      );
      // Drain stdout so the process never blocks on a full pipe.
      unawaited(proc.stdout.drain<void>());
      await for (final line in proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final parsed = GitProgressParser.parse(line);
        if (parsed != null) {
          yield parsed;
        } else {
          // Non-progress stderr lines — usually error messages. Keep them
          // for the exception in case the process exits non-zero.
          stderrBuf.writeln(line);
        }
      }
      final exit = await proc.exitCode;
      if (exit != 0) {
        final stderr = stderrBuf.toString().trim();
        appLog.w('git[progress] exit=$exit stderr=$stderr');
        throw GitProcessException(effectiveArgs, exit, stderr);
      }
      appLog.d('git[progress] exit=0');
    } finally {
      helper.dispose();
    }
  }
  @override
  Future<GitResult<void>> stashSave(
    RepoLocation r,
    String message, {
    bool includeUntracked = false,
  }) async {
    final args = <String>['stash', 'push', '-m', message];
    if (includeUntracked) args.add('-u');
    return _runVoid(r, args);
  }

  @override
  Future<GitResult<void>> stashPop(RepoLocation r, int index) async {
    return _runVoid(r, ['stash', 'pop', 'stash@{$index}']);
  }

  @override
  Future<GitResult<void>> stashApply(RepoLocation r, int index) async {
    return _runVoid(r, ['stash', 'apply', 'stash@{$index}']);
  }

  @override
  Future<GitResult<void>> stashDrop(RepoLocation r, int index) async {
    return _runVoid(r, ['stash', 'drop', 'stash@{$index}']);
  }

  @override
  Future<GitResult<MergeOutcome>> merge(RepoLocation r, String ref,
      {MergeStrategy strategy = MergeStrategy.defaultStrategy}) async {
    final args = <String>['merge'];
    switch (strategy) {
      case MergeStrategy.defaultStrategy:
        break;
      case MergeStrategy.noFF:
        args.add('--no-ff');
      case MergeStrategy.squash:
        // `--squash` implies `--no-commit`; pair with `--ff` so git never
        // creates a merge commit, only updates the index.
        args.addAll(['--squash', '--ff']);
      case MergeStrategy.noCommit:
        args.addAll(['--no-ff', '--no-commit']);
    }
    args.add(ref);
    // Use Process.run directly so we can inspect both stdout and stderr on
    // failure.
    final result = await Process.run(
      _runner.executable, args,
      workingDirectory: r.path,
      environment: buildGitEnvironment(),
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final out = result.stdout.toString();
    final err = result.stderr.toString();
    if (result.exitCode == 0) {
      if (out.contains('Already up to date')) {
        return const GitSuccess(MergeUpToDate());
      }
      // Squash and no-commit leave changes staged without creating a commit.
      if (strategy == MergeStrategy.squash ||
          strategy == MergeStrategy.noCommit) {
        return const GitSuccess(MergeStaged());
      }
      final ff = out.contains('Fast-forward');
      final head = (await _runner.run(r.path, ['rev-parse', 'HEAD'])).trim();
      if (ff) return GitSuccess(MergeFastForward(CommitSha(head)));
      return GitSuccess(MergeMerged(CommitSha(head)));
    }
    // Check for conflict in both stdout and stderr
    final combined = out + err;
    if (combined.contains('CONFLICT') ||
        combined.contains('Automatic merge failed')) {
      return GitSuccess(MergeConflict(await _listUnmergedPaths(r)));
    }
    final exc = GitProcessException(args, result.exitCode, err);
    return GitFailure(_classify(exc), err, err);
  }

  @override
  Future<GitResult<void>> mergeAbort(RepoLocation r) async {
    return _runVoid(r, ['merge', '--abort']);
  }

  @override
  Future<GitResult<CommitSha>> mergeContinue(RepoLocation r) =>
      _runThenHead(r, ['merge', '--continue', '--no-edit']);
  @override
  Future<GitResult<MergePreview>> previewMerge(
    RepoLocation r,
    String ref,
  ) async {
    // `git merge-tree --write-tree` is the modern (git 2.38+) dry-run form:
    // exits 0 on a clean merge, 1 on conflict, >1 on usage/error. With
    // `--name-only`, conflicted paths are printed after the tree OID and a
    // blank line.
    final head = (await _runner.run(r.path, ['rev-parse', 'HEAD'])).trim();
    final result = await Process.run(
      _runner.executable,
      [
        'merge-tree',
        '--write-tree',
        '--name-only',
        '--no-messages',
        head,
        ref,
      ],
      workingDirectory: r.path,
      environment: buildGitEnvironment(),
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode == 0) return const GitSuccess(MergePreviewClean());
    if (result.exitCode == 1) {
      final lines = (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      // First line is the conflicted tree OID; the rest are paths.
      final paths = lines.length > 1 ? lines.sublist(1) : const <String>[];
      return GitSuccess(MergePreviewConflicts(paths));
    }
    final err = result.stderr.toString();
    final exc = GitProcessException(['merge-tree'], result.exitCode, err);
    return GitFailure(_classify(exc), err, err);
  }

  @override
  Future<GitResult<RebaseOutcome>> rebase(
    RepoLocation r,
    String upstream,
  ) async {
    final args = ['rebase', upstream];
    final result = await Process.run(
      _runner.executable, args,
      workingDirectory: r.path,
      environment: buildGitEnvironment(),
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final out = result.stdout.toString();
    final err = result.stderr.toString();
    if (result.exitCode == 0) {
      if (out.contains('is up to date') || out.contains('up to date')) {
        return const GitSuccess(RebaseUpToDate());
      }
      final head = (await _runner.run(r.path, ['rev-parse', 'HEAD'])).trim();
      return GitSuccess(RebaseApplied(CommitSha(head)));
    }
    final combined = out + err;
    if (combined.contains('CONFLICT') ||
        combined.contains('could not apply') ||
        combined.contains('Resolve all conflicts')) {
      return GitSuccess(RebaseConflict(await _listUnmergedPaths(r)));
    }
    final exc = GitProcessException(args, result.exitCode, err);
    return GitFailure(_classify(exc), err, err);
  }

  @override
  Future<GitResult<RebaseOutcome>> interactiveRebase(
    RepoLocation r,
    CommitSha onto,
    List<RebaseTodoEntry> plan,
  ) async {
    // Build the todo text — one line per entry, oldest-first, exactly as git
    // writes its own todo file. `drop` is emitted explicitly so the rebase is
    // self-documenting (omitting the line would also drop the commit).
    final todo = StringBuffer();
    for (final e in plan) {
      final verb = switch (e.action) {
        RebaseTodoAction.pick => 'pick',
        RebaseTodoAction.squash => 'squash',
        RebaseTodoAction.fixup => 'fixup',
        RebaseTodoAction.drop => 'drop',
      };
      todo.writeln('$verb ${e.sha.value}');
    }

    // Write the scripted todo to a temp file. Git invokes
    //   sh -c "$GIT_SEQUENCE_EDITOR <git-todo-path>"
    // so we set GIT_SEQUENCE_EDITOR to a `cp` that overwrites git's todo file
    // with ours. Forward-slash paths keep Git-for-Windows' bundled `sh` happy.
    final tmpDir = Directory.systemTemp.createTempSync('gitopen-irebase-');
    final todoFile = File(p.join(tmpDir.path, 'todo'))
      ..writeAsStringSync(todo.toString());
    final todoPosix = todoFile.path.replaceAll(r'\', '/');

    final args = <String>[
      // `core.editor=true` is a no-op editor for any commit-message prompt
      // squash would otherwise raise (we keep messages as-is).
      '-c', 'core.editor=true',
      'rebase', '-i', onto.value,
    ];

    final env = buildGitEnvironment({
      // The trailing space lets git append the todo path as a second argument:
      //   cp "<ourtodo>" <git-todo-path>
      'GIT_SEQUENCE_EDITOR': "cp '$todoPosix' ",
      // No-op editor for squash/fixup message prompts (kept identical via
      // core.editor too, for safety across git versions).
      'GIT_EDITOR': 'true',
    });

    try {
      final result = await Process.run(
        _runner.executable,
        args,
        workingDirectory: r.path,
        environment: env,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      final out = result.stdout.toString();
      final err = result.stderr.toString();
      if (result.exitCode == 0) {
        if (out.contains('is up to date') || out.contains('up to date')) {
          return const GitSuccess(RebaseUpToDate());
        }
        final head = (await _runner.run(r.path, ['rev-parse', 'HEAD'])).trim();
        return GitSuccess(RebaseApplied(CommitSha(head)));
      }
      final combined = out + err;
      if (combined.contains('CONFLICT') ||
          combined.contains('could not apply') ||
          combined.contains('Resolve all conflicts')) {
        return GitSuccess(RebaseConflict(await _listUnmergedPaths(r)));
      }
      final exc = GitProcessException(args, result.exitCode, err);
      return GitFailure(_classify(exc), err, err);
    } finally {
      try {
        tmpDir.deleteSync(recursive: true);
      } on Object {
        // Best-effort cleanup; ignore failures (e.g. locked files on Windows).
      }
    }
  }

  @override
  Future<GitResult<void>> rebaseAbort(RepoLocation r) async {
    return _runVoid(r, ['rebase', '--abort']);
  }

  @override
  Future<GitResult<CommitSha>> rebaseContinue(RepoLocation r) =>
      _runThenHead(r, ['-c', 'core.editor=true', 'rebase', '--continue']);

  @override
  Future<GitResult<void>> rebaseSkip(RepoLocation r) =>
      _runVoid(r, ['rebase', '--skip']);

  @override
  Future<GitResult<CherryPickOutcome>> cherryPick(
    RepoLocation r,
    CommitSha sha,
  ) async {
    // Use Process.run directly to capture stdout for conflict detection
    // (git may write CONFLICT to stdout).
    final result = await Process.run(
      _runner.executable, ['cherry-pick', sha.value],
      workingDirectory: r.path,
      environment: buildGitEnvironment(),
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final out = result.stdout.toString();
    final err = result.stderr.toString();
    if (result.exitCode == 0) {
      final head = (await _runner.run(r.path, ['rev-parse', 'HEAD'])).trim();
      return GitSuccess(CherryPickApplied(CommitSha(head)));
    }
    final combined = out + err;
    if (combined.contains('CONFLICT') ||
        combined.contains('after resolving the conflicts')) {
      return GitSuccess(CherryPickConflict(await _listUnmergedPaths(r)));
    }
    final exc = GitProcessException(
      ['cherry-pick', sha.value],
      result.exitCode,
      err,
    );
    return GitFailure(_classify(exc), err, err);
  }

  @override
  Future<GitResult<void>> cherryPickAbort(RepoLocation r) async {
    return _runVoid(r, ['cherry-pick', '--abort']);
  }

  @override
  Future<GitResult<CommitSha>> cherryPickContinue(RepoLocation r) =>
      _runThenHead(r, ['cherry-pick', '--continue']);

  @override
  Future<GitResult<RevertOutcome>> revert(
    RepoLocation r,
    CommitSha sha,
  ) async {
    final result = await Process.run(
      _runner.executable, ['revert', '--no-edit', sha.value],
      workingDirectory: r.path,
      environment: buildGitEnvironment(),
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final combined = '${result.stdout}\n${result.stderr}';
    if (result.exitCode == 0) {
      final head = (await _runner.run(r.path, ['rev-parse', 'HEAD'])).trim();
      return GitSuccess(RevertApplied(CommitSha(head)));
    }
    if (combined.contains('CONFLICT')) {
      final status = await _runner.run(
        r.path,
        ['diff', '--name-only', '--diff-filter=U'],
      );
      return GitSuccess(
        RevertConflict(
          status.split('\n').where((l) => l.isNotEmpty).toList(),
        ),
      );
    }
    return GitFailure(
      _classify(
        GitProcessException(
          ['revert'],
          result.exitCode,
          result.stderr.toString(),
        ),
      ),
      result.stderr.toString(),
      combined,
    );
  }

  @override
  Future<GitResult<void>> revertAbort(RepoLocation r) async {
    return _runVoid(r, ['revert', '--abort']);
  }

  @override
  Future<GitResult<CommitSha>> revertContinue(RepoLocation r) =>
      _runThenHead(r, ['revert', '--continue', '--no-edit']);

  @override
  Future<GitResult<void>> reset(
    RepoLocation r,
    CommitSha to,
    ResetMode mode,
  ) async {
    final flag = switch (mode) {
      ResetMode.soft => '--soft',
      ResetMode.mixed => '--mixed',
      ResetMode.hard => '--hard',
    };
    return _runVoid(r, ['reset', flag, to.value]);
  }
  @override
  Stream<GitProgress> clone(
    String url,
    String destination, {
    AuthSpec? auth,
  }) async* {
    final args = ['clone', '--progress', url, destination];
    await for (final p in _runProgressStream('.', args, auth: auth)) {
      yield p;
    }
  }
}
