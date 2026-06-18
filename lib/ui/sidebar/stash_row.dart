import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    return Semantics(
      button: true,
      label: 'Stash ${stash.index}: ${stash.message}',
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, ref, details.globalPosition),
        child: InkWell(
          onTap: () => revealCommit(ref, stash.sha),
          child: Padding(
            padding: const EdgeInsets.only(
                left: kSidebarRowIndent, right: 26, top: 3, bottom: 3),
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
