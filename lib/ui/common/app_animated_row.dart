import 'package:flutter/material.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';

class AppAnimatedRow extends StatelessWidget {
  const AppAnimatedRow({
    required this.child,
    required this.selected,
    required this.onTap,
    super.key,
    this.semanticLabel,
    this.onSecondaryTapDown,
    this.height,
    this.padding,
    this.tooltip,
    this.autofocus = false,
    this.visualStates = const {},
  });

  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final GestureTapDownCallback? onSecondaryTapDown;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final String? tooltip;
  final bool autofocus;
  final Set<WidgetState> visualStates;

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    return AppInteractiveSurface(
      onTap: onTap,
      selected: selected,
      autofocus: autofocus,
      visualStates: visualStates,
      semanticLabel: semanticLabel,
      tooltip: tooltip,
      onSecondaryTapDown: onSecondaryTapDown,
      height: height,
      padding: padding ?? spacing.row,
      borderRadius: AppRadii.of(context).rowRadius,
      alignment: Alignment.centerLeft,
      child: (context, visual) => child,
    );
  }
}
