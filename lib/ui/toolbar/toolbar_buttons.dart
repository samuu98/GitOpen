import 'package:flutter/material.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// A toolbar action with the shared pointer and keyboard states.
class ToolbarButton extends StatelessWidget {
  const ToolbarButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    super.key,
    this.tooltip,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final String? tooltip;
  final bool compact;

  @override
  Widget build(BuildContext context) => _ToolbarSurface(
    icon: icon,
    label: label,
    tooltip: tooltip ?? label,
    enabled: enabled,
    onTap: onTap,
    compact: compact,
  );
}

/// Toolbar action that opens a menu.
class ToolbarDropdownButton extends StatelessWidget {
  const ToolbarDropdownButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    super.key,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => _ToolbarSurface(
    icon: icon,
    label: label,
    tooltip: label,
    enabled: enabled,
    onTap: onTap,
    compact: compact,
    dropdown: true,
  );
}

class _ToolbarSurface extends StatelessWidget {
  const _ToolbarSurface({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    required this.compact,
    this.dropdown = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;
  final bool compact;
  final bool dropdown;

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    final typography = AppTypography.of(context);
    final palette = AppPalette.of(context);
    return AppInteractiveSurface(
      onTap: enabled ? onTap : null,
      tooltip: tooltip,
      semanticLabel: label,
      height: spacing.regularControlHeight,
      alignment: null,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? spacing.sm : spacing.md,
      ),
      child: (context, visual) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: spacing.regularIconSize, color: visual.foreground),
          if (!compact) ...[
            SizedBox(width: spacing.xs),
            Text(
              label,
              style: typography.body.copyWith(color: visual.foreground),
            ),
          ],
          if (dropdown) ...[
            SizedBox(width: spacing.xxs),
            Icon(
              Icons.expand_more,
              size: spacing.compactIconSize,
              color: enabled ? palette.fg2 : visual.foreground,
            ),
          ],
        ],
      ),
    );
  }
}
