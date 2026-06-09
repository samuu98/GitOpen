import 'package:flutter/material.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Plain toolbar action button (icon + label).
class ToolbarButton extends StatelessWidget {
  const ToolbarButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    super.key,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: palette.fg1),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: palette.fg0,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dropdown trigger button — same visual style as [ToolbarButton] but includes
/// a small chevron to signal it opens a menu.
class ToolbarDropdownButton extends StatelessWidget {
  const ToolbarDropdownButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    super.key,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: palette.fg1),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: palette.fg0,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.expand_more, size: 12, color: palette.fg2),
            ],
          ),
        ),
      ),
    );
  }
}
