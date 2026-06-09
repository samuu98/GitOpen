import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/commit_request.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  group('commit', () {
    test('creates a commit with a message', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        File(p.join(f.path, 'new.txt')).writeAsStringSync('hi');
        await Process.run('git', ['add', 'new.txt'], workingDirectory: f.path);
        final sut = GitCliWriteOperations();
        final res = await sut.commit(RepoLocation(RepoId.newId(), f.path, 't'),
            const CommitRequest(message: 'add new'));
        expect(res, isA<GitSuccess<CommitSha>>());
        final log = await Process.run(
          'git',
          ['log', '-1', '--format=%s'],
          workingDirectory: f.path,
        );
        expect(log.stdout.toString().trim(), 'add new');
      } finally { await f.dispose(); }
    });

    test('amend rewrites the last commit', () async {
      final f = await RepoFixture.withLinearHistory(2);
      try {
        final sut = GitCliWriteOperations();
        final res = await sut.commit(RepoLocation(RepoId.newId(), f.path, 't'),
            const CommitRequest(message: 'amended', amend: true));
        expect(res, isA<GitSuccess<CommitSha>>());
        final log = await Process.run(
          'git',
          ['log', '-1', '--format=%s'],
          workingDirectory: f.path,
        );
        expect(log.stdout.toString().trim(), 'amended');
      } finally { await f.dispose(); }
    });

    test('sign-off appends Signed-off-by trailer', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        File(p.join(f.path, 'new.txt')).writeAsStringSync('hi');
        await Process.run('git', ['add', 'new.txt'], workingDirectory: f.path);
        final sut = GitCliWriteOperations();
        final res = await sut.commit(RepoLocation(RepoId.newId(), f.path, 't'),
            const CommitRequest(message: 'signed', signOff: true));
        expect(res, isA<GitSuccess<CommitSha>>());
        final body = await Process.run(
          'git',
          ['log', '-1', '--format=%B'],
          workingDirectory: f.path,
        );
        expect(body.stdout.toString(), contains('Signed-off-by'));
      } finally { await f.dispose(); }
    });

    // GPG signing: rather than depend on the host actually having a working
    // gpg key (non-deterministic across CI/dev machines), we point the repo at
    // a non-existent gpg program. With sign:true, git invokes that program and
    // fails — proving `-S` was passed and git attempted to sign. With
    // sign:false, git never touches gpg, so the same repo commits cleanly.
    test('sign true attempts to GPG-sign and fails on a missing gpg program',
        () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        // Force the signing path to be deterministic regardless of the host's
        // real gpg setup: a gpg.program that does not exist always fails.
        await Process.run(
          'git',
          ['config', 'gpg.program', 'gitopen-no-such-gpg'],
          workingDirectory: f.path,
        );
        File(p.join(f.path, 'new.txt')).writeAsStringSync('hi');
        await Process.run('git', ['add', 'new.txt'], workingDirectory: f.path);
        final sut = GitCliWriteOperations();
        final res = await sut.commit(RepoLocation(RepoId.newId(), f.path, 't'),
            const CommitRequest(message: 'signed commit', sign: true));
        expect(res, isA<GitFailure<CommitSha>>());
      } finally { await f.dispose(); }
    });

    test('sign false still commits cleanly (unchanged behaviour)', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        // Same broken gpg.program as the sign:true case — it must be ignored
        // entirely when sign is false, proving `-S` is only passed on demand.
        await Process.run(
          'git',
          ['config', 'gpg.program', 'gitopen-no-such-gpg'],
          workingDirectory: f.path,
        );
        File(p.join(f.path, 'new.txt')).writeAsStringSync('hi');
        await Process.run('git', ['add', 'new.txt'], workingDirectory: f.path);
        final sut = GitCliWriteOperations();
        final res = await sut.commit(RepoLocation(RepoId.newId(), f.path, 't'),
            const CommitRequest(message: 'unsigned commit'));
        expect(res, isA<GitSuccess<CommitSha>>());
        final log = await Process.run(
          'git',
          ['log', '-1', '--format=%s'],
          workingDirectory: f.path,
        );
        expect(log.stdout.toString().trim(), 'unsigned commit');
      } finally { await f.dispose(); }
    });
  });
}
