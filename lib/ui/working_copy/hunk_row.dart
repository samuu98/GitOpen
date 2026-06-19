import 'package:flutter/material.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/ui/common/diff_horizontal_scroll.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class HunkRow extends StatelessWidget {
  const HunkRow({
    required this.hunk,
    required this.index,
    required this.staged,
    required this.isChecked,
    required this.onToggle,
    required this.selectedLines,
    required this.onToggleLine,
    required this.onAction,
    super.key,
  });
  final DiffHunk hunk;
  final int index;

  /// Whether this hunk belongs to a staged row. Drives the inline action:
  /// staged → unstage the hunk; unstaged → discard it.
  final bool staged;
  final bool isChecked;
  final VoidCallback onToggle;
  final Set<int> selectedLines;
  final ValueChanged<int> onToggleLine;

  /// Inline per-hunk action: discard (unstaged) or unstage (staged).
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ColoredBox(
      color: palette.bg0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            selected: isChecked,
            label:
                '${isChecked ? 'Selected' : 'Unselected'} '
                'hunk ${index + 1}, ${hunk.header}',
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 32,
                  right: 8,
                  top: 3,
                  bottom: 3,
                ),
                child: Row(
                  children: [
                    Icon(
                      isChecked
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 13,
                      color: palette.fg2,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hunk.header,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.accentRemote,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Tooltip(
                      message: staged ? 'Unstage hunk' : 'Discard hunk',
                      waitDuration: const Duration(milliseconds: 400),
                      child: Semantics(
                        button: true,
                        label: staged
                            ? 'Unstage hunk ${index + 1}'
                            : 'Discard hunk ${index + 1}',
                        child: InkWell(
                          onTap: onAction,
                          borderRadius: BorderRadius.circular(3),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              staged ? Icons.remove_circle_outline : Icons.undo,
                              size: 13,
                              color: staged ? palette.fg2 : palette.accentErr,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          DiffHorizontalScroll(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (lineIndex, line) in hunk.lines.indexed)
                    _HunkLineRow(
                      line: line,
                      isChecked: selectedLines.contains(lineIndex),
                      onToggle: () => onToggleLine(lineIndex),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HunkLineRow extends StatelessWidget {
  const _HunkLineRow({
    required this.line,
    required this.isChecked,
    required this.onToggle,
  });
  final DiffLine line;
  final bool isChecked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final selectable = line.kind != DiffLineKind.context;
    final (prefix, bg) = switch (line.kind) {
      DiffLineKind.addition => (
        '+',
        palette.accentCurrent.withValues(alpha: 0.08),
      ),
      DiffLineKind.deletion => ('-', palette.accentErr.withValues(alpha: 0.10)),
      DiffLineKind.context => (' ', Colors.transparent),
    };
    final changeLabel = line.kind == DiffLineKind.addition
        ? 'addition'
        : 'deletion';
    return InkWell(
      onTap: selectable ? onToggle : null,
      child: Semantics(
        button: selectable,
        selected: selectable ? isChecked : null,
        label: selectable
            ? '${isChecked ? 'Selected' : 'Unselected'} $changeLabel '
                  'line ${line.content}'
            : 'Context line ${line.content}',
        child: Container(
          color: bg,
          padding: const EdgeInsets.only(
            left: 50,
            right: 12,
            top: 1,
            bottom: 1,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                child: selectable
                    ? Icon(
                        isChecked
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 12,
                        color: palette.fg2,
                      )
                    : null,
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 12,
                child: Text(
                  prefix,
                  style: TextStyle(
                    color: palette.fg3,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              Text(
                line.content,
                softWrap: false,
                style: TextStyle(
                  color: palette.fg1,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
