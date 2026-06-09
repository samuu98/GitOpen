import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';

/// Builds a minimal unified-diff patch containing only the supplied hunks.
String buildPatchForHunks(String filePath, List<DiffHunk> hunks) {
  final buf = StringBuffer()
    ..writeln('diff --git a/$filePath b/$filePath')
    ..writeln('--- a/$filePath')
    ..writeln('+++ b/$filePath');
  for (final h in hunks) {
    buf.writeln(h.header);
    for (final line in h.lines) {
      switch (line.kind) {
        case DiffLineKind.addition:
          buf.writeln('+${line.content}');
        case DiffLineKind.deletion:
          buf.writeln('-${line.content}');
        case DiffLineKind.context:
          buf.writeln(' ${line.content}');
      }
    }
  }
  return buf.toString();
}
