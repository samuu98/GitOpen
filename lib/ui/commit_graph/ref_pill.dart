import 'package:flutter/material.dart';
import 'package:gitopen/ui/commit_graph/ref_decoration.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Fork-style ref pill. Renders as a single pill split into two halves
/// when the local branch is synced with one or more remotes: left half
/// shows the branch name (with ✓ if current), right half shows the
/// remote name(s) prefixed with ⇄ to signal the sync.
class RefPill extends StatelessWidget {
  const RefPill({
    required this.decoration,
    super.key,
    this.onTap,
    this.onDoubleTap,
  });
  final RefDecoration decoration;

  /// Invoked when the user single-clicks the pill.
  final VoidCallback? onTap;

  /// Invoked when the user double-clicks the pill (typically: checkout).
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final appPalette = AppPalette.of(context);
    final palette = _palette(appPalette);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);
    final sectionPadding = EdgeInsets.symmetric(
      horizontal: spacing.sm,
      vertical: spacing.xxs / 2,
    );

    final localSide = _Section(
      icon: _leadingIcon(palette),
      label: decoration.name,
      fg: palette.fg,
    );

    final Widget pill;
    if (!decoration.isSynced) {
      pill = Container(
        padding: sectionPadding,
        decoration: BoxDecoration(
          color: palette.bg,
          border: Border.all(color: palette.border),
          borderRadius: radii.controlRadius,
        ),
        child: localSide,
      );
    } else {
      pill = Container(
        decoration: BoxDecoration(
          color: palette.bg,
          border: Border.all(color: palette.border),
          borderRadius: radii.controlRadius,
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: sectionPadding, child: localSide),
              Container(width: 1, color: palette.border),
              Container(
                padding: sectionPadding,
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

    if (onTap == null && onDoubleTap == null) return pill;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
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
  const _Section({required this.icon, required this.label, required this.fg});
  final Widget icon;
  final String label;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final typography = AppTypography.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 4),
        Text(
          label,
          style: typography.monoSmall.copyWith(
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ],
    );
  }
}

class _PillPalette {
  const _PillPalette({
    required this.bg,
    required this.border,
    required this.fg,
    required this.remoteTintBg,
    required this.remoteFg,
  });
  final Color bg;
  final Color border;
  final Color fg;
  final Color remoteTintBg;
  final Color remoteFg;
}
