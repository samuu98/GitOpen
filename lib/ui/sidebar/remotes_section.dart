import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/remote.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/dialogs/remote_dialog.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/operations/action_feedback.dart';
import 'package:gitopen/ui/sidebar/branch_tree.dart';
import 'package:gitopen/ui/sidebar/branch_tree_view.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
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
    final pending = ref
        .watch(busyProvider)
        .isRunning('${repo.id.value}/remote-add');
    return AppIconButton(
      icon: Icons.add,
      tooltip: 'Add remote…',
      size: AppSpacing.of(context).compactControlHeight,
      onPressed: pending ? null : () => _addRemote(context, ref, repo),
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
    final pending = ref
        .watch(busyProvider)
        .isRunning('${repo.id.value}/remote-add');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppButton.secondary(
          onPressed: pending ? null : () => _addRemote(context, ref, repo),
          icon: Icons.add,
          label: 'Add remote…',
          compact: true,
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

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final branchCount = widget.remote.branches.length;
    final busy = ref.watch(busyProvider);
    final pending = ['remote-remove:', 'remote-rename:', 'remote-url:'].any(
      (key) =>
          busy.isRunning('${widget.repo.id.value}/$key${widget.remote.name}'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SidebarRowSurface(
          tooltip: widget.remote.url,
          semanticLabel: 'Remote ${widget.remote.name}',
          onTap: pending ? null : () => setState(() => _open = !_open),
          onSecondaryTapDown: pending
              ? null
              : (details) => _showMenu(context, ref, details.globalPosition),
          child: Padding(
            padding: const EdgeInsets.only(
              left: kSidebarRowGlyphIndent - 1,
              right: 6,
            ),
            child: Row(
              children: [
                // Same glyph column + gap as a branch-tree folder, so the
                // remote name lands in the shared label column and its
                // branches nest exactly one step past it. (The cloud icon
                // that used to sit between chevron and name pushed the
                // label 17px right of every other level-1 row.)
                Icon(
                  _open ? Icons.expand_more : Icons.chevron_right,
                  size: kSidebarGlyphColumnWidth,
                  color: palette.fg3,
                ),
                const SizedBox(width: kSidebarGlyphGap),
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
                if (pending)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    Icons.cloud_outlined,
                    size: AppSpacing.of(context).compactIconSize,
                    color: palette.fg3,
                  ),
                if (branchCount > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$branchCount',
                    style: TextStyle(
                      color: palette.fg3,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_open)
          BranchTreeView(
            // Remote branches are named "origin/main"; the header above
            // already says "origin", so strip it or the tree renders a second
            // "origin" folder underneath it.
            nodes: BranchTree.build(
              widget.remote.branches,
              stripPrefix: widget.remote.name,
            ),
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

    switch (selected) {
      case 'fetch':
        await ref
            .read(gitActionsControllerProvider)
            .fetchRemote(context, repo, remote.name);

      case 'edit_url':
        final result = await RemoteDialog.showEditUrl(
          context,
          remote.name,
          remote.url,
        );
        if (result == null) return;
        await _runRemoteWrite(
          ref,
          repo,
          'remote-url:${remote.name}',
          () => write.setRemoteUrl(repo, remote.name, result.url),
        );

      case 'rename':
        final result = await RemoteDialog.showRename(context, remote.name);
        if (result == null) return;
        await _runRemoteWrite(
          ref,
          repo,
          'remote-rename:${remote.name}',
          () => write.renameRemote(repo, remote.name, result.name),
        );

      case 'remove':
        if (!context.mounted) return;
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Remove remote?',
          body:
              'Remote "${remote.name}" will be removed. Tracking branches '
              'under it will no longer update.',
          confirmLabel: 'Remove',
          dangerous: true,
        );
        if (!confirmed) return;
        await _runRemoteWrite(
          ref,
          repo,
          'remote-remove:${remote.name}',
          () => write.removeRemote(repo, remote.name),
        );
    }
  }
}

Future<void> _addRemote(
  BuildContext context,
  WidgetRef ref,
  RepoLocation repo,
) async {
  final result = await RemoteDialog.showAdd(context);
  if (result == null) return;
  final write = ref.read(gitWriteOperationsProvider);
  await _runRemoteWrite(
    ref,
    repo,
    'remote-add',
    () => write.addRemote(repo, result.name, result.url),
  );
}

Future<void> _runRemoteWrite(
  WidgetRef ref,
  RepoLocation repo,
  String key,
  Future<GitResult<void>> Function() action,
) async {
  final run = await ref
      .read(actionRunnerProvider)
      .runAndRefresh(
        key: key,
        repo: repo,
        scopes: const {RefreshScope.sidebar, RefreshScope.status},
        action: action,
        failed: (result) => result is GitFailure<void>,
      );
  if (run.status
      case ActionRunStatus.succeeded || ActionRunStatus.refreshFailed) {
    ref.read(authResolverProvider).clearCache(repo.id.value);
  } else if (run.value case GitFailure<void>(:final message)) {
    ref.read(actionFeedbackProvider).showActionFailure(message);
  }
}
