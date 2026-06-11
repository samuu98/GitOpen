import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/repo_fixture.dart';

void main() {
  test('countDivergence reports commits unique to each side', () async {
    // withBranches: master(3 commits) + feature(master tip + 1 commit).
    final f = await RepoFixture.withBranches();
    try {
      // Advance master by one more commit so BOTH sides have unique commits.
      await File(p.join(f.path, 'm.txt')).writeAsString('m\n');
      await Process.run('git', ['add', '-A'], workingDirectory: f.path);
      await Process.run(
        'git',
        ['commit', '-q', '-m', 'master only'],
        workingDirectory: f.path,
      );
      String sha(String ref) {
        final r = Process.runSync(
          'git',
          ['rev-parse', ref],
          workingDirectory: f.path,
        );
        return (r.stdout as String).trim();
      }

      final sut = GitCliReadOperations();
      final repo = RepoLocation(RepoId.newId(), f.path, 'fx');
      final d = await sut.countDivergence(
        repo,
        CommitSha(sha('master')),
        CommitSha(sha('feature')),
      );
      expect(d.left, 1); // 'master only'
      expect(d.right, 1); // 'on feature'

      final same = await sut.countDivergence(
        repo,
        CommitSha(sha('master')),
        CommitSha(sha('master')),
      );
      expect(same.left, 0);
      expect(same.right, 0);
    } finally {
      await f.dispose();
    }
  });
}
