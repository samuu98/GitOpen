import 'dart:convert';

import 'package:gitopen/domain/blame/blame_line.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';

/// Parser for `git blame --porcelain` output.
///
/// Porcelain groups one or more consecutive final-file lines per record.
/// Each record begins with a header line:
///   `<40-hex-sha> <orig-line> <final-line> [<lines-in-this-group>]`
/// followed by zero or more extended headers (`author `, `author-mail `,
/// `author-time `, `summary `, …) and finally the literal content line, which
/// is the only line that starts with a TAB.
///
/// The author/time headers are emitted in full only the FIRST time a commit
/// is seen; later groups for the same commit carry just the header line.  So
/// we cache author name + time per sha and reuse them for repeat appearances.
class BlameParser {
  BlameParser(this._stdout);

  final String _stdout;

  final Map<String, ({String name, DateTime time})> _meta = {};

  List<BlameLine> parse() {
    final lines = const LineSplitter().convert(_stdout);
    final result = <BlameLine>[];

    String? currentSha;
    var currentFinalLine = 0;
    String? pendingName;
    int? pendingTimeSecs;

    for (final line in lines) {
      if (line.startsWith('\t')) {
        // Content line — closes the current record's first (or only) line.
        final sha = currentSha;
        if (sha == null) continue;

        if (pendingName != null && pendingTimeSecs != null) {
          _meta[sha] = (
            name: pendingName,
            time: DateTime.fromMillisecondsSinceEpoch(
              pendingTimeSecs * 1000,
              isUtc: true,
            ),
          );
        }
        final meta = _meta[sha];

        result.add(BlameLine(
          lineNumber: currentFinalLine,
          content: line.substring(1),
          sha: CommitSha(sha),
          authorName: meta?.name ?? '',
          authorTime: meta?.time ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ));

        pendingName = null;
        pendingTimeSecs = null;
        continue;
      }

      if (line.startsWith('author ')) {
        pendingName = line.substring('author '.length);
        continue;
      }
      if (line.startsWith('author-time ')) {
        pendingTimeSecs =
            int.tryParse(line.substring('author-time '.length).trim());
        continue;
      }

      // Header line: "<sha> <orig> <final> [count]".  A 40-hex prefix followed
      // by a space and a digit distinguishes it from extended headers like
      // "summary ..." or "filename ...".
      final m = RegExp(r'^([0-9a-f]{40}) \d+ (\d+)(?: \d+)?$').firstMatch(line);
      if (m != null) {
        currentSha = m.group(1);
        currentFinalLine = int.parse(m.group(2)!);
      }
    }

    return result;
  }
}
