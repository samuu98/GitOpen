import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_stash_safety_operations.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/repo_fixture.dart';

Future<ProcessResult> git(String cwd, List<String> args) =>
    Process.run('git', args, workingDirectory: cwd);

void main() {
  test(
    'overlap saves local edits and keeps both on a restore conflict',
    () async {
      final fixture = await RepoFixture.withLinearHistory(1);
      addTearDown(fixture.dispose);
      final repo = RepoLocation(RepoId.newId(), fixture.path, 'repo');
      final file = File(p.join(fixture.path, 'file_0.txt'));
      await file.writeAsString('stash edit\n');
      expect(
        (await git(fixture.path, ['stash', 'push', '-m', 'target'])).exitCode,
        0,
      );
      await file.writeAsString('local edit\n');

      final safety = GitCliStashSafetyOperations();
      final overlap = await safety.overlap(repo, 0);
      expect(overlap, isA<GitSuccess<List<String>>>());
      expect((overlap as GitSuccess<List<String>>).value, ['file_0.txt']);

      final result = await safety.applyPreservingLocal(repo, 0, pop: true);
      expect(result, isA<GitSuccess<StashRestoreResult>>());
      final restored = (result as GitSuccess<StashRestoreResult>).value;
      final contents = await file.readAsString();
      if (restored.hasConflict) {
        expect(restored.localStash, isNotNull);
        expect(contents, contains('local edit'));
        expect(contents, contains('stash edit'));
        final list = await git(fixture.path, ['stash', 'list']);
        expect(list.stdout.toString(), contains('GitOpen local edits'));
      } else {
        expect(contents, contains('local edit'));
        expect(contents, contains('stash edit'));
      }
      final target = await git(fixture.path, ['stash', 'list']);
      if (restored.hasConflict) {
        expect(target.stdout.toString(), contains('target'));
      }
    },
  );

  test('failure after local backup retains local and target stashes', () async {
    final fixture = await RepoFixture.withLinearHistory(1);
    addTearDown(fixture.dispose);
    final repo = RepoLocation(RepoId.newId(), fixture.path, 'repo');
    final file = File(p.join(fixture.path, 'file_0.txt'));
    await file.writeAsString('stash edit\n');
    expect(
      (await git(fixture.path, ['stash', 'push', '-m', 'target'])).exitCode,
      0,
    );
    await file.writeAsString('local edit\n');

    final result = await GitCliStashSafetyOperations(
      runner: _FailApplyRunner(),
    ).applyPreservingLocal(repo, 0, pop: true);
    expect(result, isA<GitFailure<StashRestoreResult>>());
    final list = await git(fixture.path, ['stash', 'list']);
    expect(list.stdout.toString(), contains('target'));
    expect(list.stdout.toString(), contains('GitOpen local edits'));
    final backup = await git(fixture.path, [
      'stash',
      'show',
      '-p',
      'stash@{0}',
    ]);
    expect(backup.stdout.toString(), contains('local edit'));
  });

  test('non-overlapping stash leaves plain pop behavior available', () async {
    final fixture = await RepoFixture.withLinearHistory(2);
    addTearDown(fixture.dispose);
    final repo = RepoLocation(RepoId.newId(), fixture.path, 'repo');
    await File(
      p.join(fixture.path, 'file_0.txt'),
    ).writeAsString('stash edit\n');
    expect(
      (await git(fixture.path, ['stash', 'push', '-m', 'target'])).exitCode,
      0,
    );
    await File(
      p.join(fixture.path, 'file_1.txt'),
    ).writeAsString('local edit\n');

    final overlap = await GitCliStashSafetyOperations().overlap(repo, 0);
    expect((overlap as GitSuccess<List<String>>).value, isEmpty);
    final popped = await GitCliWriteOperations().stashPop(repo, 0);
    expect(popped, isA<GitSuccess<void>>());
    expect(
      (await File(
        p.join(fixture.path, 'file_0.txt'),
      ).readAsString()).replaceAll('\r\n', '\n'),
      'stash edit\n',
    );
    expect(
      await File(p.join(fixture.path, 'file_1.txt')).readAsString(),
      'local edit\n',
    );
    expect(
      (await git(fixture.path, ['stash', 'list'])).stdout.toString(),
      isEmpty,
    );
  });

  test('overlap includes untracked files stored in the stash', () async {
    final fixture = await RepoFixture.withLinearHistory(1);
    addTearDown(fixture.dispose);
    final repo = RepoLocation(RepoId.newId(), fixture.path, 'repo');
    final file = File(p.join(fixture.path, 'folder', 'new.txt'));
    await file.parent.create();
    await file.writeAsString('stash version\n');
    expect(
      (await git(fixture.path, [
        'stash',
        'push',
        '-u',
        '-m',
        'target',
      ])).exitCode,
      0,
    );
    await file.parent.create();
    await file.writeAsString('local version\n');

    final overlap = await GitCliStashSafetyOperations().overlap(repo, 0);
    expect((overlap as GitSuccess<List<String>>).value, ['folder/new.txt']);
  });

  test('clean merge restores the original staged selection', () async {
    final fixture = await RepoFixture.withLinearHistory(1);
    addTearDown(fixture.dispose);
    final repo = RepoLocation(RepoId.newId(), fixture.path, 'repo');
    final file = File(p.join(fixture.path, 'file_0.txt'));
    final base = List.generate(30, (i) => 'line $i').join('\n');
    await file.writeAsString('$base\n');
    expect((await git(fixture.path, ['add', 'file_0.txt'])).exitCode, 0);
    expect(
      (await git(fixture.path, ['commit', '-qm', 'long file'])).exitCode,
      0,
    );
    await file.writeAsString('${base.replaceFirst('line 0', 'target')}\n');
    expect(
      (await git(fixture.path, ['stash', 'push', '-m', 'target'])).exitCode,
      0,
    );
    await file.writeAsString('${base.replaceFirst('line 29', 'local')}\n');
    expect((await git(fixture.path, ['add', 'file_0.txt'])).exitCode, 0);

    final result = await GitCliStashSafetyOperations().applyPreservingLocal(
      repo,
      0,
      pop: true,
    );
    expect(result, isA<GitSuccess<StashRestoreResult>>());
    expect(
      (result as GitSuccess<StashRestoreResult>).value.hasConflict,
      isFalse,
    );
    final contents = await file.readAsString();
    expect(contents, contains('target'));
    expect(contents, contains('local'));
    final staged = await git(fixture.path, [
      'diff',
      '--cached',
      '--',
      'file_0.txt',
    ]);
    expect(staged.stdout.toString(), contains('+local'));
    expect(staged.stdout.toString(), isNot(contains('+target')));
    expect(
      (await git(fixture.path, ['stash', 'list'])).stdout.toString(),
      isEmpty,
    );
  });

  test('failed target cleanup reports local edits in worktree', () async {
    final fixture = await RepoFixture.withLinearHistory(1);
    addTearDown(fixture.dispose);
    final repo = RepoLocation(RepoId.newId(), fixture.path, 'repo');
    final file = File(p.join(fixture.path, 'file_0.txt'));
    final base = List.generate(30, (i) => 'line $i').join('\n');
    await file.writeAsString('$base\n');
    expect((await git(fixture.path, ['add', 'file_0.txt'])).exitCode, 0);
    expect(
      (await git(fixture.path, ['commit', '-qm', 'long file'])).exitCode,
      0,
    );
    await file.writeAsString('${base.replaceFirst('line 0', 'target')}\n');
    expect(
      (await git(fixture.path, ['stash', 'push', '-m', 'target'])).exitCode,
      0,
    );
    await file.writeAsString('${base.replaceFirst('line 29', 'local')}\n');

    final result = await GitCliStashSafetyOperations(
      runner: _FailSecondDropRunner(),
    ).applyPreservingLocal(repo, 0, pop: true);
    expect(result, isA<GitFailure<StashRestoreResult>>());
    expect(
      (result as GitFailure<StashRestoreResult>).message,
      contains('Local edits are in the worktree'),
    );
    final contents = await file.readAsString();
    expect(contents, contains('target'));
    expect(contents, contains('local'));
    final list = await git(fixture.path, ['stash', 'list']);
    expect(list.stdout.toString(), contains('target'));
  });
}

class _FailApplyRunner extends GitProcessRunner {
  final GitProcessRunner _real = GitProcessRunner();

  @override
  Future<String> run(
    String workingDir,
    List<String> args, {
    Duration? timeout,
  }) {
    if (args.length >= 3 && args[0] == 'stash' && args[1] == 'apply') {
      throw GitProcessException(args, 1, 'injected failure');
    }
    return _real.run(workingDir, args, timeout: timeout);
  }
}

class _FailSecondDropRunner extends GitProcessRunner {
  final GitProcessRunner _real = GitProcessRunner();
  int drops = 0;

  @override
  Future<String> run(
    String workingDir,
    List<String> args, {
    Duration? timeout,
  }) {
    if (args.length >= 2 && args[0] == 'stash' && args[1] == 'drop') {
      drops++;
      if (drops == 2) {
        throw GitProcessException(args, 1, 'injected cleanup failure');
      }
    }
    return _real.run(workingDir, args, timeout: timeout);
  }
}
