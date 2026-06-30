import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/bottom_panel/commit_details_view.dart';
import 'package:gitopen/ui/bottom_panel/diff_view.dart';
import 'package:gitopen/ui/bottom_panel/file_tree_view.dart';
import 'package:gitopen/ui/common/app_empty_state.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class BottomPanel extends ConsumerStatefulWidget {
  const BottomPanel({required this.repo, super.key});
  final RepoLocation repo;

  @override
  ConsumerState<BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends ConsumerState<BottomPanel> {
  @override
  Widget build(BuildContext context) {
    final sha = ref.watch(selectedCommitShaProvider);
    final tab = ref.watch(bottomPanelTabProvider);
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.bg1,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Column(
        children: [
          _TabsBar(
            active: tab,
            onSelect: (v) =>
                ref.read(bottomPanelTabProvider.notifier).state = v,
          ),
          Expanded(child: _body(context, sha, tab)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, CommitSha? sha, String tab) {
    if (sha == null) {
      return const AppEmptyState(
        icon: Icons.commit,
        title: 'No commit selected',
        message: 'Select a commit to see its details, changes, and files.',
      );
    }
    switch (tab) {
      case 'commit':
        return CommitDetailsView(repo: widget.repo, sha: sha);
      case 'changes':
        return DiffView(repo: widget.repo, sha: sha);
      case 'files':
        return FileTreeViewWidget(repo: widget.repo, sha: sha);
    }
    return const SizedBox.shrink();
  }
}

class _TabsBar extends StatelessWidget {
  const _TabsBar({required this.active, required this.onSelect});
  final String active;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      color: palette.bg3,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _Tab(
            label: 'Commit',
            value: 'commit',
            active: active,
            onSelect: onSelect,
          ),
          _Tab(
            label: 'Changes',
            value: 'changes',
            active: active,
            onSelect: onSelect,
          ),
          _Tab(
            label: 'File Tree',
            value: 'files',
            active: active,
            onSelect: onSelect,
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.value,
    required this.active,
    required this.onSelect,
  });
  final String label;
  final String value;
  final String active;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final motion = AppMotion.of(context);
    final isActive = active == value;
    return InkWell(
      onTap: () => onSelect(value),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.lg,
          vertical: spacing.sm,
        ),
        child: AnimatedContainer(
          duration: motion.fast,
          curve: motion.curve,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? palette.accentCurrent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            label,
            style: AppTypography.of(context).body.copyWith(
                  color: isActive ? palette.fg0 : palette.fg1,
                ),
          ),
        ),
      ),
    );
  }
}
