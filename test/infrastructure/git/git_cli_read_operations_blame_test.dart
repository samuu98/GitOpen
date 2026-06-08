import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) =>
      RepoLocation(RepoId.newId(), f.path, 'test');

  group('GitCliReadOperations.getBlame', () {
    test('attributes each line to its introducing commit and author',
        () async {
      final f = await RepoFixture.withBlameHistory();
      try {
        final sut = GitCliReadOperations();
        final lines = await sut.getBlame(loc(f), 'blame.txt');

        expect(lines, hasLength(2));

        // Line 1 'alpha' was added by Alice in the first commit.
        expect(lines[0].lineNumber, 1);
        expect(lines[0].content, 'alpha');
        expect(lines[0].sha.value, f.firstSha);
        expect(lines[0].authorName, 'Alice');

        // Line 2 'beta' was added by Bob in the second (HEAD) commit.
        expect(lines[1].lineNumber, 2);
        expect(lines[1].content, 'beta');
        expect(lines[1].sha.value, f.headSha);
        expect(lines[1].authorName, 'Bob');
      } finally {
        await f.dispose();
      }
    });

    test('parses author time as a DateTime', () async {
      final f = await RepoFixture.withBlameHistory();
      try {
        final sut = GitCliReadOperations();
        final lines = await sut.getBlame(loc(f), 'blame.txt');
        expect(lines, hasLength(2));
        // Alice committed before Bob.
        expect(
          lines[0].authorTime.isAfter(lines[1].authorTime),
          isFalse,
        );
      } finally {
        await f.dispose();
      }
    });

    test('blames a file at a specific revision (at)', () async {
      final f = await RepoFixture.withBlameHistory();
      try {
        final sut = GitCliReadOperations();
        // At the first commit the file had only one line, attributed to Alice.
        final lines =
            await sut.getBlame(loc(f), 'blame.txt', at: CommitSha(f.firstSha));
        expect(lines, hasLength(1));
        expect(lines.single.content, 'alpha');
        expect(lines.single.sha.value, f.firstSha);
        expect(lines.single.authorName, 'Alice');
      } finally {
        await f.dispose();
      }
    });
  });
}
