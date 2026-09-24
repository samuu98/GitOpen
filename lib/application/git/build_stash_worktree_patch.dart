import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';

/// Patch from the worktree with selected lines removed back to the current
/// worktree. Reversing it removes only those lines, even beside other edits.
String buildStashWorktreePatch(
  String path,
  DiffHunk hunk,
  Set<int> selected,
) {
  final body = StringBuffer();
  var oldCount = 0;
  var newCount = 0;
  for (final (index, line) in hunk.lines.indexed) {
    switch (line.kind) {
      case DiffLineKind.context:
        body.writeln(' ${line.content}');
        oldCount++;
        newCount++;
      case DiffLineKind.addition:
        if (selected.contains(index)) {
          body.writeln('+${line.content}');
          newCount++;
        } else {
          body.writeln(' ${line.content}');
          oldCount++;
          newCount++;
        }
      case DiffLineKind.deletion:
        if (selected.contains(index)) {
          body.writeln('-${line.content}');
          oldCount++;
        }
    }
  }
  return (StringBuffer()
        ..writeln('diff --git a/$path b/$path')
        ..writeln('--- a/$path')
        ..writeln('+++ b/$path')
        ..writeln(
          '@@ -${hunk.newStart},$oldCount '
          '+${hunk.newStart},$newCount @@',
        )
        ..write(body))
      .toString();
}
