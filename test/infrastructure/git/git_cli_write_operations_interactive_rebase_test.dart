import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';

import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) => RepoLocation(RepoId.newId(), f.path, 't');

  /// Subject messages of every commit reachable from HEAD, newest-first.
  Future<List<String>> logSubjects(String path) async {
    final r = await Process.run(
      'git',
      ['log', '--pretty=format:%s'],
      workingDirectory: path,
    );
    return (r.stdout as String).split('\n').where((l) => l.isNotEmpty).toList();
  }

  /// Number of commits reachable from HEAD.
  Future<int> commitCount(String path) async {
    final r = await Process.run(
      'git',
      ['rev-list', '--count', 'HEAD'],
      workingDirectory: path,
    );
    return int.parse((r.stdout as String).trim());
  }

  Future<String> headSha(String path) async {
    final r = await Process.run(
      'git',
      ['rev-parse', 'HEAD'],
      workingDirectory: path,
    );
    return (r.stdout as String).trim();
  }

  Future<bool> tracks(String path, String file) async {
    final r = await Process.run(
      'git',
      ['ls-files', '--error-unmatch', file],
      workingDirectory: path,
    );
    return r.exitCode == 0;
  }

  test('DROP a middle commit removes only that commit', () async {
    final f = await RepoFixture.withRebaseHistory();
    try {
      final sut = GitCliWriteOperations();
      // base = c0; plan over c1..c3, dropping c2.
      final res = await sut.interactiveRebase(
        loc(f),
        CommitSha(f.rebaseShas[0]),
        [
          RebaseTodoEntry(CommitSha(f.rebaseShas[1]), RebaseTodoAction.pick),
          RebaseTodoEntry(CommitSha(f.rebaseShas[2]), RebaseTodoAction.drop),
          RebaseTodoEntry(CommitSha(f.rebaseShas[3]), RebaseTodoAction.pick),
        ],
      );
      expect(res, isA<GitSuccess<RebaseOutcome>>());
      expect((res as GitSuccess<RebaseOutcome>).value, isA<RebaseApplied>());

      final subjects = await logSubjects(f.path);
      expect(subjects, equals(['c3', 'c1', 'c0 base']));
      expect(await tracks(f.path, 'c2.txt'), isFalse);
      expect(await tracks(f.path, 'c1.txt'), isTrue);
      expect(await tracks(f.path, 'c3.txt'), isTrue);
    } finally {
      await f.dispose();
    }
  });

  test('REORDER two commits is reflected in git log', () async {
    final f = await RepoFixture.withRebaseHistory();
    try {
      final sut = GitCliWriteOperations();
      // base = c0; reorder c1..c3 so c3 comes before c2 (final order
      // oldest-first: c1, c3, c2).
      final res = await sut.interactiveRebase(
        loc(f),
        CommitSha(f.rebaseShas[0]),
        [
          RebaseTodoEntry(CommitSha(f.rebaseShas[1]), RebaseTodoAction.pick),
          RebaseTodoEntry(CommitSha(f.rebaseShas[3]), RebaseTodoAction.pick),
          RebaseTodoEntry(CommitSha(f.rebaseShas[2]), RebaseTodoAction.pick),
        ],
      );
      expect(res, isA<GitSuccess<RebaseOutcome>>());
      expect((res as GitSuccess<RebaseOutcome>).value, isA<RebaseApplied>());

      // newest-first log => c2, c3, c1, c0 base
      final subjects = await logSubjects(f.path);
      expect(subjects, equals(['c2', 'c3', 'c1', 'c0 base']));
      expect(await commitCount(f.path), 4);
    } finally {
      await f.dispose();
    }
  });

  test('FIXUP squashes a commit into its parent dropping the count', () async {
    final f = await RepoFixture.withRebaseHistory();
    try {
      final before = await commitCount(f.path);
      final sut = GitCliWriteOperations();
      // base = c0; fixup c2 into c1, keep c3.
      final res = await sut.interactiveRebase(
        loc(f),
        CommitSha(f.rebaseShas[0]),
        [
          RebaseTodoEntry(CommitSha(f.rebaseShas[1]), RebaseTodoAction.pick),
          RebaseTodoEntry(CommitSha(f.rebaseShas[2]), RebaseTodoAction.fixup),
          RebaseTodoEntry(CommitSha(f.rebaseShas[3]), RebaseTodoAction.pick),
        ],
      );
      expect(res, isA<GitSuccess<RebaseOutcome>>());
      expect((res as GitSuccess<RebaseOutcome>).value, isA<RebaseApplied>());

      expect(await commitCount(f.path), before - 1);
      // fixup keeps the parent's message and the squashed file content.
      final subjects = await logSubjects(f.path);
      expect(subjects, equals(['c3', 'c1', 'c0 base']));
      expect(await tracks(f.path, 'c2.txt'), isTrue);
      expect(await tracks(f.path, 'c1.txt'), isTrue);
    } finally {
      await f.dispose();
    }
  });

  test('SQUASH merges a commit into its parent keeping contents', () async {
    final f = await RepoFixture.withRebaseHistory();
    try {
      final before = await commitCount(f.path);
      final sut = GitCliWriteOperations();
      // base = c0; squash c2 into c1.
      final res = await sut.interactiveRebase(
        loc(f),
        CommitSha(f.rebaseShas[0]),
        [
          RebaseTodoEntry(CommitSha(f.rebaseShas[1]), RebaseTodoAction.pick),
          RebaseTodoEntry(CommitSha(f.rebaseShas[2]), RebaseTodoAction.squash),
          RebaseTodoEntry(CommitSha(f.rebaseShas[3]), RebaseTodoAction.pick),
        ],
      );
      expect(res, isA<GitSuccess<RebaseOutcome>>());
      expect((res as GitSuccess<RebaseOutcome>).value, isA<RebaseApplied>());

      expect(await commitCount(f.path), before - 1);
      expect(await tracks(f.path, 'c2.txt'), isTrue);
      expect(await tracks(f.path, 'c1.txt'), isTrue);
    } finally {
      await f.dispose();
    }
  });

  /// Full message (subject + body) of the commit whose subject is [subject].
  Future<String> fullMessageOf(String path, String subject) async {
    final sha = await Process.run(
      'git',
      ['log', '--format=%H', '--grep', '^$subject\$', '-1'],
      workingDirectory: path,
    );
    final r = await Process.run(
      'git',
      ['log', '--format=%B', '-1', (sha.stdout as String).trim()],
      workingDirectory: path,
    );
    return (r.stdout as String).trim();
  }

  test('REWORD via the plan rewrites the message', () async {
    final f = await RepoFixture.withRebaseHistory();
    try {
      final sut = GitCliWriteOperations();
      final res = await sut.interactiveRebase(
        loc(f),
        CommitSha(f.rebaseShas[0]),
        [
          RebaseTodoEntry(
            CommitSha(f.rebaseShas[1]),
            RebaseTodoAction.reword,
            message: 'c1 reworded\n\nwith a body',
          ),
          RebaseTodoEntry(CommitSha(f.rebaseShas[2]), RebaseTodoAction.pick),
          RebaseTodoEntry(CommitSha(f.rebaseShas[3]), RebaseTodoAction.pick),
        ],
      );
      expect(res, isA<GitSuccess<RebaseOutcome>>());
      expect((res as GitSuccess<RebaseOutcome>).value, isA<RebaseApplied>());
      final subjects = await logSubjects(f.path);
      expect(subjects, equals(['c3', 'c2', 'c1 reworded', 'c0 base']));
      expect(
        await fullMessageOf(f.path, 'c1 reworded'),
        'c1 reworded\n\nwith a body',
      );
    } finally {
      await f.dispose();
    }
  });

  test('SQUASH with a custom message uses it for the folded commit', () async {
    final f = await RepoFixture.withRebaseHistory();
    try {
      final sut = GitCliWriteOperations();
      final res = await sut.interactiveRebase(
        loc(f),
        CommitSha(f.rebaseShas[0]),
        [
          RebaseTodoEntry(CommitSha(f.rebaseShas[1]), RebaseTodoAction.pick),
          RebaseTodoEntry(
            CommitSha(f.rebaseShas[2]),
            RebaseTodoAction.squash,
            message: 'c1+c2 folded',
          ),
          RebaseTodoEntry(CommitSha(f.rebaseShas[3]), RebaseTodoAction.pick),
        ],
      );
      expect(res, isA<GitSuccess<RebaseOutcome>>());
      expect((res as GitSuccess<RebaseOutcome>).value, isA<RebaseApplied>());
      expect(
        await logSubjects(f.path),
        equals(['c3', 'c1+c2 folded', 'c0 base']),
      );
      expect(await tracks(f.path, 'c2.txt'), isTrue);
    } finally {
      await f.dispose();
    }
  });

  test('REWORD and SQUASH messages land on the right stops', () async {
    final f = await RepoFixture.withRebaseHistory();
    try {
      final sut = GitCliWriteOperations();
      final res = await sut.interactiveRebase(
        loc(f),
        CommitSha(f.rebaseShas[0]),
        [
          RebaseTodoEntry(
            CommitSha(f.rebaseShas[1]),
            RebaseTodoAction.reword,
            message: 'c1 first stop',
          ),
          RebaseTodoEntry(CommitSha(f.rebaseShas[2]), RebaseTodoAction.pick),
          RebaseTodoEntry(
            CommitSha(f.rebaseShas[3]),
            RebaseTodoAction.squash,
            message: 'c2+c3 second stop',
          ),
        ],
      );
      expect(res, isA<GitSuccess<RebaseOutcome>>());
      expect(
        await logSubjects(f.path),
        equals(['c2+c3 second stop', 'c1 first stop', 'c0 base']),
      );
    } finally {
      await f.dispose();
    }
  });

  test('a no-op plan (all pick, same order) leaves history alone', () async {
    final f = await RepoFixture.withRebaseHistory();
    try {
      final beforeSubjects = await logSubjects(f.path);
      final beforeHead = await headSha(f.path);

      final sut = GitCliWriteOperations();
      final res = await sut.interactiveRebase(
        loc(f),
        CommitSha(f.rebaseShas[0]),
        [
          RebaseTodoEntry(CommitSha(f.rebaseShas[1]), RebaseTodoAction.pick),
          RebaseTodoEntry(CommitSha(f.rebaseShas[2]), RebaseTodoAction.pick),
          RebaseTodoEntry(CommitSha(f.rebaseShas[3]), RebaseTodoAction.pick),
        ],
      );
      expect(res, isA<GitSuccess<RebaseOutcome>>());

      final afterHead = await headSha(f.path);
      expect(await logSubjects(f.path), equals(beforeSubjects));
      // A no-op pick rebase replays identical commits => same SHAs.
      expect(afterHead, equals(beforeHead));
    } finally {
      await f.dispose();
    }
  });
}
