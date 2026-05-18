import 'package:flutter/material.dart';
import '../theme/app_palette.dart';

/// Palette-aware modal frame used across the app. Replaces bare
/// [AlertDialog]/[Dialog] usages so every modal has matching chrome —
/// header band, separator, padded body, and a footer action row.
class AppDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget content;
  final List<Widget> actions;
  final double width;
  final EdgeInsetsGeometry contentPadding;
  final bool busy;

  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.subtitle,
    this.width = 460,
    this.contentPadding = const EdgeInsets.fromLTRB(20, 16, 20, 16),
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Dialog(
      backgroundColor: palette.bg2,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
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
                    style: TextStyle(
                      color: palette.fg0,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: TextStyle(color: palette.fg2, fontSize: 11.5),
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
class AppButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final IconData? icon;
  final bool autofocus;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = AppButtonKind.secondary,
    this.icon,
    this.autofocus = false,
  });

  const AppButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.autofocus = false,
  }) : kind = AppButtonKind.primary;

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.autofocus = false,
  }) : kind = AppButtonKind.secondary;

  const AppButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.autofocus = false,
  }) : kind = AppButtonKind.danger;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final disabled = widget.onPressed == null;
    final (bg, bgHover, fg, border) = switch (widget.kind) {
      AppButtonKind.primary => (
          palette.accentCurrent,
          palette.accentCurrent.withValues(alpha: 0.85),
          Colors.white,
          palette.accentCurrent,
        ),
      AppButtonKind.danger => (
          palette.accentErr,
          palette.accentErr.withValues(alpha: 0.85),
          Colors.white,
          palette.accentErr,
        ),
      AppButtonKind.secondary => (
          palette.bg3,
          palette.bg4,
          palette.fg0,
          palette.borderStrong,
        ),
    };
    return MouseRegion(
      cursor: disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : widget.onPressed,
        child: Focus(
          autofocus: widget.autofocus,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: disabled
                  ? palette.bg3
                  : (_hover ? bgHover : bg),
              border: Border.all(color: disabled ? palette.border : border),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon,
                      size: 14,
                      color: disabled ? palette.fg3 : fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    color: disabled ? palette.fg3 : fg,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
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
  return InputDecoration(
    labelText: label,
    hintText: hint,
    isDense: true,
    labelStyle: TextStyle(color: palette.fg2, fontSize: 12),
    hintStyle: TextStyle(color: palette.fg3, fontSize: 12),
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    filled: true,
    fillColor: palette.bg1,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(5),
      borderSide: BorderSide(color: palette.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(5),
      borderSide: BorderSide(color: palette.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(5),
      borderSide: BorderSide(color: palette.accentCurrent, width: 1.2),
    ),
  );
}
