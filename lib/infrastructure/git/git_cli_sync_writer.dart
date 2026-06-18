import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/credential_helper.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/infrastructure/git/git_progress_parser.dart';
import 'package:gitopen/infrastructure/logging/app_logger.dart';

/// The remote-syncing streaming commands (fetch/pull/push/clone) with
/// progress parsing and in-app credential injection.  Moved verbatim from
/// `GitCliWriteOperations`.
final class GitCliSyncWriter {
  GitCliSyncWriter(this._runner);
  final GitProcessRunner _runner;

  Stream<GitProgress> fetch(
    RepoLocation r, {
    String? remote,
    bool all = false,
    AuthSpec? auth,
  }) async* {
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

  Stream<GitProgress> fetchRefspec(
    RepoLocation r,
    String remote,
    String refspec, {
    AuthSpec? auth,
  }) async* {
    final args = <String>['fetch', '--progress', remote, refspec];
    await for (final p in _runProgressStream(r.path, args, auth: auth)) {
      yield p;
    }
  }

  Stream<GitProgress> pull(
    RepoLocation r,
    PullStrategy strategy, {
    AuthSpec? auth,
  }) async* {
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

  Stream<GitProgress> push(
    RepoLocation r, {
    String? remote,
    String? branch,
    bool forceWithLease = false,
    bool pushTags = false,
    AuthSpec? auth,
  }) async* {
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

  /// `git push <remote> --delete <branch>` with progress + in-app credential
  /// injection (deleting a remote branch is a push and needs auth). [remoteRef]
  /// is `<remote>/<branch>` (e.g. "origin/feature").
  Stream<GitProgress> deleteRemoteBranch(
    RepoLocation r,
    String remoteRef, {
    AuthSpec? auth,
  }) async* {
    final slash = remoteRef.indexOf('/');
    final remoteName = slash < 0 ? remoteRef : remoteRef.substring(0, slash);
    final branch = slash < 0 ? '' : remoteRef.substring(slash + 1);
    final args = ['push', '--progress', remoteName, '--delete', branch];
    await for (final p in _runProgressStream(r.path, args, auth: auth)) {
      yield p;
    }
  }

  Stream<GitProgress> _runProgressStream(
    String cwd,
    List<String> args, {
    AuthSpec? auth,
  }) async* {
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
        .map(
          (a) => a.startsWith('http.extraheader=Authorization:')
              ? 'http.extraheader=Authorization: <redacted>'
              : a,
        )
        .join(' ');
    appLog.d(
      'git[progress] auth=${auth?.runtimeType ?? 'none'} '
      'env_keys=${helper.env.keys.toList()} '
      'cmd: git $redacted',
    );
    final stderrBuf = StringBuffer();
    try {
      final proc = await Process.start(
        _runner.executable,
        effectiveArgs,
        workingDirectory: cwd,
        environment: buildGitEnvironment(helper.env),
      );
      // Drain stdout so the process never blocks on a full pipe; awaited
      // before exitCode below so no output is lost to a race on exit.
      final stdoutDrained = proc.stdout.drain<void>();
      await for (final line
          in proc.stderr
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
      await stdoutDrained;
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
}
