import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import 'ref_decoration.dart';

/// Fork-style ref pill. Renders as a single pill split into two halves
/// when the local branch is synced with one or more remotes: left half
/// shows the branch name (with ✓ if current), right half shows the
/// remote name(s) prefixed with ⇄ to signal the sync.
class RefPill extends StatelessWidget {
  final RefDecoration decoration;
  /// Invoked when the user left-clicks the pill. When null the pill is
  /// rendered without any tap handling.
  final VoidCallback? onTap;
  const RefPill({super.key, required this.decoration, this.onTap});

  @override
  Widget build(BuildContext context) {
    final appPalette = AppPalette.of(context);
    final palette = _palette(appPalette);

    final localSide = _Section(
      icon: _leadingIcon(palette),
      label: decoration.name,
      fg: palette.fg,
    );

    final Widget pill;
    if (!decoration.isSynced) {
      pill = Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
        decoration: BoxDecoration(
          color: palette.bg,
          border: Border.all(color: palette.border, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: localSide,
      );
    } else {
      pill = Container(
        decoration: BoxDecoration(
          color: palette.bg,
          border: Border.all(color: palette.border, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                child: localSide,
              ),
              Container(
                width: 1,
                color: palette.border,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                color: palette.remoteTintBg,
                child: _Section(
                  icon: Icon(Icons.sync_alt, size: 10, color: palette.remoteFg),
                  label: decoration.syncedRemotes.join(', '),
                  fg: palette.remoteFg,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (onTap == null) return pill;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: pill,
      ),
    );
  }

  Widget _leadingIcon(_PillPalette palette) {
    if (decoration.isCurrent) {
      return Icon(Icons.check, size: 11, color: palette.fg);
    }
    if (decoration.isTag) {
      return Icon(Icons.local_offer_outlined, size: 10, color: palette.fg);
    }
    if (decoration.isRemote) {
      return Icon(Icons.cloud_outlined, size: 11, color: palette.fg);
    }
    return Icon(Icons.commit_outlined, size: 10, color: palette.fg);
  }

  _PillPalette _palette(AppPalette p) {
    if (decoration.isTag) {
      return _PillPalette(
        bg: p.bg3,
        border: p.accentTag,
        fg: p.accentTag,
        remoteTintBg: p.bg1,
        remoteFg: p.accentRemote,
      );
    }
    if (decoration.isRemote) {
      return _PillPalette(
        bg: p.bg1,
        border: p.accentRemote,
        fg: p.accentRemote,
        remoteTintBg: p.bg1,
        remoteFg: p.accentRemote,
      );
    }
    if (decoration.isCurrent) {
      return _PillPalette(
        bg: p.bg1,
        border: p.accentCurrent,
        fg: p.accentCurrent,
        remoteTintBg: p.bg1,
        remoteFg: p.accentRemote,
      );
    }
    return _PillPalette(
      bg: p.bg2,
      border: p.accentCurrent,
      fg: p.accentCurrent,
      remoteTintBg: p.bg1,
      remoteFg: p.accentRemote,
    );
  }
}

class _Section extends StatelessWidget {
  final Widget icon;
  final String label;
  final Color fg;
  const _Section({required this.icon, required this.label, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: fg,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _PillPalette {
  final Color bg;
  final Color border;
  final Color fg;
  final Color remoteTintBg;
  final Color remoteFg;
  const _PillPalette({
    required this.bg,
    required this.border,
    required this.fg,
    required this.remoteTintBg,
    required this.remoteFg,
  });
}
