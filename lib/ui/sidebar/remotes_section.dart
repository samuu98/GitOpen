import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/remote.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/dialogs/remote_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/sidebar/branch_tree.dart';
import 'package:gitopen/ui/sidebar/branch_tree_view.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// The "+" affordance in the REMOTES section header.
class AddRemoteIconButton extends ConsumerWidget {
  const AddRemoteIconButton({
    required this.repo,
    required this.onChanged,
    super.key,
  });
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

/// Inline call-to-action shown when the repository has no remotes yet.
class AddRemoteEmptyState extends ConsumerWidget {
  const AddRemoteEmptyState({
    required this.repo,
    required this.onChanged,
    super.key,
  });
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

/// One remote with its collapsible branch tree and a fetch/edit/rename/remove
/// context menu.
class RemoteGroup extends ConsumerStatefulWidget {
  const RemoteGroup({
    required this.remote,
    required this.repo,
    required this.onChanged,
    super.key,
  });
  final Remote remote;
  final RepoLocation repo;
  final VoidCallback onChanged;

  @override
  ConsumerState<RemoteGroup> createState() => _RemoteGroupState();
}

class _RemoteGroupState extends ConsumerState<RemoteGroup> {
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
                  left: kSidebarChevronIndent,
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
    BuildContext context,
    WidgetRef ref,
    Offset globalPos,
  ) async {
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
        await ref
            .read(gitActionsControllerProvider)
            .fetchRemote(context, repo, remote.name);
        onChanged();

      case 'edit_url':
        final result = await RemoteDialog.showEditUrl(
          context,
          remote.name,
          remote.url,
        );
        if (result == null) return;
        await write.setRemoteUrl(repo, remote.name, result.url);
        ref.read(authResolverProvider).clearCache(repo.id.value);
        onChanged();

      case 'rename':
        final result = await RemoteDialog.showRename(context, remote.name);
        if (result == null) return;
        await write.renameRemote(repo, remote.name, result.name);
        ref.read(authResolverProvider).clearCache(repo.id.value);
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
        ref.read(authResolverProvider).clearCache(repo.id.value);
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
  ref.read(authResolverProvider).clearCache(repo.id.value);
  onChanged();
}
