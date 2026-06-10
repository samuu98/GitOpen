import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/repo_fixture.dart';

RepoLocation loc(RepoFixture f) => RepoLocation(const RepoId('t'), f.path, 't');

Future<String> _git(String cwd, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
  }
  return r.stdout.toString();
}

void main() {
  group('GitCliWriteOperations.rewordCommit', () {
    test('rewrites a non-HEAD commit message and keeps the history shape',
        () async {
      final f = await RepoFixture.withRebaseHistory(); // c0..c3
      try {
        final sut = GitCliWriteOperations();
        final target = CommitSha(f.rebaseShas[1]); // "c1"
        final result = await sut.rewordCommit(
          loc(f),
          target,
          'c1 reworded\n\nWith a body line.',
        );
        expect(result, isA<GitSuccess<RebaseOutcome>>());

        final subjects =
            (await _git(f.path, ['log', '--format=%s'])).trim().split('\n');
        expect(subjects, ['c3', 'c2', 'c1 reworded', 'c0 base']);

        // Files from every commit are still present.
        for (var i = 0; i < 4; i++) {
          expect(File(p.join(f.path, 'c$i.txt')).existsSync(), isTrue);
        }
      } finally {
        await f.dispose();
      }
    });

    test('reword of HEAD works too', () async {
      final f = await RepoFixture.withRebaseHistory();
      try {
        final sut = GitCliWriteOperations();
        final result = await sut.rewordCommit(
          loc(f),
          CommitSha(f.rebaseShas[3]),
          'c3 new subject',
        );
        expect(result, isA<GitSuccess<RebaseOutcome>>());
        final head = (await _git(f.path, ['log', '-1', '--format=%s'])).trim();
        expect(head, 'c3 new subject');
      } finally {
        await f.dispose();
      }
    });

    test('rewording the root commit fails cleanly', () async {
      final f = await RepoFixture.withRebaseHistory();
      try {
        final sut = GitCliWriteOperations();
        final result = await sut.rewordCommit(
          loc(f),
          CommitSha(f.rebaseShas[0]),
          'nope',
        );
        expect(result, isA<GitFailure<RebaseOutcome>>());
      } finally {
        await f.dispose();
      }
    });
  });

  group('GitCliWriteOperations.editAtCommit', () {
    test('pauses the rebase at the chosen commit; continue finishes it',
        () async {
      final f = await RepoFixture.withRebaseHistory();
      try {
        final sut = GitCliWriteOperations();
        final result =
            await sut.editAtCommit(loc(f), CommitSha(f.rebaseShas[2]));
        expect(result, isA<GitSuccess<RebaseOutcome>>());
        expect(
          (result as GitSuccess<RebaseOutcome>).value,
          isA<RebaseStoppedForEdit>(),
        );

        // The repo is mid-rebase, stopped at c2.
        expect(
          Directory(p.join(f.path, '.git', 'rebase-merge')).existsSync(),
          isTrue,
        );
        final head = (await _git(f.path, ['log', '-1', '--format=%s'])).trim();
        expect(head, 'c2');

        final cont = await sut.rebaseContinue(loc(f));
        expect(cont, isA<GitSuccess<CommitSha>>());
        expect(
          Directory(p.join(f.path, '.git', 'rebase-merge')).existsSync(),
          isFalse,
        );
      } finally {
        await f.dispose();
      }
    });
  });
}
