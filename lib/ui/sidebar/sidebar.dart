import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/branch_visibility_provider.dart';
import '../../application/providers.dart';
import '../../domain/refs/branch.dart';
import '../../domain/refs/remote.dart';
import '../../domain/refs/stash.dart';
import '../../domain/refs/tag.dart';
import '../../application/git/git_result.dart';
import '../../application/git/merge_outcome.dart';
import '../../domain/repositories/repo_location.dart';
import '../dialogs/confirm_dialog.dart';
import 'branch_tree.dart';

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
  final branches = await git.getBranches(repo);
  final tags = await git.getTags(repo);
  final remotes = await git.getRemotes(repo);
  final stashes = await git.getStashes(repo);
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

    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: Color(0xFF25252A),
        border: Border(right: BorderSide(color: Color(0xFF313137))),
      ),
      child: activeWs == null
          ? const Center(
              child: Text(
                'No repository selected',
                style: TextStyle(
                    color: Color(0xFF888892), fontStyle: FontStyle.italic),
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
                            const TextStyle(color: Color(0xFFF48771))),
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
          child: data.remotes.isEmpty
              ? const _EmptyHint('No remotes')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final r in data.remotes) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                            left: 14, top: 4, bottom: 2),
                        child: Text(
                          r.name.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF888892),
                            fontSize: 10.5,
                            letterSpacing: 0.4,
                          ),
                        ),
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
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 3),
          child: Text(
            tag.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFB8B8BC), fontSize: 12.5),
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
            style: const TextStyle(color: Color(0xFFB8B8BC), fontSize: 12.5),
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
  const _Section({required this.title, required this.child});

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
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
                color: const Color(0xFF5D5D65),
              ),
              const SizedBox(width: 4),
              Text(
                widget.title,
                style: const TextStyle(
                  color: Color(0xFF888892),
                  fontSize: 10.5,
                  letterSpacing: 0.5,
                ),
              ),
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
            style: const TextStyle(
                color: Color(0xFF5D5D65),
                fontSize: 11.5,
                fontStyle: FontStyle.italic)),
      );
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
              backgroundColor: const Color(0xFFC4314B),
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
            onTap: () {},
            child: Padding(
              padding: EdgeInsets.only(
                  left: indent + 18, right: 6, top: 3, bottom: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    child: current
                        ? const Text('✓',
                            style: TextStyle(
                                color: Color(0xFF4EC9B0), fontSize: 11))
                        : null,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      n.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: current
                            ? const Color(0xFF4EC9B0)
                            : const Color(0xFFB8B8BC),
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
                              ? const Color(0xFF5D5D65)
                              : const Color(0xFF888892),
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
                color: const Color(0xFF5D5D65),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(n.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB8B8BC),
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
