import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../infrastructure/logging/app_logger.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/branch_visibility_provider.dart';
import '../../application/commit_graph/commit_graph_layout.dart';
import '../../application/commit_graph/commit_node.dart';
import '../../application/git/git_read_operations.dart';
import '../../application/git/git_result.dart';
import '../../application/git/git_write_operations.dart';
import '../../application/git/merge_outcome.dart';
import '../../application/git/repo_state_provider.dart';
import '../../application/providers.dart';
import '../../application/repo_revision.dart';
import '../../application/scroll_request_provider.dart';
import '../../domain/commits/commit_info.dart';
import '../../domain/commits/commit_sha.dart';
import '../../domain/repositories/repo_location.dart';
import '../checkout/safe_checkout.dart';
import '../common/app_context_menu.dart';
import '../common/skeleton.dart';
import '../dialogs/app_dialog.dart';
import '../dialogs/branch_create_dialog.dart';
import '../dialogs/confirm_dialog.dart';
import '../dialogs/merge_dialog.dart';
import '../theme/app_palette.dart';
import 'commit_row.dart';
import 'lane_painter.dart';
import 'local_changes_row.dart';
import 'ref_decoration.dart';

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

class _GraphData {
  final List<CommitNode> nodes;
  final Map<String, List<RefDecoration>> refsBySha;
  final int maxLane;
  _GraphData(this.nodes, this.refsBySha, this.maxLane);
}

final commitGraphDataProvider =
    FutureProvider.family<_GraphData, RepoLocation>((ref, repo) async {
  ref.watch(repoRevisionProvider(repo));
  final git = ref.watch(gitReadOperationsProvider);

  // Watch hidden refs so the provider re-runs when visibility changes.
  final hidden = ref.watch(hiddenRefsProvider);

  appLog.i('graph: start load for ${repo.displayName}');
  // Share the branch fetch with the sidebar — same repo, same data, no
  // need to spawn a second `git for-each-ref`.
  final branches = await ref.watch(branchesProvider(repo).future);
  appLog.i('graph: branches=${branches.length}');

  // Compute the set of visible branch fullNames to pass to git log.
  final visibleBranches =
      branches.where((b) => !hidden.contains(b.fullName)).toList();
  final refsForLog = visibleBranches.map((b) => b.fullName).toList();

  // Fall back to HEAD (via --all) when every branch is hidden so the panel
  // does not go completely empty.
  // Take is capped at 2000: enough to fill several screen-heights of graph
  // even on the densest history, while keeping memory predictable on very
  // large monorepos.  Body is loaded on demand in the details panel, not
  // here, so each commit row costs ~150 bytes.
  const takeCommits = 2000;
  final query = refsForLog.isEmpty
      ? const CommitQuery(take: takeCommits)
      : CommitQuery(take: takeCommits, refs: refsForLog);

  appLog.i('graph: running git log (max=$takeCommits, refs=${refsForLog.length})');
  final List<CommitInfo> commits;
  try {
    commits = await git.getCommits(repo, query).toList().timeout(
          _gitLogTimeout,
          onTimeout: () => throw TimeoutException(
              'git log did not return within ${_gitLogTimeout.inSeconds}s '
              'on ${repo.displayName}.  Repo is likely very large; try '
              'hiding some branches or check that .git is on local disk.',
              _gitLogTimeout),
        );
  } on TimeoutException catch (e) {
    appLog.w('graph: git log timeout — ${e.message}');
    rethrow;
  }
  appLog.i('graph: commits=${commits.length} — computing layout (isolate)');
  // Run the layout in a background isolate so a big graph cannot pin the
  // UI thread.  The overhead of [compute] (~tens of ms to spawn) is
  // dwarfed by the layout cost on any non-trivial history.
  final nodes = await compute(_layoutInIsolate, commits);
  appLog.i('graph: layout done (${nodes.length} nodes)');

  // Bucket all branches by tip sha, splitting locals from remotes.
  final localsBySha = <String, List<dynamic>>{};
  final remotesBySha = <String, List<dynamic>>{};
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
    for (final dynamic b in entry.value) {
      final merged = <String>[];
      // A local branch with upstream pointing to a remote that also lives at
      // this same sha gets merged.
      if (b.upstreamFullName != null) {
        final remotesHere = remotesBySha[sha] ?? const [];
        for (final dynamic r in remotesHere) {
          if (r.fullName == b.upstreamFullName) {
            merged.add(r.name); // e.g. "origin/master"
            consumedRemotes.add(r.fullName);
          }
        }
      }
      // Also fold remotes that share the bare branch name even without
      // explicit upstream config (covers detached configurations).
      final remotesHere = remotesBySha[sha] ?? const [];
      for (final dynamic r in remotesHere) {
        if (consumedRemotes.contains(r.fullName)) continue;
        final remoteBare = r.name.contains('/')
            ? r.name.substring(r.name.indexOf('/') + 1)
            : r.name;
        if (remoteBare == b.name) {
          merged.add(r.name);
          consumedRemotes.add(r.fullName);
        }
      }

      (refsBySha[sha] ??= []).add(RefDecoration(
        name: b.name,
        isRemote: false,
        isTag: false,
        isCurrent: b.isCurrent,
        syncedRemotes: merged,
      ));
    }
  }

  // Second pass: remote refs that weren't merged into any local.
  for (final entry in remotesBySha.entries) {
    final sha = entry.key;
    for (final dynamic r in entry.value) {
      if (consumedRemotes.contains(r.fullName)) continue;
      (refsBySha[sha] ??= []).add(RefDecoration(
        name: r.name,
        isRemote: true,
        isTag: false,
        isCurrent: false,
      ));
    }
  }

  // Tags (never merged with branches).
  final tags = await git.getTags(repo);
  for (final t in tags) {
    (refsBySha[t.targetSha.value] ??= []).add(RefDecoration(
      name: t.name,
      isRemote: false,
      isTag: true,
      isCurrent: false,
    ));
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
  return _GraphData(nodes, refsBySha, maxLane);
});

class CommitGraphPanel extends ConsumerStatefulWidget {
  final RepoLocation repo;
  const CommitGraphPanel({super.key, required this.repo});

  @override
  ConsumerState<CommitGraphPanel> createState() => _CommitGraphPanelState();
}

class _CommitGraphPanelState extends ConsumerState<CommitGraphPanel> {
  final ScrollController _controller = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'commitGraph');

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToSha(CommitSha sha, List<dynamic> nodes) {
    final index = nodes.indexWhere((n) => n.commit.sha == sha);
    if (index < 0 || !_controller.hasClients) return;
    final target = index * kRowHeight;
    final position = _controller.position;
    final viewport = position.viewportDimension;
    final maxScroll = position.maxScrollExtent;
    // Center the row in the viewport if possible.
    final centered = (target - viewport / 2 + kHalfHeight).clamp(0.0, maxScroll);
    _controller.animateTo(
      centered,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// Scrolls just enough to bring [index]'s row fully into view (no centering),
  /// so arrow-key navigation tracks the selection without jumping around.
  void _ensureVisible(int index) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final rowTop = index * kRowHeight;
    final rowBottom = rowTop + kRowHeight;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;
    double? target;
    if (rowTop < viewTop) {
      target = rowTop;
    } else if (rowBottom > viewBottom) {
      target = rowBottom - position.viewportDimension;
    }
    if (target == null) return;
    _controller.animateTo(
      target.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  /// Moves the commit selection by [delta] rows (e.g. +1 for ArrowDown).
  /// With nothing selected, ArrowDown selects the first row and ArrowUp the
  /// last.  Keeps the new selection scrolled into view.
  void _moveSelection(int delta, List<CommitNode> nodes) {
    if (nodes.isEmpty) return;
    final current = ref.read(selectedCommitShaProvider);
    final currentIndex =
        nodes.indexWhere((n) => n.commit.sha == current);
    final int next;
    if (currentIndex < 0) {
      next = delta > 0 ? 0 : nodes.length - 1;
    } else {
      next = (currentIndex + delta).clamp(0, nodes.length - 1);
    }
    ref.read(selectedCommitShaProvider.notifier).state =
        nodes[next].commit.sha;
    _ensureVisible(next);
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final async = ref.watch(commitGraphDataProvider(repo));
    final palette = AppPalette.of(context);

    // Listen for scroll requests from the sidebar / other panels.
    ref.listen<CommitSha?>(scrollRequestProvider, (prev, next) {
      if (next == null) return;
      final data = ref.read(commitGraphDataProvider(repo)).valueOrNull;
      if (data == null) return;
      // Schedule after the current frame so the ListView has measured.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSha(next, data.nodes);
        ref.read(scrollRequestProvider.notifier).state = null;
      });
    });

    return Container(
      color: palette.bg1,
      child: async.when(
        data: (data) {
          if (data.nodes.isEmpty) {
            return Center(
              child: Text('No commits in this repository.',
                  style: TextStyle(color: palette.fg2)),
            );
          }
          final selected = ref.watch(selectedCommitShaProvider);
          return Focus(
            focusNode: _focusNode,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                return KeyEventResult.ignored;
              }
              switch (event.logicalKey) {
                case LogicalKeyboardKey.arrowDown:
                  _moveSelection(1, data.nodes);
                  return KeyEventResult.handled;
                case LogicalKeyboardKey.arrowUp:
                  _moveSelection(-1, data.nodes);
                  return KeyEventResult.handled;
                case LogicalKeyboardKey.home:
                  _moveSelection(-data.nodes.length, data.nodes);
                  return KeyEventResult.handled;
                case LogicalKeyboardKey.end:
                  _moveSelection(data.nodes.length, data.nodes);
                  return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LocalChangesRow(repo: repo),
              Expanded(
                child: ListView.builder(
                  controller: _controller,
                  itemExtent: kRowHeight,
                  itemCount: data.nodes.length,
                  itemBuilder: (context, i) {
                    final node = data.nodes[i];
                    final refs = data.refsBySha[node.commit.sha.value] ?? const [];
                    return CommitRow(
                      node: node,
                      maxLane: data.maxLane,
                      refs: refs,
                      isSelected: selected == node.commit.sha,
                      onTap: () {
                        _focusNode.requestFocus();
                        ref.read(selectedCommitShaProvider.notifier).state =
                            node.commit.sha;
                      },
                      onSecondaryTap: (globalPos) => _showCommitContextMenu(
                        context,
                        ref,
                        node.commit.sha,
                        globalPos,
                      ),
                      onRefTap: (r) {
                        ref.read(selectedCommitShaProvider.notifier).state =
                            node.commit.sha;
                      },
                      onRefDoubleTap: (r) async {
                        final ok = await safeCheckout(
                          context: context,
                          ref: ref,
                          repo: widget.repo,
                          targetRef: r.name,
                        );
                        if (ok) {
                          ref.invalidate(commitGraphDataProvider(repo));
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          );
        },
        loading: () =>
            const SkeletonList(rows: 18, rowHeight: 11, gap: 15),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load graph: $e',
                style: TextStyle(color: palette.accentErr)),
          ),
        ),
      ),
    );
  }

  Future<void> _showCommitContextMenu(
    BuildContext context,
    WidgetRef ref,
    CommitSha sha,
    Offset globalPos,
  ) async {
    final selected = await AppContextMenu.show<String>(
      context,
      globalPosition: globalPos,
      entries: const [
        AppMenuItem(value: 'checkout', label: 'Checkout this commit', icon: Icons.commit),
        AppMenuDivider(),
        AppMenuItem(value: 'merge', label: 'Merge into current', icon: Icons.call_merge),
        AppMenuItem(value: 'rebase', label: 'Rebase current onto this', icon: Icons.compare_arrows),
        AppMenuDivider(),
        AppMenuItem(value: 'cherry_pick', label: 'Cherry-pick into current', icon: Icons.add_card_outlined),
        AppMenuItem(value: 'revert', label: 'Revert this commit', icon: Icons.undo),
        AppMenuDivider(),
        AppMenuItem(value: 'branch_here', label: 'Create branch here…', icon: Icons.alt_route),
        AppMenuItem(value: 'tag_here', label: 'Tag here…', icon: Icons.local_offer_outlined),
        AppMenuDivider(),
        AppMenuItem(value: 'copy_sha', label: 'Copy SHA', icon: Icons.copy),
        AppMenuItem(value: 'copy_short_sha', label: 'Copy short SHA', icon: Icons.copy_outlined),
        AppMenuDivider(),
        AppMenuItem(value: 'reset_soft', label: 'Reset (soft)', icon: Icons.restore),
        AppMenuItem(value: 'reset_mixed', label: 'Reset (mixed)', icon: Icons.restore),
        AppMenuItem(value: 'reset_hard', label: 'Reset (hard)…', icon: Icons.restore, danger: true),
      ],
    );

    if (selected == null || !context.mounted) return;

    final write = ref.read(gitWriteOperationsProvider);
    final repo = widget.repo;
    final palette = AppPalette.of(context);
    switch (selected) {
      case 'checkout':
        // Checking out a bare SHA lands on a detached HEAD. safeCheckout
        // reuses the discard/stash/keep dialog for a dirty working tree.
        final ok = await safeCheckout(
          context: context,
          ref: ref,
          repo: repo,
          targetRef: sha.value,
        );
        if (ok) {
          ref.invalidate(commitGraphDataProvider(repo));
          ref.invalidate(repoStateProvider(repo));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Detached HEAD at ${sha.short()} — create a branch here to keep new commits.'),
              backgroundColor: palette.accentCurrent,
            ));
          }
        }

      case 'merge':
        final current = await currentBranchName(ref, repo);
        if (!context.mounted) return;
        final strategy = await MergeDialog.show(
          context,
          repo: repo,
          sourceRef: sha.short(),
          targetRef: current ?? 'HEAD',
        );
        if (strategy == null) return;
        final result =
            await write.merge(repo, sha.value, strategy: strategy);
        refreshRepo(ref, repo);
        ref.invalidate(repoStateProvider(repo));
        if (!context.mounted) return;
        if (result case GitSuccess(value: final MergeConflict outcome)) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Merge conflict in ${outcome.conflictedPaths.length} file(s). Resolve in the conflicts panel below.'),
            backgroundColor: palette.accentErr,
          ));
        } else if (result case GitFailure(:final message)) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Merge failed: $message'),
            backgroundColor: palette.accentErr,
          ));
        }

      case 'rebase':
        if (!context.mounted) return;
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Rebase current branch',
          body: 'Rebase the current branch onto ${sha.short()}? '
              'This rewrites commits on the current branch.',
          confirmLabel: 'Rebase',
        );
        if (!confirmed) return;
        final result = await write.rebase(repo, sha.value);
        refreshRepo(ref, repo);
        ref.invalidate(repoStateProvider(repo));
        if (!context.mounted) return;
        if (result case GitSuccess(value: final RebaseConflict outcome)) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Rebase conflict in ${outcome.conflictedPaths.length} file(s). Resolve in the conflicts panel below.'),
            backgroundColor: palette.accentErr,
          ));
        } else if (result case GitFailure(:final message)) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Rebase failed: $message'),
            backgroundColor: palette.accentErr,
          ));
        }

      case 'cherry_pick':
        await write.cherryPick(repo, sha);
        refreshRepo(ref, repo);

      case 'revert':
        final res = await write.revert(repo, sha);
        if (res is GitFailure && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Revert failed: ${(res as GitFailure).message}')));
        }
        ref.invalidate(commitGraphDataProvider(repo));
        ref.invalidate(repoStateProvider(repo));

      case 'branch_here':
        await BranchCreateDialog.show(context, repo, at: sha);
        refreshRepo(ref, repo);

      case 'tag_here':
        if (!context.mounted) return;
        final tagName =
            await _promptText(context, 'Tag here', label: 'Tag name');
        if (tagName == null || tagName.trim().isEmpty) return;
        await write.createTag(repo, tagName.trim(), at: sha);
        refreshRepo(ref, repo);

      case 'copy_sha':
        await Clipboard.setData(ClipboardData(text: sha.value));

      case 'copy_short_sha':
        await Clipboard.setData(ClipboardData(text: sha.short()));

      case 'reset_soft':
        await _doReset(context, ref, sha, ResetMode.soft);

      case 'reset_mixed':
        await _doReset(context, ref, sha, ResetMode.mixed);

      case 'reset_hard':
        await _doReset(context, ref, sha, ResetMode.hard);
    }
  }

  Future<void> _doReset(
    BuildContext context,
    WidgetRef ref,
    CommitSha sha,
    ResetMode mode,
  ) async {
    if (mode == ResetMode.hard) {
      if (!context.mounted) return;
      final confirmed = await ConfirmDialog.show(
        context,
        title: 'Hard reset',
        body: 'This will discard all uncommitted changes and rewrite history. Are you sure?',
        confirmLabel: 'Reset',
        dangerous: true,
      );
      if (!confirmed) return;
    }
    await ref.read(gitWriteOperationsProvider).reset(widget.repo, sha, mode);
    refreshRepo(ref, widget.repo);
  }

  Future<String?> _promptText(BuildContext context, String title,
      {required String label, String? initial}) async {
    final ctl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return AppDialog(
          title: title,
          width: 420,
          content: TextField(
            controller: ctl,
            autofocus: true,
            style: TextStyle(color: palette.fg0, fontSize: 13),
            decoration: appInputDecoration(ctx, label: label),
            onSubmitted: (_) => Navigator.pop(ctx, ctl.text),
          ),
          actions: [
            AppButton.secondary(
              label: 'Cancel',
              onPressed: () => Navigator.pop(ctx),
            ),
            AppButton.primary(
              label: 'OK',
              onPressed: () => Navigator.pop(ctx, ctl.text),
            ),
          ],
        );
      },
    );
    ctl.dispose();
    return result;
  }
}

