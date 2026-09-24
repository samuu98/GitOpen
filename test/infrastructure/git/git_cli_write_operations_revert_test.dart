import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  test('revert conflict returns an unquoted path', () async {
    final f = await RepoFixture.empty();
    try {
      final file = File(p.join(f.path, 'café.txt'));
      await file.writeAsString('base\n');
      await Process.run('git', ['add', '-A'], workingDirectory: f.path);
      await Process.run('git', ['commit', '-qm', 'base'],
          workingDirectory: f.path);
      await file.writeAsString('first\n');
      await Process.run('git', ['commit', '-qam', 'first'],
          workingDirectory: f.path);
      final target = await Process.run('git', ['rev-parse', 'HEAD'],
          workingDirectory: f.path);
      await file.writeAsString('second\n');
      await Process.run('git', ['commit', '-qam', 'second'],
          workingDirectory: f.path);
      final result = await GitCliWriteOperations().revert(
          RepoLocation(RepoId.newId(), f.path, 't'),
          CommitSha((target.stdout as String).trim()));
      expect(result, isA<GitSuccess<RevertOutcome>>());
      expect((result as GitSuccess<RevertOutcome>).value,
          isA<RevertConflict>());
      expect((result.value as RevertConflict).conflictedPaths, ['café.txt']);
    } finally {
      await f.dispose();
    }
  });

  test('revert undoes a commit', () async {
    final f = await RepoFixture.withLinearHistory(2);
    try {
      final headSha = f.headSha;
      final sut = GitCliWriteOperations();
      final res = await sut.revert(
        RepoLocation(RepoId.newId(), f.path, 't'),
        CommitSha(headSha),
      );
      expect(res, isA<GitSuccess<RevertOutcome>>());
      expect((res as GitSuccess<RevertOutcome>).value, isA<RevertApplied>());
      // Verify the revert commit appears in the log
      final out = await Process.run(
        'git',
        ['log', '--oneline'],
        workingDirectory: f.path,
      );
      expect(out.stdout.toString(), contains('Revert'));
    } finally {
      await f.dispose();
    }
  });
}
