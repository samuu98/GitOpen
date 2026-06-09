import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';

import '../../_helpers/repo_fixture.dart';

RepoLocation loc(RepoFixture f) => RepoLocation(const RepoId('t'), f.path, 't');

void main() {
  group('GitCliReadOperations.getReflog', () {
    test('lists entries newest-first with selector and message', () async {
      final f = await RepoFixture.withLinearHistory(3);
      try {
        final sut = GitCliReadOperations();
        final entries = await sut.getReflog(loc(f));
        expect(entries.length, greaterThanOrEqualTo(3));
        expect(entries.first.selector, 'HEAD@{0}');
        // Newest entry is the last commit made by the fixture.
        expect(entries.first.sha.value, f.headSha);
        expect(entries.first.message, contains('commit'));
      } finally {
        await f.dispose();
      }
    });

    test('respects the limit', () async {
      final f = await RepoFixture.withLinearHistory(5);
      try {
        final sut = GitCliReadOperations();
        final entries = await sut.getReflog(loc(f), limit: 2);
        expect(entries, hasLength(2));
      } finally {
        await f.dispose();
      }
    });

    test('returns empty for an empty repository', () async {
      final f = await RepoFixture.empty();
      try {
        final sut = GitCliReadOperations();
        final entries = await sut.getReflog(loc(f));
        expect(entries, isEmpty);
      } finally {
        await f.dispose();
      }
    });
  });
}
