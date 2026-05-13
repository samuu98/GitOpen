import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/branch_visibility_provider.dart';
import '../../application/commit_graph/commit_node.dart';
import '../../application/git/git_read_operations.dart';
import '../../application/git/git_result.dart';
import '../../application/git/git_write_operations.dart';
import '../../application/git/repo_state_provider.dart';
import '../../application/providers.dart';
import '../../domain/commits/commit_sha.dart';
import '../../domain/repositories/repo_location.dart';
import '../dialogs/branch_create_dialog.dart';
import '../dialogs/confirm_dialog.dart';
import '../theme/app_palette.dart';
import 'commit_row.dart';
import 'local_changes_row.dart';
import 'ref_decoration.dart';

class _GraphData {
  final List<CommitNode> nodes;
  final Map<String, List<RefDecoration>> refsBySha;
  final int maxLane;
  _GraphData(this.nodes, this.refsBySha, this.maxLane);
}

final commitGraphDataProvider =
    FutureProvider.family<_GraphData, RepoLocation>((ref, repo) async {
  final git = ref.watch(gitReadOperationsProvider);
  final layout = ref.watch(commitGraphLayoutProvider);

  // Watch hidden refs so the provider re-runs when visibility changes.
  final hidden = ref.watch(hiddenRefsProvider);

  // Fetch branches once — used both for the git log refs and for decorations.
  final branches = await git.getBranches(repo);

  // Compute the set of visible branch fullNames to pass to git log.
  final visibleBranches =
      branches.where((b) => !hidden.contains(b.fullName)).toList();
  final refsForLog = visibleBranches.map((b) => b.fullName).toList();

  // Fall back to HEAD (via --all) when every branch is hidden so the panel
  // does not go completely empty.
  final query = refsForLog.isEmpty
      ? const CommitQuery(take: 5000)
      : CommitQuery(take: 5000, refs: refsForLog);

  final commits = <dynamic>[];
  await for (final c in git.getCommits(repo, query)) {
    commits.add(c);
  }
  final nodes = layout.compute(commits.cast());

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

class CommitGraphPanel extends ConsumerWidget {
  final RepoLocation repo;
  const CommitGraphPanel({super.key, required this.repo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(commitGraphDataProvider(repo));
    final palette = AppPalette.of(context);
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LocalChangesRow(repo: repo),
              Expanded(
                child: ListView.builder(
                  itemExtent: 26,
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
                        ref.read(selectedCommitShaProvider.notifier).state =
                            node.commit.sha;
                        ref.read(localChangesSelectedProvider.notifier).state =
                            false;
                      },
                      onSecondaryTap: (globalPos) => _showCommitContextMenu(
                        context,
                        ref,
                        node.commit.sha,
                        globalPos,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
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
    final rect = RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy);

    final selected = await showMenu<String>(
      context: context,
      position: rect,
      items: [
        const PopupMenuItem(
            value: 'cherry_pick', child: Text('Cherry-pick into current')),
        const PopupMenuItem(
            value: 'revert', child: Text('Revert this commit')),
        const PopupMenuItem(
            value: 'branch_here', child: Text('Create branch here…')),
        const PopupMenuItem(value: 'tag_here', child: Text('Tag here…')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'copy_sha', child: Text('Copy SHA')),
        const PopupMenuItem(
            value: 'copy_short_sha', child: Text('Copy short SHA')),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'reset_submenu',
          child: _ResetSubmenuTile(
            sha: sha,
            repo: repo,
            onAction: (mode) async {
              Navigator.pop(context, '__reset_handled__');
              if (!context.mounted) return;
              await _doReset(context, ref, sha, mode);
            },
          ),
        ),
      ],
    );

    if (selected == null || selected == '__reset_handled__' || !context.mounted) {
      return;
    }

    final write = ref.read(gitWriteOperationsProvider);

    switch (selected) {
      case 'cherry_pick':
        await write.cherryPick(repo, sha);
        ref.invalidate(gitReadOperationsProvider);

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
        ref.invalidate(gitReadOperationsProvider);

      case 'tag_here':
        if (!context.mounted) return;
        final tagName = await _promptText(context, 'Tag here', label: 'Tag name');
        if (tagName == null || tagName.trim().isEmpty) return;
        await write.createTag(repo, tagName.trim(), at: sha);
        ref.invalidate(gitReadOperationsProvider);

      case 'copy_sha':
        await Clipboard.setData(ClipboardData(text: sha.value));

      case 'copy_short_sha':
        await Clipboard.setData(ClipboardData(text: sha.short()));
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
    await ref.read(gitWriteOperationsProvider).reset(repo, sha, mode);
    ref.invalidate(gitReadOperationsProvider);
  }

  Future<String?> _promptText(BuildContext context, String title,
      {required String label, String? initial}) async {
    final ctl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctl.text),
              child: const Text('OK')),
        ],
      ),
    );
    ctl.dispose();
    return result;
  }
}

// ---------------------------------------------------------------------------
// Reset submenu tile — inline submenu within the context menu
// ---------------------------------------------------------------------------

class _ResetSubmenuTile extends StatelessWidget {
  final CommitSha sha;
  final RepoLocation repo;
  final void Function(ResetMode mode) onAction;

  const _ResetSubmenuTile({
    required this.sha,
    required this.repo,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: () => onAction(ResetMode.soft),
          child: const Text('Soft'),
        ),
        MenuItemButton(
          onPressed: () => onAction(ResetMode.mixed),
          child: const Text('Mixed'),
        ),
        MenuItemButton(
          onPressed: () => onAction(ResetMode.hard),
          child: const Text('Hard…'),
        ),
      ],
      builder: (context, controller, child) => InkWell(
        onTap: () =>
            controller.isOpen ? controller.close() : controller.open(),
        child: Row(
          children: const [
            Expanded(child: Text('Reset to here')),
            Icon(Icons.chevron_right, size: 16),
          ],
        ),
      ),
    );
  }
}
