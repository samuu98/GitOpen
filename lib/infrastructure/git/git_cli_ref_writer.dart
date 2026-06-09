import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_result_runner.dart';

/// Ref bookkeeping (branch/remote/tag/stash CRUD, reset, submodule update)
/// for the write-operations facade.  Every command is a classified
/// fire-and-forget `runVoid`.  Moved verbatim from `GitCliWriteOperations`.
final class GitCliRefWriter {
  GitCliRefWriter(this._git);
  final GitResultRunner _git;

  Future<GitResult<void>> createBranch(
    RepoLocation r,
    String name, {
    CommitSha? at,
    bool checkout = false,
  }) {
    final args = checkout ? ['checkout', '-b', name] : ['branch', name];
    if (at != null) args.add(at.value);
    return _git.runVoid(r, args);
  }

  Future<GitResult<void>> checkout(
    RepoLocation r,
    String ref, {
    bool force = false,
  }) {
    final args = <String>['checkout'];
    if (force) args.add('--force');
    args.add(ref);
    return _git.runVoid(r, args);
  }

  Future<GitResult<void>> deleteBranch(
    RepoLocation r,
    String name, {
    bool force = false,
    bool remote = false,
  }) {
    if (remote) {
      // Delete remote branch via push --delete
      final parts = name.split('/');
      if (parts.length < 2) {
        return Future.value(const GitFailure(
          GitErrorKind.invalidArgument,
          'remote branch name must be <remote>/<branch>',
        ));
      }
      final remoteName = parts.first;
      final branchName = parts.sublist(1).join('/');
      return _git.runVoid(r, ['push', remoteName, '--delete', branchName]);
    }
    final flag = force ? '-D' : '-d';
    return _git.runVoid(r, ['branch', flag, name]);
  }

  Future<GitResult<void>> renameBranch(
    RepoLocation r,
    String oldName,
    String newName,
  ) =>
      _git.runVoid(r, ['branch', '-m', oldName, newName]);

  Future<GitResult<void>> setUpstream(
    RepoLocation r,
    String branch,
    String upstream,
  ) =>
      _git.runVoid(r, ['branch', '--set-upstream-to=$upstream', branch]);

  Future<GitResult<void>> addRemote(RepoLocation r, String name, String url) =>
      _git.runVoid(r, ['remote', 'add', name, url]);

  Future<GitResult<void>> removeRemote(RepoLocation r, String name) =>
      _git.runVoid(r, ['remote', 'remove', name]);

  Future<GitResult<void>> renameRemote(
    RepoLocation r,
    String oldName,
    String newName,
  ) =>
      _git.runVoid(r, ['remote', 'rename', oldName, newName]);

  Future<GitResult<void>> setRemoteUrl(
    RepoLocation r,
    String name,
    String url,
  ) =>
      _git.runVoid(r, ['remote', 'set-url', name, url]);

  Future<GitResult<void>> createTag(
    RepoLocation r,
    String name, {
    CommitSha? at,
    String? message,
  }) {
    final args = <String>['tag'];
    if (message != null) args.addAll(['-a', '-m', message]);
    args.add(name);
    if (at != null) args.add(at.value);
    return _git.runVoid(r, args);
  }

  Future<GitResult<void>> deleteTag(RepoLocation r, String name) =>
      _git.runVoid(r, ['tag', '-d', name]);

  Future<GitResult<void>> stashSave(
    RepoLocation r,
    String message, {
    bool includeUntracked = false,
  }) {
    final args = <String>['stash', 'push', '-m', message];
    if (includeUntracked) args.add('-u');
    return _git.runVoid(r, args);
  }

  Future<GitResult<void>> stashPop(RepoLocation r, int index) =>
      _git.runVoid(r, ['stash', 'pop', 'stash@{$index}']);

  Future<GitResult<void>> stashApply(RepoLocation r, int index) =>
      _git.runVoid(r, ['stash', 'apply', 'stash@{$index}']);

  Future<GitResult<void>> stashDrop(RepoLocation r, int index) =>
      _git.runVoid(r, ['stash', 'drop', 'stash@{$index}']);

  Future<GitResult<void>> reset(RepoLocation r, CommitSha to, ResetMode mode) {
    final flag = switch (mode) {
      ResetMode.soft => '--soft',
      ResetMode.mixed => '--mixed',
      ResetMode.hard => '--hard',
    };
    return _git.runVoid(r, ['reset', flag, to.value]);
  }

  Future<GitResult<void>> updateSubmodule(
    RepoLocation r,
    String path, {
    bool init = true,
  }) =>
      _git.runVoid(r, _submoduleUpdateArgs(init: init, path: path));

  Future<GitResult<void>> updateAllSubmodules(
    RepoLocation r, {
    bool init = true,
  }) =>
      _git.runVoid(r, _submoduleUpdateArgs(init: init));

  /// Builds the argv for `git submodule update`, optionally `--init` and
  /// optionally scoped to a single [path] (after `--`).
  ///
  /// We deliberately do NOT force `protocol.file.allow=always`: that would
  /// re-enable the local/`file://` submodule transport git disables by default
  /// (CVE-2022-39253 mitigation). Submodules over https/ssh initialize fine;
  /// users who genuinely vendor local-path submodules can opt in via their own
  /// `git config protocol.file.allow` rather than have the client weaken it
  /// for everyone.
  List<String> _submoduleUpdateArgs({required bool init, String? path}) {
    return <String>[
      'submodule', 'update',
      if (init) '--init',
      if (path != null) ...['--', path],
    ];
  }
}
