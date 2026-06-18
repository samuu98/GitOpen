import 'package:flutter/material.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// A loading placeholder: a column of rounded grey bars that gently pulse,
/// shown in place of a bare spinner so the UI hints at the shape of the
/// content about to load (graph rows, sidebar entries, file lists).
///
/// One repeating opacity animation — no shimmer dependency. The row count
/// adapts to the available height so it never overflows a short panel.
class SkeletonList extends StatefulWidget {
  const SkeletonList({
    super.key,
    this.rows = 12,
    this.rowHeight = 12,
    this.gap = 12,
    this.padding = const EdgeInsets.all(16),
  });

  final int rows;
  final double rowHeight;
  final double gap;
  final EdgeInsets padding;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  // Deterministic pseudo-random widths so the bars read like varied content
  // without needing Random (unavailable in some contexts / breaks resume).
  static const _widths = [0.9, 0.6, 0.75, 0.5, 0.85, 0.65, 0.7, 0.55];

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final radii = AppRadii.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Draw only as many bars as fit the available height — a fixed count
        // overflows a short panel. Fall back to [rows] when unbounded.
        final available = constraints.maxHeight - widget.padding.vertical;
        final perRow = widget.rowHeight + widget.gap;
        final fit = available.isFinite
            ? ((available + widget.gap) / perRow).floor()
            : widget.rows;
        final count = fit.clamp(0, widget.rows);
        return Padding(
          padding: widget.padding,
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.35, end: 0.7).animate(
              CurvedAnimation(parent: _ctl, curve: Curves.easeInOut),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < count; i++) ...[
                  FractionallySizedBox(
                    widthFactor: _widths[i % _widths.length],
                    child: Container(
                      height: widget.rowHeight,
                      decoration: BoxDecoration(
                        color: palette.bg4,
                        borderRadius: radii.controlRadius,
                      ),
                    ),
                  ),
                  if (i != count - 1) SizedBox(height: widget.gap),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
