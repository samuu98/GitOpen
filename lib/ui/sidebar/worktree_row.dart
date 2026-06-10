import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:path/path.dart' as p;

/// One worktree in the WORKTREES section. Tapping opens it as a workspace;
/// the context menu can also remove a linked worktree.
class WorktreeRow extends ConsumerWidget {
  const WorktreeRow({
    required this.worktree,
    required this.repo,
    required this.onRefresh,
    super.key,
  });
  final Worktree worktree;
  final RepoLocation repo;
  final VoidCallback onRefresh;

  bool get _isThisCheckout =>
      p.equals(worktree.path, repo.path);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final label = worktree.branch ??
        (worktree.isDetached
            ? (worktree.headSha?.short() ?? 'detached')
            : 'bare');
    return Semantics(
      button: true,
      label: 'Worktree ${p.basename(worktree.path)} on $label',
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, ref, details.globalPosition),
        child: InkWell(
          onTap: _isThisCheckout ? null : () => _open(ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  child: _isThisCheckout
                      ? Text(
                          '✓',
                          style: TextStyle(
                            color: palette.accentCurrent,
                            fontSize: 11,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Tooltip(
                    message: worktree.path,
                    waitDuration: const Duration(milliseconds: 500),
                    child: Text(
                      p.basename(worktree.path),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.fg1, fontSize: 12.5),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: palette.fg3,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(WidgetRef ref) async {
    final manager = ref.read(workspaceManagerProvider.notifier);
    final ws = await manager.open(worktree.path);
    ref.read(activeWorkspaceIdProvider.notifier).state = ws.location.id;
  }

  Future<void> _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset globalPos,
  ) async {
    final selected = await AppContextMenu.show<String>(
      context,
      globalPosition: globalPos,
      entries: [
        const AppMenuItem(
          value: 'open',
          label: 'Open as workspace',
          icon: Icons.open_in_new,
        ),
        if (!_isThisCheckout)
          const AppMenuItem(
            value: 'remove',
            label: 'Remove worktree…',
            icon: Icons.delete_outline,
            danger: true,
          ),
      ],
    );
    if (selected == null || !context.mounted) return;

    switch (selected) {
      case 'open':
        await _open(ref);

      case 'remove':
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Remove worktree',
          body: 'Remove the worktree at "${worktree.path}"? '
              'Uncommitted changes in it will block the removal.',
          confirmLabel: 'Remove',
          dangerous: true,
        );
        if (!confirmed || !context.mounted) return;
        final result = await ref
            .read(gitWriteOperationsProvider)
            .removeWorktree(repo, worktree.path);
        onRefresh();
        if (!context.mounted) return;
        if (result case GitFailure(:final message)) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Remove worktree failed: $message'),
            backgroundColor: AppPalette.of(context).accentErr,
          ));
        }
    }
  }
}
