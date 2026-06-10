import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/file_diff.dart';

/// Per-file line budget applied by the read facade to every multi-file diff,
/// so a giant generated/lock file cannot swamp memory or the renderer. The
/// UI offers "Load full diff" (an uncapped single-file fetch) for the rest.
const int kDiffLineCap = 2000;

/// Caps each file at [maxLines] total hunk lines. Hunks are kept whole: the
/// first hunk that would cross the budget — and everything after it — is
/// dropped and the file is marked [FileDiff.truncated]. Untouched files are
/// returned as the same instance.
DiffResult capDiffResult(DiffResult result, {int maxLines = kDiffLineCap}) {
  var changed = false;
  final files = result.files.map((f) {
    var total = 0;
    final kept = <DiffHunk>[];
    var truncated = false;
    for (final h in f.hunks) {
      if (total + h.lines.length > maxLines) {
        truncated = true;
        break;
      }
      total += h.lines.length;
      kept.add(h);
    }
    if (!truncated) return f;
    changed = true;
    return FileDiff(
      path: f.path,
      oldPath: f.oldPath,
      changeKind: f.changeKind,
      isBinary: f.isBinary,
      linesAdded: f.linesAdded,
      linesDeleted: f.linesDeleted,
      hunks: kept,
      truncated: true,
    );
  }).toList();
  return changed ? DiffResult(files: files) : result;
}
