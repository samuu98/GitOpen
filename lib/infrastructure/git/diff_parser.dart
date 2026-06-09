import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/file_diff.dart';

/// Stateful parser for git's combined `--raw -p` (unified) diff output.
///
/// Extracted verbatim from `GitCliReadOperations.getDiff` so that the diff
/// command construction stays in the read-operations facade while the line-by
/// -line parsing — which is the bulk of the logic — lives in one focused
/// place.  Behaviour is identical: same field indices, regexes, and guards.
class DiffParser {
  DiffParser(this._stdout);

  final String _stdout;

  final List<FileDiff> _files = <FileDiff>[];
  final Map<String, _RawEntry> _rawByPath = <String, _RawEntry>{};

  DiffResult parse() {
    final lines = _stdout.split('\n');
    var i = 0;

    // Skip blank lines at start (--format= produces an empty header line)
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }

    // Parse raw status block (lines starting with ':')
    while (i < lines.length && lines[i].startsWith(':')) {
      final line = lines[i].trimRight();
      final tabIdx = line.indexOf('\t');
      if (tabIdx >= 0) {
        final meta = line.substring(0, tabIdx).split(' ');
        if (meta.length >= 5) {
          final status = meta[4]; // 'A', 'M', 'R100', etc.
          final letter = status[0];
          final parts = line.split('\t');
          String path;
          String? oldPath;
          if ((letter == 'R' || letter == 'C') && parts.length >= 3) {
            oldPath = parts[1];
            path = parts[2];
          } else {
            path = parts[1];
          }
          _rawByPath[path] = _RawEntry(letter, oldPath);
        }
      }
      i++;
    }

    // Parse unified diff blocks
    while (i < lines.length) {
      if (!lines[i].startsWith('diff --git ')) {
        i++;
        continue;
      }

      // Extract new path from "diff --git a/<path> b/<path>"
      final pathMatch =
          RegExp(r'^diff --git a/(.+) b/(.+)$').firstMatch(lines[i]);
      if (pathMatch == null) {
        i++;
        continue;
      }
      final newPath = pathMatch.group(2)!;
      final raw = _rawByPath[newPath];
      final changeKind = _mapDiffStatus(raw?.status ?? 'M');
      var isBinary = false;
      final hunks = <DiffHunk>[];
      var added = 0;
      var deleted = 0;
      i++;

      // Skip header lines until first @@ or next diff --git
      while (i < lines.length &&
          !lines[i].startsWith('@@') &&
          !lines[i].startsWith('diff --git ')) {
        if (lines[i].contains('Binary files')) {
          isBinary = true;
        }
        i++;
      }

      DiffHunk? currentHunk;
      var hunkLines = <DiffLine>[];
      var oldLine = 0;
      var newLine = 0;

      while (
          i < lines.length && !lines[i].startsWith('diff --git ')) {
        final line = lines[i];
        if (line.startsWith('@@')) {
          // Flush previous hunk
          if (currentHunk != null) {
            hunks.add(DiffHunk(
              oldStart: currentHunk.oldStart,
              oldCount: currentHunk.oldCount,
              newStart: currentHunk.newStart,
              newCount: currentHunk.newCount,
              header: currentHunk.header,
              lines: hunkLines,
            ));
            hunkLines = [];
          }
          final m = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')
              .firstMatch(line);
          if (m == null) {
            i++;
            continue;
          }
          final oldStart = int.parse(m.group(1)!);
          final oldCount =
              m.group(2) != null ? int.parse(m.group(2)!) : 1;
          final newStart = int.parse(m.group(3)!);
          final newCount =
              m.group(4) != null ? int.parse(m.group(4)!) : 1;
          oldLine = oldStart;
          newLine = newStart;
          currentHunk = DiffHunk(
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            header: line,
            lines: const [],
          );
          i++;
          continue;
        }

        if (currentHunk == null) {
          i++;
          continue;
        }
        if (line.isEmpty) {
          i++;
          continue;
        }

        switch (line[0]) {
          case '+':
            if (line.startsWith('+++')) {
              i++;
              continue;
            }
            hunkLines.add(DiffLine(
                kind: DiffLineKind.addition,
                newLine: newLine++,
                content: line.substring(1)));
            added++;
          case '-':
            if (line.startsWith('---')) {
              i++;
              continue;
            }
            hunkLines.add(DiffLine(
                kind: DiffLineKind.deletion,
                oldLine: oldLine++,
                content: line.substring(1)));
            deleted++;
          case ' ':
            hunkLines.add(DiffLine(
                kind: DiffLineKind.context,
                oldLine: oldLine++,
                newLine: newLine++,
                content: line.substring(1)));
          case r'\':
            // "\ No newline at end of file" — ignore
            break;
          default:
            break;
        }
        i++;
      }

      if (currentHunk != null) {
        hunks.add(DiffHunk(
          oldStart: currentHunk.oldStart,
          oldCount: currentHunk.oldCount,
          newStart: currentHunk.newStart,
          newCount: currentHunk.newCount,
          header: currentHunk.header,
          lines: hunkLines,
        ));
      }

      _files.add(FileDiff(
        path: newPath,
        oldPath: raw?.oldPath,
        changeKind: changeKind,
        isBinary: isBinary,
        linesAdded: added,
        linesDeleted: deleted,
        hunks: hunks,
      ));
    }

    return DiffResult(files: _files);
  }

  FileChangeKind _mapDiffStatus(String letter) {
    switch (letter) {
      case 'A':
        return FileChangeKind.added;
      case 'D':
        return FileChangeKind.deleted;
      case 'M':
        return FileChangeKind.modified;
      case 'R':
        return FileChangeKind.renamed;
      case 'C':
        return FileChangeKind.copied;
      case 'T':
        return FileChangeKind.typeChanged;
      case 'U':
        return FileChangeKind.unmerged;
      default:
        return FileChangeKind.modified;
    }
  }
}

class _RawEntry {
  _RawEntry(this.status, this.oldPath);
  final String status;
  final String? oldPath;
}
