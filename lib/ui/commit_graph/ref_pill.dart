import 'package:flutter/material.dart';
import 'ref_decoration.dart';

/// Fork-style ref pill: muted dark background, accent border + icon
/// per type. Current branch shows a green check before the name.
class RefPill extends StatelessWidget {
  final RefDecoration decoration;
  const RefPill({super.key, required this.decoration});

  @override
  Widget build(BuildContext context) {
    final palette = _palette();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border.all(color: palette.border, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _leadingIcon(palette),
          if (decoration.isCurrent || decoration.isRemote || decoration.isTag)
            const SizedBox(width: 4),
          Text(
            decoration.name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: palette.fg,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _leadingIcon(_PillPalette palette) {
    if (decoration.isCurrent) {
      return const Icon(Icons.check, size: 11, color: Color(0xFF4EC9B0));
    }
    if (decoration.isTag) {
      return Icon(Icons.local_offer_outlined, size: 10, color: palette.fg);
    }
    if (decoration.isRemote) {
      return Icon(Icons.cloud_outlined, size: 11, color: palette.fg);
    }
    return const SizedBox.shrink();
  }

  _PillPalette _palette() {
    if (decoration.isTag) {
      return const _PillPalette(
        bg: Color(0xFF2C2A22),
        border: Color(0xFF5A4E2D),
        fg: Color(0xFFD7BA7D),
      );
    }
    if (decoration.isRemote) {
      return const _PillPalette(
        bg: Color(0xFF1E2A36),
        border: Color(0xFF3F5F7F),
        fg: Color(0xFF7FB3DE),
      );
    }
    if (decoration.isCurrent) {
      return const _PillPalette(
        bg: Color(0xFF1F3128),
        border: Color(0xFF4EC9B0),
        fg: Color(0xFFA5E4D2),
      );
    }
    // Regular local branch
    return const _PillPalette(
      bg: Color(0xFF252A28),
      border: Color(0xFF3F5F55),
      fg: Color(0xFF8FD4C0),
    );
  }
}

class _PillPalette {
  final Color bg;
  final Color border;
  final Color fg;
  const _PillPalette({required this.bg, required this.border, required this.fg});
}
