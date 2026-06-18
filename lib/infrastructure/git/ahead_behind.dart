/// Parses git's `%(upstream:track)` value, e.g. `[ahead 2, behind 3]`,
/// `[ahead 2]`, `[behind 1]`, `[gone]`, or `''`, into an (ahead, behind) pair.
///
/// Each side is matched independently — an all-optional single regex would
/// match the empty string and report 0/0 for everything.
({int ahead, int behind}) parseAheadBehind(String track) {
  final a = RegExp(r'ahead (\d+)').firstMatch(track);
  final b = RegExp(r'behind (\d+)').firstMatch(track);
  return (
    ahead: a == null ? 0 : int.tryParse(a.group(1)!) ?? 0,
    behind: b == null ? 0 : int.tryParse(b.group(1)!) ?? 0,
  );
}
