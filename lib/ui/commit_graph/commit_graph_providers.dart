import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/branch_visibility_provider.dart';
import 'package:gitopen/application/commit_graph/commit_graph_layout.dart';
import 'package:gitopen/application/commit_graph/commit_node.dart';
import 'package:gitopen/application/commit_search_provider.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/commit_graph/ref_decoration.dart';

/// Top-level wrapper required by [compute] to run the layout in a
/// background isolate.  The layout pass is O(N×L) on the commit count and
/// the active-lane count; for big repos it can pin the UI thread for
/// hundreds of milliseconds, which is enough to look frozen during scroll.
List<CommitNode> _layoutInIsolate(List<CommitInfo> commits) {
  return const DefaultCommitGraphLayout().compute(commits);
}

/// Hard ceiling so the graph never appears to hang indefinitely on a slow
/// or corrupted repo.  60s is generous — most large monorepos return
/// 2000 commits in <5s.  When exceeded we surface a clear error to the
/// UI rather than spinning forever.
const _gitLogTimeout = Duration(seconds: 60);

/// Commits fetched in the first page and added on each scroll-to-load. A small
/// first page paints fast; more stream in as the user scrolls, so large repos
/// no longer block on a single 2000-commit `git log` + full layout.
const int graphPageSize = 300;

/// Per-repo upper bound on how many commits the graph currently loads. Starts
/// at [graphPageSize] and grows by a page each time the user scrolls near the
/// bottom; [commitGraphDataProvider] re-runs and re-lays-out the larger
/// window (keeping the visible graph via skipLoadingOnReload).
final StateProviderFamily<int, RepoLocation> graphLimitProvider =
    StateProvider.family<int, RepoLocation>((ref, repo) => graphPageSize);

class GraphData {
  GraphData(
    this.nodes,
    this.refsBySha,
    this.maxLane, {
    required this.hasMore,
  });
  final List<CommitNode> nodes;
  final Map<String, List<RefDecoration>> refsBySha;
  final int maxLane;

  /// Whether the last page came back full — i.e. older commits likely remain.
  final bool hasMore;
}

final FutureProviderFamily<GraphData, RepoLocation>
commitGraphDataProvider = FutureProvider.family<GraphData, RepoLocation>((
  ref,
  repo,
) async {
  final git = ref.watch(gitReadOperationsProvider);

  // Watch hidden refs so the provider re-runs when visibility changes.
  final hidden = ref.watch(hiddenRefsProvider);

  // Watch the search terms so the provider re-runs when the query changes.
  // When empty, the CommitQuery below carries null search fields and the
  // graph behaves exactly as before search existed.
  final logger = ref.read(loggerProvider);
  final search = ref.watch(commitSearchProvider);

  logger.i('graph: start load for ${repo.displayName}');
  // Share the branch fetch with the sidebar — same repo, same data, no
  // need to spawn a second `git for-each-ref`.
  final branches = await ref.watch(branchesProvider(repo).future);
  logger.i('graph: branches=${branches.length}');

  // Compute the set of visible branch fullNames to pass to git log.
  final visibleBranches = branches
      .where((b) => !hidden.contains(b.fullName))
      .toList();
  final refsForLog = visibleBranches.map((b) => b.fullName).toList();

  // Fall back to HEAD (via --all) when every branch is hidden so the panel
  // does not go completely empty.
  // Load only the current page window; it grows as the user scrolls toward the
  // bottom. Bodies are loaded on demand in the details panel, so each row
  // costs ~150 bytes.
  final takeCommits = ref.watch(graphLimitProvider(repo));
  final query = CommitQuery(
    take: takeCommits,
    refs: refsForLog.isEmpty ? null : refsForLog,
    grep: search.grep,
    author: search.author,
    touchingContent: search.touchingContent,
  );

  logger.i(
    'graph: running git log '
    '(max=$takeCommits, refs=${refsForLog.length}, '
    'search=${search.isEmpty ? 'none' : 'active'})',
  );
  final List<CommitInfo> commits;
  try {
    commits = await git
        .getCommits(repo, query)
        .toList()
        .timeout(
          _gitLogTimeout,
          onTimeout: () => throw TimeoutException(
            'git log did not return within ${_gitLogTimeout.inSeconds}s '
            'on ${repo.displayName}.  Repo is likely very large; try '
            'hiding some branches or check that .git is on local disk.',
            _gitLogTimeout,
          ),
        );
  } on TimeoutException catch (e) {
    logger.w('graph: git log timeout — ${e.message}');
    rethrow;
  }
  logger.i('graph: commits=${commits.length} — computing layout (isolate)');
  // Run the layout in a background isolate so a big graph cannot pin the
  // UI thread.  The overhead of [compute] (~tens of ms to spawn) is
  // dwarfed by the layout cost on any non-trivial history.
  final nodes = await compute(_layoutInIsolate, commits);
  logger.i('graph: layout done (${nodes.length} nodes)');

  // Bucket all branches by tip sha, splitting locals from remotes.
  final localsBySha = <String, List<Branch>>{};
  final remotesBySha = <String, List<Branch>>{};
  for (final b in branches) {
    final tip = b.tipSha;
    if (tip == null) continue;
    final bucket = b.isRemote ? remotesBySha : localsBySha;
    (bucket[tip.value] ??= []).add(b);
  }

  final refsBySha = <String, List<RefDecoration>>{};
  final consumedRemotes = <String>{}; // refs/remotes/<full> already merged

  // First pass: locals (possibly merged with their tracked remote(s)).
  for (final entry in localsBySha.entries) {
    final sha = entry.key;
    for (final b in entry.value) {
      final merged = <String>[];
      // A local branch with upstream pointing to a remote that also lives at
      // this same sha gets merged.
      if (b.upstreamFullName != null) {
        final remotesHere = remotesBySha[sha] ?? const [];
        for (final r in remotesHere) {
          if (r.fullName == b.upstreamFullName) {
            merged.add(r.name); // e.g. "origin/master"
            consumedRemotes.add(r.fullName);
          }
        }
      }
      // Also fold remotes that share the bare branch name even without
      // explicit upstream config (covers detached configurations).
      final remotesHere = remotesBySha[sha] ?? const [];
      for (final r in remotesHere) {
        if (consumedRemotes.contains(r.fullName)) continue;
        final remoteBare = r.name.contains('/')
            ? r.name.substring(r.name.indexOf('/') + 1)
            : r.name;
        if (remoteBare == b.name) {
          merged.add(r.name);
          consumedRemotes.add(r.fullName);
        }
      }

      (refsBySha[sha] ??= []).add(
        RefDecoration(
          name: b.name,
          isRemote: false,
          isTag: false,
          isCurrent: b.isCurrent,
          syncedRemotes: merged,
        ),
      );
    }
  }

  // Second pass: remote refs that weren't merged into any local.
  for (final entry in remotesBySha.entries) {
    final sha = entry.key;
    for (final r in entry.value) {
      if (consumedRemotes.contains(r.fullName)) continue;
      (refsBySha[sha] ??= []).add(
        RefDecoration(
          name: r.name,
          isRemote: true,
          isTag: false,
          isCurrent: false,
        ),
      );
    }
  }

  // Tags (never merged with branches).
  final tags = await git.getTags(repo);
  for (final t in tags) {
    (refsBySha[t.targetSha.value] ??= []).add(
      RefDecoration(
        name: t.name,
        isRemote: false,
        isTag: true,
        isCurrent: false,
      ),
    );
  }

  // Sort within each sha: current first, then locals, then tags, then remotes.
  for (final list in refsBySha.values) {
    list.sort((a, b) {
      int rank(RefDecoration r) {
        if (r.isCurrent) return 0;
        if (!r.isRemote && !r.isTag) return 1;
        if (r.isTag) return 2;
        return 3;
      }

      final cmp = rank(a).compareTo(rank(b));
      if (cmp != 0) return cmp;
      return a.name.compareTo(b.name);
    });
  }

  var maxLane = 0;
  for (final n in nodes) {
    if (n.lane > maxLane) maxLane = n.lane;
    for (final s in n.topSegments) {
      if (s.fromLane > maxLane) maxLane = s.fromLane;
      if (s.toLane > maxLane) maxLane = s.toLane;
    }
    for (final s in n.bottomSegments) {
      if (s.fromLane > maxLane) maxLane = s.fromLane;
      if (s.toLane > maxLane) maxLane = s.toLane;
    }
  }
  // A full window back from git means there are (probably) older commits to
  // page in as the user keeps scrolling.
  final hasMore = commits.length >= takeCommits;
  return GraphData(nodes, refsBySha, maxLane, hasMore: hasMore);
});
