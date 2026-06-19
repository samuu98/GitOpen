import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/diff/intraline_diff.dart';
import 'package:gitopen/application/diff/split_diff.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/ui/bottom_panel/diff_syntax.dart';
import 'package:gitopen/ui/common/diff_horizontal_scroll.dart';
import 'package:gitopen/ui/common/diff_prefs.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// One rendered unified-diff line: old/new line-number gutters, the +/-/space
/// prefix and the syntax-highlighted content. Shared by the commit diff view
/// and the working-copy preview pane (which use slightly different gutter
/// widths, hence the parameters).
///
/// When [changedRange] is set (word-diff mode) the changed substring gets a
/// stronger tint; the line is then rendered without syntax colouring so the
/// highlight stays readable.
class DiffLineRow extends StatelessWidget {
  const DiffLineRow({
    required this.line,
    super.key,
    this.language,
    this.gutterWidth = 40,
    this.prefixWidth = 14,
    this.changedRange,
  });
  final DiffLine line;
  final String? language;
  final double gutterWidth;
  final double prefixWidth;
  final (int, int)? changedRange;

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
          Text.rich(
            TextSpan(children: _contentSpans(palette)),
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            softWrap: false,
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _contentSpans(AppPalette palette) {
    final range = changedRange;
    if (range == null || range.$1 >= range.$2) {
      return buildHighlightedSpans(
        line.content,
        language,
        baseColor: palette.fg0,
      );
    }
    final (start, end) = range;
    final tint = line.kind == DiffLineKind.addition
        ? palette.accentCurrent.withValues(alpha: 0.35)
        : palette.accentErr.withValues(alpha: 0.35);
    final base = TextStyle(color: palette.fg0);
    return [
      TextSpan(text: line.content.substring(0, start), style: base),
      TextSpan(
        text: line.content.substring(start, end),
        style: base.copyWith(backgroundColor: tint),
      ),
      TextSpan(text: line.content.substring(end), style: base),
    ];
  }
}

/// Renders a hunk's lines, computing intraline highlights for paired
/// removed/added lines when the word-diff preference is on. Shared by both
/// diff views so the pairing logic lives in one place.
class HunkLines extends ConsumerWidget {
  const HunkLines({
    required this.lines,
    super.key,
    this.language,
    this.gutterWidth = 40,
    this.prefixWidth = 14,
  });
  final List<DiffLine> lines;
  final String? language;
  final double gutterWidth;
  final double prefixWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(diffViewModeProvider);
    if (mode == DiffViewMode.sideBySide) {
      return SplitHunkLines(
        lines: lines,
        language: language,
        gutterWidth: gutterWidth,
      );
    }

    final wordDiff = ref.watch(wordDiffEnabledProvider);
    final ranges = <int, (int, int)>{};
    if (wordDiff) {
      final pairs = pairChangedLines([
        for (final (i, line) in lines.indexed)
          (
            kind: switch (line.kind) {
              DiffLineKind.addition => PairKind.addition,
              DiffLineKind.deletion => PairKind.deletion,
              DiffLineKind.context => PairKind.context,
            },
            index: i,
          ),
      ]);
      for (final MapEntry(key: i, value: j) in pairs.entries) {
        if (lines[i].kind != DiffLineKind.deletion) continue;
        final d = intralineDiff(lines[i].content, lines[j].content);
        if (d == null) continue;
        ranges[i] = (d.oldStart, d.oldEnd);
        ranges[j] = (d.newStart, d.newEnd);
      }
    }
    return DiffHorizontalScroll(
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, line) in lines.indexed)
              DiffLineRow(
                line: line,
                language: language,
                gutterWidth: gutterWidth,
                prefixWidth: prefixWidth,
                changedRange: ranges[i],
              ),
          ],
        ),
      ),
    );
  }
}

/// Side-by-side rendering of a hunk: old file on the left, new file on the
/// right, with blanks where one side has no counterpart.
class SplitHunkLines extends StatelessWidget {
  const SplitHunkLines({
    required this.lines,
    super.key,
    this.language,
    this.gutterWidth = 40,
  });
  final List<DiffLine> lines;
  final String? language;
  final double gutterWidth;

  @override
  Widget build(BuildContext context) {
    final rows = buildSplitRows(lines);
    final borderColor = AppPalette.of(context).border;
    // A Table with intrinsic-width columns aligns the two sides across all
    // rows (and sizes row heights automatically) without measuring text. The
    // whole table is wrapped so long lines scroll horizontally.
    return DiffHorizontalScroll(
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        columnWidths: const {1: FixedColumnWidth(1)},
        children: [
          for (final row in rows)
            TableRow(
              children: [
                _SplitCell(
                  line: row.left,
                  old: true,
                  language: language,
                  gutterWidth: gutterWidth,
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.fill,
                  child: ColoredBox(color: borderColor),
                ),
                _SplitCell(
                  line: row.right,
                  old: false,
                  language: language,
                  gutterWidth: gutterWidth,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SplitCell extends StatelessWidget {
  const _SplitCell({
    required this.line,
    required this.old,
    required this.language,
    required this.gutterWidth,
  });
  final DiffLine? line;
  final bool old;
  final String? language;
  final double gutterWidth;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l = line;
    if (l == null) {
      return ColoredBox(color: palette.bg2.withValues(alpha: 0.4));
    }
    final bg = switch (l.kind) {
      DiffLineKind.addition => palette.accentCurrent.withValues(alpha: 0.10),
      DiffLineKind.deletion => palette.accentErr.withValues(alpha: 0.12),
      DiffLineKind.context => Colors.transparent,
    };
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gutterWidth,
            child: Text(
              (old ? l.oldLine : l.newLine)?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: palette.fg3,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text.rich(
            TextSpan(
              children: buildHighlightedSpans(
                l.content,
                language,
                baseColor: palette.fg0,
              ),
            ),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            softWrap: false,
          ),
        ],
      ),
    );
  }
}
