import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/diff/build_patch_for_lines.dart';
import 'package:gitopen/application/git/build_stash_worktree_patch.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) => RepoLocation(RepoId.newId(), f.path, 't');

  test('stashSave + stashPop', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      File(p.join(f.path, 'file_0.txt')).writeAsStringSync('changed');
      final sut = GitCliWriteOperations();
      final saved = await sut.stashSave(loc(f), 'my stash');
      expect(saved, isA<GitSuccess<void>>());
      final list = await Process.run(
        'git',
        ['stash', 'list'],
        workingDirectory: f.path,
      );
      expect(list.stdout.toString(), contains('my stash'));
      final popped = await sut.stashPop(loc(f), 0);
      expect(popped, isA<GitSuccess<void>>());
    } finally {
      await f.dispose();
    }
  });

  test('stashSave can scope the stash to selected paths', () async {
    final f = await RepoFixture.withLinearHistory(2);
    try {
      File(p.join(f.path, 'file_0.txt')).writeAsStringSync('changed 0\n');
      File(p.join(f.path, 'file_1.txt')).writeAsStringSync('changed 1\n');

      final sut = GitCliWriteOperations();
      final saved = await sut.stashSave(
        loc(f),
        'partial',
        paths: ['file_0.txt'],
      );

      expect(saved, isA<GitSuccess<void>>());
      expect(
        File(
          p.join(f.path, 'file_0.txt'),
        ).readAsStringSync().replaceAll('\r\n', '\n'),
        'content 0\n',
      );
      expect(
        File(p.join(f.path, 'file_1.txt')).readAsStringSync(),
        'changed 1\n',
      );

      final diff = await Process.run(
        'git',
        ['stash', 'show', '--name-only', 'stash@{0}'],
        workingDirectory: f.path,
      );
      final stdout = diff.stdout.toString();
      expect(stdout, contains('file_0.txt'));
      expect(stdout, isNot(contains('file_1.txt')));
    } finally {
      await f.dispose();
    }
  });

  test(
    'stashPatch stores one hunk without touching another or the index',
    () async {
      final f = await RepoFixture.withLinearHistory(2);
      try {
        final file = File(p.join(f.path, 'file_0.txt'));
        final middle = 'middle\n' * 12;
        await file.writeAsString(
          'changed first\n${middle}changed last\n',
        );
        await Process.run('git', [
          'add',
          'file_0.txt',
        ], workingDirectory: f.path);
        await Process.run('git', [
          'commit',
          '-m',
          'long file',
        ], workingDirectory: f.path);
        await file.writeAsString(
          'selected first\n${middle}other last\n',
        );
        final staged = File(p.join(f.path, 'file_1.txt'));
        await staged.writeAsString('staged only\n');
        await Process.run('git', [
          'add',
          'file_1.txt',
        ], workingDirectory: f.path);
        final untracked = File(p.join(f.path, 'untracked.txt'));
        await untracked.writeAsString('keep me\n');
        final diff = await Process.run('git', [
          'diff',
          '-U3',
          '--',
          'file_0.txt',
        ], workingDirectory: f.path);
        final parts = diff.stdout.toString().split(
          RegExp('(?=^@@ )', multiLine: true),
        );
        expect(parts, hasLength(3));
        final patch = '${parts[0]}${parts[1]}';
        final saved = await GitCliWriteOperations().stashPatch(loc(f), [
          patch,
        ], 'selected');
        expect(saved, isA<GitSuccess<void>>());
        expect(
          (await file.readAsString()).replaceAll('\r\n', '\n'),
          'changed first\n${middle}other last\n',
        );
        expect(await staged.readAsString(), 'staged only\n');
        expect(await untracked.readAsString(), 'keep me\n');
        final cached = await Process.run('git', [
          'diff',
          '--cached',
          '--name-only',
        ], workingDirectory: f.path);
        expect(cached.stdout.toString().trim(), 'file_1.txt');
        final show = await Process.run('git', [
          'stash',
          'show',
          '--name-only',
        ], workingDirectory: f.path);
        expect(show.stdout.toString().trim(), 'file_0.txt');
        await Process.run('git', [
          'add',
          'file_0.txt',
        ], workingDirectory: f.path);
        final commit = await Process.run('git', [
          'commit',
          '-m',
          'keep other changes',
        ], workingDirectory: f.path);
        expect(commit.exitCode, 0, reason: commit.stderr.toString());
        final pop = await Process.run('git', [
          'stash',
          'pop',
        ], workingDirectory: f.path);
        expect(pop.exitCode, 0, reason: pop.stderr.toString());
        expect(
          (await file.readAsString()).replaceAll('\r\n', '\n'),
          'selected first\n${middle}other last\n',
        );
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'stashPatch failure preserves worktree, index, and stash list',
    () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final file = File(p.join(f.path, 'file_0.txt'));
        await file.writeAsString('local edit\n');
        final before = await Process.run('git', [
          'status',
          '--porcelain',
        ], workingDirectory: f.path);
        final result = await GitCliWriteOperations().stashPatch(loc(f), [
          'invalid patch',
        ], 'bad');
        expect(result, isA<GitFailure<void>>());
        expect(await file.readAsString(), 'local edit\n');
        final after = await Process.run('git', [
          'status',
          '--porcelain',
        ], workingDirectory: f.path);
        expect(after.stdout, before.stdout);
        final list = await Process.run('git', [
          'stash',
          'list',
        ], workingDirectory: f.path);
        expect(list.stdout.toString(), isEmpty);
      } finally {
        await f.dispose();
      }
    },
  );

  test('stashPatch stores one selected line beside another', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      final file = File(p.join(f.path, 'file_0.txt'));
      await file.writeAsString('content 0\nselected\nother\n');
      const hunk = DiffHunk(
        oldStart: 1,
        oldCount: 1,
        newStart: 1,
        newCount: 3,
        header: '@@ -1 +1,3 @@',
        lines: [
          DiffLine(kind: DiffLineKind.context, content: 'content 0'),
          DiffLine(kind: DiffLineKind.addition, content: 'selected'),
          DiffLine(kind: DiffLineKind.addition, content: 'other'),
        ],
      );
      final patch = buildPatchForLines('file_0.txt', hunk, {1});
      final result = await GitCliWriteOperations().stashPatch(
        loc(f),
        [patch],
        'one line',
        worktreePatches: [
          buildStashWorktreePatch('file_0.txt', hunk, {1}),
        ],
      );
      expect(
        result,
        isA<GitSuccess<void>>(),
        reason: result is GitFailure<void> ? result.message : null,
      );
      expect(
        (await file.readAsString()).replaceAll('\r\n', '\n'),
        'content 0\nother\n',
      );
      final diff = await Process.run(
        'git',
        ['stash', 'show', '-p'],
        workingDirectory: f.path,
      );
      expect(diff.stdout.toString(), contains('+selected'));
      expect(diff.stdout.toString(), isNot(contains('+other')));
    } finally {
      await f.dispose();
    }
  });

  test('stashSave staged only preserves unstaged changes', () async {
    final f = await RepoFixture.withLinearHistory(2);
    try {
      final staged = File(p.join(f.path, 'file_0.txt'));
      final unstaged = File(p.join(f.path, 'file_1.txt'));
      await staged.writeAsString('staged\n');
      await Process.run('git', ['add', 'file_0.txt'], workingDirectory: f.path);
      await unstaged.writeAsString('unstaged\n');
      final saved = await GitCliWriteOperations().stashSave(
        loc(f),
        'staged',
        stagedOnly: true,
      );
      expect(saved, isA<GitSuccess<void>>());
      expect(await unstaged.readAsString(), 'unstaged\n');
      final cached = await Process.run('git', [
        'diff',
        '--cached',
        '--name-only',
      ], workingDirectory: f.path);
      expect(cached.stdout.toString(), isEmpty);
      final show = await Process.run('git', [
        'stash',
        'show',
        '--name-only',
      ], workingDirectory: f.path);
      expect(show.stdout.toString().trim(), 'file_0.txt');
    } finally {
      await f.dispose();
    }
  });
}
