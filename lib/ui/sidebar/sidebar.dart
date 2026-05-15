import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../infrastructure/logging/app_logger.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/branch_visibility_provider.dart';
import '../../application/main_view_provider.dart';
import '../../application/providers.dart';
import '../../application/scroll_request_provider.dart';
import '../../domain/commits/commit_sha.dart';
import '../../domain/refs/branch.dart';
import '../../domain/refs/remote.dart';
import '../../domain/refs/stash.dart';
import '../../domain/refs/tag.dart';
import '../../application/git/git_result.dart';
import '../../application/git/merge_outcome.dart';
import '../../domain/repositories/repo_location.dart';
import '../../application/operations/running_operation.dart';
import '../checkout/safe_checkout.dart';
import '../dialogs/confirm_dialog.dart';
import '../dialogs/remote_dialog.dart';
import '../theme/app_palette.dart';
import 'branch_tree.dart';

/// Selects [sha] in the graph and asks the graph panel to scroll it into
/// view. Also switches the main view back to the graph if the user is
/// currently looking at the working-copy changes.
void _revealCommit(WidgetRef ref, CommitSha sha) {
  ref.read(mainViewProvider.notifier).state = MainView.graph;
  ref.read(selectedCommitShaProvider.notifier).state = sha;
  ref.read(scrollRequestProvider.notifier).state = sha;
}

class _SidebarData {
  final List<Branch> branches;
  final List<Tag> tags;
  final List<Remote> remotes;
  final List<Stash> stashes;
  _SidebarData(this.branches, this.tags, this.remotes, this.stashes);
}

final _sidebarDataProvider =
    FutureProvider.family<_SidebarData, RepoLocation>((ref, repo) async {
  final git = ref.watch(gitReadOperationsProvider);
  appLog.i('sidebar: awaiting shared branches for ${repo.displayName}');
  final branches = await ref.watch(branchesProvider(repo).future);
  appLog.i('sidebar: ${branches.length} branches — loading tags');
  final tags = await git.getTags(repo);
  appLog.i('sidebar: ${tags.length} tags — loading remotes');
  final remotes = await git.getRemotes(repo);
  appLog.i('sidebar: ${remotes.length} remotes — loading stashes');
  final stashes = await git.getStashes(repo);
  appLog.i('sidebar: ${stashes.length} stashes — done');
  return _SidebarData(branches, tags, remotes, stashes);
});

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspaceManagerProvider);
    final activeWs = active == null
        ? null
        : workspaces
            .where((w) => w.location.id == active)
            .cast<dynamic>()
            .firstOrNull;

    final palette = AppPalette.of(context);
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: palette.bg2,
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: activeWs == null
          ? Center(
              child: Text(
                'No repository selected',
                style: TextStyle(
                    color: palette.fg2, fontStyle: FontStyle.italic),
              ),
            )
          : Consumer(builder: (context, ref, _) {
              final repo = activeWs.location as RepoLocation;
              final async =
                  ref.watch(_sidebarDataProvider(repo));
              return async.when(
                data: (data) => _SidebarContent(data: data, repo: repo),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error: $e',
                        style:
                            TextStyle(color: palette.accentErr)),
                  ),
                ),
              );
            }),
    );
  }
}

class _SidebarContent extends ConsumerWidget {
  final _SidebarData data;
  final RepoLocation repo;
  const _SidebarContent({required this.data, required this.repo});

  void _refreshSidebar(WidgetRef ref) {
    ref.invalidate(_sidebarDataProvider(repo));
    ref.invalidate(gitReadOperationsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localBranches = data.branches.where((b) => !b.isRemote).toList();
    final localTree = BranchTree.build(localBranches);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _Section(
          title: 'LOCAL BRANCHES',
          child: BranchTreeView(nodes: localTree, repo: repo),
        ),
        _Section(
          title: 'REMOTES',
          trailing: _AddRemoteIconButton(
              repo: repo, onChanged: () => _refreshSidebar(ref)),
          child: data.remotes.isEmpty
              ? _AddRemoteEmptyState(
                  repo: repo, onChanged: () => _refreshSidebar(ref))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final r in data.remotes) ...[
                      _RemoteHeaderRow(
                        remote: r,
                        repo: repo,
                        onChanged: () => _refreshSidebar(ref),
                      ),
                      BranchTreeView(
                          nodes: BranchTree.build(r.branches),
                          repo: repo),
                    ],
                  ],
                ),
        ),
        _Section(
          title: 'TAGS',
          child: data.tags.isEmpty
              ? const _EmptyHint('No tags')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final t in data.tags)
                      _TagRow(tag: t, repo: repo, onRefresh: () => _refreshSidebar(ref)),
                  ],
                ),
        ),
        _Section(
          title: 'STASHES',
          child: data.stashes.isEmpty
              ? const _EmptyHint('No stashes')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in data.stashes)
                      _StashRow(stash: s, repo: repo, onRefresh: () => _refreshSidebar(ref)),
                  ],
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tag row with context menu
// ---------------------------------------------------------------------------

class _TagRow extends ConsumerWidget {
  final Tag tag;
  final RepoLocation repo;
  final VoidCallback onRefresh;

  const _TagRow({required this.tag, required this.repo, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, ref, details.globalPosition),
      child: InkWell(
        onTap: () => _revealCommit(ref, tag.targetSha),
        onDoubleTap: () async {
          final ok = await safeCheckout(
            context: context,
            ref: ref,
            repo: repo,
            targetRef: tag.name,
          );
          if (ok) onRefresh();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 3),
          child: Text(
            tag.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppPalette.of(context).fg1, fontSize: 12.5),
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(
      BuildContext context, WidgetRef ref, Offset globalPos) async {
    final rect = RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy);

    final selected = await showMenu<String>(
      context: context,
      position: rect,
      items: const [
        PopupMenuItem(value: 'checkout', child: Text('Checkout')),
        PopupMenuItem(value: 'push_tag', child: Text('Push tag')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete_tag', child: Text('Delete tag')),
      ],
    );

    if (selected == null || !context.mounted) return;
    final write = ref.read(gitWriteOperationsProvider);

    switch (selected) {
      case 'checkout':
        await write.checkout(repo, tag.name);
        onRefresh();

      case 'push_tag':
        // Push the specific tag to origin using the push stream; fire-and-forget
        // with no progress tracking for simplicity.
        final stream = write.push(repo, branch: tag.name, pushTags: true);
        await stream.drain<void>();
        onRefresh();

      case 'delete_tag':
        if (!context.mounted) return;
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Delete tag',
          body: 'Delete tag "${tag.name}"? This cannot be undone.',
          confirmLabel: 'Delete',
          dangerous: true,
        );
        if (!confirmed) return;
        await write.deleteTag(repo, tag.name);
        onRefresh();
    }
  }
}

// ---------------------------------------------------------------------------
// Stash row with context menu
// ---------------------------------------------------------------------------

class _StashRow extends ConsumerWidget {
  final Stash stash;
  final RepoLocation repo;
  final VoidCallback onRefresh;

  const _StashRow({required this.stash, required this.repo, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, ref, details.globalPosition),
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 3),
          child: Text(
            'stash@{${stash.index}} — ${stash.message}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppPalette.of(context).fg1, fontSize: 12.5),
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(
      BuildContext context, WidgetRef ref, Offset globalPos) async {
    final rect = RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy);

    final selected = await showMenu<String>(
      context: context,
      position: rect,
      items: const [
        PopupMenuItem(value: 'apply', child: Text('Apply')),
        PopupMenuItem(value: 'pop', child: Text('Pop')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'drop', child: Text('Drop')),
      ],
    );

    if (selected == null || !context.mounted) return;
    final write = ref.read(gitWriteOperationsProvider);

    switch (selected) {
      case 'apply':
        await write.stashApply(repo, stash.index);
        onRefresh();

      case 'pop':
        await write.stashPop(repo, stash.index);
        onRefresh();

      case 'drop':
        if (!context.mounted) return;
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Drop stash',
          body: 'Drop "stash@{${stash.index}}"? This cannot be undone.',
          confirmLabel: 'Drop',
          dangerous: true,
        );
        if (!confirmed) return;
        await write.stashDrop(repo, stash.index);
        onRefresh();
    }
  }
}

class _Section extends StatefulWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const _Section({required this.title, required this.child, this.trailing});

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(children: [
              Icon(
                _open ? Icons.expand_more : Icons.chevron_right,
                size: 14,
                color: palette.fg3,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: palette.fg2,
                    fontSize: 10.5,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ]),
          ),
        ),
        if (_open)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: widget.child),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Text(text,
            style: TextStyle(
                color: AppPalette.of(context).fg3,
                fontSize: 11.5,
                fontStyle: FontStyle.italic)),
      );
}

// ---------------------------------------------------------------------------
// Remote management widgets
// ---------------------------------------------------------------------------

class _AddRemoteIconButton extends ConsumerWidget {
  final RepoLocation repo;
  final VoidCallback onChanged;
  const _AddRemoteIconButton({required this.repo, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => _addRemote(context, ref, repo, onChanged),
      borderRadius: BorderRadius.circular(2),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(Icons.add, size: 14, color: AppPalette.of(context).fg2),
      ),
    );
  }
}

class _AddRemoteEmptyState extends ConsumerWidget {
  final RepoLocation repo;
  final VoidCallback onChanged;
  const _AddRemoteEmptyState({required this.repo, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _addRemote(context, ref, repo, onChanged),
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Add remote…'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: AppPalette.of(context).fg2,
          ),
        ),
      ),
    );
  }
}

class _RemoteHeaderRow extends ConsumerWidget {
  final Remote remote;
  final RepoLocation repo;
  final VoidCallback onChanged;
  const _RemoteHeaderRow({
    required this.remote,
    required this.repo,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showMenu(context, ref, details.globalPosition),
      child: Padding(
        padding: const EdgeInsets.only(left: 14, top: 4, bottom: 2, right: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                remote.name.toUpperCase(),
                style: TextStyle(
                  color: AppPalette.of(context).fg2,
                  fontSize: 10.5,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMenu(
      BuildContext context, WidgetRef ref, Offset globalPos) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy),
      items: const [
        PopupMenuItem(value: 'fetch', child: Text('Fetch')),
        PopupMenuItem(value: 'edit_url', child: Text('Edit URL…')),
        PopupMenuItem(value: 'rename', child: Text('Rename…')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'remove', child: Text('Remove')),
      ],
    );
    if (selected == null || !context.mounted) return;
    final write = ref.read(gitWriteOperationsProvider);

    switch (selected) {
      case 'fetch':
        await _fetchRemote(ref, repo, remote.name);
        onChanged();

      case 'edit_url':
        final result =
            await RemoteDialog.showEditUrl(context, remote.name, remote.url);
        if (result == null) return;
        await write.setRemoteUrl(repo, remote.name, result.url);
        onChanged();

      case 'rename':
        final result = await RemoteDialog.showRename(context, remote.name);
        if (result == null) return;
        await write.renameRemote(repo, remote.name, result.name);
        onChanged();

      case 'remove':
        if (!context.mounted) return;
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Remove remote',
          body:
              'Remove remote "${remote.name}"? Tracking branches under this '
              'remote will no longer update.',
          confirmLabel: 'Remove',
          dangerous: true,
        );
        if (!confirmed) return;
        await write.removeRemote(repo, remote.name);
        onChanged();
    }
  }
}

Future<void> _addRemote(
  BuildContext context,
  WidgetRef ref,
  RepoLocation repo,
  VoidCallback onChanged,
) async {
  final result = await RemoteDialog.showAdd(context);
  if (result == null) return;
  final write = ref.read(gitWriteOperationsProvider);
  await write.addRemote(repo, result.name, result.url);
  onChanged();
}

/// Fetches a single remote, tracking the operation in the operations notifier.
/// Uses the resolved auth profile but does not implement the wrong-account
/// retry flow — that lives in the toolbar's full fetch button.
Future<void> _fetchRemote(
    WidgetRef ref, RepoLocation repo, String remoteName) async {
  final ops = ref.read(operationsProvider.notifier);
  final id = ops.start(OpKind.fetch, 'Fetching $remoteName', repo: repo);
  try {
    final profile = await ref.read(authResolverProvider).resolveForRepo(repo);
    final write = ref.read(gitWriteOperationsProvider);
    await for (final ev
        in write.fetch(repo, remote: remoteName, auth: profile?.spec)) {
      ops.updateProgress(id, ev.fraction, ev.phase);
    }
    ops.finishSuccess(id);
    ref.invalidate(gitReadOperationsProvider);
  } catch (e) {
    ops.finishFailure(id, e.toString());
  }
}

class BranchTreeView extends ConsumerStatefulWidget {
  final List<BranchTreeNode> nodes;
  final int depth;
  final RepoLocation repo;
  const BranchTreeView(
      {super.key, required this.nodes, this.depth = 0, required this.repo});

  @override
  ConsumerState<BranchTreeView> createState() => _BranchTreeViewState();
}

class _BranchTreeViewState extends ConsumerState<BranchTreeView> {
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    // Watch hidden refs so the tree re-renders when visibility changes.
    ref.watch(hiddenRefsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final n in widget.nodes) _renderNode(n, widget.depth)
      ],
    );
  }

  /// Invalidates sidebar data so the tree refreshes after a write op.
  void _refresh() {
    ref.invalidate(_sidebarDataProvider(widget.repo));
  }

  Future<void> _handleContextMenu(
      BuildContext context, BranchTreeNode n, Offset globalPos) async {
    final branch = n.branch;
    if (branch == null) return;
    final branchName = branch.name;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy),
      items: const [
        PopupMenuItem(value: 'checkout', child: Text('Checkout')),
        PopupMenuItem(value: 'merge', child: Text('Merge into current')),
        PopupMenuItem(value: 'rename', child: Text('Rename…')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
        PopupMenuItem(value: 'upstream', child: Text('Set upstream…')),
      ],
    );

    if (selected == null || !context.mounted) return;
    final write = ref.read(gitWriteOperationsProvider);

    switch (selected) {
      case 'checkout':
        await write.checkout(widget.repo, branchName);
        _refresh();

      case 'merge':
        final result = await write.merge(widget.repo, branchName);
        _refresh();
        if (!context.mounted) return;
        if (result case GitSuccess(value: final MergeConflict outcome)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Merge conflict in ${outcome.conflictedPaths.length} file(s). Full conflict UI coming in 2D.'),
              backgroundColor: AppPalette.of(context).accentErr,
            ),
          );
        }

      case 'rename':
        final newName = await _promptText(context, 'Rename branch',
            label: 'New name', initial: branchName);
        if (newName == null || newName.trim().isEmpty) return;
        await write.renameBranch(widget.repo, branchName, newName.trim());
        _refresh();

      case 'delete':
        if (!context.mounted) return;
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Delete branch',
          body: 'Delete "$branchName"? This cannot be undone.',
          confirmLabel: 'Delete',
          dangerous: true,
        );
        if (!confirmed) return;
        await write.deleteBranch(widget.repo, branchName);
        _refresh();

      case 'upstream':
        final upstream = await _promptText(context, 'Set upstream',
            label: 'Upstream ref (e.g. origin/main)');
        if (upstream == null || upstream.trim().isEmpty) return;
        await write.setUpstream(widget.repo, branchName, upstream.trim());
        _refresh();
    }
  }

  /// Shows a simple single-TextField AlertDialog and returns the entered text,
  /// or null if the user cancelled.
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

  Widget _renderNode(BranchTreeNode n, int depth) {
    final indent = 6.0 + depth * 14.0;
    if (n.children.isEmpty) {
      final branch = n.branch;
      final current = branch?.isCurrent ?? false;
      final fullName = branch?.fullName;
      final isHidden = fullName != null &&
          ref.read(hiddenRefsProvider).contains(fullName);
      return Opacity(
        opacity: isHidden ? 0.5 : 1.0,
        child: GestureDetector(
          onSecondaryTapDown: (details) =>
              _handleContextMenu(context, n, details.globalPosition),
          child: InkWell(
            onTap: branch?.tipSha == null
                ? null
                : () => _revealCommit(ref, branch!.tipSha!),
            onDoubleTap: branch == null || current
                ? null
                : () async {
                    final ok = await safeCheckout(
                      context: context,
                      ref: ref,
                      repo: widget.repo,
                      targetRef: branch.name,
                    );
                    if (ok) _refresh();
                  },
            child: Padding(
              padding: EdgeInsets.only(
                  left: indent + 18, right: 6, top: 3, bottom: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    child: current
                        ? Text('✓',
                            style: TextStyle(
                                color: AppPalette.of(context).accentCurrent, fontSize: 11))
                        : null,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      n.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: current
                            ? AppPalette.of(context).accentCurrent
                            : AppPalette.of(context).fg1,
                        fontSize: 12.5,
                        fontWeight: current
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  // Visibility eye icon — always visible, click toggles.
                  if (fullName != null)
                    GestureDetector(
                      onTap: () => ref
                          .read(hiddenRefsProvider.notifier)
                          .toggle(fullName),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          isHidden
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 13,
                          color: isHidden
                              ? AppPalette.of(context).fg3
                              : AppPalette.of(context).fg2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final open = !_collapsed.contains(n.fullPath);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (!_collapsed.add(n.fullPath)) {
                _collapsed.remove(n.fullPath);
              }
            });
          },
          child: Padding(
            padding: EdgeInsets.only(
                left: indent, right: 12, top: 3, bottom: 3),
            child: Row(children: [
              Icon(
                open ? Icons.expand_more : Icons.chevron_right,
                size: 14,
                color: AppPalette.of(context).fg3,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(n.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppPalette.of(context).fg1,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    )),
              ),
            ]),
          ),
        ),
        if (open) BranchTreeView(nodes: n.children, depth: depth + 1, repo: widget.repo),
      ],
    );
  }
}
