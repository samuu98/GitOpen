import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';

/// Builds a unified-diff patch applying only selected line indexes in [hunk].
///
/// Unselected deletions stay in the file, so they are emitted as context.
/// Unselected additions do not enter the file, so they are omitted.
String buildPatchForLines(
  String filePath,
  DiffHunk hunk,
  Set<int> selected,
) {
  final body = StringBuffer();
  var oldCount = 0;
  var newCount = 0;
  var changes = 0;

  for (final (i, line) in hunk.lines.indexed) {
    switch (line.kind) {
      case DiffLineKind.context:
        body.writeln(' ${line.content}');
        oldCount++;
        newCount++;
      case DiffLineKind.deletion:
        if (selected.contains(i)) {
          body.writeln('-${line.content}');
          oldCount++;
          changes++;
        } else {
          body.writeln(' ${line.content}');
          oldCount++;
          newCount++;
        }
      case DiffLineKind.addition:
        if (selected.contains(i)) {
          body.writeln('+${line.content}');
          newCount++;
          changes++;
        }
    }
  }
  if (changes == 0) return '';

  return (StringBuffer()
        ..writeln('diff --git a/$filePath b/$filePath')
        ..writeln('--- a/$filePath')
        ..writeln('+++ b/$filePath')
        ..writeln(
          '@@ -${hunk.oldStart},$oldCount +${hunk.newStart},$newCount @@',
        )
        ..write(body))
      .toString();
}
