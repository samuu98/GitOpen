import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/branch_visibility_provider.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/main_view_provider.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/scroll_request_provider.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/remote.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/refs/submodule.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/checkout/safe_checkout.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/dialogs/merge_dialog.dart';
import 'package:gitopen/ui/dialogs/remote_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/sidebar/branch_tree.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Selects [sha] in the graph and asks the graph panel to scroll it into
/// view. Also switches the main view back to the graph if the user is
/// currently looking at the working-copy changes.
void _revealCommit(WidgetRef ref, CommitSha sha) {
  ref.read(mainViewProvider.notifier).state = MainView.graph;
  ref.read(selectedCommitShaProvider.notifier).state = sha;
  ref.read(scrollRequestProvider.notifier).state = sha;
}

class _SidebarData {
  _SidebarData(
    this.branches,
    this.tags,
    this.remotes,
    this.stashes,
    this.submodules,
  );
  final List<Branch> branches;
  final List<Tag> tags;
  final List<Remote> remotes;
  final List<Stash> stashes;
  final List<Submodule> submodules;
}

final FutureProviderFamily<_SidebarData, RepoLocation> _sidebarDataProvider =
    FutureProvider.family<_SidebarData, RepoLocation>((ref, repo) async {
  final logger = ref.read(loggerProvider);
  final git = ref.watch(gitReadOperationsProvider);
  logger.i('sidebar: awaiting shared branches for ${repo.displayName}');
  final branches = await ref.watch(branchesProvider(repo).future);
  logger.i('sidebar: ${branches.length} branches — loading tags');
  final tags = await git.getTags(repo);
  logger.i('sidebar: ${tags.length} tags — loading remotes');
  final remotes = await git.getRemotes(repo);
  logger.i('sidebar: ${remotes.length} remotes — loading stashes');
  final stashes = await git.getStashes(repo);
  logger.i('sidebar: ${stashes.length} stashes — loading submodules');
  final submodules = await git.getSubmodules(repo);
  logger.i('sidebar: ${submodules.length} submodules — done');
  return _SidebarData(branches, tags, remotes, stashes, submodules);
});

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspaceManagerProvider);
    final activeWs = active == null
        ? null
        : workspaces.where((w) => w.location.id == active).firstOrNull;

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
              final repo = activeWs.location;
              final async = ref.watch(_sidebarDataProvider(repo));
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
  const _SidebarContent({required this.data, required this.repo});
  final _SidebarData data;
  final RepoLocation repo;

  void _refreshSidebar(WidgetRef ref) {
    ref
      ..invalidate(_sidebarDataProvider(repo))
      ..invalidate(gitReadOperationsProvider);
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
                    for (final r in data.remotes)
                      _RemoteGroup(
                        remote: r,
                        repo: repo,
                        onChanged: () => _refreshSidebar(ref),
                      ),
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
                      _TagRow(
                        tag: t,
                        repo: repo,
                        onRefresh: () => _refreshSidebar(ref),
                      ),
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
                      _StashRow(
                        stash: s,
                        repo: repo,
                        onRefresh: () => _refreshSidebar(ref),
                      ),
                  ],
                ),
        ),
        _Section(
          title: 'SUBMODULES',
          child: data.submodules.isEmpty
              ? const _EmptyHint('No submodules')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in data.submodules)
                      _SubmoduleRow(
                        submodule: s,
                        repo: repo,
                        onRefresh: () => _refreshSidebar(ref),
                      ),
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

  const _TagRow({
    required this.tag,
    required this.repo,
    required this.onRefresh,
  });
  final Tag tag;
  final RepoLocation repo;
  final VoidCallback onRefresh;

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
            style: TextStyle(
              color: AppPalette.of(context).fg1,
              fontSize: 12.5,
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
        AppMenuItem(
          value: 'checkout',
          label: 'Checkout',
          icon: Icons.swap_horiz,
        ),
        AppMenuItem(value: 'push_tag', label: 'Push tag', icon: Icons.upload),
        AppMenuDivider(),
        AppMenuItem(
          value: 'delete_tag',
          label: 'Delete tag',
          icon: Icons.delete_outline,
          danger: true,
        ),
      ],
    );

    if (selected == null || !context.mounted) return;
    final write = ref.read(gitWriteOperationsProvider);

    switch (selected) {
      case 'checkout':
        await ref
            .read(gitActionsControllerProvider)
            .checkout(context, repo, tag.name);
        onRefresh();

      case 'push_tag':
        // Push the specific tag to origin using the push stream;
        // fire-and-forget with no progress tracking for simplicity.
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
        if (!context.mounted) return;
        await ref
            .read(gitActionsControllerProvider)
            .deleteTag(context, repo, tag.name);
        onRefresh();
    }
  }
}

// ---------------------------------------------------------------------------
// Stash row with context menu
// ---------------------------------------------------------------------------

class _StashRow extends ConsumerWidget {

  const _StashRow({
    required this.stash,
    required this.repo,
    required this.onRefresh,
  });
  final Stash stash;
  final RepoLocation repo;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, ref, details.globalPosition),
      child: InkWell(
        onTap: () => _revealCommit(ref, stash.sha),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 3),
          child: Text(
            'stash@{${stash.index}} — ${stash.message}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppPalette.of(context).fg1,
              fontSize: 12.5,
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
        AppMenuItem(
          value: 'apply',
          label: 'Apply',
          icon: Icons.file_download_outlined,
        ),
        AppMenuItem(value: 'pop', label: 'Pop', icon: Icons.upload_outlined),
        AppMenuDivider(),
        AppMenuItem(
          value: 'drop',
          label: 'Drop',
          icon: Icons.delete_outline,
          danger: true,
        ),
      ],
    );

    if (selected == null || !context.mounted) return;
    final actions = ref.read(gitActionsControllerProvider);

    switch (selected) {
      case 'apply':
        await actions.stashApply(context, repo, stash.index);
        onRefresh();

      case 'pop':
        await actions.stashPop(context, repo, stash.index);
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
        if (!confirmed || !context.mounted) return;
        await actions.stashDrop(context, repo, stash.index);
        onRefresh();
    }
  }
}

// ---------------------------------------------------------------------------
// Submodule row with status badge + update context menu
// ---------------------------------------------------------------------------

class _SubmoduleRow extends ConsumerWidget {
  const _SubmoduleRow({
    required this.submodule,
    required this.repo,
    required this.onRefresh,
  });
  final Submodule submodule;
  final RepoLocation repo;
  final VoidCallback onRefresh;

  bool get _isUninitialized =>
      submodule.status == SubmoduleStatus.uninitialized;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, ref, details.globalPosition),
      child: InkWell(
        // Initialized submodules point at a real commit; reveal it in the
        // graph. Uninitialized ones still record the expected SHA, but it may
        // not be present locally yet, so tapping is a no-op there.
        onTap: _isUninitialized
            ? null
            : () => _revealCommit(ref, submodule.sha),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  submodule.path,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.fg1, fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                submodule.sha.short(),
                style: TextStyle(
                  color: palette.fg3,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 6),
              _SubmoduleStatusBadge(status: submodule.status),
            ],
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
      entries: [
        if (_isUninitialized)
          const AppMenuItem(
            value: 'init',
            label: 'Init & update',
            icon: Icons.download_for_offline_outlined,
          )
        else
          const AppMenuItem(
            value: 'update',
            label: 'Update',
            icon: Icons.sync,
          ),
      ],
    );
    if (selected == null || !context.mounted) return;
    final write = ref.read(gitWriteOperationsProvider);
    final palette = AppPalette.of(context);

    // `init` and `update` both go through updateSubmodule; `init: true`
    // additionally registers + clones an uninitialized submodule.
    final result = await write.updateSubmodule(
      repo,
      submodule.path,
      init: selected == 'init',
    );
    onRefresh();
    if (!context.mounted) return;
    if (result case GitFailure(:final message)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Submodule update failed: $message'),
        backgroundColor: palette.accentErr,
      ));
    }
  }
}

class _SubmoduleStatusBadge extends StatelessWidget {
  const _SubmoduleStatusBadge({required this.status});
  final SubmoduleStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (label, color) = switch (status) {
      SubmoduleStatus.uninitialized => ('uninit', palette.fg3),
      SubmoduleStatus.upToDate => ('ok', palette.accentCurrent),
      SubmoduleStatus.modified => ('modified', palette.accentWarn),
      SubmoduleStatus.mergeConflict => ('conflict', palette.accentErr),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10),
      ),
    );
  }
}

class _Section extends StatefulWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

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
  const _EmptyHint(this.text);
  final String text;

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
  const _AddRemoteIconButton({required this.repo, required this.onChanged});
  final RepoLocation repo;
  final VoidCallback onChanged;

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
  const _AddRemoteEmptyState({required this.repo, required this.onChanged});
  final RepoLocation repo;
  final VoidCallback onChanged;

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
  const _RemoteGroup({
    required this.remote,
    required this.repo,
    required this.onChanged,
  });
  final Remote remote;
  final RepoLocation repo;
  final VoidCallback onChanged;

  @override
  ConsumerState<_RemoteGroup> createState() => _RemoteGroupState();
}

class _RemoteGroupState extends ConsumerState<_RemoteGroup> {
  bool _open = true;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final branchCount = widget.remote.branches.length;
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
                padding: const EdgeInsets.only(
                  left: 6,
                  right: 6,
                  top: 3,
                  bottom: 3,
                ),
                child: Row(
                  children: [
                    Icon(
                      _open ? Icons.expand_more : Icons.chevron_right,
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
        if (_open)
          BranchTreeView(
            nodes: BranchTree.build(widget.remote.branches),
            depth: 1,
            repo: widget.repo,
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
        AppMenuItem(
          value: 'fetch',
          label: 'Fetch',
          icon: Icons.cloud_download_outlined,
        ),
        AppMenuItem(value: 'edit_url', label: 'Edit URL…', icon: Icons.link),
        AppMenuItem(
          value: 'rename',
          label: 'Rename…',
          icon: Icons.drive_file_rename_outline,
        ),
        AppMenuDivider(),
        AppMenuItem(
          value: 'remove',
          label: 'Remove',
          icon: Icons.delete_outline,
          danger: true,
        ),
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
    ref.invalidate(gitReadOperationsProvider);
  } on Object catch (e) {
    ops.finishFailure(id, e.toString());
  }
}

class BranchTreeView extends ConsumerStatefulWidget {
  const BranchTreeView(
      {required this.nodes, required this.repo, super.key, this.depth = 0});
  final List<BranchTreeNode> nodes;
  final int depth;
  final RepoLocation repo;

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
    // Merge/rebase only make sense when the right-clicked branch isn't the
    // one already checked out. Local renaming applies to local branches only.
    final isCurrent = branch.isCurrent;
    final isLocal = !branch.isRemote;

    final entries = <AppContextMenuEntry<String>>[
      if (!isCurrent)
        const AppMenuItem(
          value: 'checkout',
          label: 'Checkout',
          icon: Icons.swap_horiz,
        ),
      if (!isCurrent) ...const [
        AppMenuItem(
          value: 'merge',
          label: 'Merge into current',
          icon: Icons.call_merge,
        ),
        AppMenuItem(
          value: 'rebase',
          label: 'Rebase current onto this',
          icon: Icons.compare_arrows,
        ),
        AppMenuDivider(),
      ],
      if (isLocal) ...const [
        AppMenuItem(
          value: 'rename',
          label: 'Rename…',
          icon: Icons.drive_file_rename_outline,
        ),
        AppMenuItem(
          value: 'upstream',
          label: 'Set upstream…',
          icon: Icons.link,
        ),
        AppMenuDivider(),
      ],
      const AppMenuItem(
        value: 'delete',
        label: 'Delete',
        icon: Icons.delete_outline,
        danger: true,
      ),
    ];

    final selected = await AppContextMenu.show<String>(
      context,
      globalPosition: globalPos,
      entries: entries,
    );

    if (selected == null || !context.mounted) return;
    final actions = ref.read(gitActionsControllerProvider);

    switch (selected) {
      case 'checkout':
        await actions.checkout(context, widget.repo, branchName);
        _refresh();

      case 'merge':
        final current = await currentBranchName(ref, widget.repo);
        if (!context.mounted) return;
        final strategy = await MergeDialog.show(
          context,
          repo: widget.repo,
          sourceRef: branchName,
          targetRef: current ?? 'HEAD',
        );
        if (strategy == null || !context.mounted) return;
        await ref
            .read(gitActionsControllerProvider)
            .merge(context, widget.repo, branchName, strategy);
        _refresh();

      case 'rebase':
        if (!context.mounted) return;
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Rebase current branch',
          body: 'Rebase the current branch onto "$branchName"? '
              'This rewrites commits on the current branch.',
          confirmLabel: 'Rebase',
        );
        if (!confirmed || !context.mounted) return;
        await ref
            .read(gitActionsControllerProvider)
            .rebase(context, widget.repo, branchName);
        _refresh();

      case 'rename':
        final newName = await _promptText(context, 'Rename branch',
            label: 'New name', initial: branchName);
        if (newName == null || newName.trim().isEmpty) return;
        if (!context.mounted) return;
        await actions.renameBranch(
          context,
          widget.repo,
          branchName,
          newName.trim(),
        );
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
        if (!confirmed || !context.mounted) return;
        await actions.deleteBranch(context, widget.repo, branchName);
        _refresh();

      case 'upstream':
        final upstream = await _promptText(context, 'Set upstream',
            label: 'Upstream ref (e.g. origin/main)');
        if (upstream == null || upstream.trim().isEmpty) return;
        if (!context.mounted) return;
        await actions.setUpstream(
          context,
          widget.repo,
          branchName,
          upstream.trim(),
        );
        _refresh();
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
                        ? Text(
                            '✓',
                            style: TextStyle(
                              color: AppPalette.of(context).accentCurrent,
                              fontSize: 11,
                            ),
                          )
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
        if (open)
          BranchTreeView(
            nodes: n.children,
            depth: depth + 1,
            repo: widget.repo,
          ),
      ],
    );
  }
}
