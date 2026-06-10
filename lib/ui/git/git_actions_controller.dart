import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/git/auth_failure_classifier.dart';
import 'package:gitopen/application/git/git_action_ports.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/account_switcher_dialog.dart';
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

  /// `git push` with progress + auth-retry.
  Future<ActionResult> push(BuildContext context, RepoLocation repo) {
    return _run(
      context,
      repo,
      (prompt, progress) => _ref
          .read(gitActionsServiceProvider)
          .push(repo, prompt: prompt, progress: progress),
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

  /// `git merge <ref>` into the current branch.
  Future<ActionResult> merge(
    BuildContext context,
    RepoLocation repo,
    String ref,
    MergeStrategy strategy,
  ) =>
      _runLocal(
        context,
        repo,
        () => _ref.read(gitActionsServiceProvider).merge(repo, ref, strategy),
      );

  /// `git rebase <upstream>`.
  Future<ActionResult> rebase(
    BuildContext context,
    RepoLocation repo,
    String upstream,
  ) =>
      _runLocal(
        context,
        repo,
        () => _ref.read(gitActionsServiceProvider).rebase(repo, upstream),
      );

  /// `git cherry-pick <sha>` onto the current branch.
  Future<ActionResult> cherryPick(
    BuildContext context,
    RepoLocation repo,
    CommitSha sha,
  ) =>
      _runLocal(
        context,
        repo,
        () => _ref.read(gitActionsServiceProvider).cherryPick(repo, sha),
      );

  /// `git revert <sha>`.
  Future<ActionResult> revert(
    BuildContext context,
    RepoLocation repo,
    CommitSha sha,
  ) =>
      _runLocal(
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
  ) =>
      _runLocal(
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
  ) =>
      _runLocal(
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
  ) =>
      _runLocal(
        context,
        repo,
        () => _ref
            .read(gitActionsServiceProvider)
            .rewordCommit(repo, sha, message),
      );

  /// Starts a rebase paused at [sha] for amending.
  Future<ActionResult> editAtCommit(
    BuildContext context,
    RepoLocation repo,
    CommitSha sha,
  ) =>
      _runLocal(
        context,
        repo,
        () => _ref.read(gitActionsServiceProvider).editAtCommit(repo, sha),
      );

  /// `git checkout <ref>`.
  Future<ActionResult> checkout(
    BuildContext context,
    RepoLocation repo,
    String ref,
  ) =>
      _runLocal(
        context,
        repo,
        () => _ref.read(gitActionsServiceProvider).checkout(repo, ref),
      );

  /// `git checkout --track <remoteRef>` (remote branch → local branch).
  Future<ActionResult> checkoutTrack(
    BuildContext context,
    RepoLocation repo,
    String remoteRef,
  ) =>
      _runLocal(
        context,
        repo,
        () => _ref
            .read(gitActionsServiceProvider)
            .checkoutTrack(repo, remoteRef),
      );

  /// `git branch <name>` (optionally at [at], optionally checked out).
  Future<ActionResult> createBranch(
    BuildContext context,
    RepoLocation repo,
    String name, {
    CommitSha? at,
    bool checkout = false,
  }) =>
      _runLocal(
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
  ) =>
      _runLocal(
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
  }) =>
      _runLocal(
        context,
        repo,
        () => _ref
            .read(gitActionsServiceProvider)
            .deleteBranch(repo, name, force: force),
      );

  /// `git branch --set-upstream-to=<upstream> <branch>`.
  Future<ActionResult> setUpstream(
    BuildContext context,
    RepoLocation repo,
    String branch,
    String upstream,
  ) =>
      _runLocal(
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
  }) =>
      _runLocal(
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
  ) =>
      _runLocal(
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
  }) =>
      _runLocal(
        context,
        repo,
        () => _ref.read(gitActionsServiceProvider).stashSave(
              repo,
              message,
              includeUntracked: includeUntracked,
            ),
      );

  /// `git stash apply stash@{index}`.
  Future<ActionResult> stashApply(
    BuildContext context,
    RepoLocation repo,
    int index,
  ) =>
      _runLocal(
        context,
        repo,
        () => _ref.read(gitActionsServiceProvider).stashApply(repo, index),
      );

  /// `git stash pop stash@{index}`.
  Future<ActionResult> stashPop(
    BuildContext context,
    RepoLocation repo,
    int index,
  ) =>
      _runLocal(
        context,
        repo,
        () => _ref.read(gitActionsServiceProvider).stashPop(repo, index),
      );

  /// `git stash drop stash@{index}`.
  Future<ActionResult> stashDrop(
    BuildContext context,
    RepoLocation repo,
    int index,
  ) =>
      _runLocal(
        context,
        repo,
        () => _ref.read(gitActionsServiceProvider).stashDrop(repo, index),
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
  ) =>
      _runLocal(
        context,
        repo,
        () => _ref.read(gitActionsServiceProvider).mergeContinue(repo),
      );

  /// `git cherry-pick --abort`.
  Future<ActionResult> cherryPickAbort(
    BuildContext context,
    RepoLocation repo,
  ) =>
      _runLocal(
        context,
        repo,
        () => _ref.read(gitActionsServiceProvider).cherryPickAbort(repo),
      );

  /// `git cherry-pick --continue`.
  Future<ActionResult> cherryPickContinue(
    BuildContext context,
    RepoLocation repo,
  ) =>
      _runLocal(
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
  ) =>
      _runLocal(
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
  ) =>
      _runLocal(
        context,
        repo,
        () => _ref.read(gitActionsServiceProvider).rebaseContinue(repo),
      );

  Future<ActionResult> _run(
    BuildContext context,
    RepoLocation repo,
    Future<ActionResult> Function(AuthPrompt prompt, ProgressSink progress) op,
  ) async {
    final result = await op(
      _DialogAuthPrompt(context, _ref),
      _OperationsProgressSink(_ref),
    );
    _invalidate(repo, result.invalidate);
    final message = result.message;
    if (message != null && context.mounted) {
      _showSnack(context, message, result.severity);
    }
    return result;
  }

  Future<ActionResult> _runLocal(
    BuildContext context,
    RepoLocation repo,
    Future<ActionResult> Function() op,
  ) async {
    final result = await op();
    _invalidate(repo, result.invalidate);
    final message = result.message;
    if (message != null && context.mounted) {
      _showSnack(context, message, result.severity);
    }
    return result;
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
        backgroundColor:
            severity == MessageSeverity.error ? palette.accentErr : null,
      ),
    );
  }
}

/// Bridges the pure [AuthPrompt] to the account-switcher dialog. Captures the
/// [BuildContext] for the duration of one action.
class _DialogAuthPrompt implements AuthPrompt {
  _DialogAuthPrompt(this._context, this._ref);
  final BuildContext _context;
  final Ref _ref;

  @override
  Future<AuthProfile?> forAccount(
    RepoLocation repo,
    AuthFailureReason reason,
  ) async {
    final host =
        await _ref.read(authResolverProvider).hostFromRepo(repo, 'origin') ??
            'github.com';
    if (!_context.mounted) return null;
    final chosen = await AccountSwitcherDialog.show(
      _context,
      host: host,
      contextMessage: switch (reason) {
        AuthFailureReason.wrongAccount =>
          'Git returned "repository not found" — the active account likely '
              'cannot see this repo.',
        AuthFailureReason.authRequired => 'The active credential was rejected.',
      },
    );
    if (chosen == null) return null;
    await _ref
        .read(appSettingsProvider.notifier)
        .setAuthBinding(repo.id.value, chosen.id);
    return chosen;
  }
}

/// Bridges the pure [ProgressSink] to the operations notifier.
class _OperationsProgressSink implements ProgressSink {
  _OperationsProgressSink(this._ref);
  final Ref _ref;

  OperationsNotifier get _ops => _ref.read(operationsProvider.notifier);

  @override
  String start(OpKind kind, String label, {RepoLocation? repo}) =>
      _ops.start(kind, label, repo: repo);

  @override
  void progress(String id, double? fraction, String phase) =>
      _ops.updateProgress(id, fraction, phase);

  @override
  void success(String id) => _ops.finishSuccess(id);

  @override
  void failure(String id, String message) => _ops.finishFailure(id, message);
}
