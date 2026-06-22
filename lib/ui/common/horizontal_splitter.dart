import 'package:flutter/material.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Two-pane horizontal split with a draggable vertical handle in between.
/// Right pane fills the leftover space; left pane is the resizable one.
///
/// - Drag the handle to resize.
/// - Double-click resets the left pane to [defaultLeft].
/// - Left width is clamped to [minLeft] .. (parent width - [minRight]).
///
/// Sibling of VerticalSplitter (which splits top/bottom).
class HorizontalSplitter extends StatefulWidget {
  const HorizontalSplitter({
    required this.left,
    required this.right,
    super.key,
    this.defaultLeft = 380,
    this.minLeft = 380,
    this.minRight = 320,
    this.handleWidth = 5,
  });
  final Widget left;
  final Widget right;
  final double defaultLeft;
  final double minLeft;
  final double minRight;
  final double handleWidth;

  @override
  State<HorizontalSplitter> createState() => _HorizontalSplitterState();
}

class _HorizontalSplitterState extends State<HorizontalSplitter> {
  late double _left = widget.defaultLeft;
  bool _hover = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxLeft = constraints.maxWidth - widget.minRight;
        final clamped = _left.clamp(
          widget.minLeft,
          maxLeft < widget.minLeft ? widget.minLeft : maxLeft,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: clamped, child: widget.left),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) =>
                    setState(() => _dragging = true),
                onHorizontalDragUpdate: (d) {
                  setState(() {
                    _left = (_left + d.delta.dx).clamp(
                      widget.minLeft,
                      constraints.maxWidth - widget.minRight,
                    );
                  });
                },
                onHorizontalDragEnd: (_) =>
                    setState(() => _dragging = false),
                onDoubleTap: () =>
                    setState(() => _left = widget.defaultLeft),
                child: Container(
                  width: widget.handleWidth,
                  color: _dragging
                      ? palette.accentCurrent
                      : (_hover ? palette.borderStrong : palette.border),
                ),
              ),
            ),
            Expanded(child: widget.right),
          ],
        );
      },
    );
  }
}
