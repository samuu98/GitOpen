import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../infrastructure/logging/app_logger.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/branch_visibility_provider.dart';
import '../../application/main_view_provider.dart';
import '../../application/providers.dart';
import '../../application/repo_revision.dart';
import '../../application/scroll_request_provider.dart';
import '../../domain/commits/commit_sha.dart';
import '../../domain/refs/branch.dart';
import '../../domain/refs/remote.dart';
import '../../domain/refs/stash.dart';
import '../../domain/refs/tag.dart';
import '../../application/git/git_result.dart';
import '../../application/git/merge_outcome.dart';
import '../../application/git/remote_web_url.dart';
import '../../domain/repositories/repo_location.dart';
import '../../application/operations/running_operation.dart';
import '../checkout/safe_checkout.dart';
import '../common/app_context_menu.dart';
import '../common/skeleton.dart';
import '../dialogs/app_dialog.dart';
import '../dialogs/confirm_dialog.dart';
import '../dialogs/merge_dialog.dart';
import '../dialogs/remote_dialog.dart';
import '../theme/app_palette.dart';
import '../theme/app_typography.dart';
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
  ref.watch(repoRevisionProvider(repo));
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

class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({super.key});

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  static const double _min = 180;
  static const double _max = 480;
  double? _width;
  bool _handleHover = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    _width ??= ref.read(appSettingsProvider).sidebarWidth.clamp(_min, _max);
    final active = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspaceManagerProvider);
    final activeWs = active == null
        ? null
        : workspaces
            .where((w) => w.location.id == active)
            .cast<dynamic>()
            .firstOrNull;

    final palette = AppPalette.of(context);
    final panel = Container(
      width: _width,
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
                loading: () => const SkeletonList(rows: 10, rowHeight: 12),
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

    return Row(children: [
      panel,
      MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _handleHover = true),
        onExit: (_) => setState(() => _handleHover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: (d) {
            setState(() {
              _width = (_width! + d.delta.dx).clamp(_min, _max);
            });
          },
          onHorizontalDragEnd: (_) {
            setState(() => _dragging = false);
            ref.read(appSettingsProvider.notifier).setSidebarWidth(_width!);
          },
          child: Container(
            width: 5,
            color: _dragging
                ? palette.accentCurrent
                : (_handleHover ? palette.borderStrong : Colors.transparent),
          ),
        ),
      ),
    ]);
  }
}

class _SidebarContent extends ConsumerStatefulWidget {
  final _SidebarData data;
  final RepoLocation repo;
  const _SidebarContent({required this.data, required this.repo});

  @override
  ConsumerState<_SidebarContent> createState() => _SidebarContentState();
}

class _SidebarContentState extends ConsumerState<_SidebarContent> {
  final _filterCtl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _filterCtl.dispose();
    super.dispose();
  }

  void _refreshSidebar() => refreshRepo(ref, widget.repo);

  bool _matches(String name) =>
      _query.isEmpty || name.toLowerCase().contains(_query);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final repo = widget.repo;
    final data = widget.data;
    final filtering = _query.isNotEmpty;

    final allLocals = data.branches.where((b) => !b.isRemote).toList();
    final locals = allLocals.where((b) => _matches(b.name)).toList();
    final localTree = BranchTree.build(locals);

    // Pinned (favourite) local branches, shown flat in their own section.
    final pinnedSet = ref.watch(appSettingsProvider
        .select((s) => s.pinnedBranches[repo.id.value] ?? const <String>[]));
    final pinned = allLocals
        .where((b) => pinnedSet.contains(b.fullName) && _matches(b.name))
        .toList();
    final pinnedNodes = [
      for (final b in pinned)
        BranchTreeNode(name: b.name, fullPath: b.name, branch: b),
    ];

    final tags = data.tags.where((t) => _matches(t.name)).toList();
    // Remotes whose name OR any branch matches the query.
    final remotes = data.remotes.where((r) {
      if (!filtering) return true;
      return _matches(r.name) || r.branches.any((b) => _matches(b.name));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterField(
          controller: _filterCtl,
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
        Divider(height: 1, color: palette.border),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (pinnedNodes.isNotEmpty)
                _Section(
                  title: 'PINNED',
                  count: pinned.length,
                  child: BranchTreeView(
                    nodes: pinnedNodes,
                    repo: repo,
                    forceExpanded: true,
                  ),
                ),
              _Section(
                title: 'LOCAL BRANCHES',
                count: allLocals.length,
                child: localTree.isEmpty
                    ? _EmptyHint(filtering ? 'No matches' : 'No local branches')
                    : BranchTreeView(
                        nodes: localTree,
                        repo: repo,
                        forceExpanded: filtering,
                      ),
              ),
              _Section(
                title: 'REMOTES',
                count: data.remotes.length,
                trailing: _AddRemoteIconButton(
                    repo: repo, onChanged: _refreshSidebar),
                child: data.remotes.isEmpty
                    ? _AddRemoteEmptyState(
                        repo: repo, onChanged: _refreshSidebar)
                    : remotes.isEmpty
                        ? const _EmptyHint('No matches')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final r in remotes)
                                _RemoteGroup(
                                  remote: r,
                                  repo: repo,
                                  query: _query,
                                  onChanged: _refreshSidebar,
                                ),
                            ],
                          ),
              ),
              _Section(
                title: 'TAGS',
                count: data.tags.length,
                child: tags.isEmpty
                    ? _EmptyHint(filtering ? 'No matches' : 'No tags')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final t in tags)
                            _TagRow(
                                tag: t,
                                repo: repo,
                                onRefresh: _refreshSidebar),
                        ],
                      ),
              ),
              _Section(
                title: 'STASHES',
                count: data.stashes.length,
                child: data.stashes.isEmpty
                    ? const _EmptyHint('No stashes')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final s in data.stashes)
                            _StashRow(
                                stash: s,
                                repo: repo,
                                onRefresh: _refreshSidebar),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact branch/ref filter box pinned at the top of the sidebar.
class _FilterField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _FilterField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: SizedBox(
        height: 30,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: TextStyle(color: palette.fg0, fontSize: 12.5),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: palette.bg1,
            hintText: 'Filter branches, tags…',
            hintStyle: TextStyle(color: palette.fg3, fontSize: 12.5),
            prefixIcon: Icon(Icons.search, size: 15, color: palette.fg3),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 30, minHeight: 30),
            suffixIcon: controller.text.isEmpty
                ? null
                : GestureDetector(
                    onTap: () {
                      controller.clear();
                      onChanged('');
                    },
                    child: Icon(Icons.close, size: 14, color: palette.fg3),
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: palette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: palette.accentCurrent),
            ),
          ),
        ),
      ),
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
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          hoverColor: AppPalette.of(context).bg3,
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
              style:
                  TextStyle(color: AppPalette.of(context).fg1, fontSize: 12.5),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(
      BuildContext context, WidgetRef ref, Offset globalPos) async {
    final selected = await AppContextMenu.show<String>(
      context,
      globalPosition: globalPos,
      entries: const [
        AppMenuItem(value: 'checkout', label: 'Checkout', icon: Icons.swap_horiz),
        AppMenuItem(value: 'push_tag', label: 'Push tag', icon: Icons.upload),
        AppMenuDivider(),
        AppMenuItem(value: 'delete_tag', label: 'Delete tag', icon: Icons.delete_outline, danger: true),
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
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          hoverColor: AppPalette.of(context).bg3,
          onTap: () => _revealCommit(ref, stash.sha),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 3),
            child: Text(
              'stash@{${stash.index}} — ${stash.message}',
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(color: AppPalette.of(context).fg1, fontSize: 12.5),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(
      BuildContext context, WidgetRef ref, Offset globalPos) async {
    final selected = await AppContextMenu.show<String>(
      context,
      globalPosition: globalPos,
      entries: const [
        AppMenuItem(value: 'apply', label: 'Apply', icon: Icons.file_download_outlined),
        AppMenuItem(value: 'pop', label: 'Pop', icon: Icons.upload_outlined),
        AppMenuDivider(),
        AppMenuItem(value: 'drop', label: 'Drop', icon: Icons.delete_outline, danger: true),
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

class _Section extends ConsumerWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  final int? count;
  const _Section(
      {required this.title, required this.child, this.trailing, this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final open = !ref.watch(appSettingsProvider
        .select((s) => s.collapsedSections.contains(title)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
          hoverColor: palette.bg3,
          onTap: () => ref
              .read(appSettingsProvider.notifier)
              .toggleSectionCollapsed(title),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(children: [
              Icon(
                open ? Icons.expand_more : Icons.chevron_right,
                size: 14,
                color: palette.fg3,
              ),
              const SizedBox(width: 4),
              Text(
                title,
                style: AppTypography.of(context)
                    .label
                    .copyWith(color: palette.fg2),
              ),
              if (count != null && count! > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: palette.bg3,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '$count',
                    style: AppTypography.of(context)
                        .label
                        .copyWith(color: palette.fg2, letterSpacing: 0),
                  ),
                ),
              ],
              const Spacer(),
              ?trailing,
            ]),
          ),
          ),
        ),
        if (open)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: child),
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

class _RemoteGroup extends ConsumerStatefulWidget {
  final Remote remote;
  final RepoLocation repo;
  final VoidCallback onChanged;
  final String query;
  const _RemoteGroup({
    required this.remote,
    required this.repo,
    required this.onChanged,
    this.query = '',
  });

  @override
  ConsumerState<_RemoteGroup> createState() => _RemoteGroupState();
}

class _RemoteGroupState extends ConsumerState<_RemoteGroup> {
  bool _open = true;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final filtering = widget.query.isNotEmpty;
    // When the remote name itself matches, show all its branches; otherwise
    // show only the branches that match the query.
    final nameMatches =
        filtering && widget.remote.name.toLowerCase().contains(widget.query);
    final branches = filtering && !nameMatches
        ? widget.remote.branches
            .where((b) => b.name.toLowerCase().contains(widget.query))
            .toList()
        : widget.remote.branches;
    final branchCount = widget.remote.branches.length;
    final open = _open || filtering;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: widget.remote.url,
          waitDuration: const Duration(milliseconds: 500),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              onSecondaryTapDown: (details) =>
                  _showMenu(context, ref, details.globalPosition),
              child: Container(
                color: _hover ? palette.bg3 : Colors.transparent,
                padding: const EdgeInsets.only(left: 6, right: 6, top: 3, bottom: 3),
                child: Row(
                  children: [
                    Icon(
                      open ? Icons.expand_more : Icons.chevron_right,
                      size: 14,
                      color: palette.fg3,
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.cloud_outlined, size: 13, color: palette.fg2),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.remote.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.fg1,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (branchCount > 0)
                      Text(
                        '$branchCount',
                        style: TextStyle(
                          color: palette.fg3,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (open)
          BranchTreeView(
            nodes: BranchTree.build(branches),
            depth: 1,
            repo: widget.repo,
            forceExpanded: filtering,
          ),
      ],
    );
  }

  Future<void> _showMenu(
      BuildContext context, WidgetRef ref, Offset globalPos) async {
    final selected = await AppContextMenu.show<String>(
      context,
      globalPosition: globalPos,
      entries: const [
        AppMenuItem(value: 'fetch', label: 'Fetch', icon: Icons.cloud_download_outlined),
        AppMenuItem(value: 'edit_url', label: 'Edit URL…', icon: Icons.link),
        AppMenuItem(value: 'rename', label: 'Rename…', icon: Icons.drive_file_rename_outline),
        AppMenuDivider(),
        AppMenuItem(value: 'remove', label: 'Remove', icon: Icons.delete_outline, danger: true),
      ],
    );
    if (selected == null || !context.mounted) return;
    final write = ref.read(gitWriteOperationsProvider);
    final remote = widget.remote;
    final repo = widget.repo;
    final onChanged = widget.onChanged;

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
    refreshRepo(ref, repo);
  } catch (e) {
    ops.finishFailure(id, e.toString());
  }
}

class BranchTreeView extends ConsumerStatefulWidget {
  final List<BranchTreeNode> nodes;
  final int depth;
  final RepoLocation repo;

  /// When true, folders ignore their collapsed state and render expanded —
  /// used while a filter is active so matches are never hidden inside a
  /// collapsed folder.
  final bool forceExpanded;

  const BranchTreeView(
      {super.key,
      required this.nodes,
      this.depth = 0,
      required this.repo,
      this.forceExpanded = false});

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

  /// Refreshes the whole repo view after a write op so the graph, status and
  /// sidebar all reflect the change (e.g. a checkout switches the current
  /// branch everywhere, not just in this tree).
  void _refresh() {
    refreshRepo(ref, widget.repo);
  }

  Future<void> _handleContextMenu(
      BuildContext context, BranchTreeNode n, Offset globalPos) async {
    final branch = n.branch;
    if (branch == null) return;
    final branchName = branch.name;
    // Merge/rebase only make sense when the right-clicked branch isn't the
    // one already checked out. Local renaming applies to local branches only.
    final isCurrent = branch.isCurrent;
    final isLocal = !branch.isRemote;

    final entries = <AppContextMenuEntry<String>>[
      if (!isCurrent && isLocal)
        const AppMenuItem(value: 'checkout', label: 'Checkout', icon: Icons.swap_horiz),
      if (!isLocal)
        const AppMenuItem(
            value: 'checkout_local',
            label: 'Checkout as local branch',
            icon: Icons.swap_horiz),
      if (!isCurrent) ...const [
        AppMenuItem(value: 'merge', label: 'Merge into current', icon: Icons.call_merge),
        AppMenuItem(value: 'rebase', label: 'Rebase current onto this', icon: Icons.compare_arrows),
        AppMenuDivider(),
      ],
      if (isLocal) ...const [
        AppMenuItem(value: 'rename', label: 'Rename…', icon: Icons.drive_file_rename_outline),
        AppMenuItem(value: 'upstream', label: 'Set upstream…', icon: Icons.link),
        AppMenuDivider(),
      ],
      const AppMenuItem(
          value: 'open_remote',
          label: 'Open on remote…',
          icon: Icons.open_in_browser),
      const AppMenuDivider(),
      const AppMenuItem(value: 'delete', label: 'Delete', icon: Icons.delete_outline, danger: true),
    ];

    final selected = await AppContextMenu.show<String>(
      context,
      globalPosition: globalPos,
      entries: entries,
    );

    if (selected == null || !context.mounted) return;
    final write = ref.read(gitWriteOperationsProvider);
    final palette = AppPalette.of(context);

    switch (selected) {
      case 'checkout':
        await write.checkout(widget.repo, branchName);
        _refresh();

      case 'checkout_local':
        // `git checkout <local>` with a matching remote ref DWIM-creates a
        // local tracking branch. Strip the remote prefix (origin/foo → foo).
        final localName = branchName.contains('/')
            ? branchName.substring(branchName.indexOf('/') + 1)
            : branchName;
        final r = await write.checkout(widget.repo, localName);
        _refresh();
        if (r is GitFailure && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Checkout failed: ${r.message}'),
            backgroundColor: palette.accentErr,
          ));
        }

      case 'merge':
        final current = await currentBranchName(ref, widget.repo);
        if (!context.mounted) return;
        final strategy = await MergeDialog.show(
          context,
          repo: widget.repo,
          sourceRef: branchName,
          targetRef: current ?? 'HEAD',
        );
        if (strategy == null) return;
        final result = await write.merge(widget.repo, branchName, strategy: strategy);
        _refresh();
        if (!context.mounted) return;
        if (result case GitSuccess(value: final MergeConflict outcome)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Merge conflict in ${outcome.conflictedPaths.length} file(s). Resolve in the conflicts panel below.'),
              backgroundColor: palette.accentErr,
            ),
          );
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
          body: 'Rebase the current branch onto "$branchName"? '
              'This rewrites commits on the current branch.',
          confirmLabel: 'Rebase',
        );
        if (!confirmed) return;
        final result = await write.rebase(widget.repo, branchName);
        _refresh();
        if (!context.mounted) return;
        if (result case GitSuccess(value: final RebaseConflict outcome)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Rebase conflict in ${outcome.conflictedPaths.length} file(s). Resolve in the conflicts panel below.'),
              backgroundColor: palette.accentErr,
            ),
          );
        } else if (result case GitFailure(:final message)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rebase failed: $message'),
              backgroundColor: palette.accentErr,
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

      case 'open_remote':
        final remotes =
            await ref.read(gitReadOperationsProvider).getRemotes(widget.repo);
        final remote =
            remotes.where((r) => r.name == 'origin').firstOrNull ??
                remotes.firstOrNull;
        final web = remote == null ? null : RemoteWebUrl.parse(remote.url);
        if (web == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('No web-mappable remote configured.')));
          }
          return;
        }
        // origin/foo on the web is just branch foo of that remote.
        final webBranch = branch.isRemote && branchName.contains('/')
            ? branchName.substring(branchName.indexOf('/') + 1)
            : branchName;
        await launchUrl(Uri.parse(web.branch(webBranch)),
            mode: LaunchMode.externalApplication);
    }
  }

  /// Shows a simple single-TextField dialog and returns the entered text,
  /// or null if the user cancelled.
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

  Widget _renderNode(BranchTreeNode n, int depth) {
    final indent = 6.0 + depth * 14.0;
    if (n.children.isEmpty) {
      return _BranchLeafRow(
        node: n,
        indent: indent,
        repo: widget.repo,
        onContextMenu: (pos) => _handleContextMenu(context, n, pos),
        onRefresh: _refresh,
      );
    }
    final open = widget.forceExpanded || !_collapsed.contains(n.fullPath);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
          hoverColor: AppPalette.of(context).bg3,
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
        ),
        if (open)
          BranchTreeView(
              nodes: n.children,
              depth: depth + 1,
              repo: widget.repo,
              forceExpanded: widget.forceExpanded),
      ],
    );
  }
}

/// A single leaf branch row: selectable, with visible hover/selection feedback
/// (a real Material ancestor so InkWell ink shows over the sidebar's own
/// background) and an on-hover "⋯" actions button so the context menu is
/// discoverable without right-clicking.
class _BranchLeafRow extends ConsumerStatefulWidget {
  final BranchTreeNode node;
  final double indent;
  final RepoLocation repo;
  final void Function(Offset globalPosition) onContextMenu;
  final VoidCallback onRefresh;

  const _BranchLeafRow({
    required this.node,
    required this.indent,
    required this.repo,
    required this.onContextMenu,
    required this.onRefresh,
  });

  @override
  ConsumerState<_BranchLeafRow> createState() => _BranchLeafRowState();
}

class _BranchLeafRowState extends ConsumerState<_BranchLeafRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final n = widget.node;
    final branch = n.branch;
    final current = branch?.isCurrent ?? false;
    final fullName = branch?.fullName;
    final isHidden =
        fullName != null && ref.watch(hiddenRefsProvider).contains(fullName);
    final isSelected =
        fullName != null && ref.watch(selectedSidebarRefProvider) == fullName;

    // Ahead/behind (and uncommitted changes) are only cheaply available for
    // the current branch (from `git status`), so only the current row shows
    // those badges.
    final status =
        current ? ref.watch(repoStatusProvider(widget.repo)).valueOrNull : null;
    final ahead = status?.ahead ?? 0;
    final behind = status?.behind ?? 0;
    final hasUncommitted = current && (status?.entries.isNotEmpty ?? false);

    final repoId = widget.repo.id.value;
    final isPinned = fullName != null &&
        ref.watch(appSettingsProvider.select(
            (s) => (s.pinnedBranches[repoId] ?? const []).contains(fullName)));

    final fg = current
        ? palette.accentCurrent
        : (isSelected ? Colors.white : palette.fg1);

    final tooltip = branch == null
        ? null
        : [
            branch.name,
            if (branch.tipSha != null) '@ ${branch.tipSha!.short()}',
            if (branch.upstreamFullName != null)
              '→ ${branch.upstreamFullName}',
          ].join('  ');

    final row = Opacity(
      opacity: isHidden ? 0.5 : 1.0,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            hoverColor: palette.bg3,
            onTap: () {
              if (fullName != null) {
                ref.read(selectedSidebarRefProvider.notifier).state = fullName;
              }
              if (branch?.tipSha != null) _revealCommit(ref, branch!.tipSha!);
            },
            onDoubleTap: branch == null || current
                ? null
                : () async {
                    final ok = await safeCheckout(
                      context: context,
                      ref: ref,
                      repo: widget.repo,
                      targetRef: branch.name,
                    );
                    if (ok) widget.onRefresh();
                  },
            onSecondaryTapDown: (d) => widget.onContextMenu(d.globalPosition),
            child: Container(
              color: isSelected ? palette.bgAccent : Colors.transparent,
              padding: EdgeInsets.only(
                  left: widget.indent + 18, right: 4, top: 3, bottom: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    child: current
                        ? Text('✓',
                            style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : palette.accentCurrent,
                                fontSize: 11))
                        : null,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      n.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: 12.5,
                        fontWeight:
                            current ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  // Uncommitted-changes dot on the current branch.
                  if (hasUncommitted)
                    Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Tooltip(
                        message: 'Uncommitted changes',
                        child: Icon(Icons.circle,
                            size: 7, color: palette.accentWarn),
                      ),
                    ),
                  // Ahead/behind divergence badge for the current branch.
                  if (current && (ahead > 0 || behind > 0)) ...[
                    if (ahead > 0)
                      _AheadBehindBadge(
                          icon: Icons.arrow_upward,
                          count: ahead,
                          color: palette.accentCurrent),
                    if (behind > 0)
                      _AheadBehindBadge(
                          icon: Icons.arrow_downward,
                          count: behind,
                          color: palette.accentRemote),
                  ],
                  // Pin (favourite) star — filled when pinned, shown on hover
                  // otherwise. Local branches only.
                  if (fullName != null && !branch!.isRemote && (_hover || isPinned))
                    _RowIconButton(
                      icon: isPinned ? Icons.star : Icons.star_border,
                      tooltip: isPinned ? 'Unpin' : 'Pin',
                      color: isPinned
                          ? palette.accentTag
                          : (isSelected ? Colors.white70 : palette.fg2),
                      onTapAt: (_) => ref
                          .read(appSettingsProvider.notifier)
                          .togglePinnedBranch(repoId, fullName),
                    ),
                  // On hover: a "⋯" button that opens the same actions menu,
                  // so users don't have to discover right-click.
                  if (_hover && branch != null)
                    _RowIconButton(
                      icon: Icons.more_horiz,
                      tooltip: 'Actions',
                      color: isSelected ? Colors.white70 : palette.fg2,
                      onTapAt: widget.onContextMenu,
                    ),
                  // Visibility eye — shown on hover, or always when hidden so
                  // the hidden state stays discoverable.
                  if (fullName != null && (_hover || isHidden))
                    GestureDetector(
                      onTap: () =>
                          ref.read(hiddenRefsProvider.notifier).toggle(fullName),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Icon(
                          isHidden ? Icons.visibility_off : Icons.visibility,
                          size: 13,
                          color: isHidden ? palette.fg3 : palette.fg2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (tooltip == null) return row;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: row,
    );
  }
}

/// Small icon button that reports the global tap position, used to anchor a
/// context menu where the button is.
class _RowIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final void Function(Offset globalPosition) onTapAt;
  const _RowIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTapAt,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => onTapAt(d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

/// Tiny "↑3" / "↓2" divergence badge for the current branch.
class _AheadBehindBadge extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;
  const _AheadBehindBadge(
      {required this.icon, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          Text('$count',
              style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
