final class GitHubPatchLine {
  const GitHubPatchLine({
    required this.content,
    required this.oldLine,
    required this.newLine,
  });

  final String content;
  final int? oldLine;
  final int? newLine;

  bool get isAddition => content.startsWith('+');
  bool get isDeletion => content.startsWith('-');
  bool get isContext => content.startsWith(' ');
  bool get isCommentable => isAddition || isDeletion || isContext;
  String get side => isDeletion ? 'LEFT' : 'RIGHT';
  int? get commentLine => isDeletion ? oldLine : newLine;
}

final _hunkHeader = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');

List<GitHubPatchLine> parseGitHubPatch(String patch) {
  final result = <GitHubPatchLine>[];
  var oldLine = 0;
  var newLine = 0;
  for (final raw in patch.split('\n')) {
    final hunk = _hunkHeader.firstMatch(raw);
    if (hunk != null) {
      oldLine = int.parse(hunk.group(1)!);
      newLine = int.parse(hunk.group(2)!);
      continue;
    }
    if (raw.isEmpty || raw.startsWith(r'\')) continue;
    if (raw.startsWith('+')) {
      result.add(
        GitHubPatchLine(content: raw, oldLine: null, newLine: newLine),
      );
      newLine++;
      continue;
    }
    if (raw.startsWith('-')) {
      result.add(
        GitHubPatchLine(content: raw, oldLine: oldLine, newLine: null),
      );
      oldLine++;
      continue;
    }
    result.add(
      GitHubPatchLine(content: raw, oldLine: oldLine, newLine: newLine),
    );
    oldLine++;
    newLine++;
  }
  return result;
}
