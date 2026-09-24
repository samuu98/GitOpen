import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/branch_deletion.dart';
import 'package:gitopen/application/git/git_action_ports.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/git/stash_safety_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/git/git_action_bridges.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

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
    BuildContext context,
    RepoLocation repo,
    String ref,
    MergeStrategy strategy,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).merge(repo, ref, strategy),
  );

  /// `git rebase <upstream>`.
  Future<ActionResult> rebase(
    BuildContext context,
    RepoLocation repo,
    String upstream,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).rebase(repo, upstream),
  );

  /// `git cherry-pick <sha>` onto the current branch.
  Future<ActionResult> cherryPick(
    BuildContext context,
    RepoLocation repo,
    CommitSha sha,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).cherryPick(repo, sha),
  );

  /// `git revert <sha>`.
  Future<ActionResult> revert(
    BuildContext context,
    RepoLocation repo,
    CommitSha sha,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).revert(repo, sha),
  );

  /// `git reset --<mode>` to [to].
  Future<ActionResult> reset(
    BuildContext context,
    RepoLocation repo,
    CommitSha to,
    ResetMode mode,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).reset(repo, to, mode),
  );

  /// `git rebase -i` driven by a scripted [plan].
  Future<ActionResult> interactiveRebase(
    BuildContext context,
    RepoLocation repo,
    CommitSha onto,
    List<RebaseTodoEntry> plan,
  ) => _runLocal(
    context,
    repo,
    () => _ref
        .read(gitActionsServiceProvider)
        .interactiveRebase(repo, onto, plan),
  );

  /// Rewrites [sha]'s commit message via a scripted rebase.
  Future<ActionResult> rewordCommit(
    BuildContext context,
    RepoLocation repo,
    CommitSha sha,
    String message,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).rewordCommit(repo, sha, message),
  );

  /// Starts a rebase paused at [sha] for amending.
  Future<ActionResult> editAtCommit(
    BuildContext context,
    RepoLocation repo,
    CommitSha sha,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).editAtCommit(repo, sha),
  );

  /// `git checkout <ref>`.
  Future<ActionResult> checkout(
    BuildContext context,
    RepoLocation repo,
    String ref,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).checkout(repo, ref),
    busyLabel: 'Checking out $ref…',
    afterSuccess: () => _waitForCheckoutRefresh(repo),
  );

  /// `git checkout --track <remoteRef>` (remote branch → local branch).
  Future<ActionResult> checkoutTrack(
    BuildContext context,
    RepoLocation repo,
    String remoteRef,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).checkoutTrack(repo, remoteRef),
    busyLabel: 'Checking out $remoteRef…',
    afterSuccess: () => _waitForCheckoutRefresh(repo),
  );

  /// `git branch <name>` (optionally at [at], optionally checked out).
  Future<ActionResult> createBranch(
    BuildContext context,
    RepoLocation repo,
    String name, {
    CommitSha? at,
    bool checkout = false,
  }) => _runLocal(
    context,
    repo,
    () => _ref
        .read(gitActionsServiceProvider)
        .createBranch(repo, name, at: at, checkout: checkout),
  );

  /// `git branch -m <old> <new>`.
  Future<ActionResult> renameBranch(
    BuildContext context,
    RepoLocation repo,
    String oldName,
    String newName,
  ) => _runLocal(
    context,
    repo,
    () => _ref
        .read(gitActionsServiceProvider)
        .renameBranch(repo, oldName, newName),
  );

  /// `git branch -d/-D <name>`.
  Future<ActionResult> deleteBranch(
    BuildContext context,
    RepoLocation repo,
    String name, {
    bool force = false,
  }) => _runLocal(
    context,
    repo,
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
      final result = await deleteBranch(
        context,
        repo,
        localName,
        force: forceLocal,
      );
      localNeedsForce =
          !forceLocal &&
          result.outcome == ActionOutcome.failed &&
          isNotFullyMergedError(result.message ?? '');
    }
    return (localNeedsForce: localNeedsForce);
  }

  /// `git branch --set-upstream-to=<upstream> <branch>`.
  Future<ActionResult> setUpstream(
    BuildContext context,
    RepoLocation repo,
    String branch,
    String upstream,
  ) => _runLocal(
    context,
    repo,
    () => _ref
        .read(gitActionsServiceProvider)
        .setUpstream(repo, branch, upstream),
  );

  /// `git tag <name>` (optionally at [at]).
  Future<ActionResult> createTag(
    BuildContext context,
    RepoLocation repo,
    String name, {
    CommitSha? at,
    String? message,
  }) => _runLocal(
    context,
    repo,
    () => _ref
        .read(gitActionsServiceProvider)
        .createTag(repo, name, at: at, message: message),
  );

  /// `git tag -d <name>`.
  Future<ActionResult> deleteTag(
    BuildContext context,
    RepoLocation repo,
    String name,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).deleteTag(repo, name),
  );

  /// `git stash push`.
  Future<ActionResult> stashSave(
    BuildContext context,
    RepoLocation repo,
    String message, {
    bool includeUntracked = false,
    List<String> paths = const [],
  }) => _runLocal(
    context,
    repo,
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
      _showSnack(context, result.message!, result.severity);
      return result;
    }
    final paths = (checked as GitSuccess<List<String>>).value;
    if (paths.isEmpty) {
      return _runLocal(
        context,
        repo,
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
    return _runLocal(context, repo, () async {
      final result = await safety.applyPreservingLocal(repo, index, pop: pop);
      return switch (result) {
        GitSuccess<StashRestoreResult>(:final value) when value.hasConflict =>
          ActionResult(
            ActionOutcome.conflict,
            invalidate: const {RepoDataScope.reads, RepoDataScope.repoState},
            message:
                'Local edits conflicted while restoring. Resolve in the '
                'conflicts panel. Your local edits remain in '
                '${value.localStash}. '
                'The target stash was kept.',
            severity: MessageSeverity.error,
          ),
        GitSuccess<StashRestoreResult>() => const ActionResult(
          ActionOutcome.success,
          invalidate: {RepoDataScope.reads, RepoDataScope.repoState},
        ),
        GitFailure<StashRestoreResult>(:final message) => ActionResult(
          ActionOutcome.failed,
          invalidate: const {RepoDataScope.reads, RepoDataScope.repoState},
          message: 'Stash apply failed: $message',
          severity: MessageSeverity.error,
        ),
      };
    });
  }

  /// `git stash drop stash@{index}`.
  Future<ActionResult> stashDrop(
    BuildContext context,
    RepoLocation repo,
    int index,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).stashDrop(repo, index),
  );

  /// Resolves a conflicted file by taking one side wholesale.
  Future<ActionResult> takeConflictSide(
    BuildContext context,
    RepoLocation repo,
    String path, {
    required bool ours,
  }) => _runLocal(
    context,
    repo,
    () => _ref
        .read(gitActionsServiceProvider)
        .takeConflictSide(repo, path, ours: ours),
  );

  /// Discards a unified-diff patch from the working tree.
  Future<ActionResult> discardHunk(
    BuildContext context,
    RepoLocation repo,
    String patch,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).discardHunk(repo, patch),
  );

  /// `git merge --abort`.
  Future<ActionResult> mergeAbort(BuildContext context, RepoLocation repo) =>
      _runLocal(
        context,
        repo,
        () => _ref.read(gitActionsServiceProvider).mergeAbort(repo),
      );

  /// `git merge --continue`.
  Future<ActionResult> mergeContinue(
    BuildContext context,
    RepoLocation repo,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).mergeContinue(repo),
  );

  /// `git cherry-pick --abort`.
  Future<ActionResult> cherryPickAbort(
    BuildContext context,
    RepoLocation repo,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).cherryPickAbort(repo),
  );

  /// `git cherry-pick --continue`.
  Future<ActionResult> cherryPickContinue(
    BuildContext context,
    RepoLocation repo,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).cherryPickContinue(repo),
  );

  /// `git revert --abort`.
  Future<ActionResult> revertAbort(BuildContext context, RepoLocation repo) =>
      _runLocal(
        context,
        repo,
        () => _ref.read(gitActionsServiceProvider).revertAbort(repo),
      );

  /// `git revert --continue`.
  Future<ActionResult> revertContinue(
    BuildContext context,
    RepoLocation repo,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).revertContinue(repo),
  );

  /// `git rebase --abort`.
  Future<ActionResult> rebaseAbort(BuildContext context, RepoLocation repo) =>
      _runLocal(
        context,
        repo,
        () => _ref.read(gitActionsServiceProvider).rebaseAbort(repo),
      );

  /// `git rebase --continue`.
  Future<ActionResult> rebaseContinue(
    BuildContext context,
    RepoLocation repo,
  ) => _runLocal(
    context,
    repo,
    () => _ref.read(gitActionsServiceProvider).rebaseContinue(repo),
  );

  Future<ActionResult> _run(
    BuildContext context,
    RepoLocation repo,
    Future<ActionResult> Function(AuthPrompt prompt, ProgressSink progress) op,
  ) async {
    final busy = _ref.read(busyProvider.notifier)..begin();
    try {
      final result = await op(
        DialogAuthPrompt(context, _ref),
        OperationsProgressSink(_ref),
      );
      _invalidate(repo, result.invalidate);
      final message = result.message;
      if (message != null && context.mounted) {
        _showSnack(context, message, result.severity);
      }
      return result;
    } finally {
      busy.end();
    }
  }

  Future<ActionResult> _runLocal(
    BuildContext context,
    RepoLocation repo,
    Future<ActionResult> Function() op, {
    String? busyLabel,
    Future<void> Function()? afterSuccess,
  }) async {
    final busy = _ref.read(busyProvider.notifier)..begin(busyLabel);
    try {
      final result = await op();
      _invalidate(repo, result.invalidate);
      if (result.outcome == ActionOutcome.success) {
        await afterSuccess?.call();
      }
      final message = result.message;
      if (message != null && context.mounted) {
        _showSnack(context, message, result.severity);
      }
      return result;
    } finally {
      busy.end();
    }
  }

  Future<void> _waitForCheckoutRefresh(RepoLocation repo) async {
    _ref
      ..invalidate(repoStatusProvider(repo))
      ..invalidate(localBranchesProvider(repo))
      ..invalidate(remoteBranchesProvider(repo));
    await Future.wait<void>([
      _ignoreRefreshError(_ref.read(repoStatusProvider(repo).future)),
      _ignoreRefreshError(_ref.read(branchesProvider(repo).future)),
    ]);
  }

  Future<void> _ignoreRefreshError<T>(Future<T> future) async {
    try {
      await future;
    } on Object {
      // The checkout already completed; let the normal consumers render the
      // provider error instead of keeping the blocking overlay stuck.
    }
  }

  void _invalidate(RepoLocation repo, Set<RepoDataScope> scopes) {
    // Needs no context; runs whether or not the caller is still mounted.
    for (final scope in scopes) {
      switch (scope) {
        case RepoDataScope.reads:
          _ref.invalidate(gitReadOperationsProvider);
        case RepoDataScope.repoState:
          _ref.invalidate(repoStateProvider(repo));
      }
    }
  }

  void _showSnack(
    BuildContext context,
    String message,
    MessageSeverity? severity,
  ) {
    final palette = AppPalette.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: severity == MessageSeverity.error
            ? palette.accentErr
            : null,
      ),
    );
  }
}
