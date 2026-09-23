import 'dart:convert';
import 'dart:io';

import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/infrastructure/git/git_result_runner.dart';
import 'package:path/path.dart' as p;

/// Builds a normal two-parent stash while leaving the real index untouched.
final class GitCliPartialStashWriter {
  GitCliPartialStashWriter(this._git);

  final GitResultRunner _git;

  Future<GitResult<void>> stashPatch(
    RepoLocation repo,
    List<String> patches,
    String message, {
    List<String>? worktreePatches,
  }) async {
    final toRemove = worktreePatches ?? patches;
    if (patches.isEmpty ||
        toRemove.length != patches.length ||
        patches.any((patch) => patch.trim().isEmpty) ||
        toRemove.any((patch) => patch.trim().isEmpty)) {
      return const GitFailure(
        GitErrorKind.invalidArgument,
        'No patch selected',
      );
    }
    Directory? temp;
    var removed = 0;
    try {
      final head = (await _run(repo, ['rev-parse', 'HEAD'])).trim();
      for (final patch in toRemove) {
        await _run(repo, ['apply', '--reverse', '--check', '-'], input: patch);
      }
      temp = await Directory.systemTemp.createTemp('gitopen-stash-');
      final env = {'GIT_INDEX_FILE': p.join(temp.path, 'index')};
      await _run(repo, ['read-tree', head], extraEnv: env);
      for (final patch in patches) {
        await _run(
          repo,
          ['apply', '--cached', '--whitespace=nowarn', '-'],
          input: patch,
          extraEnv: env,
        );
      }
      final worktreeTree = (await _run(repo, [
        'write-tree',
      ], extraEnv: env)).trim();
      final headTree = (await _run(repo, ['rev-parse', 'HEAD^{tree}'])).trim();
      if (worktreeTree == headTree) {
        return const GitFailure(
          GitErrorKind.invalidArgument,
          'No change selected',
        );
      }
      final indexCommit = (await _run(
        repo,
        ['commit-tree', headTree, '-p', head],
        input: 'index on $head\n',
      )).trim();
      final stashCommit = (await _run(
        repo,
        ['commit-tree', worktreeTree, '-p', head, '-p', indexCommit],
        input: 'On HEAD: $message\n',
      )).trim();

      // All fallible object construction and patch validation precedes any
      // worktree edit. The real index is never passed to a mutating command.
      for (final patch in toRemove) {
        await _run(
          repo,
          ['apply', '--reverse', '--whitespace=nowarn', '-'],
          input: patch,
        );
        removed++;
      }
      await _run(repo, ['stash', 'store', '-m', message, stashCommit]);
      return const GitSuccess(null);
    } on GitProcessException catch (e) {
      for (final patch in toRemove.take(removed).toList().reversed) {
        try {
          await _run(repo, ['apply', '--whitespace=nowarn', '-'], input: patch);
        } on Object {
          return GitFailure(
            GitErrorKind.other,
            'Stash failed and worktree restoration failed: ${e.stderr}',
          );
        }
      }
      return GitFailure(_git.classify(e), e.stderr, e.stderr);
    } on FileSystemException catch (e) {
      return GitFailure(GitErrorKind.other, e.message, '$e');
    } finally {
      if (temp != null) {
        try {
          await temp.delete(recursive: true);
        } on FileSystemException {
          // A temporary index can be cleaned up later by the OS.
        }
      }
    }
  }

  Future<String> _run(
    RepoLocation repo,
    List<String> args, {
    String? input,
    Map<String, String> extraEnv = const {},
  }) async {
    late final Process proc;
    try {
      proc = await Process.start(
        _git.runner.executable,
        args,
        workingDirectory: repo.path,
        environment: buildGitEnvironment(extraEnv),
      );
    } on ProcessException catch (e) {
      throw GitProcessException(args, -1, e.message);
    }
    if (input != null) proc.stdin.add(utf8.encode(input));
    await proc.stdin.close();
    final stdout = proc.stdout.transform(utf8.decoder).join();
    final stderr = proc.stderr.transform(utf8.decoder).join();
    final exit = await proc.exitCode;
    final out = await stdout;
    final err = await stderr;
    if (exit != 0) throw GitProcessException(args, exit, err);
    return out;
  }
}
