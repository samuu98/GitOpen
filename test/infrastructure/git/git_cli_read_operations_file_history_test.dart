import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) => RepoLocation(RepoId.newId(), f.path, 'test');

  group('getFileHistory', () {
    test('returns only commits that touched the file, newest first', () async {
      final f = await RepoFixture.withLinearHistory(3);
      try {
        // Touch file_0.txt again in a fourth commit.
        File(p.join(f.path, 'file_0.txt')).writeAsStringSync('updated\n');
        await Process.run('git', ['add', 'file_0.txt'],
            workingDirectory: f.path);
        await Process.run('git', ['commit', '-q', '-m', 'update file_0'],
            workingDirectory: f.path);

        final sut = GitCliReadOperations();
        final history = await sut.getFileHistory(loc(f), 'file_0.txt');
        expect(history, hasLength(2));
        expect(history.first.summary, 'update file_0');
        expect(history.last.summary, 'commit 0');
      } finally {
        await f.dispose();
      }
    });

    test('follows renames', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        await Process.run('git', ['mv', 'file_0.txt', 'renamed.txt'],
            workingDirectory: f.path);
        await Process.run('git', ['commit', '-q', '-m', 'rename'],
            workingDirectory: f.path);

        final sut = GitCliReadOperations();
        final history = await sut.getFileHistory(loc(f), 'renamed.txt');
        expect(history, hasLength(2));
        expect(history.map((c) => c.summary), contains('commit 0'));
      } finally {
        await f.dispose();
      }
    });

    test('respects the limit', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        for (var i = 0; i < 3; i++) {
          File(p.join(f.path, 'file_0.txt')).writeAsStringSync('v$i\n');
          await Process.run('git', ['add', 'file_0.txt'],
              workingDirectory: f.path);
          await Process.run('git', ['commit', '-q', '-m', 'edit $i'],
              workingDirectory: f.path);
        }
        final sut = GitCliReadOperations();
        final history =
            await sut.getFileHistory(loc(f), 'file_0.txt', limit: 2);
        expect(history, hasLength(2));
        expect(history.first.summary, 'edit 2');
      } finally {
        await f.dispose();
      }
    });

    test('returns empty list for unknown path', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final sut = GitCliReadOperations();
        final history = await sut.getFileHistory(loc(f), 'missing.txt');
        expect(history, isEmpty);
      } finally {
        await f.dispose();
      }
    });
  });
}
