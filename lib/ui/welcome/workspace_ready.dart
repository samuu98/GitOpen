import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_providers.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';

/// The first visible workspace needs all three initial data sets to resolve.
/// Keeping this as one provider also gives open and clone the same Retry path.
final workspaceReadyProvider = FutureProvider.autoDispose
    .family<void, RepoLocation>((ref, repo) async {
      await Future.wait<Object>([
        ref.watch(repoStatusProvider(repo).future),
        ref.watch(sidebarDataProvider(repo).future),
        ref.watch(commitGraphDataProvider(repo).future),
      ]);
    });

/// Re-run each failed initial view as well as the aggregate readiness gate.
Future<void> retryWorkspaceReady(
  ProviderContainer container,
  RepoLocation repo,
) {
  container
    ..invalidate(repoStatusProvider(repo))
    ..invalidate(sidebarDataProvider(repo))
    ..invalidate(commitGraphDataProvider(repo))
    ..invalidate(workspaceReadyProvider(repo));
  return container.read(workspaceReadyProvider(repo).future);
}
