import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/watch/repo_change.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_providers.dart';
import 'package:gitopen/ui/operations/action_feedback.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

/// A group of views an action affects. The runner invalidates the group's
/// providers and then *waits* for the ones that are currently on screen, so an
/// action is only "done" once the user can see its result.
enum RefreshScope {
  /// `git status`: working-tree entries, ahead/behind, HEAD.
  status,

  /// Local and remote branch lists.
  branches,

  /// The sidebar's one-shot load (branches, tags, remotes, stashes, …).
  sidebar,

  /// The commit graph window and its ref decorations.
  graph,

  /// In-progress merge/rebase/bisect detection.
  repoState,

  /// The working-copy file list and the selected file's diff.
  workingCopy,
}

/// How a [ActionRunner.runAndRefresh] call ended.
enum ActionRunStatus {
  /// The action ran and every affected view reloaded.
  succeeded,

  /// The action itself failed; nothing was refreshed.
  failed,

  /// The action succeeded but a view could not reload.
  refreshFailed,

  /// The same action was already in flight, so nothing ran.
  skipped,

  /// The action completed after the repository changed; the result was
  /// dropped instead of being applied to another repository's views.
  stale,
}

/// Outcome of one [ActionRunner.runAndRefresh] call.
final class ActionRun<T> {
  const ActionRun(this.status, {this.value});
  final ActionRunStatus status;

  /// The action's own return value; null when the action never ran.
  final T? value;

  bool get ran => status != ActionRunStatus.skipped;
}

/// Shown when git did its job but the UI could not reload afterwards — never
/// phrased as a failed command.
const String refreshFailureMessage =
    'The command completed, but the view could not refresh.';

final actionRunnerProvider = Provider<ActionRunner>(ActionRunner.new);

/// Runs any write action — a git command, a GitHub API call — behind one
/// lifecycle: scoped pending state, the action, an awaited refresh of the
/// declared [RefreshScope]s, and only then success.
class ActionRunner {
  ActionRunner(this._ref) {
    _ref.onDispose(() => _disposed = true);
  }

  final Ref _ref;
  bool _disposed = false;
  final List<_ActiveRefresh> _active = [];

  /// The refreshes in flight, with the watcher scopes they already cover, so
  /// the repo auto-refresh can join them instead of starting a second one.
  ({Future<void> done, Set<RepoRefreshScope> covered})? get activeRefresh {
    if (_active.isEmpty) return null;
    return (
      done: Future.wait([for (final a in _active) a.settled.future]),
      covered: {for (final a in _active) ...a.covered},
    );
  }

  /// Runs [action] with a pending state keyed by [key], then reloads [scopes].
  ///
  /// [failed] classifies the action's own return value as a failure (a git
  /// error); when it does, nothing is refreshed and the caller reports it.
  /// [operationId] points at the progress record the action started, which
  /// becomes successful only once the refresh completed — or failed, with the
  /// refresh message and a retry.
  Future<ActionRun<T>> runAndRefresh<T>({
    required String key,
    required RepoLocation repo,
    required Set<RefreshScope> scopes,
    required Future<T> Function() action,
    String? label,
    bool Function(T value)? failed,
    String? Function(T value)? operationId,
    String? successMessage,
  }) async {
    final scopedKey = '${repo.id.value}/$key';
    final busy = _ref.read(busyProvider.notifier);
    if (_ref.read(busyProvider).isRunning(scopedKey)) {
      return ActionRun<T>(ActionRunStatus.skipped);
    }
    final generation = _ref.read(activeWorkspaceIdProvider);
    busy.begin(scopedKey, label);
    // Tracked from the first line: the git write fires watcher events while it
    // is still running, and those must join this refresh, not race it.
    return _tracked(scopes, () async {
      try {
        return await _run(
          repo: repo,
          scopes: scopes,
          action: action,
          generation: generation,
          failed: failed,
          operationId: operationId,
          successMessage: successMessage,
        );
      } finally {
        if (!_disposed) busy.end(scopedKey);
      }
    });
  }

  Future<ActionRun<T>> _run<T>({
    required RepoLocation repo,
    required Set<RefreshScope> scopes,
    required Future<T> Function() action,
    required RepoId? generation,
    bool Function(T value)? failed,
    String? Function(T value)? operationId,
    String? successMessage,
  }) async {
    final value = await action();
    if (failed?.call(value) ?? false) {
      // A failed command can still have moved the repository (a stash that
      // applied halfway, a push that updated one ref), so the views are
      // refreshed anyway — but git's own error is what the caller reports.
      if (!_isStale(generation)) {
        try {
          await _refresh(repo, scopes);
        } on Object {
          // The action already failed; one message is enough.
        }
      }
      return ActionRun<T>(ActionRunStatus.failed, value: value);
    }
    final opId = operationId?.call(value);
    if (_isStale(generation)) {
      // The command finished; record it, but never touch another repository's
      // views with it.
      if (opId != null) _operations.finishSuccess(opId);
      return ActionRun<T>(ActionRunStatus.stale, value: value);
    }
    try {
      await _refresh(repo, scopes);
    } on Object {
      void retry() => unawaited(refreshOnly(repo, scopes));
      if (opId != null) {
        _operations.finishFailure(opId, refreshFailureMessage, onRetry: retry);
      } else {
        _ref
            .read(actionFeedbackProvider)
            .showActionFailure(refreshFailureMessage, retry: retry);
      }
      return ActionRun<T>(ActionRunStatus.refreshFailed, value: value);
    }
    if (opId != null) _operations.finishSuccess(opId);
    if (successMessage != null) {
      _ref.read(actionFeedbackProvider).showActionSuccess(successMessage);
    }
    return ActionRun<T>(ActionRunStatus.succeeded, value: value);
  }

  /// Reloads [scopes] on their own — the Retry behind a refresh failure.
  Future<void> refreshOnly(RepoLocation repo, Set<RefreshScope> scopes) async {
    if (_disposed) return;
    try {
      await _tracked(scopes, () => _refresh(repo, scopes));
    } on Object {
      _ref
          .read(actionFeedbackProvider)
          .showActionFailure(
            refreshFailureMessage,
            retry: () => unawaited(refreshOnly(repo, scopes)),
          );
    }
  }

  OperationsNotifier get _operations => _ref.read(operationsProvider.notifier);

  bool _isStale(RepoId? generation) =>
      _disposed || _ref.read(activeWorkspaceIdProvider) != generation;

  /// Publishes the work as the active refresh for its whole life, so watcher
  /// events can wait for it and skip what it already covers.
  Future<T> _tracked<T>(
    Set<RefreshScope> scopes,
    Future<T> Function() body,
  ) async {
    final active = _ActiveRefresh(_watcherScopes(scopes));
    _active.add(active);
    try {
      return await body();
    } finally {
      _active.remove(active);
      active.settled.complete();
    }
  }

  Future<void> _refresh(RepoLocation repo, Set<RefreshScope> scopes) =>
      _invalidateAndAwait(repo, scopes);

  /// Invalidates every declared provider, then awaits only the ones that were
  /// already alive: a panel nobody has open needs no git process to prove the
  /// action finished.
  Future<void> _invalidateAndAwait(
    RepoLocation repo,
    Set<RefreshScope> scopes,
  ) async {
    final wantStatus =
        scopes.contains(RefreshScope.status) &&
        _ref.exists(repoStatusProvider(repo));
    final wantBranches =
        scopes.contains(RefreshScope.branches) &&
        _ref.exists(branchesProvider(repo));
    final wantSidebar =
        scopes.contains(RefreshScope.sidebar) &&
        _ref.exists(sidebarDataProvider(repo));
    final wantGraph =
        scopes.contains(RefreshScope.graph) &&
        _ref.exists(commitGraphDataProvider(repo));
    final wantState =
        scopes.contains(RefreshScope.repoState) &&
        _ref.exists(repoStateProvider(repo));
    final wantWorkingCopy =
        scopes.contains(RefreshScope.workingCopy) &&
        _ref.exists(workingCopyStatusProvider(repo));
    final selected =
        scopes.contains(RefreshScope.workingCopy) &&
            _ref.exists(selectedFileProvider)
        ? _ref.read(selectedFileProvider)
        : null;

    // One read-cache bust covers every `git`-backed provider (that is what the
    // service's RepoDataScope.reads has always meant); the family
    // invalidations below are for the providers this scope waits on.
    if (scopes.any((s) => s != RefreshScope.repoState)) {
      _ref.invalidate(gitReadOperationsProvider);
    }
    if (scopes.contains(RefreshScope.status)) {
      _ref.invalidate(repoStatusProvider(repo));
    }
    if (scopes.contains(RefreshScope.branches)) {
      _ref
        ..invalidate(localBranchesProvider(repo))
        ..invalidate(remoteBranchesProvider(repo));
    }
    if (scopes.contains(RefreshScope.sidebar)) {
      _ref.invalidate(sidebarDataProvider(repo));
    }
    if (scopes.contains(RefreshScope.graph)) {
      _ref.invalidate(commitGraphDataProvider(repo));
    }
    if (scopes.contains(RefreshScope.repoState)) {
      _ref
        ..invalidate(repoStateProvider(repo))
        ..invalidate(bisectStateProvider(repo));
    }
    if (selected != null) {
      _ref.invalidate(
        selected.staged
            ? stagedFileDiffProvider((repo, selected.path))
            : unstagedFileDiffProvider((repo, selected.path)),
      );
    }

    await Future.wait<void>([
      if (wantStatus) _ref.read(repoStatusProvider(repo).future),
      if (wantBranches) _ref.read(branchesProvider(repo).future),
      if (wantSidebar) _ref.read(sidebarDataProvider(repo).future),
      if (wantGraph) _ref.read(commitGraphDataProvider(repo).future),
      if (wantState) _ref.read(repoStateProvider(repo).future),
      if (wantWorkingCopy) _ref.read(workingCopyStatusProvider(repo).future),
      if (selected != null)
        _ref.read(
          (selected.staged
                  ? stagedFileDiffProvider((repo, selected.path))
                  : unstagedFileDiffProvider((repo, selected.path)))
              .future,
        ),
    ]);
  }

  /// The watcher scopes this refresh already covers, so coalesced watcher
  /// events for the same data do not trigger a second reload.
  Set<RepoRefreshScope> _watcherScopes(Set<RefreshScope> scopes) => {
    if (scopes.contains(RefreshScope.status) ||
        scopes.contains(RefreshScope.workingCopy))
      RepoRefreshScope.worktree,
    if (scopes.contains(RefreshScope.branches) ||
        scopes.contains(RefreshScope.sidebar) ||
        scopes.contains(RefreshScope.graph))
      RepoRefreshScope.refs,
    if (scopes.contains(RefreshScope.repoState)) RepoRefreshScope.state,
  };
}

class _ActiveRefresh {
  _ActiveRefresh(this.covered);
  final Set<RepoRefreshScope> covered;

  /// Completes (never with an error) when the refresh settles; the watcher
  /// waits on it and the runner reports the failure itself.
  final Completer<void> settled = Completer<void>();
}
