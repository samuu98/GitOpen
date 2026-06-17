import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';

import '../../_helpers/repo_fixture.dart';

void main() {
  test('getRemotes parses real `git remote -v` (tab name, space + (fetch))',
      () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      // Real git writes:  origin<TAB>url<SPACE>(fetch)  — not two tabs.
      final add = await Process.run(
        'git',
        ['remote', 'add', 'origin', 'https://example.com/x.git'],
        workingDirectory: f.path,
      );
      expect(add.exitCode, 0, reason: '${add.stderr}');

      final ops = GitCliReadOperations(runner: GitProcessRunner());
      final repo = RepoLocation(RepoId.newId(), f.path, 'x');
      final remotes = await ops.getRemotes(repo);

      expect(remotes, hasLength(1));
      expect(remotes.single.name, 'origin');
      expect(remotes.single.url, 'https://example.com/x.git');
    } finally {
      await f.dispose();
    }
  });
}
