import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
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
  const TagRow({required this.tag, required this.repo, super.key});
  final Tag tag;
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(busyProvider);
    final pending =
        busy.isRunning('${repo.id.value}/tag-delete:${tag.name}') ||
        busy.isRunning('${repo.id.value}/push-tag:${tag.name}');
    // A second checkout while one is in flight would race git's index lock,
    // so any checkout in this repository disables the double click too.
    final checkingOut = busy.actions.any(
      (a) => a.running && a.key.startsWith('${repo.id.value}/checkout:'),
    );
    return SidebarRowSurface(
      semanticLabel: 'Tag ${tag.name}',
      onTap: pending ? null : () => revealCommit(ref, tag.targetSha),
      // The checkout refreshes the sidebar through the runner; no extra
      // invalidation here.
      onDoubleTap: pending || checkingOut
          ? null
          : () => unawaited(
              safeCheckout(
                context: context,
                ref: ref,
                repo: repo,
                targetRef: tag.name,
              ),
            ),
      onSecondaryTapDown: pending
          ? null
          : (details) => _showContextMenu(context, ref, details.globalPosition),
      child: Padding(
        padding: const EdgeInsets.only(
          left: kSidebarRowIndent - 1,
          right: 26,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                tag.name,
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
        await safeCheckout(
          context: context,
          ref: ref,
          repo: repo,
          targetRef: tag.name,
        );

      case 'push_tag':
        await ref
            .read(gitActionsControllerProvider)
            .pushTag(context, repo, tag.name);

      case 'delete_tag':
        if (!context.mounted) return;
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Delete tag?',
          body: 'Tag "${tag.name}" will be deleted. This cannot be undone.',
          confirmLabel: 'Delete',
          dangerous: true,
        );
        if (!confirmed) return;
        if (!context.mounted) return;
        await ref.read(gitActionsControllerProvider).deleteTag(repo, tag.name);
    }
  }
}
