import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) => RepoLocation(RepoId.newId(), f.path, 't');

  Future<RepoFixture> conflictFixture() async {
    final f = await RepoFixture.empty();
    Future<void> git(List<String> args) async {
      final r = await Process.run('git', args, workingDirectory: f.path);
      if (args.first != 'merge') {
        expect(r.exitCode, 0, reason: '${args.join(' ')}: ${r.stderr}');
      }
    }

    final file = File(p.join(f.path, 'clash.txt'));
    await file.writeAsString('base\n');
    await git(['add', 'clash.txt']);
    await git(['commit', '-q', '-m', 'base']);
    await git(['checkout', '-q', '-b', 'feature']);
    await file.writeAsString('theirs\n');
    await git(['add', 'clash.txt']);
    await git(['commit', '-q', '-m', 'feature edit']);
    await git(['checkout', '-q', 'master']);
    await file.writeAsString('ours\n');
    await git(['add', 'clash.txt']);
    await git(['commit', '-q', '-m', 'master edit']);
    await git(['merge', 'feature']);
    return f;
  }

  group('takeConflictSide', () {
    test('ours keeps our content and stages the file', () async {
      final f = await conflictFixture();
      try {
        final sut = GitCliWriteOperations();
        final res =
            await sut.takeConflictSide(loc(f), 'clash.txt', ours: true);

        expect(res, isA<GitSuccess<void>>());
        final content = await File(p.join(f.path, 'clash.txt')).readAsString();
        expect(content.trim(), 'ours');
        final status = await Process.run(
          'git',
          ['status', '--porcelain'],
          workingDirectory: f.path,
        );
        expect(status.stdout.toString(), isNot(contains('UU clash.txt')));
      } finally {
        await f.dispose();
      }
    });

    test('theirs takes the incoming content', () async {
      final f = await conflictFixture();
      try {
        final sut = GitCliWriteOperations();
        final res =
            await sut.takeConflictSide(loc(f), 'clash.txt', ours: false);

        expect(res, isA<GitSuccess<void>>());
        final content = await File(p.join(f.path, 'clash.txt')).readAsString();
        expect(content.trim(), 'theirs');
      } finally {
        await f.dispose();
      }
    });
  });

  group('discardPatch', () {
    test('reverses a working-tree change', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        await File(p.join(f.path, 'file_0.txt'))
            .writeAsString('content 0\nextra\n');
        final diff = await Process.run(
          'git',
          ['diff'],
          workingDirectory: f.path,
        );
        final sut = GitCliWriteOperations();
        final res = await sut.discardPatch(loc(f), diff.stdout.toString());

        expect(res, isA<GitSuccess<void>>());
        final content =
            await File(p.join(f.path, 'file_0.txt')).readAsString();
        expect(content.replaceAll('\r\n', '\n'), 'content 0\n');
      } finally {
        await f.dispose();
      }
    });
  });
}
