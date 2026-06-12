import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git_lfs/git_cli_lfs_operations.dart';

import '../../_helpers/repo_fixture.dart';

void main() {
  test('track and untrack pattern when git lfs is available', () async {
    final version = await Process.run('git', ['lfs', 'version']);
    if (version.exitCode != 0) {
      markTestSkipped('git lfs is not installed');
      return;
    }

    final fixture = await RepoFixture.empty();
    addTearDown(fixture.dispose);
    final repo = RepoLocation(RepoId.newId(), fixture.path, 'repo');
    final sut = GitCliLfsOperations();

    await sut.installLocal(repo);
    await sut.track(repo, '*.bin');
    expect((await sut.trackedPatterns(repo)).single.pattern, '*.bin');
    await sut.untrack(repo, '*.bin');
    expect(await sut.trackedPatterns(repo), isEmpty);
  });
}
