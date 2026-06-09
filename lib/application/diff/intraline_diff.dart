/// The changed middle of a paired old/new line once their common prefix and
/// suffix are stripped. Ranges are half-open (`start <= end`); an empty range
/// means pure insertion/deletion on that side.
final class IntralineDiff {
  const IntralineDiff({
    required this.oldStart,
    required this.oldEnd,
    required this.newStart,
    required this.newEnd,
  });
  final int oldStart;
  final int oldEnd;
  final int newStart;
  final int newEnd;
}

/// Computes the changed region between [oldLine] and [newLine] by stripping
/// the longest common prefix and suffix (the classic cheap "word diff").
/// Returns null when the lines are identical.
IntralineDiff? intralineDiff(String oldLine, String newLine) {
  if (oldLine == newLine) return null;

  var prefix = 0;
  final maxPrefix =
      oldLine.length < newLine.length ? oldLine.length : newLine.length;
  while (prefix < maxPrefix &&
      oldLine.codeUnitAt(prefix) == newLine.codeUnitAt(prefix)) {
    prefix++;
  }

  var suffix = 0;
  // The suffix must not eat into the prefix on either side.
  while (suffix < oldLine.length - prefix &&
      suffix < newLine.length - prefix &&
      oldLine.codeUnitAt(oldLine.length - 1 - suffix) ==
          newLine.codeUnitAt(newLine.length - 1 - suffix)) {
    suffix++;
  }

  return IntralineDiff(
    oldStart: prefix,
    oldEnd: oldLine.length - suffix,
    newStart: prefix,
    newEnd: newLine.length - suffix,
  );
}

/// Line kind as seen by [pairChangedLines] — a minimal projection of
/// `DiffLineKind` so this stays a pure, domain-free helper.
enum PairKind { context, deletion, addition }

/// Pairs the k-th deletion with the k-th addition inside each contiguous
/// changed run (deletions followed by additions, the order unified diffs
/// use). Returns a symmetric index map: both `del→add` and `add→del` entries.
/// Context lines end a run; unbalanced lines stay unpaired.
Map<int, int> pairChangedLines(
  List<({PairKind kind, int index})> lines,
) {
  final pairs = <int, int>{};
  final deletions = <int>[];
  final additions = <int>[];

  void flush() {
    final n = deletions.length < additions.length
        ? deletions.length
        : additions.length;
    for (var k = 0; k < n; k++) {
      pairs[deletions[k]] = additions[k];
      pairs[additions[k]] = deletions[k];
    }
    deletions.clear();
    additions.clear();
  }

  for (final line in lines) {
    switch (line.kind) {
      case PairKind.deletion:
        // A new deletion after additions started means a new run.
        if (additions.isNotEmpty) flush();
        deletions.add(line.index);
      case PairKind.addition:
        additions.add(line.index);
      case PairKind.context:
        flush();
    }
  }
  flush();
  return pairs;
}
