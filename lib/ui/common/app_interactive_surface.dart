import 'package:flutter/material.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// The resolved colors and opacity of one interactive surface.
@immutable
class AppInteractionVisual {
  const AppInteractionVisual({
    required this.background,
    required this.foreground,
    required this.border,
    required this.opacity,
  });

  final Color background;
  final Color foreground;
  final Color border;
  final double opacity;
}

/// Shared desktop pointer, keyboard, semantics and state-layer contract.
/// Domain colors are inputs; hover, press and focus are resolved consistently.
class AppInteractiveSurface extends StatefulWidget {
  const AppInteractiveSurface({
    required this.child,
    required this.onTap,
    super.key,
    this.semanticLabel,
    this.tooltip,
    this.selected = false,
    this.autofocus = false,
    this.onSecondaryTapDown,
    this.height,
    this.width,
    this.padding,
    this.borderRadius,
    this.baseColor,
    this.hoverColor,
    this.selectedColor,
    this.foregroundColor,
    this.borderColor,
    this.visualStates = const {},
    this.alignment = Alignment.center,
  });

  final Widget Function(BuildContext context, AppInteractionVisual visual)
  child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final String? tooltip;
  final bool selected;
  final bool autofocus;
  final GestureTapDownCallback? onSecondaryTapDown;
  final double? height;
  final double? width;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Color? baseColor;
  final Color? hoverColor;
  final Color? selectedColor;
  final Color? foregroundColor;
  final Color? borderColor;

  /// Additional visual states supplied by a parent or component gallery.
  final Set<WidgetState> visualStates;

  /// Null lets the surface shrink-wrap its child, as buttons do.
  final AlignmentGeometry? alignment;

  /// Resolve a state set for themed controls and deterministic previews.
  static AppInteractionVisual resolve(
    AppPalette palette,
    Set<WidgetState> states, {
    Color? baseColor,
    Color? hoverColor,
    Color? selectedColor,
    Color? foregroundColor,
    Color? borderColor,
  }) {
    final disabled = states.contains(WidgetState.disabled);
    final selected = states.contains(WidgetState.selected);
    final hovered = states.contains(WidgetState.hovered);
    final pressed = states.contains(WidgetState.pressed);
    final focused = states.contains(WidgetState.focused);
    final base = selected
        ? selectedColor ?? palette.interactionSelected
        : baseColor ?? Colors.transparent;
    final background = disabled
        ? base
        : pressed
        ? baseColor == null && !selected
              ? palette.interactionPressed
              : Color.lerp(base, palette.interactionPressed, 0.25)!
        : hovered
        ? selected
              ? palette.interactionSelectedHover
              : hoverColor ??
                    (baseColor == null
                        ? palette.interactionHover
                        : Color.lerp(base, palette.interactionHover, 0.2)!)
        : base;
    return AppInteractionVisual(
      background: background,
      foreground: disabled
          ? palette.interactionDisabledForeground
          : foregroundColor ?? palette.fg0,
      border: focused && !disabled
          ? palette.interactionFocusRing
          : selected
          ? palette.borderStrong
          : borderColor ?? Colors.transparent,
      opacity: disabled ? palette.interactionDisabledOpacity : 1,
    );
  }

  @override
  State<AppInteractiveSurface> createState() => _AppInteractiveSurfaceState();
}

class _AppInteractiveSurfaceState extends State<AppInteractiveSurface> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final states = <WidgetState>{
      if (!enabled) WidgetState.disabled,
      if (widget.selected) WidgetState.selected,
      if (_hovered) WidgetState.hovered,
      if (_pressed) WidgetState.pressed,
      if (_focused) WidgetState.focused,
      ...widget.visualStates,
    };
    final visual = AppInteractiveSurface.resolve(
      AppPalette.of(context),
      states,
      baseColor: widget.baseColor,
      hoverColor: widget.hoverColor,
      selectedColor: widget.selectedColor,
      foregroundColor: widget.foregroundColor,
      borderColor: widget.borderColor,
    );
    final radius = widget.borderRadius ?? AppRadii.of(context).controlRadius;
    final surface = Semantics(
      button: true,
      enabled: enabled,
      selected: states.contains(WidgetState.selected),
      label: widget.semanticLabel,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Opacity(
          opacity: visual.opacity,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              autofocus: widget.autofocus,
              canRequestFocus: enabled,
              excludeFromSemantics: true,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              borderRadius: radius,
              onHover: (value) => setState(() => _hovered = value),
              onHighlightChanged: (value) => setState(() => _pressed = value),
              onFocusChange: (value) => setState(() => _focused = value),
              child: GestureDetector(
                onSecondaryTapDown: widget.onSecondaryTapDown,
                child: AnimatedContainer(
                  duration: AppMotion.of(context).fast,
                  curve: AppMotion.of(context).curve,
                  height: widget.height,
                  width: widget.width,
                  padding: widget.padding,
                  alignment: widget.alignment,
                  decoration: BoxDecoration(
                    color: visual.background,
                    borderRadius: radius,
                    border: Border.all(
                      color: visual.border,
                      width: states.contains(WidgetState.focused) && enabled
                          ? 1.5
                          : 1,
                    ),
                  ),
                  child: widget.child(context, visual),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    return tooltip == null
        ? surface
        : Tooltip(message: tooltip, child: surface);
  }
}
