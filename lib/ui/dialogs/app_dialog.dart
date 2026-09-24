import 'package:flutter/material.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Palette-aware modal frame used across the app. Replaces bare
/// [AlertDialog]/[Dialog] usages so every modal has matching chrome —
/// header band, separator, padded body, and a footer action row.
class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.title,
    required this.content,
    super.key,
    this.actions = const [],
    this.subtitle,
    this.width = 460,
    this.contentPadding = const EdgeInsets.fromLTRB(20, 16, 20, 16),
    this.busy = false,
  });
  final String title;
  final String? subtitle;
  final Widget content;
  final List<Widget> actions;
  final double width;
  final EdgeInsetsGeometry contentPadding;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final typography = AppTypography.of(context);
    final radii = AppRadii.of(context);
    return Dialog(
      backgroundColor: palette.bg2,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: radii.dialogRadius,
        side: BorderSide(color: palette.border),
      ),
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: typography.title.copyWith(
                      color: palette.fg0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: typography.caption.copyWith(color: palette.fg2),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: palette.border),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(padding: contentPadding, child: content),
              ),
            ),
            if (actions.isNotEmpty) ...[
              Divider(height: 1, thickness: 1, color: palette.border),
              Container(
                color: palette.bg1,
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
                child: Row(
                  children: [
                    if (busy) ...[
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                    ],
                    const Spacer(),
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions[i],
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Visual variants for [AppButton].
enum AppButtonKind { primary, secondary, danger }

/// Button that adapts to the app palette and three semantic kinds.
/// Use as the action in [AppDialog].
class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.kind = AppButtonKind.secondary,
    this.icon,
    this.autofocus = false,
    this.selected = false,
    this.compact = false,
    this.tooltip,
    this.visualStates = const {},
  });

  const AppButton.primary({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.autofocus = false,
    this.selected = false,
    this.compact = false,
    this.tooltip,
    this.visualStates = const {},
  }) : kind = AppButtonKind.primary;

  const AppButton.secondary({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.autofocus = false,
    this.selected = false,
    this.compact = false,
    this.tooltip,
    this.visualStates = const {},
  }) : kind = AppButtonKind.secondary;

  const AppButton.danger({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.autofocus = false,
    this.selected = false,
    this.compact = false,
    this.tooltip,
    this.visualStates = const {},
  }) : kind = AppButtonKind.danger;
  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final IconData? icon;
  final bool autofocus;
  final bool selected;
  final bool compact;
  final String? tooltip;
  final Set<WidgetState> visualStates;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final (bg, fg, border) = switch (kind) {
      AppButtonKind.primary => (
        palette.accentCurrent,
        palette.onAccentCurrent,
        palette.accentCurrent,
      ),
      AppButtonKind.danger => (
        palette.accentErr,
        palette.onAccentErr,
        palette.accentErr,
      ),
      AppButtonKind.secondary => (
        palette.bg3,
        palette.fg0,
        palette.borderStrong,
      ),
    };
    return AppInteractiveSurface(
      onTap: onPressed,
      semanticLabel: label,
      tooltip: tooltip,
      selected: selected,
      autofocus: autofocus,
      visualStates: visualStates,
      height: compact
          ? spacing.compactControlHeight
          : spacing.regularControlHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: null,
      baseColor: bg,
      hoverColor: kind == AppButtonKind.secondary ? palette.bg4 : null,
      foregroundColor: fg,
      borderColor: border,
      child: (context, visual) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: spacing.regularIconSize, color: visual.foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AppTypography.of(context).body.copyWith(
              color: visual.foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Drop-in palette-aware [TextField] decoration used by app dialogs so the
/// labels/borders match the rest of the chrome.
InputDecoration appInputDecoration(
  BuildContext context, {
  required String label,
  String? hint,
}) {
  final palette = AppPalette.of(context);
  final radii = AppRadii.of(context);
  final typography = AppTypography.of(context);
  return InputDecoration(
    labelText: label,
    hintText: hint,
    isDense: true,
    labelStyle: typography.caption.copyWith(color: palette.fg2),
    hintStyle: typography.caption.copyWith(color: palette.fg3),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    filled: true,
    fillColor: palette.bg1,
    border: OutlineInputBorder(
      borderRadius: radii.controlRadius,
      borderSide: BorderSide(color: palette.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radii.controlRadius,
      borderSide: BorderSide(color: palette.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radii.controlRadius,
      borderSide: BorderSide(color: palette.accentCurrent, width: 1.2),
    ),
  );
}
