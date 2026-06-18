import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/main_view_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
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
    return Container(
      height: 30,
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
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final radii = AppRadii.of(context);
    final typography = AppTypography.of(context);
    // fg0 is the adaptive on-surface ink — near-white in dark, near-black in
    // light. Using it (instead of a hardcoded Colors.white) keeps the selected
    // label readable on bgAccent in BOTH themes: light bgAccent is a pale blue
    // that white text was effectively invisible against.
    final fg = selected ? palette.fg0 : palette.fg1;
    return Material(
      color: selected ? palette.bgAccent : palette.bg3,
      borderRadius: radii.controlRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radii.controlRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: Row(
            children: [
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: typography.caption.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
