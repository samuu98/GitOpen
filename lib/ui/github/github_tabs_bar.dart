import 'package:flutter/material.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class GitHubTabsBar extends StatelessWidget {
  const GitHubTabsBar({
    required this.active,
    required this.onSelect,
    super.key,
  });

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
            label: 'Pull requests',
            value: 'prs',
            active: active,
            onSelect: onSelect,
          ),
          _Tab(
            label: 'Actions',
            value: 'actions',
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
    final isActive = active == value;
    return AppInteractiveSurface(
      onTap: () => onSelect(value),
      selected: isActive,
      height: spacing.regularControlHeight,
      padding: EdgeInsets.symmetric(horizontal: spacing.lg),
      child: (context, visual) => Container(
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
            color: visual.foreground,
          ),
        ),
      ),
    );
  }
}
