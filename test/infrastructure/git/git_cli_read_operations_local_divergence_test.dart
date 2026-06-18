import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import '../../_helpers/repo_fixture.dart';

void main() {
  test('reports ahead/behind per local branch vs its upstream', () async {
    final seed = await RepoFixture.withLinearHistory(2);
    final bareDir = Directory.systemTemp.createTempSync('gitopen-test-bare-');
    await Process.run(
        'git', ['clone', '--bare', '--local', seed.path, bareDir.path]);
    try {
      await Process.run('git', ['remote', 'add', 'origin', bareDir.path],
          workingDirectory: seed.path);
      await Process.run('git', ['push', '-u', 'origin', 'master'],
          workingDirectory: seed.path);
      // master ahead by 1
      await Process.run('git', ['commit', '--allow-empty', '-m', 'ahead'],
          workingDirectory: seed.path);

      final ops = GitCliReadOperations();
      final div = await ops.localBranchDivergence(
          RepoLocation(const RepoId('r'), seed.path, 'w'));

      expect(div['master'], (ahead: 1, behind: 0));
    } finally {
      await seed.dispose();
      bareDir.deleteSync(recursive: true);
    }
  });

  test('omits branches in sync or without upstream', () async {
    final seed = await RepoFixture.withLinearHistory(1);
    try {
      final ops = GitCliReadOperations();
      final div = await ops.localBranchDivergence(
          RepoLocation(const RepoId('r'), seed.path, 'w'));
      expect(div, isEmpty);
    } finally {
      await seed.dispose();
    }
  });
}
