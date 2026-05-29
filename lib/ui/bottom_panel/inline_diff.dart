/// Word-level (intra-line) diff used to highlight exactly which parts of a
/// changed line differ, the way Fork / GitHub do — instead of fl-lagging the
/// whole line.
///
/// Pure Dart, no dependencies: tokenise both sides, run a token LCS, and mark
/// tokens not on the common subsequence as changed.
library;

class InlineSegment {
  final String text;
  final bool changed;
  const InlineSegment(this.text, this.changed);
}

/// Splits into words, runs of whitespace, and individual punctuation marks,
/// so highlighting snaps to word boundaries rather than single characters.
final RegExp _token = RegExp(r'\s+|\w+|[^\w\s]');

List<String> _tokenize(String s) =>
    _token.allMatches(s).map((m) => m.group(0)!).toList();

/// Returns (oldSegments, newSegments) for a deletion/addition line pair.
/// Common tokens are marked unchanged; the rest are marked changed.
(List<InlineSegment>, List<InlineSegment>) computeInlineDiff(
    String oldLine, String newLine) {
  final a = _tokenize(oldLine);
  final b = _tokenize(newLine);

  // LCS length table.
  final n = a.length;
  final m = b.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }

  final oldSegs = <InlineSegment>[];
  final newSegs = <InlineSegment>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      _append(oldSegs, a[i], false);
      _append(newSegs, b[j], false);
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      _append(oldSegs, a[i], true);
      i++;
    } else {
      _append(newSegs, b[j], true);
      j++;
    }
  }
  while (i < n) {
    _append(oldSegs, a[i++], true);
  }
  while (j < m) {
    _append(newSegs, b[j++], true);
  }
  return (oldSegs, newSegs);
}

/// Appends [text], coalescing with the previous segment when the changed flag
/// matches, to keep the span list short.
void _append(List<InlineSegment> segs, String text, bool changed) {
  if (segs.isNotEmpty && segs.last.changed == changed) {
    segs[segs.length - 1] = InlineSegment(segs.last.text + text, changed);
  } else {
    segs.add(InlineSegment(text, changed));
  }
}
