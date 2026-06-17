import 'package:path/path.dart' as p;

/// What kind of git bookkeeping changed on disk. Drives scoped auto-refresh.
enum RepoChange { head, refs, fetch, mergeState }

/// A coarse refresh scope. Each maps to a set of providers in
/// `RepoAutoRefreshScope`.
enum RepoRefreshScope { worktree, refs, state }

/// Classifies a changed path under `.git` into a [RepoChange], or null when it
/// is transient noise (`index`, `*.lock`) or irrelevant. Pure.
RepoChange? classifyGitChange(String path) {
  final name = p.basename(path);
  if (name == 'index' || name.endsWith('.lock')) return null;

  const mergeNames = {
    'MERGE_HEAD',
    'CHERRY_PICK_HEAD',
    'REVERT_HEAD',
    'MERGE_MSG',
  };
  if (mergeNames.contains(name)) return RepoChange.mergeState;

  final segments = p.split(path);
  if (segments.contains('rebase-merge') ||
      segments.contains('rebase-apply')) {
    return RepoChange.mergeState;
  }

  if (name == 'FETCH_HEAD' || name == 'ORIG_HEAD') return RepoChange.fetch;

  if (name == 'HEAD') return RepoChange.head;
  if (segments.contains('logs')) return RepoChange.head; // reflog

  if (name == 'packed-refs') return RepoChange.refs;
  if (segments.contains('refs')) return RepoChange.refs;

  return null;
}

/// Union of scopes that the given [changes] require refreshing.
Set<RepoRefreshScope> scopesForChange(Set<RepoChange> changes) {
  final scopes = <RepoRefreshScope>{};
  for (final c in changes) {
    switch (c) {
      case RepoChange.head:
        scopes
          ..add(RepoRefreshScope.worktree)
          ..add(RepoRefreshScope.refs)
          ..add(RepoRefreshScope.state);
      case RepoChange.refs:
      case RepoChange.fetch:
        scopes
          ..add(RepoRefreshScope.refs)
          ..add(RepoRefreshScope.state);
      case RepoChange.mergeState:
        scopes
          ..add(RepoRefreshScope.worktree)
          ..add(RepoRefreshScope.state);
    }
  }
  return scopes;
}

/// Scopes to refresh on window focus-regain. Working tree + in-progress state
/// always; refs only when HEAD moved while away (safety net for a missed
/// watcher event).
Set<RepoRefreshScope> scopesForFocus({required bool headMoved}) {
  return {
    RepoRefreshScope.worktree,
    RepoRefreshScope.state,
    if (headMoved) RepoRefreshScope.refs,
  };
}
