import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';

import '../../_helpers/repo_fixture.dart';

RepoLocation loc(RepoFixture f) => RepoLocation(const RepoId('t'), f.path, 't');

void main() {
  group('GitCliReadOperations error mapping', () {
    test('getFileTree on an unknown sha throws a classified GitReadException',
        () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final sut = GitCliReadOperations();
        await expectLater(
          sut.getFileTree(
            loc(f),
            CommitSha('deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'),
            '',
          ),
          throwsA(
            isA<GitReadException>()
                .having((e) => e.kind, 'kind', GitErrorKind.unknownRef),
          ),
        );
      } finally {
        await f.dispose();
      }
    });

    test('message carries git stderr but not the argv dump', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final sut = GitCliReadOperations();
        Object? caught;
        try {
          await sut.getFileTree(
            loc(f),
            CommitSha('deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'),
            '',
          );
        } on Object catch (e) {
          caught = e;
        }
        final e = caught! as GitReadException;
        expect(e.message, contains('fatal'));
        // GitProcessException.toString embeds "git <argv> failed (<code>)";
        // the typed read error must surface only git's own message.
        expect(e.toString(), isNot(contains('failed (')));
      } finally {
        await f.dispose();
      }
    });

    test('getCommits stream surfaces GitReadException for a broken repo',
        () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final sut = GitCliReadOperations();
        // A refSpec that is not even a valid revision string errors out
        // (unlike an unknown-but-wellformed revision, which yields empty).
        await expectLater(
          sut
              .getCommits(
                loc(f),
                const CommitQuery(refSpec: '--not-a-revision'),
              )
              .toList(),
          throwsA(isA<GitReadException>()),
        );
      } finally {
        await f.dispose();
      }
    });
  });
}
