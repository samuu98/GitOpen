import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/main_view_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Segmented toggle between the commit-graph view, the working-copy changes
/// view and (for github.com origins) the GitHub PRs/Actions view. Lives at
/// the top of the main panel area.
class ViewSelector extends ConsumerWidget {
  const ViewSelector({required this.repo, super.key});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final current = ref.watch(mainViewProvider);
    final isGitHub = ref.watch(githubSlugProvider(repo)).valueOrNull != null;
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
          if (isGitHub) ...[
            const SizedBox(width: 4),
            _SegmentButton(
              label: 'GitHub',
              icon: Icons.cloud_outlined,
              selected: current == MainView.github,
              onTap: () =>
                  ref.read(mainViewProvider.notifier).state = MainView.github,
            ),
          ],
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
    final fg = selected ? Colors.white : palette.fg1;
    return Material(
      color: selected ? palette.bgAccent : palette.bg3,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: Row(
            children: [
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 11.5,
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
