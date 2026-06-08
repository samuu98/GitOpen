import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) =>
      RepoLocation(RepoId.newId(), f.path, 'test');

  group('GitCliReadOperations.getFileHistory', () {
    test('returns every commit that touched the file, newest first', () async {
      final f = await RepoFixture.withFileHistory();
      try {
        final sut = GitCliReadOperations();
        // The file is named main.txt at HEAD.  --follow must still surface the
        // commits made while it was app.txt.
        final history = await sut.getFileHistory(loc(f), 'main.txt');
        final messages = history.map((c) => c.summary).toList();
        expect(
          messages,
          ['edit main', 'rename app', 'edit app', 'create app'],
        );
        // Newest first: HEAD is the first entry.
        expect(history.first.sha.value, f.headSha);
      } finally {
        await f.dispose();
      }
    });

    test('an unrelated file history excludes the tracked file commits',
        () async {
      final f = await RepoFixture.withFileHistory();
      try {
        final sut = GitCliReadOperations();
        final history = await sut.getFileHistory(loc(f), 'other.txt');
        final messages = history.map((c) => c.summary).toList();
        expect(messages, ['create app']);
        // None of the app/main edit commits leak in.
        expect(messages, isNot(contains('edit main')));
        expect(messages, isNot(contains('rename app')));
      } finally {
        await f.dispose();
      }
    });

    test('respects take (--max-count)', () async {
      final f = await RepoFixture.withFileHistory();
      try {
        final sut = GitCliReadOperations();
        final history = await sut.getFileHistory(loc(f), 'main.txt', take: 2);
        expect(history, hasLength(2));
        expect(history.first.summary, 'edit main');
        expect(history.last.summary, 'rename app');
      } finally {
        await f.dispose();
      }
    });

    test('parses author signature for history commits', () async {
      final f = await RepoFixture.withFileHistory();
      try {
        final sut = GitCliReadOperations();
        final history = await sut.getFileHistory(loc(f), 'main.txt');
        expect(history.first.author.name, 'Test');
        expect(history.first.author.email, 'test@example.com');
      } finally {
        await f.dispose();
      }
    });

    test('returns empty list for a path that never existed', () async {
      final f = await RepoFixture.withFileHistory();
      try {
        final sut = GitCliReadOperations();
        final history = await sut.getFileHistory(loc(f), 'does_not_exist.txt');
        expect(history, isEmpty);
      } finally {
        await f.dispose();
      }
    });
  });
}
