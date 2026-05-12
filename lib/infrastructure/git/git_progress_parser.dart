import '../../application/git/git_progress.dart';

class GitProgressParser {
  static final _regex = RegExp(r'^(?:remote:\s*)?(?<phase>[^:]+):\s+(?<pct>\d+)%');

  static GitProgress? parse(String line) {
    final m = _regex.firstMatch(line);
    if (m == null) return null;
    final phase = m.namedGroup('phase')!.trim();
    final pct = int.parse(m.namedGroup('pct')!);
    return GitProgress(phase: phase, fraction: pct / 100.0, rawLine: line);
  }
}
