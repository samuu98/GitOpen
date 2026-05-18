import 'package:flutter/material.dart';
import '../theme/app_palette.dart';

/// Spec for a single entry in [AppContextMenu]. Either a normal item or a
/// divider.
sealed class AppContextMenuEntry<T> {
  const AppContextMenuEntry();
}

class AppMenuItem<T> extends AppContextMenuEntry<T> {
  final T value;
  final String label;
  final IconData? icon;
  final bool danger;
  final bool enabled;
  const AppMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.danger = false,
    this.enabled = true,
  });
}

class AppMenuDivider<T> extends AppContextMenuEntry<T> {
  const AppMenuDivider();
}

/// Palette-aware context menu — styling lines up with the [MenuAnchor]
/// dropdowns in [RepoSelector] / toolbar.
class AppContextMenu {
  static Future<T?> show<T>(
    BuildContext context, {
    required Offset globalPosition,
    required List<AppContextMenuEntry<T>> entries,
  }) {
    final palette = AppPalette.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
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
            PopupMenuItem<T>(
              value: e.value,
              enabled: e.enabled,
              height: 30,
              padding: EdgeInsets.zero,
              child: _MenuRow(
                label: e.label,
                icon: e.icon,
                danger: e.danger,
                enabled: e.enabled,
              ),
            )
          else
            PopupMenuDivider(height: 6, color: palette.border),
      ],
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
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool danger;

  const AppMenuButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final enabled = onPressed != null;
    final fg = !enabled
        ? palette.fg3
        : (danger ? palette.accentErr : palette.fg0);
    return MenuItemButton(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) return palette.bg4;
          return Colors.transparent;
        }),
        padding: WidgetStateProperty.all(EdgeInsets.zero),
        minimumSize: WidgetStateProperty.all(const Size.fromHeight(30)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
        ),
      ),
      onPressed: onPressed,
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
                    : Icon(icon,
                        size: 14,
                        color: enabled ? palette.fg2 : palette.fg3),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

class _MenuRow extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool danger;
  final bool enabled;
  const _MenuRow({
    required this.label,
    required this.icon,
    required this.danger,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fg = !enabled
        ? palette.fg3
        : (danger ? palette.accentErr : palette.fg0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: icon == null
                ? null
                : Icon(icon, size: 14, color: enabled ? palette.fg2 : palette.fg3),
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(color: fg, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
