import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/repositories/repo_location.dart';

/// Monotonic per-repo revision counter.
///
/// Repo-scoped read providers (status, branches, graph, sidebar, working
/// copy, conflicts, repo state) `ref.watch` this so they re-run when their
/// repo's on-disk state changes.  [refreshRepo] bumps it after a write op.
///
/// This replaces the old `ref.invalidate(gitReadOperationsProvider)`
/// cache-bust: that invalidated the shared *service* provider, which forced
/// the read providers of EVERY open repo to re-run at once — a rebuild storm
/// (and a burst of git subprocesses) on multi-repo sessions.  Bumping a single
/// repo's revision leaves every other repo's cached reads untouched.
final repoRevisionProvider =
    StateProvider.family<int, RepoLocation>((ref, _) => 0);

/// Signals that [repo]'s state changed, refreshing exactly that repo's reads.
/// Call this after any write operation instead of invalidating the git
/// service provider.
void refreshRepo(WidgetRef ref, RepoLocation repo) {
  ref.read(repoRevisionProvider(repo).notifier).state++;
}

/// `Ref`-based variant for use from inside providers or other non-widget code.
void refreshRepoFromRef(Ref ref, RepoLocation repo) {
  ref.read(repoRevisionProvider(repo).notifier).state++;
}
