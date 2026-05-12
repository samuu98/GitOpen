import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  test('stashSave + stashPop', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      File(p.join(f.path, 'file_0.txt')).writeAsStringSync('changed');
      final sut = GitCliWriteOperations();
      final saved = await sut.stashSave(RepoLocation(RepoId.newId(), f.path, 't'), 'my stash');
      expect(saved, isA<GitSuccess>());
      final list = await Process.run('git', ['stash', 'list'], workingDirectory: f.path);
      expect(list.stdout.toString(), contains('my stash'));
      final popped = await sut.stashPop(RepoLocation(RepoId.newId(), f.path, 't'), 0);
      expect(popped, isA<GitSuccess>());
    } finally { await f.dispose(); }
  });
}
