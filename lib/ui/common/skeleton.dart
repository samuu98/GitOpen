import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// A lightweight loading placeholder: a column of rounded grey bars that
/// gently pulse.  Used in place of a bare spinner so the UI shows the shape
/// of the content that's about to appear (graph rows, sidebar entries, …).
///
/// Implemented with a single repeating opacity animation — no external
/// shimmer dependency.
class SkeletonList extends StatefulWidget {
  final int rows;
  final double rowHeight;
  final double gap;
  final EdgeInsets padding;

  const SkeletonList({
    super.key,
    this.rows = 12,
    this.rowHeight = 14,
    this.gap = 12,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Deterministic pseudo-random widths so bars look like varied content
    // without needing Random (which is unavailable in some contexts).
    const widths = [0.9, 0.6, 0.75, 0.5, 0.85, 0.65, 0.7, 0.55];
    return LayoutBuilder(
      builder: (context, constraints) {
        // Only draw as many bars as fit the available height. A fixed row
        // count overflows the bottom in short panels (small window or a
        // tall bottom panel) — this is just a loading placeholder, so it
        // must adapt rather than assert. Fall back to the requested count
        // when the height is unbounded.
        final available = constraints.maxHeight - widget.padding.vertical;
        final perRow = widget.rowHeight + widget.gap;
        final fit = available.isFinite
            // n rows take n*rowHeight + (n-1)*gap = n*perRow - gap.
            ? ((available + widget.gap) / perRow).floor()
            : widget.rows;
        final count = fit.clamp(0, widget.rows);
        return Padding(
          padding: widget.padding,
          child: FadeTransition(
            opacity: Tween(begin: 0.35, end: 0.7).animate(
              CurvedAnimation(parent: _ctl, curve: Curves.easeInOut),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < count; i++) ...[
                  FractionallySizedBox(
                    widthFactor: widths[i % widths.length],
                    child: Container(
                      height: widget.rowHeight,
                      decoration: BoxDecoration(
                        color: palette.bg4,
                        borderRadius: BorderRadius.circular(3),
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
