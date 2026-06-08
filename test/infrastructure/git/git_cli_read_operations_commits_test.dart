import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) =>
      RepoLocation(RepoId.newId(), f.path, 'test');

  group('GitCliReadOperations.getCommits', () {
    test('returns all commits in topological order', () async {
      final f = await RepoFixture.withLinearHistory(5);
      try {
        final sut = GitCliReadOperations();
        final commits =
            await sut.getCommits(loc(f), const CommitQuery()).toList();
        expect(commits, hasLength(5));
        expect(commits.first.sha.value, f.headSha);
      } finally {
        await f.dispose();
      }
    });

    test('respects skip and take', () async {
      final f = await RepoFixture.withLinearHistory(10);
      try {
        final sut = GitCliReadOperations();
        final commits = await sut
            .getCommits(loc(f), const CommitQuery(skip: 2, take: 3))
            .toList();
        expect(commits, hasLength(3));
      } finally {
        await f.dispose();
      }
    });

    test('returns empty for empty repo', () async {
      final f = await RepoFixture.empty();
      try {
        final sut = GitCliReadOperations();
        final commits =
            await sut.getCommits(loc(f), const CommitQuery()).toList();
        expect(commits, isEmpty);
      } finally {
        await f.dispose();
      }
    });

    test('parses author and committer signatures', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final sut = GitCliReadOperations();
        final commits =
            await sut.getCommits(loc(f), const CommitQuery()).toList();
        expect(commits, hasLength(1));
        final c = commits.first;
        expect(c.author.name, 'Test');
        expect(c.author.email, 'test@example.com');
        expect(c.committer.name, 'Test');
      } finally {
        await f.dispose();
      }
    });
  });

  group('GitCliReadOperations.getCommits search', () {
    test('empty query returns all commits (search is additive)', () async {
      final f = await RepoFixture.withSearchableHistory();
      try {
        final sut = GitCliReadOperations();
        final commits =
            await sut.getCommits(loc(f), const CommitQuery()).toList();
        expect(commits, hasLength(3));
      } finally {
        await f.dispose();
      }
    });

    test('grep filters by commit message (case-insensitive)', () async {
      final f = await RepoFixture.withSearchableHistory();
      try {
        final sut = GitCliReadOperations();
        final commits = await sut
            .getCommits(loc(f), const CommitQuery(grep: 'logout'))
            .toList();
        expect(commits, hasLength(1));
        expect(commits.single.summary, 'Fix logout bug');

        // Case-insensitivity: uppercase query still matches.
        final upper = await sut
            .getCommits(loc(f), const CommitQuery(grep: 'LOGIN'))
            .toList();
        expect(upper, hasLength(1));
        expect(upper.single.summary, 'Add login feature');
      } finally {
        await f.dispose();
      }
    });

    test('author filters by commit author', () async {
      final f = await RepoFixture.withSearchableHistory();
      try {
        final sut = GitCliReadOperations();
        final alice = await sut
            .getCommits(loc(f), const CommitQuery(author: 'Alice'))
            .toList();
        expect(alice, hasLength(2));
        expect(
          alice.map((c) => c.author.name).toSet(),
          {'Alice'},
        );

        final bob = await sut
            .getCommits(loc(f), const CommitQuery(author: 'Bob'))
            .toList();
        expect(bob, hasLength(1));
        expect(bob.single.summary, 'Fix logout bug');
      } finally {
        await f.dispose();
      }
    });

    test('touchingContent filters by changed content (pickaxe)', () async {
      final f = await RepoFixture.withSearchableHistory();
      try {
        final sut = GitCliReadOperations();
        final commits = await sut
            .getCommits(loc(f), const CommitQuery(touchingContent: 'token'))
            .toList();
        expect(commits, hasLength(1));
        expect(commits.single.summary, 'Add login feature');
      } finally {
        await f.dispose();
      }
    });

    test('grep AND author together use --all-match', () async {
      final f = await RepoFixture.withSearchableHistory();
      try {
        final sut = GitCliReadOperations();
        // "session" matches only Alice's refactor commit. Bob authored no
        // commit mentioning session, so author:Bob + grep:session is empty.
        final aliceSession = await sut
            .getCommits(
              loc(f),
              const CommitQuery(grep: 'session', author: 'Alice'),
            )
            .toList();
        expect(aliceSession, hasLength(1));
        expect(aliceSession.single.summary, 'Refactor session store');

        final bobSession = await sut
            .getCommits(
              loc(f),
              const CommitQuery(grep: 'session', author: 'Bob'),
            )
            .toList();
        expect(bobSession, isEmpty);
      } finally {
        await f.dispose();
      }
    });
  });
}
