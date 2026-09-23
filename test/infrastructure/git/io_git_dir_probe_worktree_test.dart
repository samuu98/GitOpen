import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:gitopen/infrastructure/git/io_git_dir_probe.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/repo_fixture.dart';

Future<void> git(String cwd, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: cwd);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')}: ${result.stderr}');
  }
}

void main() {
  test('resolves a relative gitdir pointer without invoking git', () async {
    final root = Directory.systemTemp.createTempSync('gitopen-probe-');
    try {
      final repoPath = p.join(root.path, 'repo');
      final gitDir = p.join(root.path, 'metadata');
      Directory(repoPath).createSync();
      Directory(p.join(gitDir, 'rebase-merge')).createSync(recursive: true);
      File(p.join(gitDir, 'MERGE_HEAD')).writeAsStringSync('sha\n');
      File(p.join(repoPath, '.git')).writeAsStringSync('gitdir: ../metadata\n');
      final repo = RepoLocation(RepoId.newId(), repoPath, 'pointer');
      const probe = IoGitDirProbe();
      expect(probe.fileExists(repo, 'MERGE_HEAD'), isTrue);
      expect(probe.dirExists(repo, 'rebase-merge'), isTrue);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('linked worktree reports an in-progress merge', () async {
    final fixture = await RepoFixture.withLinearHistory(1);
    final worktree = p.join(fixture.path, 'linked');
    try {
      await git(fixture.path, ['checkout', '-q', '-b', 'feature']);
      await File(p.join(fixture.path, 'file_0.txt')).writeAsString('feature\n');
      await git(fixture.path, ['commit', '-qam', 'feature']);
      await git(fixture.path, ['checkout', '-q', 'master']);
      await git(fixture.path, ['worktree', 'add', '-qb', 'linked', worktree]);
      await File(p.join(worktree, 'file_0.txt')).writeAsString('linked\n');
      await git(worktree, ['commit', '-qam', 'linked']);

      final repo = RepoLocation(RepoId.newId(), worktree, 'linked');
      final result = await GitCliWriteOperations().merge(repo, 'feature');
      expect(result, isA<GitSuccess<MergeOutcome>>());
      expect((result as GitSuccess<MergeOutcome>).value, isA<MergeConflict>());
      expect(File(p.join(worktree, '.git')).existsSync(), isTrue);
      expect(
        const IoGitDirProbe().fileExists(repo, 'MERGE_HEAD'),
        isTrue,
      );
      final container = ProviderContainer();
      try {
        expect(
          await container.read(repoStateProvider(repo).future),
          InProgressOp.merge,
        );
      } finally {
        container.dispose();
      }
    } finally {
      await fixture.dispose();
    }
  });

  test('linked worktree reports an edit stop during rebase', () async {
    final fixture = await RepoFixture.withRebaseHistory();
    final worktree = p.join(fixture.path, 'linked');
    try {
      await git(fixture.path, ['worktree', 'add', '-qb', 'linked', worktree]);
      final repo = RepoLocation(RepoId.newId(), worktree, 'linked');
      final result = await GitCliWriteOperations().editAtCommit(
        repo,
        CommitSha(fixture.rebaseShas[2]),
      );
      expect(result, isA<GitSuccess<RebaseOutcome>>());
      expect(
        (result as GitSuccess<RebaseOutcome>).value,
        isA<RebaseStoppedForEdit>(),
      );
      expect(
        const IoGitDirProbe().dirExists(repo, 'rebase-merge'),
        isTrue,
      );
      final container = ProviderContainer();
      try {
        expect(
          await container.read(repoStateProvider(repo).future),
          InProgressOp.rebase,
        );
      } finally {
        container.dispose();
      }
    } finally {
      await fixture.dispose();
    }
  });
}
