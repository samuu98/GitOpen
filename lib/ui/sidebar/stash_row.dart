import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// One stash in the STASHES section, with apply / pop / drop context menu.
class StashRow extends ConsumerWidget {
  const StashRow({
    required this.stash,
    required this.repo,
    required this.onRefresh,
    super.key,
  });
  final Stash stash;
  final RepoLocation repo;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(busyProvider);
    final pending =
        busy.isRunning('${repo.id.value}/stash-restore:${stash.index}') ||
        busy.isRunning('${repo.id.value}/stash-drop:${stash.index}');
    return SidebarRowSurface(
      semanticLabel: 'Stash ${stash.index}: ${stash.message}',
      onSecondaryTapDown: pending
          ? null
          : (details) => _showContextMenu(context, ref, details.globalPosition),
      onTap: pending ? null : () => revealCommit(ref, stash.sha),
      child: Padding(
        padding: const EdgeInsets.only(left: kSidebarRowIndent - 1, right: 26),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'stash@{${stash.index}} — ${stash.message}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppPalette.of(context).fg1,
                  fontSize: 12.5,
                ),
              ),
            ),
            if (pending)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset globalPos,
  ) async {
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

      case 'pop':
        await actions.stashPop(context, repo, stash.index);

      case 'drop':
        if (!context.mounted) return;
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Drop stash?',
          body:
              '"stash@{${stash.index}}" will be dropped. This cannot be '
              'undone.',
          confirmLabel: 'Drop',
          dangerous: true,
        );
        if (!confirmed || !context.mounted) return;
        await actions.stashDrop(context, repo, stash.index);
    }
  }
}
