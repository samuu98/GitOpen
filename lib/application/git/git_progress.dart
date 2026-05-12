final class GitProgress {
  final String phase;
  final double? fraction;
  final String rawLine;
  const GitProgress({required this.phase, this.fraction, required this.rawLine});
}
