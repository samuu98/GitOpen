import 'package:flutter/material.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/ui/bottom_panel/diff_syntax.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// One rendered unified-diff line: old/new line-number gutters, the +/-/space
/// prefix and the syntax-highlighted content. Shared by the commit diff view
/// and the working-copy preview pane (which use slightly different gutter
/// widths, hence the parameters).
class DiffLineRow extends StatelessWidget {
  const DiffLineRow({
    required this.line,
    super.key,
    this.language,
    this.gutterWidth = 40,
    this.prefixWidth = 14,
  });
  final DiffLine line;
  final String? language;
  final double gutterWidth;
  final double prefixWidth;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final Color bg;
    final String prefix;
    switch (line.kind) {
      case DiffLineKind.addition:
        bg = palette.accentCurrent.withValues(alpha: 0.10);
        prefix = '+';
      case DiffLineKind.deletion:
        bg = palette.accentErr.withValues(alpha: 0.12);
        prefix = '-';
      case DiffLineKind.context:
        bg = Colors.transparent;
        prefix = ' ';
    }
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gutterWidth,
            child: Text(
              line.oldLine?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: palette.fg3,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: gutterWidth,
            child: Text(
              line.newLine?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: palette.fg3,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: prefixWidth,
            child: Text(
              prefix,
              style: TextStyle(
                color: palette.fg3,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: buildHighlightedSpans(
                  line.content,
                  language,
                  baseColor: palette.fg0,
                ),
              ),
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              softWrap: false,
              overflow: TextOverflow.clip,
            ),
          ),
        ],
      ),
    );
  }
}
