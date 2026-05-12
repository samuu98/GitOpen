import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  test('ff merge', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      await Process.run('git', ['checkout', '-b', 'feature'], workingDirectory: f.path);
      File(p.join(f.path, 'new.txt')).writeAsStringSync('hi');
      await Process.run('git', ['add', '.'], workingDirectory: f.path);
      await Process.run('git', ['commit', '-m', 'fea'], workingDirectory: f.path);
      await Process.run('git', ['checkout', 'master'], workingDirectory: f.path);
      final sut = GitCliWriteOperations();
      final res = await sut.merge(RepoLocation(RepoId.newId(), f.path, 't'), 'feature', ffOnly: true);
      expect(res, isA<GitSuccess>());
      expect((res as GitSuccess).value, isA<MergeFastForward>());
    } finally { await f.dispose(); }
  });

  test('3-way merge with conflict reports conflicted paths', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      // create branch and modify file
      await Process.run('git', ['checkout', '-b', 'feature'], workingDirectory: f.path);
      File(p.join(f.path, 'file_0.txt')).writeAsStringSync('branch version\n');
      await Process.run('git', ['commit', '-am', 'branch'], workingDirectory: f.path);
      // back to master, modify same line
      await Process.run('git', ['checkout', 'master'], workingDirectory: f.path);
      File(p.join(f.path, 'file_0.txt')).writeAsStringSync('master version\n');
      await Process.run('git', ['commit', '-am', 'master'], workingDirectory: f.path);
      final sut = GitCliWriteOperations();
      final res = await sut.merge(RepoLocation(RepoId.newId(), f.path, 't'), 'feature');
      expect(res, isA<GitSuccess>());
      final outcome = (res as GitSuccess).value as MergeOutcome;
      expect(outcome, isA<MergeConflict>());
      expect((outcome as MergeConflict).conflictedPaths, contains('file_0.txt'));
    } finally { await f.dispose(); }
  });
}
