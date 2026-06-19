import 'package:flutter/material.dart';

/// Wraps a vertical stack of diff rows so long lines become reachable by
/// horizontal scrolling instead of being clipped.
///
/// The content is allowed to take its natural width; the [LayoutBuilder]
/// captures the viewport width and applies it as a `minWidth`, so the content
/// still fills the pane (and row backgrounds reach the right edge) when it is
/// narrower than the viewport.
class DiffHorizontalScroll extends StatefulWidget {
  const DiffHorizontalScroll({required this.child, super.key});

  final Widget child;

  @override
  State<DiffHorizontalScroll> createState() => _DiffHorizontalScrollState();
}

class _DiffHorizontalScrollState extends State<DiffHorizontalScroll> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          controller: _controller,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}
