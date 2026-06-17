import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/watch/debouncer.dart';
import 'package:gitopen/application/watch/repo_change.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

/// Invisible host for a repo's auto-refresh: subscribes to the
/// [repoWatcherProvider] stream (debounced 400 ms so our own multi-command
/// operations coalesce) and refreshes when the window regains focus,
/// invalidating the same providers every git action invalidates. Controlled
/// by the `autoRefresh` setting.
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
  late final Debouncer _debouncer =
      Debouncer(const Duration(milliseconds: 400), _refresh);
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Created eagerly so focus events are observed from the first frame.
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void didUpdateWidget(RepoAutoRefreshScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repo.id != widget.repo.id) _unsubscribe();
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
    _sub ??= ref
        .read(repoWatcherProvider)
        .changes(widget.repo)
        .listen((_) => _debouncer.trigger());
  }

  void _unsubscribe() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  void _onResume() {
    if (ref.read(appSettingsProvider).autoRefresh) _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    ref
      ..invalidate(gitReadOperationsProvider)
      ..invalidate(repoStateProvider(widget.repo));
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        ref.watch(appSettingsProvider.select((s) => s.autoRefresh));
    _syncSubscription(enabled: enabled);
    return widget.child;
  }
}
