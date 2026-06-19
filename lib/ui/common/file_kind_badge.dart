import 'package:flutter/material.dart';
import 'package:gitopen/domain/diff/file_diff.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Small colored badge for a file's [FileChangeKind].
///
/// [compact] shows a single letter (M/A/D/R/C/T/U) for dense lists such as the
/// commit's changed-files overview; otherwise the full word (MODIFIED…) used
/// in the diff file header.
class FileKindBadge extends StatelessWidget {
  const FileKindBadge({required this.kind, this.compact = false, super.key});
  final FileChangeKind kind;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final (bg, fg) = _colors(p);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        compact ? _letter : kind.name.toUpperCase(),
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  String get _letter => switch (kind) {
    FileChangeKind.added => 'A',
    FileChangeKind.deleted => 'D',
    FileChangeKind.modified => 'M',
    FileChangeKind.renamed => 'R',
    FileChangeKind.copied => 'C',
    FileChangeKind.typeChanged => 'T',
    FileChangeKind.unmerged => 'U',
  };

  (Color, Color) _colors(AppPalette p) => switch (kind) {
    FileChangeKind.added => (
      p.accentCurrent.withValues(alpha: 0.18),
      p.accentCurrent,
    ),
    FileChangeKind.deleted ||
    FileChangeKind.unmerged => (
      p.accentErr.withValues(alpha: 0.18),
      p.accentErr,
    ),
    FileChangeKind.modified => (
      p.accentTag.withValues(alpha: 0.18),
      p.accentTag,
    ),
    FileChangeKind.renamed ||
    FileChangeKind.copied => (
      p.accentRemote.withValues(alpha: 0.18),
      p.accentRemote,
    ),
    FileChangeKind.typeChanged => (p.bg4, p.fg1),
  };
}
