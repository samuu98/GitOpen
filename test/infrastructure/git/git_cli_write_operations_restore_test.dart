import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) => RepoLocation(RepoId.newId(), f.path, 'test');

  group('restoreFileAt', () {
    test('restores file content from an older commit, unstaged', () async {
      final f = await RepoFixture.withLinearHistory(2);
      try {
        // file_0.txt was created in commit 0 with "content 0\n"; overwrite
        // it at HEAD so restoring from the first commit is observable.
        final firstShaOut = await Process.run(
            'git', ['rev-list', '--max-parents=0', 'HEAD'],
            workingDirectory: f.path);
        final firstSha = firstShaOut.stdout.toString().trim();
        File(p.join(f.path, 'file_0.txt')).writeAsStringSync('overwritten\n');
        await Process.run('git', ['add', 'file_0.txt'],
            workingDirectory: f.path);
        await Process.run('git', ['commit', '-q', '-m', 'overwrite'],
            workingDirectory: f.path);

        final sut = GitCliWriteOperations();
        final res = await sut
            .restoreFileAt(loc(f), CommitSha(firstSha), ['file_0.txt']);
        expect(res, isA<GitSuccess<void>>());
        // core.autocrlf may rewrite line endings on checkout — normalize.
        final restored = File(p.join(f.path, 'file_0.txt'))
            .readAsStringSync()
            .replaceAll('\r\n', '\n');
        expect(restored, 'content 0\n');
        // Restored content must be unstaged (working tree only).
        final status = await Process.run('git', ['status', '--porcelain'],
            workingDirectory: f.path);
        expect(status.stdout.toString(), contains(' M file_0.txt'));
      } finally {
        await f.dispose();
      }
    });

    test('fails on a path that does not exist at the commit', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final sut = GitCliWriteOperations();
        final res = await sut
            .restoreFileAt(loc(f), CommitSha(f.headSha), ['nope.txt']);
        expect(res, isA<GitFailure<void>>());
      } finally {
        await f.dispose();
      }
    });

    test('empty path list is a no-op success', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final sut = GitCliWriteOperations();
        final res =
            await sut.restoreFileAt(loc(f), CommitSha(f.headSha), const []);
        expect(res, isA<GitSuccess<void>>());
      } finally {
        await f.dispose();
      }
    });
  });
}
