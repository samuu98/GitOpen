import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_empty_state.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';
import 'package:gitopen/ui/common/app_panel_state.dart';
import 'package:gitopen/ui/dialogs/add_worktree_dialog.dart';
import 'package:gitopen/ui/dialogs/tag_create_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
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
    // Width is owned by the HorizontalSplitter in the shell (this is its left
    // pane); the splitter handle doubles as the right divider, so no border
    // here.
    return ColoredBox(
      color: palette.bg2,
      child: activeWs == null
          ? const AppEmptyState(
              icon: Icons.folder_open_outlined,
              title: 'No repository selected',
            )
          : Consumer(
              builder: (context, ref, _) {
                final repo = activeWs.location;
                final async = ref.watch(sidebarDataProvider(repo));
                return async.when(
                  // Keep the current branches/refs on screen while an
                  // auto-refresh (fetch / focus regain) reloads in the
                  // background — otherwise the whole panel flickers to a
                  // spinner. Mirrors the commit graph panel.
                  skipLoadingOnReload: true,
                  data: (data) => _SidebarContent(data: data, repo: repo),
                  loading: () => const AppLoadingState.list(rows: 10),
                  error: (e, _) => AppErrorState(
                    message: 'Could not load sidebar',
                    detail: '$e',
                    onRetry: () => ref.invalidate(sidebarDataProvider(repo)),
                  ),
                );
              },
            ),
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
    // Drive the local-branch list (and its current-branch ✓ marker) from
    // localBranchesProvider directly instead of the bundled SidebarData. A
    // checkout refreshes that provider eagerly, so the green marker flips as
    // soon as `git branch` reloads — rather than waiting for the whole sidebar
    // (tags, stashes, submodules, worktrees…) to refetch atomically, which is
    // what made the highlight lag behind the actual branch switch.
    final localBranches =
        (ref.watch(localBranchesProvider(repo)).value ?? data.branches)
            .where((b) => !b.isRemote)
            .toList();
    final localTree = BranchTree.build(localBranches);
    final pinnedSet = ref.watch(
      appSettingsProvider.select(
        (s) => s.pinnedBranches[repo.id.value] ?? const <String>[],
      ),
    );
    final pinnedBranches = localBranches
        .where((b) => pinnedSet.contains(b.fullName))
        .toList();
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
            repo: repo,
            onChanged: () => _refreshSidebar(ref),
          ),
          child: data.remotes.isEmpty
              ? AddRemoteEmptyState(
                  repo: repo,
                  onChanged: () => _refreshSidebar(ref),
                )
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
          trailing: _AddTagIconButton(repo: repo),
          child: data.tags.isEmpty
              ? const _EmptyHint('No tags')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final t in data.tags) TagRow(tag: t, repo: repo),
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
                      StashRow(stash: s, repo: repo),
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
                      SubmoduleRow(submodule: s, repo: repo),
                  ],
                ),
        ),
        _Section(
          title: 'WORKTREES',
          trailing: _AddWorktreeIconButton(
            repo: repo,
            onChanged: () => _refreshSidebar(ref),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final w in data.worktrees)
                WorktreeRow(worktree: w, repo: repo),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddWorktreeIconButton extends ConsumerWidget {
  const _AddWorktreeIconButton({required this.repo, required this.onChanged});
  final RepoLocation repo;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppIconButton(
      icon: Icons.add,
      tooltip: 'Add worktree…',
      size: AppSpacing.of(context).compactControlHeight,
      onPressed: () async {
        final created = await AddWorktreeDialog.show(context, repo);
        if (created) onChanged();
      },
    );
  }
}

class _AddTagIconButton extends ConsumerWidget {
  const _AddTagIconButton({required this.repo});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref
        .watch(busyProvider)
        .actions
        .any(
          (action) =>
              action.running &&
              action.key.startsWith('${repo.id.value}/tag-create:'),
        );
    if (pending) {
      return SizedBox(
        width: AppSpacing.of(context).compactControlHeight,
        height: AppSpacing.of(context).compactControlHeight,
        child: Center(
          child: SizedBox(
            width: AppSpacing.of(context).compactIconSize,
            height: AppSpacing.of(context).compactIconSize,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return AppIconButton(
      icon: Icons.add,
      tooltip: 'Create tag…',
      size: AppSpacing.of(context).compactControlHeight,
      onPressed: () async {
        final request = await TagCreateDialog.show(context);
        if (request == null || !context.mounted) return;
        await ref
            .read(gitActionsControllerProvider)
            .createTag(repo, request.name, message: request.message);
      },
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
        SidebarRowSurface(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.only(
              left: kSidebarChevronIndent - 1,
              right: 14,
            ),
            child: Row(
              children: [
                Icon(
                  _open ? Icons.expand_more : Icons.chevron_right,
                  size: AppSpacing.of(context).regularIconSize,
                  color: palette.fg3,
                ),
                const SizedBox(width: kSidebarGlyphGap),
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
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: widget.child,
          ),
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
    child: Text(
      text,
      style: AppTypography.of(context).caption.copyWith(
        color: AppPalette.of(context).fg3,
        fontStyle: FontStyle.italic,
      ),
    ),
  );
}
