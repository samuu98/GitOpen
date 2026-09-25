import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/submodule.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/operations/action_feedback.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// One submodule in the SUBMODULES section: status badge + update context
/// menu.
class SubmoduleRow extends ConsumerWidget {
  const SubmoduleRow({
    required this.submodule,
    required this.repo,
    super.key,
  });
  final Submodule submodule;
  final RepoLocation repo;

  bool get _isUninitialized =>
      submodule.status == SubmoduleStatus.uninitialized;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final pending = ref
        .watch(busyProvider)
        .isRunning('${repo.id.value}/submodule-update:${submodule.path}');
    return SidebarRowSurface(
      semanticLabel: 'Submodule ${submodule.path}, ${submodule.status.name}',
      onSecondaryTapDown: pending
          ? null
          : (details) => _showContextMenu(context, ref, details.globalPosition),
      // Initialized submodules point at a real commit; reveal it in the
      // graph. Uninitialized ones still record the expected SHA, but it may
      // not be present locally yet, so tapping is a no-op there.
      onTap: pending || _isUninitialized
          ? null
          : () => revealCommit(ref, submodule.sha),
      child: Padding(
        padding: const EdgeInsets.only(left: kSidebarRowIndent - 1, right: 26),
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
            if (pending)
              SizedBox(
                width: AppSpacing.of(context).compactIconSize,
                height: AppSpacing.of(context).compactIconSize,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            else
              _SubmoduleStatusBadge(status: submodule.status),
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
    // `init` and `update` both go through updateSubmodule; `init: true`
    // additionally registers + clones an uninitialized submodule.
    final run = await ref
        .read(actionRunnerProvider)
        .runAndRefresh(
          key: 'submodule-update:${submodule.path}',
          repo: repo,
          scopes: const {RefreshScope.sidebar, RefreshScope.status},
          label: 'Updating submodule…',
          action: () => write.updateSubmodule(
            repo,
            submodule.path,
            init: selected == 'init',
          ),
          failed: (result) => result is GitFailure<void>,
        );
    if (run.value case GitFailure<void>(:final message)) {
      ref.read(actionFeedbackProvider).showActionFailure(message);
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
