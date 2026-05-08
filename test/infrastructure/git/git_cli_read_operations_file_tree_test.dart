import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/files/file_tree_entry.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) =>
      RepoLocation(RepoId.newId(), f.path, 'test');

  group('GitCliReadOperations.getFileTree', () {
    test('lists root files for commit', () async {
      final f = await RepoFixture.withLinearHistory(3);
      try {
        final sut = GitCliReadOperations();
        final entries = await sut.getFileTree(loc(f), CommitSha(f.headSha), '');
        final names = entries.map((e) => e.name).toSet();
        expect(names, containsAll(['file_0.txt', 'file_1.txt', 'file_2.txt']));
        expect(entries.first.kind, FileTreeKind.blob);
      } finally { await f.dispose(); }
    });
  });
}
