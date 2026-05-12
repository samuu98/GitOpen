import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  test('cherry-pick applies a commit from another branch', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      await Process.run('git', ['checkout', '-b', 'feature'], workingDirectory: f.path);
      File(p.join(f.path, 'cp.txt')).writeAsStringSync('hi');
      await Process.run('git', ['add', '.'], workingDirectory: f.path);
      await Process.run('git', ['commit', '-m', 'pick me'], workingDirectory: f.path);
      final featSha = (await Process.run('git', ['rev-parse', 'HEAD'], workingDirectory: f.path)).stdout.toString().trim();
      await Process.run('git', ['checkout', 'master'], workingDirectory: f.path);
      final sut = GitCliWriteOperations();
      final res = await sut.cherryPick(RepoLocation(RepoId.newId(), f.path, 't'), CommitSha(featSha));
      expect(res, isA<GitSuccess>());
      expect((res as GitSuccess).value, isA<CherryPickApplied>());
    } finally { await f.dispose(); }
  });

  test('reset --hard moves HEAD', () async {
    final f = await RepoFixture.withLinearHistory(3);
    try {
      final older = (await Process.run('git', ['rev-parse', 'HEAD~2'], workingDirectory: f.path)).stdout.toString().trim();
      final sut = GitCliWriteOperations();
      final res = await sut.reset(RepoLocation(RepoId.newId(), f.path, 't'), CommitSha(older), ResetMode.hard);
      expect(res, isA<GitSuccess>());
    } finally { await f.dispose(); }
  });
}
