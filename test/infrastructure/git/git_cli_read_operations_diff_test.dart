import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/diff/file_diff.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) =>
      RepoLocation(RepoId.newId(), f.path, 'test');

  group('GitCliReadOperations.getDiff', () {
    test('commit vs parent lists added file', () async {
      final f = await RepoFixture.withLinearHistory(2);
      try {
        final sut = GitCliReadOperations();
        final diff = await sut.getDiff(loc(f),
            DiffSpecCommitVsParent(CommitSha(f.headSha)));
        final added = diff.files.where((d) => d.path == 'file_1.txt');
        expect(added, hasLength(1));
        expect(added.first.changeKind, FileChangeKind.added);
      } finally { await f.dispose(); }
    });

    test('initial commit (no parent) lists all added', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final sut = GitCliReadOperations();
        final diff = await sut.getDiff(loc(f),
            DiffSpecCommitVsParent(CommitSha(f.headSha)));
        expect(diff.files, hasLength(1));
        expect(diff.files.first.path, 'file_0.txt');
        expect(diff.files.first.changeKind, FileChangeKind.added);
      } finally { await f.dispose(); }
    });

    test('getDiffForFile returns only the named file, untruncated', () async {
      final f = await RepoFixture.withMergeCommit();
      try {
        final sut = GitCliReadOperations();
        final result = await sut.getDiffForFile(
          loc(f),
          DiffSpecCommitVsParent(CommitSha(f.headSha)),
          'feature.txt',
        );
        expect(result.files, hasLength(1));
        expect(result.files.single.path, 'feature.txt');
        expect(result.files.single.truncated, isFalse);
      } finally { await f.dispose(); }
    });

    test('merge commit diffs against first parent (not empty)', () async {
      final f = await RepoFixture.withMergeCommit();
      try {
        final sut = GitCliReadOperations();
        final diff = await sut.getDiff(
            loc(f), DiffSpecCommitVsParent(CommitSha(f.headSha)));
        final feature = diff.files.where((d) => d.path == 'feature.txt');
        expect(feature, hasLength(1));
        expect(feature.first.changeKind, FileChangeKind.added);
        expect(feature.first.hunks, isNotEmpty);
      } finally {
        await f.dispose();
      }
    });
  });
}
