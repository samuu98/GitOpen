import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/branch_visibility_provider.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/checkout/safe_checkout.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/dialogs/interactive_rebase_dialog.dart';
import 'package:gitopen/ui/dialogs/merge_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/sidebar/branch_tree.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Renders a [BranchTreeNode] forest with collapsible folders, the
/// current-branch marker, per-ref visibility toggles and the branch context
/// menu (checkout / merge / rebase / rename / upstream / delete).
class BranchTreeView extends ConsumerStatefulWidget {
  const BranchTreeView({
    required this.nodes,
    required this.repo,
    super.key,
    this.depth = 0,
  });
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
        for (final n in widget.nodes) _renderNode(n, widget.depth),
      ],
    );
  }

  void _refresh() {
    ref.invalidate(sidebarDataProvider(widget.repo));
  }

  Future<void> _handleContextMenu(
    BuildContext context,
    BranchTreeNode n,
    Offset globalPos,
  ) async {
    final branch = n.branch;
    if (branch == null) return;
    final branchName = branch.name;
    // Merge/rebase only make sense when the right-clicked branch isn't the
    // one already checked out. Local renaming applies to local branches only.
    final isCurrent = branch.isCurrent;
    final isLocal = !branch.isRemote;

    final entries = <AppContextMenuEntry<String>>[
      if (!isCurrent)
        AppMenuItem(
          value: 'checkout',
          label: isLocal ? 'Checkout' : 'Checkout as local branch',
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
        AppMenuItem(
          value: 'interactive_rebase',
          label: 'Interactive rebase onto this…',
          icon: Icons.playlist_play,
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
        final ok = await checkoutRef(
          context: context,
          ref: ref,
          repo: widget.repo,
          name: branchName,
          isRemote: branch.isRemote,
        );
        if (ok) _refresh();

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
          body:
              'Rebase the current branch onto "$branchName"? '
              'This rewrites commits on the current branch.',
          confirmLabel: 'Rebase',
        );
        if (!confirmed || !context.mounted) return;
        await ref
            .read(gitActionsControllerProvider)
            .rebase(context, widget.repo, branchName);
        _refresh();

      case 'interactive_rebase':
        final tip = branch.tipSha;
        if (tip == null || !context.mounted) return;
        final plan = await InteractiveRebaseDialog.show(
          context,
          repo: widget.repo,
          onto: tip,
        );
        if (plan == null || !context.mounted) return;
        await ref
            .read(gitActionsControllerProvider)
            .interactiveRebase(context, widget.repo, tip, plan);
        _refresh();

      case 'rename':
        final newName = await _promptText(
          context,
          'Rename branch',
          label: 'New name',
          initial: branchName,
        );
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
        final upstream = await _promptText(
          context,
          'Set upstream',
          label: 'Upstream ref (e.g. origin/main)',
        );
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
  Future<String?> _promptText(
    BuildContext context,
    String title, {
    required String label,
    String? initial,
  }) async {
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
      final isHidden =
          fullName != null && ref.read(hiddenRefsProvider).contains(fullName);
      return Opacity(
        opacity: isHidden ? 0.5 : 1.0,
        child: GestureDetector(
          onSecondaryTapDown: (details) =>
              _handleContextMenu(context, n, details.globalPosition),
          child: InkWell(
            onTap: branch?.tipSha == null
                ? null
                : () => revealCommit(ref, branch!.tipSha!),
            onDoubleTap: branch == null || current
                ? null
                : () async {
                    final ok = await checkoutRef(
                      context: context,
                      ref: ref,
                      repo: widget.repo,
                      name: branch.name,
                      isRemote: branch.isRemote,
                    );
                    if (ok) _refresh();
                  },
            child: Padding(
              padding: EdgeInsets.only(
                left: indent + 18,
                right: 6,
                top: 3,
                bottom: 3,
              ),
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
                    Semantics(
                      button: true,
                      label: isHidden
                          ? 'Show ${n.name} in the graph'
                          : 'Hide ${n.name} from the graph',
                      child: GestureDetector(
                        onTap: () => ref
                            .read(hiddenRefsProvider.notifier)
                            .toggle(fullName),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            isHidden ? Icons.visibility_off : Icons.visibility,
                            size: 13,
                            color: isHidden
                                ? AppPalette.of(context).fg3
                                : AppPalette.of(context).fg2,
                          ),
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
              left: indent,
              right: 12,
              top: 3,
              bottom: 3,
            ),
            child: Row(
              children: [
                Icon(
                  open ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: AppPalette.of(context).fg3,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    n.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppPalette.of(context).fg1,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
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
