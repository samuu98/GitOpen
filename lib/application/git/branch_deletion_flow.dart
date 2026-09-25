import 'package:gitopen/application/git/branch_deletion.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

/// Snapshot used for both the warning shown to the user and the final guard.
class BranchDeleteStatus {
  const BranchDeleteStatus({
    required this.exists,
    required this.merged,
    this.worktreePath,
    this.isMainWorktree = false,
    this.worktreeDirty = false,
    this.worktreeLocked = false,
  });

  final bool exists;
  final bool merged;
  final String? worktreePath;
  final bool isMainWorktree;
  final bool worktreeDirty;
  final bool worktreeLocked;
}

class WorktreeDeleteStatus {
  const WorktreeDeleteStatus({
    required this.path,
    required this.branch,
    required this.isMain,
    required this.dirty,
    required this.locked,
  });

  final String path;
  final String? branch;
  final bool isMain;
  final bool dirty;
  final bool locked;
}

abstract interface class BranchDeletionInspector {
  Future<BranchDeleteStatus> inspect(RepoLocation repo, String branch);
  Future<WorktreeDeleteStatus?> inspectWorktree(
    RepoLocation repo,
    String path,
  );
}

class BranchDeleteRequest {
  const BranchDeleteRequest(
    this.name, {
    this.remote = false,
    this.forceBranch = false,
    this.removeWorktree = false,
    this.forceWorktree = false,
  });

  final String name;
  final bool remote;
  final bool forceBranch;
  final bool removeWorktree;
  final bool forceWorktree;
}

class BranchDeleteResult {
  const BranchDeleteResult(
    this.name,
    this.error, {
    this.needsForce = false,
    this.worktreeRemoved = false,
  });
  final String name;
  final String? error;

  /// True when only `branch -D` would delete it, so the dialog can offer force
  /// instead of showing a dead end.
  final bool needsForce;

  /// True when the branch's worktree was removed, even if the branch was kept.
  final bool worktreeRemoved;
}

/// Runs a batch in order, retaining each failure for the dialog's summary.
/// Re-inspection immediately before each write closes the gap after preview.
class BranchDeletionFlow {
  const BranchDeletionFlow({required this.inspector, required this.write});

  final BranchDeletionInspector inspector;
  final GitWriteOperations write;

  Future<BranchDeleteStatus> inspect(RepoLocation repo, String name) =>
      inspector.inspect(repo, name);

  Future<WorktreeDeleteStatus?> inspectWorktree(
    RepoLocation repo,
    String path,
  ) => inspector.inspectWorktree(repo, path);

  Future<List<BranchDeleteResult>> deleteMany(
    RepoLocation repo,
    List<BranchDeleteRequest> requests, {
    void Function(int done, int total)? onProgress,
    Future<String?> Function(String remoteRef)? deleteRemote,
  }) async {
    final results = <BranchDeleteResult>[];
    for (final request in requests) {
      String? error;
      var needsForce = false;
      var worktreeRemoved = false;
      try {
        if (request.remote) {
          error = deleteRemote != null
              ? await deleteRemote(request.name)
              : _error(
                  await write.deleteBranch(
                    repo,
                    request.name,
                    remote: true,
                  ),
                );
        } else {
          final state = await inspect(repo, request.name);
          if (!state.exists) {
            error = 'Branch no longer exists.';
          } else if (state.isMainWorktree) {
            error = 'Checked out in the main worktree.';
          } else if (state.worktreeLocked) {
            error = 'The linked worktree is locked.';
          } else if (!state.merged && !request.forceBranch) {
            error = _unmergedError;
            needsForce = true;
          } else if (state.worktreePath != null && !request.removeWorktree) {
            error =
                'Checked out in a linked worktree at '
                '${state.worktreePath}. Enable worktree removal.';
          } else if (state.worktreeDirty && !request.forceWorktree) {
            error =
                'The worktree has uncommitted or untracked changes. '
                'Force removal needs confirmation.';
          } else {
            if (state.worktreePath != null) {
              error = _error(
                await write.removeWorktree(
                  repo,
                  state.worktreePath!,
                  force: request.forceWorktree,
                ),
              );
            }
            if (error == null) {
              worktreeRemoved = state.worktreePath != null;
              final refused = await _deleteBranch(
                repo,
                request.name,
                force: request.forceBranch,
              );
              error = refused.error;
              needsForce = refused.needsForce;
            }
          }
        }
      } on Object catch (e) {
        error = e.toString();
      }
      results.add(
        BranchDeleteResult(
          request.name,
          error,
          needsForce: needsForce,
          worktreeRemoved: worktreeRemoved,
        ),
      );
      onProgress?.call(results.length, requests.length);
    }
    return results;
  }

  Future<BranchDeleteResult> removeWorktree(
    RepoLocation repo,
    String path, {
    bool force = false,
    bool deleteBranch = false,
    bool forceBranch = false,
  }) async {
    try {
      final state = await inspectWorktree(repo, path);
      if (state == null) {
        return BranchDeleteResult(path, 'Worktree no longer exists.');
      }
      if (state.isMain) {
        return BranchDeleteResult(path, 'The main worktree cannot be removed.');
      }
      if (state.locked) {
        return BranchDeleteResult(path, 'The worktree is locked.');
      }
      if (state.dirty && !force) {
        return BranchDeleteResult(
          path,
          'The worktree has uncommitted or untracked changes. '
          'Force removal needs confirmation.',
        );
      }
      if (deleteBranch && state.branch != null) {
        final branch = await inspect(repo, state.branch!);
        if (!branch.merged && !forceBranch) {
          return BranchDeleteResult(
            state.branch!,
            _unmergedError,
            needsForce: true,
          );
        }
      }
      final removeError = _error(
        await write.removeWorktree(
          repo,
          path,
          force: force,
        ),
      );
      if (removeError != null) return BranchDeleteResult(path, removeError);
      if (deleteBranch && state.branch != null) {
        final refused = await _deleteBranch(
          repo,
          state.branch!,
          force: forceBranch,
        );
        return BranchDeleteResult(
          state.branch!,
          refused.error,
          needsForce: refused.needsForce,
          worktreeRemoved: true,
        );
      }
      return BranchDeleteResult(path, null);
    } on Object catch (e) {
      return BranchDeleteResult(path, e.toString());
    }
  }

  /// Deletes the branch and reports a refusal in the app's own words: git's
  /// stderr names `-D` and its advice config, which the dialog's force option
  /// already covers.
  Future<({String? error, bool needsForce})> _deleteBranch(
    RepoLocation repo,
    String name, {
    required bool force,
  }) async {
    final error = _error(await write.deleteBranch(repo, name, force: force));
    if (error != null && !force && isNotFullyMergedError(error)) {
      return (error: _unmergedError, needsForce: true);
    }
    return (error: error, needsForce: false);
  }

  String? _error(GitResult<void> result) => switch (result) {
    GitSuccess() => null,
    GitFailure(:final message) => message,
  };
}

const String _unmergedError =
    'Branch is not fully merged. Enable force delete.';
