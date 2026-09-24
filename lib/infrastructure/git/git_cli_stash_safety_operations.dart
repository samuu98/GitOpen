import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/stash_safety_operations.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_status_reader.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/infrastructure/git/git_result_runner.dart';

export 'package:gitopen/application/git/stash_safety_operations.dart'
    show StashRestoreResult;

final class GitCliStashSafetyOperations implements StashSafetyOperations {
  GitCliStashSafetyOperations({GitProcessRunner? runner})
    : _runner = runner ?? GitProcessRunner();

  final GitProcessRunner _runner;

  Future<String> _stashSha(RepoLocation repo, int index) async =>
      (await _runner.run(repo.path, [
        'rev-parse',
        '--verify',
        'stash@{$index}',
      ])).trim();

  @override
  Future<GitResult<List<String>>> overlap(RepoLocation repo, int index) async {
    try {
      final sha = await _stashSha(repo, index);
      final paths = (await _runner.run(repo.path, [
        'stash',
        'show',
        '--name-only',
        '-z',
        '--include-untracked',
        sha,
      ])).split('\x00').where((path) => path.isNotEmpty).toSet();
      final status = await GitCliStatusReader(_runner).getStatus(repo);
      final dirty = [
        for (final entry in status.entries) ...[
          entry.path,
          ?entry.oldPath,
        ],
      ];
      final overlap =
          paths
              .where(
                (path) => dirty.any(
                  (entry) =>
                      entry == path ||
                      (entry.endsWith('/') && path.startsWith(entry)),
                ),
              )
              .toList()
            ..sort();
      return GitSuccess(overlap);
    } on GitProcessException catch (error) {
      return GitFailure(
        GitResultRunner(_runner).classify(error),
        error.stderr,
      );
    }
  }

  @override
  Future<GitResult<StashRestoreResult>> applyPreservingLocal(
    RepoLocation repo,
    int index, {
    required bool pop,
  }) async {
    String? targetSha;
    String? localSha;
    var localDropped = false;
    try {
      targetSha = await _stashSha(repo, index);
      final before = await _stashSha(repo, 0);
      await _runner.run(repo.path, [
        'stash',
        'push',
        '-u',
        '-m',
        'GitOpen local edits before applying stash',
      ]);
      localSha = await _stashSha(repo, 0);
      if (localSha == before) {
        return const GitFailure(
          GitErrorKind.other,
          'No local backup was created; the target stash was left untouched.',
        );
      }
      try {
        await _runner.run(repo.path, ['stash', 'apply', targetSha]);
      } on GitProcessException catch (error) {
        final localRef = await _describe(repo, localSha);
        return GitFailure(
          GitResultRunner(_runner).classify(error),
          'Target stash was kept. Local edits are in $localRef. '
          'Target apply failed: ${error.stderr}',
        );
      }
      // Give git's three-way stash merge an index that matches the applied
      // target. Otherwise it refuses to touch a locally modified path before
      // it can create the normal unmerged index entries.
      await _runner.run(repo.path, ['add', '-A']);
      try {
        await _runner.run(repo.path, ['stash', 'apply', localSha]);
      } on GitProcessException catch (error) {
        final localRef = await _describe(repo, localSha);
        final unmerged = await _runner.run(repo.path, [
          'ls-files',
          '--unmerged',
          '-z',
        ]);
        if (unmerged.isNotEmpty) {
          return GitSuccess(
            StashRestoreResult(
              hasConflict: true,
              localStash: localRef,
            ),
          );
        }
        return GitFailure(
          GitResultRunner(_runner).classify(error),
          'Target stash was kept. Local edits are in $localRef. '
          'Local restore failed: ${error.stderr}',
        );
      }
      await _runner.run(repo.path, ['reset', '--mixed']);
      final stagedPatch = await _runner.run(repo.path, [
        'diff',
        '--binary',
        '$localSha^1',
        '$localSha^2',
      ]);
      if (stagedPatch.isNotEmpty) {
        await _runner.runWithStdin(
          repo.path,
          ['apply', '--cached', '-'],
          stagedPatch,
        );
      }
      await _dropSha(repo, localSha);
      localDropped = true;
      if (pop) await _dropSha(repo, targetSha);
      return const GitSuccess(StashRestoreResult());
    } on GitProcessException catch (error) {
      final localRef = localSha == null || localDropped
          ? null
          : await _describe(repo, localSha);
      final localMessage = localDropped
          ? 'Local edits are in the worktree.'
          : localRef == null
          ? 'Local edits remain in the worktree or a new stash.'
          : 'Local edits are in $localRef.';
      return GitFailure(
        GitResultRunner(_runner).classify(error),
        '${error.stderr} $localMessage '
        'The target stash was kept unless both changes were applied cleanly.',
      );
    }
  }

  Future<String> _describe(RepoLocation repo, String sha) async {
    final index = await _indexOf(repo, sha);
    return index == null ? sha : 'stash@{$index} ($sha)';
  }

  Future<int?> _indexOf(RepoLocation repo, String sha) async {
    final shas = (await _runner.run(repo.path, [
      'stash',
      'list',
      '--format=%H',
    ])).trim().split('\n');
    final index = shas.indexOf(sha);
    return index < 0 ? null : index;
  }

  Future<void> _dropSha(RepoLocation repo, String sha) async {
    final index = await _indexOf(repo, sha);
    if (index == null) {
      throw GitProcessException(
        ['stash', 'drop'],
        1,
        'The applied stash $sha was not found for cleanup.',
      );
    }
    await _runner.run(repo.path, ['stash', 'drop', 'stash@{$index}']);
  }
}
