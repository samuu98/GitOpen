import 'package:flutter/material.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Spec for a single entry in [AppContextMenu]. Either a normal item or a
/// divider.
sealed class AppContextMenuEntry<T> {
  const AppContextMenuEntry();
}

class AppMenuItem<T> extends AppContextMenuEntry<T> {
  const AppMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.danger = false,
    this.enabled = true,
    this.selected = false,
  });
  final T value;
  final String label;
  final IconData? icon;
  final bool danger;
  final bool enabled;
  final bool selected;
}

class AppMenuDivider<T> extends AppContextMenuEntry<T> {
  const AppMenuDivider();
}

/// Palette-aware context menu — styling lines up with [MenuAnchor] dropdowns.
class AppContextMenu {
  static Future<T?> show<T>(
    BuildContext context, {
    required Offset globalPosition,
    required List<AppContextMenuEntry<T>> entries,
  }) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    );
    return showMenu<T>(
      context: context,
      position: position,
      color: palette.bg2,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: palette.border),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      items: [
        for (final e in entries)
          if (e is AppMenuItem<T>)
            _AppPopupMenuItem<T>(
              value: e.value,
              enabled: e.enabled,
              height: spacing.menuRowHeight,
              padding: EdgeInsets.zero,
              child: AppContextMenuRow(
                label: e.label,
                icon: e.icon,
                danger: e.danger,
                enabled: e.enabled,
                selected: e.selected,
              ),
            )
          else
            PopupMenuDivider(height: 6, color: palette.border),
      ],
    );
  }
}

class _AppPopupMenuItem<T> extends PopupMenuItem<T> {
  const _AppPopupMenuItem({
    required super.value,
    required super.enabled,
    required super.height,
    required super.padding,
    required super.child,
  });

  @override
  PopupMenuItemState<T, _AppPopupMenuItem<T>> createState() =>
      _AppPopupMenuItemState<T>();
}

class _AppPopupMenuItemState<T>
    extends PopupMenuItemState<T, _AppPopupMenuItem<T>> {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: palette.interactionHover,
        highlightColor: palette.interactionPressed,
        focusColor: palette.interactionHover,
      ),
      child: super.build(context),
    );
  }
}

/// `MenuStyle` that lines up `MenuAnchor` dropdowns with the surface used by
/// [AppContextMenu] (bg2, border, radius 6, modest elevation).
MenuStyle appMenuStyle(BuildContext context) {
  final palette = AppPalette.of(context);
  return MenuStyle(
    backgroundColor: WidgetStateProperty.all(palette.bg2),
    side: WidgetStateProperty.all(BorderSide(color: palette.border)),
    shape: WidgetStateProperty.all(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    elevation: WidgetStateProperty.all(8),
    padding: WidgetStateProperty.all(
      const EdgeInsets.symmetric(vertical: 4),
    ),
  );
}

/// Drop-in [MenuItemButton] with palette-aware row styling so menus opened
/// from [MenuAnchor] look identical to entries in [AppContextMenu].
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.danger = false,
    this.selected = false,
    this.compact = false,
    this.tooltip,
    this.autofocus = false,
    this.visualStates = const {},
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool danger;
  final bool selected;
  final bool compact;
  final String? tooltip;
  final bool autofocus;
  final Set<WidgetState> visualStates;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final enabled = onPressed != null;
    final fg = danger ? palette.accentErr : palette.fg0;
    final button = MenuItemButton(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return AppInteractiveSurface.resolve(
            palette,
            {...states, ...visualStates, if (selected) WidgetState.selected},
            foregroundColor: fg,
          ).background;
        }),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        padding: WidgetStateProperty.all(EdgeInsets.zero),
        minimumSize: WidgetStateProperty.all(
          Size.fromHeight(
            compact ? spacing.compactControlHeight : spacing.menuRowHeight,
          ),
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: AppInteractiveSurface.resolve(
              palette,
              {...states, ...visualStates, if (selected) WidgetState.selected},
            ).border,
          ),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
        ),
      ),
      onPressed: onPressed,
      autofocus: autofocus,
      child: SizedBox(
        width: 220,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: icon == null
                    ? null
                    : Icon(
                        icon,
                        size: spacing.regularIconSize,
                        color: enabled
                            ? palette.fg2
                            : palette.interactionDisabledForeground,
                      ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? fg : palette.interactionDisabledForeground,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final surface = Semantics(selected: selected, child: button);
    return tooltip == null
        ? surface
        : Tooltip(message: tooltip, child: surface);
  }
}

/// Slim horizontal separator for `MenuAnchor` menus, matching the palette
/// border.
class AppMenuAnchorDivider extends StatelessWidget {
  const AppMenuAnchorDivider({super.key});
  @override
  Widget build(BuildContext context) =>
      Divider(height: 6, thickness: 1, color: AppPalette.of(context).border);
}

/// Visual row used by popup menus and interaction previews.
class AppContextMenuRow extends StatefulWidget {
  const AppContextMenuRow({
    required this.label,
    required this.icon,
    required this.danger,
    required this.enabled,
    required this.selected,
    super.key,
    this.visualStates = const {},
  });
  final String label;
  final IconData? icon;
  final bool danger;
  final bool enabled;
  final bool selected;
  final Set<WidgetState> visualStates;

  @override
  State<AppContextMenuRow> createState() => _AppContextMenuRowState();
}

class _AppContextMenuRowState extends State<AppContextMenuRow> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final visual = AppInteractiveSurface.resolve(
      palette,
      {
        if (!widget.enabled) WidgetState.disabled,
        if (widget.selected) WidgetState.selected,
        if (_hovered) WidgetState.hovered,
        if (_pressed) WidgetState.pressed,
        ...widget.visualStates,
      },
      foregroundColor: widget.danger ? palette.accentErr : palette.fg0,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: Container(
          height: spacing.menuRowHeight,
          decoration: BoxDecoration(
            color: visual.background,
            border: Border.all(color: visual.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Opacity(
            opacity: visual.opacity,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: widget.icon == null
                      ? null
                      : Icon(
                          widget.icon,
                          size: spacing.regularIconSize,
                          color: widget.enabled
                              ? palette.fg2
                              : palette.interactionDisabledForeground,
                        ),
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: visual.foreground, fontSize: 12.5),
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
