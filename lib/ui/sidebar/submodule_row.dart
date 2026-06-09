import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/submodule.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// One submodule in the SUBMODULES section: status badge + update context
/// menu.
class SubmoduleRow extends ConsumerWidget {
  const SubmoduleRow({
    required this.submodule,
    required this.repo,
    required this.onRefresh,
    super.key,
  });
  final Submodule submodule;
  final RepoLocation repo;
  final VoidCallback onRefresh;

  bool get _isUninitialized =>
      submodule.status == SubmoduleStatus.uninitialized;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, ref, details.globalPosition),
      child: InkWell(
        // Initialized submodules point at a real commit; reveal it in the
        // graph. Uninitialized ones still record the expected SHA, but it may
        // not be present locally yet, so tapping is a no-op there.
        onTap: _isUninitialized
            ? null
            : () => revealCommit(ref, submodule.sha),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  submodule.path,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.fg1, fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                submodule.sha.short(),
                style: TextStyle(
                  color: palette.fg3,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 6),
              _SubmoduleStatusBadge(status: submodule.status),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(
      BuildContext context, WidgetRef ref, Offset globalPos) async {
    final selected = await AppContextMenu.show<String>(
      context,
      globalPosition: globalPos,
      entries: [
        if (_isUninitialized)
          const AppMenuItem(
            value: 'init',
            label: 'Init & update',
            icon: Icons.download_for_offline_outlined,
          )
        else
          const AppMenuItem(
            value: 'update',
            label: 'Update',
            icon: Icons.sync,
          ),
      ],
    );
    if (selected == null || !context.mounted) return;
    final write = ref.read(gitWriteOperationsProvider);
    final palette = AppPalette.of(context);

    // `init` and `update` both go through updateSubmodule; `init: true`
    // additionally registers + clones an uninitialized submodule.
    final result = await write.updateSubmodule(
      repo,
      submodule.path,
      init: selected == 'init',
    );
    onRefresh();
    if (!context.mounted) return;
    if (result case GitFailure(:final message)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Submodule update failed: $message'),
        backgroundColor: palette.accentErr,
      ));
    }
  }
}

class _SubmoduleStatusBadge extends StatelessWidget {
  const _SubmoduleStatusBadge({required this.status});
  final SubmoduleStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (label, color) = switch (status) {
      SubmoduleStatus.uninitialized => ('uninit', palette.fg3),
      SubmoduleStatus.upToDate => ('ok', palette.accentCurrent),
      SubmoduleStatus.modified => ('modified', palette.accentWarn),
      SubmoduleStatus.mergeConflict => ('conflict', palette.accentErr),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10),
      ),
    );
  }
}
