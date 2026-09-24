import 'package:flutter/material.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
    this.selected = false,
    this.danger = false,
    this.size,
    this.iconSize,
    this.autofocus = false,
    this.visualStates = const {},
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final bool danger;
  final double? size;
  final double? iconSize;
  final bool autofocus;
  final Set<WidgetState> visualStates;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    return AppInteractiveSurface(
      onTap: onPressed,
      selected: selected,
      autofocus: autofocus,
      visualStates: visualStates,
      semanticLabel: tooltip,
      tooltip: tooltip,
      height: size ?? spacing.compactControlHeight,
      width: size ?? spacing.compactControlHeight,
      hoverColor: palette.bg4,
      foregroundColor: danger
          ? palette.accentErr
          : selected
          ? palette.fg0
          : palette.fg2,
      child: (context, visual) => Icon(
        icon,
        size: iconSize ?? spacing.regularIconSize,
        color: visual.foreground,
      ),
    );
  }
}
