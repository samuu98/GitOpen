import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/watch/repo_change.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_providers.dart';
import 'package:gitopen/ui/github/github_providers.dart';
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

  /// The Git LFS panel: install state, tracked patterns and LFS files.
  lfsPanel,

  /// The GitHub pull-request list.
  pullRequestList,

  /// One pull request's detail header.
  pullRequestDetail,

  /// One pull request's reviews, review comments and issue comments.
  pullRequestReviewData,

  /// The workflow-run list for a branch.
  workflowRuns,

  /// One workflow run's jobs.
  workflowJobs,
}

/// Which GitHub views a refresh reloads. GitHub providers are keyed by the API
/// identity (slug + token) plus the pull request or workflow run on screen, so
/// a [RepoLocation] alone cannot address them.
final class GitHubRefreshTarget {
  const GitHubRefreshTarget({
    required this.slug,
    required this.token,
    this.pullRequest,
    this.runId,
    this.branch,
  });

  final RepoSlug slug;
  final String token;

  /// The pull request whose detail and review data to reload, when known.
  final int? pullRequest;

  /// The workflow run whose jobs to reload, when known.
  final int? runId;

  /// Branch filter of the workflow-run list on screen.
  final String? branch;
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
  ///
  /// [gitHubTarget] addresses the GitHub scopes; it reads the action's value so
  /// a just-created pull request can name itself.
  Future<ActionRun<T>> runAndRefresh<T>({
    required String key,
    required RepoLocation repo,
    required Set<RefreshScope> scopes,
    required Future<T> Function() action,
    String? label,
    bool Function(T value)? failed,
    String? Function(T value)? operationId,
    String? successMessage,
    GitHubRefreshTarget? Function(T value)? gitHubTarget,
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
          gitHubTarget: gitHubTarget,
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
    GitHubRefreshTarget? Function(T value)? gitHubTarget,
  }) async {
    final value = await action();
    final gitHub = gitHubTarget?.call(value);
    if (failed?.call(value) ?? false) {
      // A failed command can still have moved the repository (a stash that
      // applied halfway, a push that updated one ref), so the views are
      // refreshed anyway — but git's own error is what the caller reports.
      if (!_isStale(generation)) {
        try {
          await _refresh(repo, scopes, gitHub);
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
      await _refresh(repo, scopes, gitHub);
    } on Object {
      void retry() => unawaited(refreshOnly(repo, scopes, gitHub: gitHub));
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
  Future<void> refreshOnly(
    RepoLocation repo,
    Set<RefreshScope> scopes, {
    GitHubRefreshTarget? gitHub,
  }) async {
    if (_disposed) return;
    try {
      await _tracked(scopes, () => _refresh(repo, scopes, gitHub));
    } on Object {
      _ref
          .read(actionFeedbackProvider)
          .showActionFailure(
            refreshFailureMessage,
            retry: () => unawaited(refreshOnly(repo, scopes, gitHub: gitHub)),
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

  Future<void> _refresh(
    RepoLocation repo,
    Set<RefreshScope> scopes,
    GitHubRefreshTarget? gitHub,
  ) => _invalidateAndAwait(repo, scopes, gitHub);

  /// Invalidates every declared provider, then awaits only the ones that were
  /// already alive: a panel nobody has open needs no git process to prove the
  /// action finished.
  Future<void> _invalidateAndAwait(
    RepoLocation repo,
    Set<RefreshScope> scopes,
    GitHubRefreshTarget? gitHub,
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
    if (scopes.any(_readsGit)) {
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
      ..._lfsPending(repo, scopes),
      ..._gitHubPending(scopes, gitHub),
    ]);
  }

  /// The LFS panel's three providers.
  List<Future<void>> _lfsPending(RepoLocation repo, Set<RefreshScope> scopes) {
    if (!scopes.contains(RefreshScope.lfsPanel)) return const [];
    return _invalidateAndRead(<FutureProvider<Object?>>[
      gitLfsStatusProvider(repo),
      gitLfsTrackedPatternsProvider(repo),
      gitLfsFilesProvider(repo),
    ]);
  }

  /// The GitHub views named by [scopes], addressed through [gitHub]. A scope
  /// whose key the target does not carry (no pull request, no run) is skipped.
  List<Future<void>> _gitHubPending(
    Set<RefreshScope> scopes,
    GitHubRefreshTarget? gitHub,
  ) {
    if (gitHub == null) return const [];
    final listKey = (slug: gitHub.slug, token: gitHub.token);
    final number = gitHub.pullRequest;
    final prKey = number == null
        ? null
        : (slug: gitHub.slug, token: gitHub.token, number: number);
    final runId = gitHub.runId;
    return _invalidateAndRead(<FutureProvider<Object?>>[
      if (scopes.contains(RefreshScope.pullRequestList))
        githubPullRequestsProvider(listKey),
      if (prKey != null && scopes.contains(RefreshScope.pullRequestDetail))
        githubPullRequestDetailProvider(prKey),
      if (prKey != null &&
          scopes.contains(RefreshScope.pullRequestReviewData)) ...[
        githubPullRequestReviewsProvider(prKey),
        githubPullRequestCommentsProvider(prKey),
        githubIssueCommentsProvider(prKey),
      ],
      if (scopes.contains(RefreshScope.workflowRuns))
        githubWorkflowRunsProvider((
          slug: gitHub.slug,
          token: gitHub.token,
          branch: gitHub.branch,
        )),
      if (runId != null && scopes.contains(RefreshScope.workflowJobs))
        githubWorkflowJobsProvider((
          slug: gitHub.slug,
          token: gitHub.token,
          runId: runId,
        )),
    ]);
  }

  /// Invalidates every [providers] entry and returns the reloads worth
  /// awaiting — the ones a view already had open, decided before the
  /// invalidation disposes the rest.
  List<Future<void>> _invalidateAndRead(
    List<FutureProvider<Object?>> providers,
  ) {
    final alive = [
      for (final p in providers)
        if (_ref.exists(p)) p,
    ];
    providers.forEach(_ref.invalidate);
    return [for (final p in alive) _ref.read(p.future)];
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

/// Whether a scope is served by the git read cache. `repoState` has its own
/// reader; the LFS and GitHub scopes go through other services entirely, so a
/// GitHub mutation must not bust the git cache.
bool _readsGit(RefreshScope scope) => switch (scope) {
  RefreshScope.status ||
  RefreshScope.branches ||
  RefreshScope.sidebar ||
  RefreshScope.graph ||
  RefreshScope.workingCopy => true,
  RefreshScope.repoState ||
  RefreshScope.lfsPanel ||
  RefreshScope.pullRequestList ||
  RefreshScope.pullRequestDetail ||
  RefreshScope.pullRequestReviewData ||
  RefreshScope.workflowRuns ||
  RefreshScope.workflowJobs => false,
};

class _ActiveRefresh {
  _ActiveRefresh(this.covered);
  final Set<RepoRefreshScope> covered;

  /// Completes (never with an error) when the refresh settles; the watcher
  /// waits on it and the runner reports the failure itself.
  final Completer<void> settled = Completer<void>();
}
