import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import '../../_helpers/repo_fixture.dart';

void main() {
  test('deleteRemoteBranch removes the branch on the remote', () async {
    final seed = await RepoFixture.withLinearHistory(1);
    final bareDir = Directory.systemTemp.createTempSync('gitopen-test-bare-');
    await Process.run(
        'git', ['clone', '--bare', '--local', seed.path, bareDir.path]);
    try {
      await Process.run('git', ['remote', 'add', 'origin', bareDir.path],
          workingDirectory: seed.path);
      // Create and push a 'feature' branch to the remote.
      await Process.run('git', ['branch', 'feature'],
          workingDirectory: seed.path);
      await Process.run('git', ['push', 'origin', 'feature'],
          workingDirectory: seed.path);
      final before = await Process.run(
          'git', ['-C', bareDir.path, 'branch', '--list', 'feature']);
      expect((before.stdout as String).trim(), isNotEmpty);

      final sut = GitCliWriteOperations();
      await sut
          .deleteRemoteBranch(
            RepoLocation(RepoId.newId(), seed.path, 't'),
            'origin/feature',
          )
          .toList();

      final after = await Process.run(
          'git', ['-C', bareDir.path, 'branch', '--list', 'feature']);
      expect((after.stdout as String).trim(), isEmpty);
    } finally {
      await seed.dispose();
      bareDir.deleteSync(recursive: true);
    }
  });
}
