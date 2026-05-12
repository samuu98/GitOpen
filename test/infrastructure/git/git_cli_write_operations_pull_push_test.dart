import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import '../../_helpers/repo_fixture.dart';

void main() {
  test('push to local bare remote succeeds', () async {
    final seed = await RepoFixture.withLinearHistory(1);
    // Create a bare remote
    final bareDir = Directory.systemTemp.createTempSync('gitopen-test-bare-');
    await Process.run(
        'git', ['clone', '--bare', '--local', seed.path, bareDir.path]);
    try {
      // Use seed as local; rewire its origin to bare
      await Process.run('git', ['remote', 'add', 'bare', bareDir.path],
          workingDirectory: seed.path);
      // Add a new commit in seed
      await Process.run(
          'git', ['commit', '--allow-empty', '-m', 'extra'],
          workingDirectory: seed.path);
      final sut = GitCliWriteOperations();
      await sut
          .push(
            RepoLocation(RepoId.newId(), seed.path, 't'),
            remote: 'bare',
            branch: 'master',
          )
          .toList();
      // Verify the bare has the new commit
      final log = await Process.run(
          'git', ['log', '-1', '--format=%s'],
          workingDirectory: bareDir.path);
      expect(log.stdout.toString().trim(), 'extra');
    } finally {
      await seed.dispose();
      bareDir.deleteSync(recursive: true);
    }
  });
}
