import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/dialogs/remove_worktree_dialog.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
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

  bool get _isThisCheckout => p.equals(worktree.path, repo.path);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final label =
        worktree.branch ??
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
            // Glyph-led row (like a branch leaf): pad to the glyph column and
            // let the marker box carry the label out to the label column.
            padding: const EdgeInsets.only(
              left: kSidebarRowGlyphIndent,
              right: 26,
              top: 3,
              bottom: 3,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: kSidebarGlyphColumnWidth,
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
                const SizedBox(width: kSidebarGlyphGap),
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
                // Flexible, not a bare Text: a long branch name (they are
                // routinely longer than the whole panel) demanded its full
                // intrinsic width, which starved the Expanded above it down
                // to ZERO — the worktree's folder name vanished and the row
                // rendered as a lone tick followed by an overflowing branch
                // name, which read as a tick stranded far from its label.
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: palette.fg3,
                      fontSize: 11,
                      fontFamily: 'monospace',
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
    final navigator = Navigator.of(context, rootNavigator: true);
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
            label: 'Remove worktree',
            icon: Icons.delete_outline,
            danger: true,
          ),
      ],
    );
    if (selected == null || !navigator.mounted) return;

    switch (selected) {
      case 'open':
        await _open(ref);

      case 'remove':
        await RemoveWorktreeDialog.show(
          navigator.context,
          repo: repo,
          worktree: worktree,
        );
    }
  }
}
