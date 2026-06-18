import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import '../../_helpers/repo_fixture.dart';

void main() {
  test('fetch from local file:// remote emits progress and succeeds', () async {
    final origin = await RepoFixture.withLinearHistory(3);
    final local = await RepoFixture.empty();
    try {
      await Process.run('git', [
        'remote',
        'add',
        'origin',
        origin.path,
      ], workingDirectory: local.path);
      final sut = GitCliWriteOperations();
      final loc = RepoLocation(RepoId.newId(), local.path, 't');
      final events = <GitProgress>[];
      await sut.fetch(loc, remote: 'origin').forEach(events.add);
      // Even if no progress lines emit on local-fs remote, the stream must
      // complete cleanly. Verify the fetch worked:
      final refs = await Process.run('git', [
        'branch',
        '-r',
      ], workingDirectory: local.path);
      expect(refs.stdout.toString(), contains('origin/'));
    } finally {
      await origin.dispose();
      await local.dispose();
    }
  });

  test('fetch prunes a remote branch deleted on the remote', () async {
    final seed = await RepoFixture.withLinearHistory(1);
    final bareDir = Directory.systemTemp.createTempSync('gitopen-test-bare-');
    await Process.run(
        'git', ['clone', '--bare', '--local', seed.path, bareDir.path]);
    try {
      await Process.run('git', ['remote', 'add', 'origin', bareDir.path],
          workingDirectory: seed.path);
      await Process.run('git', ['branch', 'feature'],
          workingDirectory: seed.path);
      await Process.run('git', ['push', 'origin', 'feature'],
          workingDirectory: seed.path);
      await Process.run('git', ['fetch', 'origin'],
          workingDirectory: seed.path);
      // Delete it on the remote, then fetch (with prune) from the work repo.
      await Process.run('git', ['-C', bareDir.path, 'branch', '-D', 'feature']);

      final sut = GitCliWriteOperations();
      await sut
          .fetch(RepoLocation(RepoId.newId(), seed.path, 'w'), remote: 'origin')
          .drain<void>();

      final refs = await Process.run(
        'git',
        ['for-each-ref', '--format=%(refname)', 'refs/remotes/origin/feature'],
        workingDirectory: seed.path,
      );
      expect((refs.stdout as String).trim(), isEmpty); // pruned
    } finally {
      await seed.dispose();
      bareDir.deleteSync(recursive: true);
    }
  });

  test('fetchRefspec materialises a remote ref as a local branch', () async {
    // Origin with an extra non-branch ref (like GitHub's refs/pull/N/head).
    final origin = await RepoFixture.withLinearHistory(2);
    final local = await RepoFixture.empty();
    try {
      await Process.run(
        'git',
        ['update-ref', 'refs/pull/3/head', origin.headSha],
        workingDirectory: origin.path,
      );
      final originUrl = origin.path.replaceAll(r'\', '/');
      await Process.run(
        'git',
        ['remote', 'add', 'origin', originUrl],
        workingDirectory: local.path,
      );

      final sut = GitCliWriteOperations();
      final repo = RepoLocation(RepoId.newId(), local.path, 'fx');
      await sut
          .fetchRefspec(repo, 'origin', '+pull/3/head:refs/heads/pr/3')
          .drain<void>();

      final sha = await Process.run(
        'git',
        ['rev-parse', 'refs/heads/pr/3'],
        workingDirectory: local.path,
      );
      expect((sha.stdout as String).trim(), origin.headSha);
    } finally {
      await origin.dispose();
      await local.dispose();
    }
  });
}
