import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/main_view_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Top-of-panel navigation. The left group holds the two working states you
/// flip between constantly — the commit Graph and the working-copy Changes.
/// Integrations sit apart on the right and only surface when the repo actually
/// uses them: GitHub for github.com origins, LFS for repos that track LFS
/// content. This keeps niche tools from competing with the daily toggle for
/// attention. (LFS setup for a not-yet-LFS repo lives in the repo-info dialog.)
class ViewSelector extends ConsumerWidget {
  const ViewSelector({required this.repo, super.key});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final current = ref.watch(mainViewProvider);
    final isGitHub = ref.watch(githubSlugProvider(repo)).value != null;
    final lfs = ref.watch(gitLfsStatusProvider(repo)).value;
    final usesLfs = lfs != null && (lfs.isRepoConfigured || lfs.hasAttributes);
    // Count of changed files, shown as a badge on the Changes tab so pending
    // work is visible from the graph without a separate clickable row.
    final changedCount =
        ref.watch(repoStatusProvider(repo)).value?.entries.length ?? 0;
    return Container(
      height: AppSpacing.of(context).listRowHeight,
      color: palette.bg2,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          _SegmentButton(
            label: 'Graph',
            icon: Icons.account_tree_outlined,
            selected: current == MainView.graph,
            onTap: () =>
                ref.read(mainViewProvider.notifier).state = MainView.graph,
          ),
          const SizedBox(width: 4),
          _SegmentButton(
            label: 'Changes',
            icon: Icons.edit_note,
            selected: current == MainView.changes,
            badgeCount: changedCount,
            onTap: () =>
                ref.read(mainViewProvider.notifier).state = MainView.changes,
          ),
          // Integrations live on the far right, away from the daily toggle.
          const Spacer(),
          if (isGitHub) ...[
            _SegmentButton(
              label: 'GitHub',
              icon: Icons.cloud_outlined,
              selected: current == MainView.github,
              onTap: () =>
                  ref.read(mainViewProvider.notifier).state = MainView.github,
            ),
            const SizedBox(width: 4),
          ],
          if (usesLfs)
            _SegmentButton(
              label: 'LFS',
              icon: Icons.storage_outlined,
              selected: current == MainView.lfs,
              onTap: () =>
                  ref.read(mainViewProvider.notifier).state = MainView.lfs,
            ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  /// When > 0, a small count pill is shown after the label.
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final radii = AppRadii.of(context);
    final typography = AppTypography.of(context);
    final spacing = AppSpacing.of(context);
    return AppInteractiveSurface(
      onTap: onTap,
      selected: selected,
      tooltip: label,
      semanticLabel: label,
      alignment: null,
      baseColor: palette.bg3,
      selectedColor: palette.bgAccent,
      borderRadius: radii.controlRadius,
      padding: EdgeInsets.symmetric(
        horizontal: spacing.md - 2,
        vertical: spacing.xxs - 1,
      ),
      child: (context, visual) => Row(
        children: [
          Icon(
            icon,
            size: spacing.compactIconSize,
            color: selected ? palette.fg0 : visual.foreground,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: typography.caption.copyWith(
              color: selected ? palette.fg0 : visual.foreground,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          if (badgeCount > 0) ...[
            const SizedBox(width: 6),
            _CountBadge(count: badgeCount, selected: selected),
          ],
        ],
      ),
    );
  }
}

/// Compact count pill rendered on a [_SegmentButton]. Uses [AppPalette.fg0]
/// ink in both states so it stays legible on the selected (bgAccent) fill and
/// the unselected (bg3) fill, in light and dark themes alike.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.selected});
  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: selected
            ? palette.fg0.withValues(alpha: 0.20)
            : palette.bgAccent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: palette.fg0,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}
