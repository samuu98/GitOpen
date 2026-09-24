import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/watch/debouncer.dart';
import 'package:gitopen/application/watch/repo_change.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_providers.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';

/// Invisible host for a repo's auto-refresh. Subscribes to the
/// [repoWatcherProvider] stream (debounced 400 ms so multi-command operations
/// coalesce) and refreshes on window focus regain. Refresh is **scoped**: the
/// watcher's [RepoChange] kind (or the focus path) maps to a set of
/// [RepoRefreshScope]s and only the affected providers are invalidated — a
/// fetch or alt-tab no longer re-logs the whole commit graph. Controlled by
/// the `autoRefresh` setting.
class RepoAutoRefreshScope extends ConsumerStatefulWidget {
  const RepoAutoRefreshScope({
    required this.repo,
    required this.child,
    super.key,
  });
  final RepoLocation repo;
  final Widget child;

  @override
  ConsumerState<RepoAutoRefreshScope> createState() =>
      _RepoAutoRefreshScopeState();
}

class _RepoAutoRefreshScopeState extends ConsumerState<RepoAutoRefreshScope> {
  StreamSubscription<RepoChange>? _sub;
  final Set<RepoChange> _pending = {};

  /// True while watcher events are waiting on an action's refresh, so a burst
  /// of events joins it once instead of queueing one wait each.
  bool _joining = false;
  late final Debouncer _debouncer =
      Debouncer(const Duration(milliseconds: 400), _flushWatcher);
  late final AppLifecycleListener _lifecycle;

  /// Last HEAD seen via [repoStatusProvider]; lets a focus refresh detect a
  /// HEAD move that happened while the window was unfocused.
  CommitSha? _lastHeadSha;

  @override
  void initState() {
    super.initState();
    // Created eagerly so focus events are observed from the first frame.
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void didUpdateWidget(RepoAutoRefreshScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repo.id != widget.repo.id) {
      _unsubscribe();
      _lastHeadSha = null;
    }
  }

  @override
  void dispose() {
    _unsubscribe();
    _debouncer.dispose();
    _lifecycle.dispose();
    super.dispose();
  }

  void _syncSubscription({required bool enabled}) {
    if (!enabled) {
      _unsubscribe();
      return;
    }
    _sub ??=
        ref.read(repoWatcherProvider).changes(widget.repo).listen((kind) {
      _pending.add(kind);
      _debouncer.trigger();
    });
  }

  void _unsubscribe() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  /// Invalidates the scopes the coalesced watcher events affect.
  ///
  /// A git action the user just ran fires these same events. Rather than
  /// reload a second time on top of the action's own refresh (or push the
  /// debounce out indefinitely while it runs), the events wait for that
  /// refresh and then only cover what it did not.
  void _flushWatcher() {
    if (!mounted || _pending.isEmpty) return;
    final active = ref.read(actionRunnerProvider).activeRefresh;
    if (active != null) {
      unawaited(_joinActionRefresh(active));
      return;
    }
    final kinds = Set<RepoChange>.of(_pending);
    _pending.clear();
    _invalidate(scopesForChange(kinds));
  }

  Future<void> _joinActionRefresh(
    ({Future<void> done, Set<RepoRefreshScope> covered}) active,
  ) async {
    if (_joining) return;
    _joining = true;
    await active.done;
    _joining = false;
    if (!mounted || _pending.isEmpty) return;
    final kinds = Set<RepoChange>.of(_pending);
    _pending.clear();
    final remaining = scopesForChange(kinds).difference(active.covered);
    if (remaining.isNotEmpty) _invalidate(remaining);
  }

  void _onResume() {
    if (ref.read(appSettingsProvider).autoRefresh) {
      unawaited(_refreshFocus());
    }
  }

  /// Focus regain refreshes the working tree + in-progress state; if HEAD
  /// moved while away (a missed watcher event), also refreshes refs/graph.
  Future<void> _refreshFocus() async {
    final before = _lastHeadSha;
    _invalidate(scopesForFocus(headMoved: false));
    try {
      final status = await ref.read(repoStatusProvider(widget.repo).future);
      if (status.headSha != before) {
        _invalidate(scopesForFocus(headMoved: true));
      }
    } on Object {
      // Status failed to load; worktree/state were already refreshed.
    }
  }

  /// Maps each scope to its providers and invalidates them.
  void _invalidate(Set<RepoRefreshScope> scopes) {
    if (!mounted) return;
    final repo = widget.repo;
    if (scopes.contains(RepoRefreshScope.worktree)) {
      ref.invalidate(repoStatusProvider(repo));
    }
    if (scopes.contains(RepoRefreshScope.refs)) {
      ref
        ..invalidate(localBranchesProvider(repo))
        ..invalidate(remoteBranchesProvider(repo))
        ..invalidate(sidebarDataProvider(repo))
        ..invalidate(commitGraphDataProvider(repo));
    }
    if (scopes.contains(RepoRefreshScope.state)) {
      ref.invalidate(repoStateProvider(repo));
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        ref.watch(appSettingsProvider.select((s) => s.autoRefresh));
    // Keep _lastHeadSha current as status reloads, for the focus safety net.
    ref.listen(repoStatusProvider(widget.repo), (_, next) {
      final sha = next.value?.headSha;
      if (sha != null) _lastHeadSha = sha;
    });
    _syncSubscription(enabled: enabled);
    return widget.child;
  }
}
