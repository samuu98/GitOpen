import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/repo_fixture.dart';

/// Regression coverage for the `--continue` family, driven from the conflict
/// panel's "Continue" button.
///
/// `git merge --continue` rejects every other argument ("fatal: --continue
/// expects no arguments"), unlike `cherry-pick`/`revert --continue` which do
/// accept `--no-edit`. The merge call passed `--no-edit` and so ALWAYS failed:
/// resolving a merge conflict left the user stuck on the conflict panel with
/// that error. The sibling commands are covered too so the next arg change to
/// any of them can't silently break Continue the same way.
///
/// Each fixture also configures a *failing* `core.editor`, standing in for the
/// interactive editor a user may have set. git only auto-opens the merge
/// editor when it has a terminal — which a desktop app never does — so this
/// asserts the property rather than reproducing a known break.
void main() {
  RepoLocation loc(RepoFixture f) => RepoLocation(RepoId.newId(), f.path, 't');

  Future<String> git(RepoFixture f, List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: f.path);
    return '${r.stdout}${r.stderr}';
  }

  /// Makes any editor launch fail, standing in for a real interactive editor
  /// (which would block instead). Repo-level config, so a command-line
  /// `-c core.editor=...` still overrides it — which is exactly the contract
  /// under test.
  Future<void> installFailingEditor(RepoFixture f) =>
      git(f, ['config', 'core.editor', 'false']);

  Future<void> commitFile(RepoFixture f, String name, String body) async {
    await File(p.join(f.path, name)).writeAsString(body);
    await git(f, ['add', name]);
    await git(f, ['commit', '-q', '-m', 'add $name']);
  }

  /// base -> feature edit / master edit on the same line, so [op] conflicts.
  Future<RepoFixture> conflictedThenResolved(
    List<String> Function(String featureSha) op,
  ) async {
    final f = await RepoFixture.empty();
    final file = File(p.join(f.path, 'clash.txt'));
    await commitFile(f, 'clash.txt', 'base\n');
    await git(f, ['checkout', '-q', '-b', 'feature']);
    await file.writeAsString('theirs\n');
    await git(f, ['commit', '-qam', 'feature edit']);
    final featureSha =
        (await git(f, ['rev-parse', 'HEAD'])).trim();
    await git(f, ['checkout', '-q', 'master']);
    await file.writeAsString('ours\n');
    await git(f, ['commit', '-qam', 'master edit']);

    await installFailingEditor(f);
    await git(f, op(featureSha)); // conflicts
    // The user resolves the conflict and stages the result.
    await file.writeAsString('resolved\n');
    await git(f, ['add', 'clash.txt']);
    return f;
  }

  void expectSuccess(GitResult<CommitSha> res) => expect(
        res,
        isA<GitSuccess<CommitSha>>(),
        reason: res is GitFailure<CommitSha> ? res.message : null,
      );

  group('sequencer --continue', () {
    test('mergeContinue concludes a resolved merge', () async {
      final f = await conflictedThenResolved((_) => ['merge', 'feature']);
      try {
        expectSuccess(await GitCliWriteOperations().mergeContinue(loc(f)));

        // MERGE_HEAD gone => the merge really was concluded, and the new HEAD
        // is a merge commit (two parents).
        expect(
          File(p.join(f.path, '.git', 'MERGE_HEAD')).existsSync(),
          isFalse,
        );
        final parents =
            await git(f, ['rev-list', '--parents', '-n', '1', 'HEAD']);
        expect(parents.trim().split(RegExp(r'\s+')).length, 3);
      } finally {
        await f.dispose();
      }
    });

    test('cherryPickContinue concludes a resolved cherry-pick', () async {
      final f = await conflictedThenResolved((sha) => ['cherry-pick', sha]);
      try {
        expectSuccess(await GitCliWriteOperations().cherryPickContinue(loc(f)));

        expect(
          Directory(p.join(f.path, '.git', 'sequencer')).existsSync(),
          isFalse,
        );
        expect(
          File(p.join(f.path, '.git', 'CHERRY_PICK_HEAD')).existsSync(),
          isFalse,
        );
      } finally {
        await f.dispose();
      }
    });

    test('revertContinue concludes a resolved revert', () async {
      // Revert needs its own shape: revert the commit that introduced a line
      // after a later commit touched the same line.
      final f = await RepoFixture.empty();
      try {
        final file = File(p.join(f.path, 'clash.txt'));
        await commitFile(f, 'clash.txt', 'base\n');
        await file.writeAsString('second\n');
        await git(f, ['commit', '-qam', 'second']);
        final target = (await git(f, ['rev-parse', 'HEAD'])).trim();
        await file.writeAsString('third\n');
        await git(f, ['commit', '-qam', 'third']);

        await installFailingEditor(f);
        await git(f, ['revert', '--no-edit', target]); // conflicts
        await file.writeAsString('resolved\n');
        await git(f, ['add', 'clash.txt']);

        expectSuccess(await GitCliWriteOperations().revertContinue(loc(f)));

        expect(
          File(p.join(f.path, '.git', 'REVERT_HEAD')).existsSync(),
          isFalse,
        );
      } finally {
        await f.dispose();
      }
    });
  });
}
