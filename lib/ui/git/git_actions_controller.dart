import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/branch_deletion.dart';
import 'package:gitopen/application/git/branch_deletion_flow.dart';
import 'package:gitopen/application/git/git_action_ports.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/application/git/stash_safety_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/git/git_action_bridges.dart';
import 'package:gitopen/ui/operations/action_feedback.dart';

/// Exposes [GitActionsController] — the single UI entry point for git actions.
final gitActionsControllerProvider = Provider<GitActionsController>(
  GitActionsController.new,
);

/// Thin UI adapter over the pure [GitActionsService].
///
/// It is the one place that turns a git action into UI effects: it supplies
/// the [AuthPrompt] (account-switcher dialog + repo binding) and [ProgressSink]
/// (operations notifier → toast/activity panel) the service needs, then applies
/// the returned [ActionResult] — invalidating the mapped providers and showing
/// a snackbar for any message. Every widget *and* the F5 shortcut funnel
/// through here, so behaviour (incl. auth-retry) is identical everywhere.
class GitActionsController {
  GitActionsController(this._ref);
  final Ref _ref;

  /// `git fetch` with progress + auth-retry.
  Future<ActionResult> fetch(BuildContext context, RepoLocation repo) {
    return _run(
      context,
      repo,
      key: 'fetch',
      scopes: _refScopes,
      (prompt, progress) => _ref
          .read(gitActionsServiceProvider)
          .fetch(repo, prompt: prompt, progress: progress),
    );
  }

  /// `git pull` using the user's configured default strategy.
  Future<ActionResult> pull(BuildContext context, RepoLocation repo) {
    final settings = _ref.read(appSettingsProvider);
    final strategy = switch (settings.defaultPullStrategy) {
      DefaultPullStrategy.ffOnly => PullStrategy.ffOnly,
      DefaultPullStrategy.merge => PullStrategy.merge,
      DefaultPullStrategy.rebase => PullStrategy.rebase,
    };
    return _run(
      context,
      repo,
      key: 'pull',
      scopes: _fullScopes,
      (prompt, progress) => _ref
          .read(gitActionsServiceProvider)
          .pull(repo, strategy, prompt: prompt, progress: progress),
    );
  }

  /// `git push` with progress + auth-retry; the optional knobs mirror
  /// [GitActionsService.push] (single ref, --force-with-lease, --tags).
  Future<ActionResult> push(
    BuildContext context,
    RepoLocation repo, {
    String? remote,
    String? branch,
    bool forceWithLease = false,
    bool pushTags = false,
  }) {
    return _run(
      context,
      repo,
      key: 'push:${remote ?? ''}/${branch ?? ''}',
      scopes: _refScopes,
      (prompt, progress) => _ref
          .read(gitActionsServiceProvider)
          .push(
            repo,
            remote: remote,
            branch: branch,
            forceWithLease: forceWithLease,
            pushTags: pushTags,
            prompt: prompt,
            progress: progress,
          ),
    );
  }

  /// `git push <remote> <tag>` with progress + auth-retry.
  Future<ActionResult> pushTag(
    BuildContext context,
    RepoLocation repo,
    String tagName,
  ) {
    return _run(
      context,
      repo,
      key: 'push-tag:$tagName',
      scopes: _tagScopes,
      (prompt, progress) => _ref
          .read(gitActionsServiceProvider)
          .pushTag(repo, tagName, prompt: prompt, progress: progress),
    );
  }

  /// `git fetch <remote>` with progress + auth-retry.
  Future<ActionResult> fetchRemote(
    BuildContext context,
    RepoLocation repo,
    String remoteName,
  ) {
    return _run(
      context,
      repo,
      key: 'fetch:$remoteName',
      scopes: _refScopes,
      (prompt, progress) => _ref
          .read(gitActionsServiceProvider)
          .fetchRemote(repo, remoteName, prompt: prompt, progress: progress),
    );
  }

  /// Fetches GitHub PR [number] into `pr/<number>` and checks it out.
  Future<ActionResult> checkoutPullRequest(
    BuildContext context,
    RepoLocation repo,
    int number,
  ) {
    return _run(
      context,
      repo,
      key: 'pr-checkout:$number',
      scopes: _fullScopes,
      (prompt, progress) => _ref
          .read(gitActionsServiceProvider)
          .checkoutPullRequest(
            repo,
            number,
            prompt: prompt,
            progress: progress,
          ),
    );
  }

  /// `git merge <ref>` into the current branch.
  Future<ActionResult> merge(
    RepoLocation repo,
    String ref,
    MergeStrategy strategy,
  ) => _runLocal(
    repo,
    key: 'merge:$ref',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).merge(repo, ref, strategy),
  );

  /// `git rebase <upstream>`.
  Future<ActionResult> rebase(
    RepoLocation repo,
    String upstream,
  ) => _runLocal(
    repo,
    key: 'rebase:$upstream',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).rebase(repo, upstream),
  );

  /// `git cherry-pick <sha>` onto the current branch.
  Future<ActionResult> cherryPick(
    RepoLocation repo,
    CommitSha sha,
  ) => _runLocal(
    repo,
    key: 'cherry-pick:${sha.value}',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).cherryPick(repo, sha),
  );

  /// `git revert <sha>`.
  Future<ActionResult> revert(
    RepoLocation repo,
    CommitSha sha,
  ) => _runLocal(
    repo,
    key: 'revert:${sha.value}',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).revert(repo, sha),
  );

  /// `git reset --<mode>` to [to].
  Future<ActionResult> reset(
    RepoLocation repo,
    CommitSha to,
    ResetMode mode,
  ) => _runLocal(
    repo,
    key: 'reset:${to.value}',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).reset(repo, to, mode),
  );

  /// `git rebase -i` driven by a scripted [plan].
  Future<ActionResult> interactiveRebase(
    RepoLocation repo,
    CommitSha onto,
    List<RebaseTodoEntry> plan,
  ) => _runLocal(
    repo,
    key: 'rebase-i:${onto.value}',
    scopes: _fullScopes,
    () => _ref
        .read(gitActionsServiceProvider)
        .interactiveRebase(repo, onto, plan),
  );

  /// Rewrites [sha]'s commit message via a scripted rebase.
  Future<ActionResult> rewordCommit(
    RepoLocation repo,
    CommitSha sha,
    String message,
  ) => _runLocal(
    repo,
    key: 'reword:${sha.value}',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).rewordCommit(repo, sha, message),
  );

  /// Starts a rebase paused at [sha] for amending.
  Future<ActionResult> editAtCommit(
    RepoLocation repo,
    CommitSha sha,
  ) => _runLocal(
    repo,
    key: 'edit:${sha.value}',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).editAtCommit(repo, sha),
  );

  /// `git checkout <ref>`.
  Future<ActionResult> checkout(
    RepoLocation repo,
    String ref,
  ) => _runLocal(
    repo,
    key: 'checkout:$ref',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).checkout(repo, ref),
    busyLabel: 'Checking out $ref…',
  );

  /// `git checkout --track <remoteRef>` (remote branch → local branch).
  Future<ActionResult> checkoutTrack(
    RepoLocation repo,
    String remoteRef,
  ) => _runLocal(
    repo,
    key: 'checkout:$remoteRef',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).checkoutTrack(repo, remoteRef),
    busyLabel: 'Checking out $remoteRef…',
  );

  /// `git branch <name>` (optionally at [at], optionally checked out).
  Future<ActionResult> createBranch(
    RepoLocation repo,
    String name, {
    CommitSha? at,
    bool checkout = false,
  }) => _runLocal(
    repo,
    key: 'branch-create:$name',
    scopes: checkout ? _fullScopes : _refScopes,
    () => _ref
        .read(gitActionsServiceProvider)
        .createBranch(repo, name, at: at, checkout: checkout),
  );

  /// `git branch -m <old> <new>`.
  Future<ActionResult> renameBranch(
    RepoLocation repo,
    String oldName,
    String newName,
  ) => _runLocal(
    repo,
    key: 'branch-rename:$oldName',
    scopes: _refScopes,
    () => _ref
        .read(gitActionsServiceProvider)
        .renameBranch(repo, oldName, newName),
  );

  /// `git branch -d/-D <name>`.
  Future<ActionResult> deleteBranch(
    RepoLocation repo,
    String name, {
    bool force = false,
  }) => _runLocal(
    repo,
    key: 'branch-delete:$name',
    scopes: _refScopes,
    busyLabel: 'Deleting branch $name…',
    () => _ref
        .read(gitActionsServiceProvider)
        .deleteBranch(repo, name, force: force),
  );

  /// `git push <remote> --delete <branch>` with progress + auth-retry.
  Future<ActionResult> deleteRemoteBranch(
    BuildContext context,
    RepoLocation repo,
    String remoteRef,
  ) {
    return _run(
      context,
      repo,
      key: 'branch-delete-remote:$remoteRef',
      scopes: _refScopes,
      (prompt, progress) => _ref
          .read(gitActionsServiceProvider)
          .deleteRemoteBranch(
            repo,
            remoteRef,
            prompt: prompt,
            progress: progress,
          ),
    );
  }

  /// Deletes the selected sides of a branch (remote then local). The sides are
  /// independent — a failure on one does not skip the other. Returns whether
  /// the LOCAL delete failed only because the branch is not fully merged, so
  /// the caller can offer a force retry.
  Future<({bool localNeedsForce})> deleteBranchTargets(
    BuildContext context,
    RepoLocation repo, {
    String? remoteRef,
    String? localName,
    bool forceLocal = false,
  }) async {
    if (remoteRef != null) {
      await deleteRemoteBranch(context, repo, remoteRef);
    }
    var localNeedsForce = false;
    if (localName != null && context.mounted) {
      final result = await deleteBranch(repo, localName, force: forceLocal);
      localNeedsForce =
          !forceLocal &&
          result.outcome == ActionOutcome.failed &&
          isNotFullyMergedError(result.message ?? '');
    }
    return (localNeedsForce: localNeedsForce);
  }

  /// One pending lifecycle and one sidebar/graph reload for a whole batch.
  /// Server-side deletes keep the push auth path (saved account, prompt on an
  /// auth failure); their progress records finish once the views reloaded.
  Future<ActionRun<List<BranchDeleteResult>>> deleteBranches(
    BuildContext context,
    RepoLocation repo,
    List<BranchDeleteRequest> requests, {
    void Function(int done, int total)? onProgress,
  }) async {
    final prompt = DialogAuthPrompt(context, _ref);
    final pushed = <String>[];
    final run = await _ref
        .read(actionRunnerProvider)
        .runAndRefresh(
          key: 'branch-delete-batch',
          repo: repo,
          scopes: _refScopes,
          label: 'Deleting branches…',
          action: () => _ref
              .read(branchDeletionFlowProvider)
              .deleteMany(
                repo,
                requests,
                onProgress: onProgress,
                deleteRemote: (remoteRef) async {
                  final result = await _ref
                      .read(gitActionsServiceProvider)
                      .deleteRemoteBranch(
                        repo,
                        remoteRef,
                        prompt: prompt,
                        progress: OperationsProgressSink(_ref),
                      );
                  if (result.operationId case final id?) pushed.add(id);
                  return result.outcome == ActionOutcome.failed
                      ? 'Could not delete the branch on the server.'
                      : null;
                },
              ),
        );
    pushed.forEach(_ref.read(operationsProvider.notifier).finishSuccess);
    return run;
  }

  Future<ActionRun<BranchDeleteResult>> removeWorktreeWithBranch(
    RepoLocation repo,
    String path, {
    bool force = false,
    bool deleteBranch = false,
    bool forceBranch = false,
  }) => _ref
      .read(actionRunnerProvider)
      .runAndRefresh(
        key: 'worktree-remove:$path',
        repo: repo,
        scopes: _refScopes,
        label: 'Removing worktree…',
        action: () => _ref
            .read(branchDeletionFlowProvider)
            .removeWorktree(
              repo,
              path,
              force: force,
              deleteBranch: deleteBranch,
              forceBranch: forceBranch,
            ),
      );

  /// `git branch --set-upstream-to=<upstream> <branch>`.
  Future<ActionResult> setUpstream(
    RepoLocation repo,
    String branch,
    String upstream,
  ) => _runLocal(
    repo,
    key: 'upstream:$branch',
    scopes: _refScopes,
    () => _ref
        .read(gitActionsServiceProvider)
        .setUpstream(repo, branch, upstream),
  );

  /// `git tag <name>` (optionally at [at]).
  Future<ActionResult> createTag(
    RepoLocation repo,
    String name, {
    CommitSha? at,
    String? message,
  }) => _runLocal(
    repo,
    key: 'tag-create:$name',
    scopes: _tagScopes,
    () => _ref
        .read(gitActionsServiceProvider)
        .createTag(repo, name, at: at, message: message),
  );

  /// `git tag -d <name>`.
  Future<ActionResult> deleteTag(
    RepoLocation repo,
    String name,
  ) => _runLocal(
    repo,
    key: 'tag-delete:$name',
    scopes: _tagScopes,
    () => _ref.read(gitActionsServiceProvider).deleteTag(repo, name),
  );

  /// `git stash push`.
  Future<ActionResult> stashSave(
    RepoLocation repo,
    String message, {
    bool includeUntracked = false,
    List<String> paths = const [],
  }) => _runLocal(
    repo,
    key: 'stash-save',
    scopes: _stashScopes,
    () => _ref
        .read(gitActionsServiceProvider)
        .stashSave(
          repo,
          message,
          includeUntracked: includeUntracked,
          paths: paths,
        ),
  );

  /// `git stash apply stash@{index}`.
  Future<ActionResult> stashApply(
    BuildContext context,
    RepoLocation repo,
    int index,
  ) => _applyStash(context, repo, index, pop: false);

  /// `git stash pop stash@{index}`.
  Future<ActionResult> stashPop(
    BuildContext context,
    RepoLocation repo,
    int index,
  ) => _applyStash(context, repo, index, pop: true);

  Future<ActionResult> _applyStash(
    BuildContext context,
    RepoLocation repo,
    int index, {
    required bool pop,
  }) async {
    final safety = _ref.read(stashSafetyOperationsProvider);
    final checked = await safety.overlap(repo, index);
    if (!context.mounted) return const ActionResult(ActionOutcome.failed);
    if (checked case GitFailure<List<String>>(:final message)) {
      final result = ActionResult(
        ActionOutcome.failed,
        message: 'Stash check failed: $message',
        severity: MessageSeverity.error,
      );
      _ref.read(actionFeedbackProvider).showActionFailure(result.message!);
      return result;
    }
    final paths = (checked as GitSuccess<List<String>>).value;
    if (paths.isEmpty) {
      return _runLocal(
        repo,
        key: 'stash-restore:$index',
        scopes: _stashScopes,
        () => pop
            ? _ref.read(gitActionsServiceProvider).stashPop(repo, index)
            : _ref.read(gitActionsServiceProvider).stashApply(repo, index),
      );
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Stash overlaps local changes',
        width: 560,
        subtitle:
            'These files have changes in both the stash and your worktree.',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final path in paths) Text(path)],
        ),
        actions: [
          AppButton.secondary(
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton.primary(
            label: pop
                ? 'Stash my changes and pop'
                : 'Stash my changes and apply',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return const ActionResult(ActionOutcome.failed);
    }
    return _runLocal(
      repo,
      key: 'stash-restore:$index',
      scopes: _stashScopes,
      () async {
        final result = await safety.applyPreservingLocal(repo, index, pop: pop);
        return switch (result) {
          GitSuccess<StashRestoreResult>(:final value) when value.hasConflict =>
            ActionResult(
              ActionOutcome.conflict,
              message:
                  'Local edits conflicted while restoring. Resolve in the '
                  'conflicts panel. Your local edits remain in '
                  '${value.localStash}. '
                  'The target stash was kept.',
              severity: MessageSeverity.error,
            ),
          GitSuccess<StashRestoreResult>() => const ActionResult(
            ActionOutcome.success,
          ),
          GitFailure<StashRestoreResult>(:final message) => ActionResult(
            ActionOutcome.failed,
            message: 'Stash apply failed: $message',
            severity: MessageSeverity.error,
          ),
        };
      },
    );
  }

  /// `git stash drop stash@{index}`.
  Future<ActionResult> stashDrop(
    RepoLocation repo,
    int index,
  ) => _runLocal(
    repo,
    key: 'stash-drop:$index',
    scopes: _stashScopes,
    () => _ref.read(gitActionsServiceProvider).stashDrop(repo, index),
  );

  /// Resolves a conflicted file by taking one side wholesale.
  Future<ActionResult> takeConflictSide(
    RepoLocation repo,
    String path, {
    required bool ours,
  }) => _runLocal(
    repo,
    key: 'conflict-side:$path',
    scopes: _worktreeScopes,
    () => _ref
        .read(gitActionsServiceProvider)
        .takeConflictSide(repo, path, ours: ours),
  );

  /// Discards a unified-diff patch from the working tree.
  Future<ActionResult> discardHunk(
    RepoLocation repo,
    String patch,
  ) => _runLocal(
    repo,
    key: 'discard-hunk:${patch.hashCode}',
    scopes: _worktreeScopes,
    () => _ref.read(gitActionsServiceProvider).discardHunk(repo, patch),
  );

  /// `git merge --abort`.
  Future<ActionResult> mergeAbort(RepoLocation repo) => _runLocal(
    repo,
    key: 'merge-abort',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).mergeAbort(repo),
  );

  /// `git merge --continue`.
  Future<ActionResult> mergeContinue(RepoLocation repo) => _runLocal(
    repo,
    key: 'merge-continue',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).mergeContinue(repo),
  );

  /// `git cherry-pick --abort`.
  Future<ActionResult> cherryPickAbort(RepoLocation repo) => _runLocal(
    repo,
    key: 'cherry-pick-abort',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).cherryPickAbort(repo),
  );

  /// `git cherry-pick --continue`.
  Future<ActionResult> cherryPickContinue(RepoLocation repo) => _runLocal(
    repo,
    key: 'cherry-pick-continue',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).cherryPickContinue(repo),
  );

  /// `git revert --abort`.
  Future<ActionResult> revertAbort(RepoLocation repo) => _runLocal(
    repo,
    key: 'revert-abort',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).revertAbort(repo),
  );

  /// `git revert --continue`.
  Future<ActionResult> revertContinue(RepoLocation repo) => _runLocal(
    repo,
    key: 'revert-continue',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).revertContinue(repo),
  );

  /// `git rebase --abort`.
  Future<ActionResult> rebaseAbort(RepoLocation repo) => _runLocal(
    repo,
    key: 'rebase-abort',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).rebaseAbort(repo),
  );

  /// `git rebase --continue`.
  Future<ActionResult> rebaseContinue(RepoLocation repo) => _runLocal(
    repo,
    key: 'rebase-continue',
    scopes: _fullScopes,
    () => _ref.read(gitActionsServiceProvider).rebaseContinue(repo),
  );

  /// Streamed network action: the progress record it starts stays running
  /// until the runner's refresh lands, so the toast never claims success
  /// before the graph and sidebar show the new commits.
  Future<ActionResult> _run(
    BuildContext context,
    RepoLocation repo,
    Future<ActionResult> Function(AuthPrompt prompt, ProgressSink progress)
    op, {
    required String key,
    required Set<RefreshScope> scopes,
  }) async {
    return _finish(
      await _ref
          .read(actionRunnerProvider)
          .runAndRefresh<ActionResult>(
            key: key,
            repo: repo,
            scopes: scopes,
            action: () => op(
              DialogAuthPrompt(context, _ref),
              OperationsProgressSink(_ref),
            ),
            failed: (result) => result.outcome == ActionOutcome.failed,
            operationId: (result) => result.operationId,
          ),
    );
  }

  /// Local (non-streamed) action: no progress toast while it runs — the
  /// blocking indicator is the feedback, and it stays up until the declared
  /// views have reloaded.
  Future<ActionResult> _runLocal(
    RepoLocation repo,
    Future<ActionResult> Function() op, {
    required String key,
    required Set<RefreshScope> scopes,
    String? busyLabel,
  }) async {
    return _finish(
      await _ref
          .read(actionRunnerProvider)
          .runAndRefresh<ActionResult>(
            key: key,
            repo: repo,
            scopes: scopes,
            label: busyLabel,
            action: op,
            failed: (result) => result.outcome == ActionOutcome.failed,
          ),
    );
  }

  /// Surfaces the action's own message (git's words) on the shared feedback
  /// surface. A refresh failure is reported by the runner instead, so it can
  /// never read as a failed command.
  ActionResult _finish(ActionRun<ActionResult> run) {
    final result = run.value;
    if (result == null) return const ActionResult(ActionOutcome.failed);
    final message = result.message;
    if (message != null && run.status != ActionRunStatus.stale) {
      final feedback = _ref.read(actionFeedbackProvider);
      if (result.severity == MessageSeverity.error) {
        feedback.showActionFailure(message);
      } else {
        feedback.showActionSuccess(message);
      }
    }
    return result;
  }
}

/// Everything a worktree-changing action touches.
const Set<RefreshScope> _fullScopes = {
  RefreshScope.status,
  RefreshScope.branches,
  RefreshScope.sidebar,
  RefreshScope.graph,
  RefreshScope.repoState,
  RefreshScope.workingCopy,
};

/// Ref bookkeeping: branches move, the worktree does not.
const Set<RefreshScope> _refScopes = {
  RefreshScope.status,
  RefreshScope.branches,
  RefreshScope.sidebar,
  RefreshScope.graph,
  RefreshScope.repoState,
};

/// Tags decorate the graph and list in the sidebar; no branch list changes.
const Set<RefreshScope> _tagScopes = {
  RefreshScope.status,
  RefreshScope.sidebar,
  RefreshScope.graph,
  RefreshScope.repoState,
};

/// Stashes change the worktree and the sidebar's stash list, not the graph.
const Set<RefreshScope> _stashScopes = {
  RefreshScope.status,
  RefreshScope.sidebar,
  RefreshScope.repoState,
  RefreshScope.workingCopy,
};

/// Worktree-only edits (conflict sides, hunk discards).
const Set<RefreshScope> _worktreeScopes = {
  RefreshScope.status,
  RefreshScope.repoState,
  RefreshScope.workingCopy,
};
