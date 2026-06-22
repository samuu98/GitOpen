import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/skeleton.dart';
import 'package:gitopen/ui/dialogs/add_worktree_dialog.dart';
import 'package:gitopen/ui/sidebar/branch_tree.dart';
import 'package:gitopen/ui/sidebar/branch_tree_view.dart';
import 'package:gitopen/ui/sidebar/remotes_section.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/sidebar/stash_row.dart';
import 'package:gitopen/ui/sidebar/submodule_row.dart';
import 'package:gitopen/ui/sidebar/tag_row.dart';
import 'package:gitopen/ui/sidebar/worktree_row.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// The left rail: branches, remotes, tags, stashes and submodules for the
/// active repository. Sections live in their own files; this file only owns
/// the panel chrome and section layout.
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
              final async = ref.watch(sidebarDataProvider(repo));
              return async.when(
                // Keep the current branches/refs on screen while an
                // auto-refresh (fetch / focus regain) reloads in the
                // background — otherwise the whole panel flickers to a
                // spinner. Mirrors the commit graph panel.
                skipLoadingOnReload: true,
                data: (data) => _SidebarContent(data: data, repo: repo),
                loading: () => const SkeletonList(rows: 10),
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
  final SidebarData data;
  final RepoLocation repo;

  void _refreshSidebar(WidgetRef ref) {
    ref
      ..invalidate(sidebarDataProvider(repo))
      ..invalidate(gitReadOperationsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localBranches = data.branches.where((b) => !b.isRemote).toList();
    final localTree = BranchTree.build(localBranches);
    final pinnedSet = ref.watch(
      appSettingsProvider
          .select((s) => s.pinnedBranches[repo.id.value] ?? const <String>[]),
    );
    final pinnedBranches =
        localBranches.where((b) => pinnedSet.contains(b.fullName)).toList();
    return _SidebarScrollView(
      children: [
        if (pinnedBranches.isNotEmpty)
          _Section(
            title: 'PINNED',
            initiallyOpen: true,
            child: BranchTreeView(
              nodes: [
                for (final b in pinnedBranches)
                  BranchTreeNode(
                    name: b.name,
                    fullPath: b.fullName,
                    branch: b,
                  ),
              ],
              repo: repo,
            ),
          ),
        _Section(
          title: 'LOCAL BRANCHES',
          initiallyOpen: true,
          child: BranchTreeView(nodes: localTree, repo: repo),
        ),
        _Section(
          title: 'REMOTES',
          trailing: AddRemoteIconButton(
              repo: repo, onChanged: () => _refreshSidebar(ref)),
          child: data.remotes.isEmpty
              ? AddRemoteEmptyState(
                  repo: repo, onChanged: () => _refreshSidebar(ref))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final r in data.remotes)
                      RemoteGroup(
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
                      TagRow(
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
                      StashRow(
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
                      SubmoduleRow(
                        submodule: s,
                        repo: repo,
                        onRefresh: () => _refreshSidebar(ref),
                      ),
                  ],
                ),
        ),
        _Section(
          title: 'WORKTREES',
          trailing: _AddWorktreeIconButton(
              repo: repo, onChanged: () => _refreshSidebar(ref)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final w in data.worktrees)
                WorktreeRow(
                  worktree: w,
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

/// Scrolls the sidebar both ways: vertical (outer) for the list of sections,
/// horizontal (inner) so long branch/tag/remote names are reachable instead of
/// being ellipsised. Content takes its intrinsic width (the widest row) but
/// fills the viewport when narrower, so row highlights still reach the edge.
class _SidebarScrollView extends StatefulWidget {
  const _SidebarScrollView({required this.children});
  final List<Widget> children;

  @override
  State<_SidebarScrollView> createState() => _SidebarScrollViewState();
}

class _SidebarScrollViewState extends State<_SidebarScrollView> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _vertical,
      child: SingleChildScrollView(
        controller: _vertical,
        // LayoutBuilder captures the viewport width (the cross axis is bounded;
        // only height is unbounded here) to use as the content's minWidth.
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Scrollbar(
              controller: _horizontal,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: IntrinsicWidth(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: widget.children,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AddWorktreeIconButton extends ConsumerWidget {
  const _AddWorktreeIconButton({required this.repo, required this.onChanged});
  final RepoLocation repo;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: 'Add worktree',
      child: InkWell(
        onTap: () async {
          final created = await AddWorktreeDialog.show(context, repo);
          if (created) onChanged();
        },
        borderRadius: BorderRadius.circular(2),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(Icons.add, size: 14, color: AppPalette.of(context).fg2),
        ),
      ),
    );
  }
}

class _Section extends StatefulWidget {
  const _Section({
    required this.title,
    required this.child,
    this.trailing,
    this.initiallyOpen = false,
  });
  final String title;
  final Widget child;
  final Widget? trailing;
  final bool initiallyOpen;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.only(
              left: kSidebarChevronIndent,
              right: 14,
              top: 6,
              bottom: 6,
            ),
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
                  style: AppTypography.of(context).caption.copyWith(
                        color: palette.fg2,
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
        padding: const EdgeInsets.only(
          left: kSidebarRowIndent,
          right: 14,
          top: 4,
          bottom: 4,
        ),
        child: Text(text,
            style: AppTypography.of(context).caption.copyWith(
                  color: AppPalette.of(context).fg3,
                  fontStyle: FontStyle.italic,
                )),
      );
}
