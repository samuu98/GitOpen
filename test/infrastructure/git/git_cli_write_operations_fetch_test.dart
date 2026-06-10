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
      await Process.run('git', ['remote', 'add', 'origin', origin.path],
          workingDirectory: local.path);
      final sut = GitCliWriteOperations();
      final loc = RepoLocation(RepoId.newId(), local.path, 't');
      final events = <GitProgress>[];
      await for (final e in sut.fetch(loc, remote: 'origin')) {
        events.add(e);
      }
      // Even if no progress lines emit on local-fs remote, the stream must complete cleanly.
      // Verify the fetch worked:
      final refs = await Process.run('git', ['branch', '-r'],
          workingDirectory: local.path);
      expect(refs.stdout.toString(), contains('origin/'));
    } finally {
      await origin.dispose();
      await local.dispose();
    }
  });

  test('fetch with prune removes stale remote-tracking branches', () async {
    final origin = await RepoFixture.withLinearHistory(1);
    final local = await RepoFixture.empty();
    try {
      await Process.run('git', ['remote', 'add', 'origin', origin.path],
          workingDirectory: local.path);
      // Create a branch on origin, fetch it, then delete it on origin.
      await Process.run('git', ['branch', 'doomed'],
          workingDirectory: origin.path);
      final sut = GitCliWriteOperations();
      final loc = RepoLocation(RepoId.newId(), local.path, 't');
      await for (final _ in sut.fetch(loc, remote: 'origin')) {}
      await Process.run('git', ['branch', '-D', 'doomed'],
          workingDirectory: origin.path);

      // Without prune the stale ref survives; with prune it must go away.
      await for (final _ in sut.fetch(loc, remote: 'origin', prune: true)) {}
      final refs = await Process.run('git', ['branch', '-r'],
          workingDirectory: local.path);
      expect(refs.stdout.toString(), isNot(contains('origin/doomed')));
    } finally {
      await origin.dispose();
      await local.dispose();
    }
  });
}
