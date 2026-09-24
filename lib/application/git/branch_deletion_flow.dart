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
  const BranchDeleteResult(this.name, this.error);
  final String name;
  final String? error;
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
            error = 'Branch is not fully merged. Enable force delete.';
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
            error ??= _error(
              await write.deleteBranch(
                repo,
                request.name,
                force: request.forceBranch,
              ),
            );
          }
        }
      } on Object catch (e) {
        error = e.toString();
      }
      results.add(BranchDeleteResult(request.name, error));
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
            'Branch is not fully merged. Enable force delete.',
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
        final deleteError = _error(
          await write.deleteBranch(
            repo,
            state.branch!,
            force: forceBranch,
          ),
        );
        return BranchDeleteResult(state.branch!, deleteError);
      }
      return BranchDeleteResult(path, null);
    } on Object catch (e) {
      return BranchDeleteResult(path, e.toString());
    }
  }

  String? _error(GitResult<void> result) => switch (result) {
    GitSuccess() => null,
    GitFailure(:final message) => message,
  };
}
