import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/checkout/safe_checkout.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// One tag in the TAGS section, with checkout / push / delete context menu.
class TagRow extends ConsumerWidget {
  const TagRow({
    required this.tag,
    required this.repo,
    required this.onRefresh,
    super.key,
  });
  final Tag tag;
  final RepoLocation repo;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: 'Tag ${tag.name}',
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, ref, details.globalPosition),
        child: InkWell(
          onTap: () => revealCommit(ref, tag.targetSha),
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
            padding: const EdgeInsets.only(
                left: kSidebarRowIndent, right: 26, top: 3, bottom: 3),
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

    switch (selected) {
      case 'checkout':
        final ok = await safeCheckout(
          context: context,
          ref: ref,
          repo: repo,
          targetRef: tag.name,
        );
        if (ok) onRefresh();

      case 'push_tag':
        await ref
            .read(gitActionsControllerProvider)
            .pushTag(context, repo, tag.name);
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
